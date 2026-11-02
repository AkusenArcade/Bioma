--!strict
-- What each running application costs: its memory and its processor, summed
-- over every process that belongs to it (services/AppLoad.qml at 2cafc17).
--
-- The process tree decides what belongs to what:
--   1. a process belongs to the nearest ancestor that owns a window (niri
--      reports each window's pid), unless that pid is Xwayland's;
--   2. otherwise to its ancestor just below the session (the child of the
--      user's systemd, of niri, or of init), which names a group of its own;
--   3. a group of the second kind holding a process named after an open
--      window's application joins that application.
-- Bioma's own process is a group like any other, and named for what it is.
--
-- One `pgrep` and one `awk` over /proc/<pid>/stat per sample; processor is
-- the difference in clock ticks between two samples. It runs only while
-- held: nothing samples while no organism shows it.
local g = require("@genoma")
local config = require("core/config")
local apps_mod = require("core/apps")
local niri = require("services/niri")

local M = {}

local holders = g.signal(0)
function M.hold(on: boolean)
    holders.value = math.max(0, g.untracked(function() return holders.value end) + (if on then 1 else -1))
end

-- { key, name, app_id, icon, ram (MiB), cpu (% of one core), processes }
local apps = g.signal({} :: { any })
local total = g.signal(0)
function M.apps(): { any } return apps.value end
function M.total_ram(): number return total.value end

local HERTZ = 100
local XWAYLAND = { Xwayland = true, ["xwayland-satell"] = true }
local previous: { [number]: number } = {}
local previous_at = 0

local SAMPLE = "echo \"self\t$PPID\"; "
    .. "cd /proc && pgrep -u \"$(id -u)\" | sed 's|$|/stat|' "
    .. "| xargs -r awk -v page=\"$(getconf PAGESIZE)\" '"
    .. "{ o = index($0, \"(\"); c = 0; "
    .. "  for (i = length($0); i > o; i--) if (substr($0, i, 1) == \")\") { c = i; break } "
    .. "  if (!c) next; "
    .. "  comm = substr($0, o + 1, c - o - 1); "
    .. "  n = split(substr($0, c + 2), f, \" \"); "
    .. "  split(FILENAME, p, \"/\"); "
    .. "  printf \"%s\\t%s\\t%s\\t%s\\t%s\\n\", p[1], f[2], f[12] + f[13], f[22] * page, comm }"
    .. "' 2>/dev/null"

-- The open application a set of processes belongs to, by name.
local function owner_of(processes: { any }, open: { string }): string?
    for _, app_id in open do
        local parts = string.split(app_id, ".")
        local short = string.lower(parts[#parts])
        local entry = apps_mod.entry_for(app_id)
        for _, p in processes do
            local comm = string.lower(p.comm)
            if comm == string.lower(app_id) or (#short >= 4 and comm == short) then return app_id end
            if entry and apps_mod.entry_for(p.comm) == entry then return app_id end
        end
    end
    return nil
end

local function digest(rows: { any }, self_pid: number)
    local now = g.now()
    local elapsed = if previous_at > 0 then now - previous_at else 0
    local procs = {}
    for _, row in rows do procs[row.pid] = row end
    -- The session's roots: the user's systemd, niri, init.
    local roots = { [1] = true }
    for _, row in rows do
        if row.comm == "systemd" or row.comm == "niri" then roots[row.pid] = true end
    end
    -- Windows by pid, Xwayland's left out.
    local window_at, open = {}, {}
    for _, w in g.untracked(niri.windows) do
        if w.app_id and w.app_id ~= "" then
            table.insert(open, w.app_id)
            local proc = procs[w.pid]
            if proc and not XWAYLAND[proc.comm] then window_at[w.pid] = w.app_id end
        end
    end
    local groups, ticks = {}, {}
    for _, row in rows do
        ticks[row.pid] = row.ticks
        local key, current = nil, row.pid
        for _ = 1, 64 do
            if not procs[current] then break end
            if window_at[current] then
                key = "app:" .. window_at[current]
                break
            end
            local parent = procs[current].ppid
            if roots[parent] or not procs[parent] then
                key = if current == self_pid then "self" else "root:" .. current
                break
            end
            current = parent
        end
        if key and not roots[row.pid] then
            local before = previous[row.pid]
            local cpu = if elapsed > 0 and before then math.max(0, (row.ticks - before) / HERTZ / elapsed * 100) else 0
            if not groups[key] then
                groups[key] = { key = key, root_comm = if procs[current] then procs[current].comm else row.comm, processes = {} }
            end
            table.insert(groups[key].processes, { pid = row.pid, comm = row.comm, ram = row.bytes / 1048576, cpu = cpu })
        end
    end
    -- A windowless group holding a process named after an open application
    -- joins it.
    for key, group in groups do
        if string.sub(key, 1, 5) == "root:" then
            local joined = owner_of(group.processes, open)
            if joined then
                local target = "app:" .. joined
                if not groups[target] then groups[target] = { key = target, root_comm = group.root_comm, processes = {} } end
                for _, p in group.processes do table.insert(groups[target].processes, p) end
                groups[key] = nil
            end
        end
    end
    local out, sum = {}, 0
    for key, group in groups do
        table.sort(group.processes, function(a: any, b: any) return a.ram > b.ram end)
        local ram, cpu = 0, 0
        for _, p in group.processes do
            ram += p.ram
            cpu += p.cpu
        end
        sum += ram
        local app_id = if string.sub(key, 1, 4) == "app:" then string.sub(key, 5) else ""
        local lookup = if app_id ~= "" then app_id else group.root_comm
        local entry = apps_mod.entry_for(lookup)
        local name = if key == "self" then "Bioma"
            elseif entry and entry.name ~= "" then entry.name
            elseif app_id ~= "" then app_id else group.root_comm
        table.insert(out, { key = key, name = name, app_id = app_id, ram = ram, cpu = cpu, processes = group.processes })
    end
    table.sort(out, function(a: any, b: any) return a.ram > b.ram end)
    previous = ticks
    previous_at = now
    g.batch(function()
        total.value = sum
        apps.value = out
    end)
end

local function sample()
    local rows, self_pid = {}, -1
    g.process {
        command = { "sh", "-c", SAMPLE },
        on_line = function(line: string)
            local f = string.split(line, "\t")
            if f[1] == "self" then
                self_pid = tonumber(f[2]) or -1
                return
            end
            if #f < 5 then return end
            table.insert(rows, { pid = tonumber(f[1]) or 0, ppid = tonumber(f[2]) or 0, ticks = tonumber(f[3]) or 0,
                bytes = tonumber(f[4]) or 0, comm = f[5] })
        end,
        on_exit = function() digest(rows, self_pid) end,
    }
end

g.effect(function()
    if holders.value <= 0 then
        g.untracked(function()
            apps.value = {}
            previous = {}
            previous_at = 0
        end)
        return
    end
    local every = math.max(500, config.get("vitals.process_interval", 3000)) / 1000
    g.untracked(sample)
    g.timer { every = every, on_tick = sample }
end)

return M
