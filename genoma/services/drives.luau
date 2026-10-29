--!strict
-- Removable drives, and whether they are being written to (services/
-- Drives.qml at 11bb81e), through `scripts/drives`, which follows udisks
-- and reads the kernel's write counts once a second while one is mounted.
-- Run only while a cell holds it.
--
-- BIOMA_CHECK_DRIVES names another program to read instead: a check
-- without a stick in the machine.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

local holders: { [any]: boolean } = {}
local held = g.signal(0)
function M.hold(owner: any, wanted: boolean)
    if (holders[owner] == true) == wanted then return end
    holders[owner] = if wanted then true else nil
    local n = 0
    for _ in holders do n += 1 end
    held.value = n
end

local drives = g.signal({})
g.effect(function()
    if held.value == 0 then return end
    local loops = config.get("drives.include_loop", false) == true
    g.untracked(function()
        local function watch()
            local command = { g.env("BIOMA_CHECK_DRIVES") or paths.script("drives") }
            if loops then table.insert(command, "--loop") end
            g.process {
                command = command,
                on_line = function(line: string)
                    local ok, data = pcall(g.parse_json, line)
                    if ok and type(data) == "table" and type(data.drives) == "table" then drives.value = data.drives end
                end,
                on_exit = function()
                    drives.value = {}
                    g.after(5, function() if g.untracked(function() return held.value end) > 0 then watch() end end)
                end,
            }
        end
        watch()
    end)
end)

function M.drives(): { any } return drives.value end
function M.attached(): boolean return #drives.value > 0 end
function M.rate(): number
    local sum = 0
    for _, d in drives.value do sum += d.rate or 0 end
    return sum
end
function M.writing(d: any): boolean return d ~= nil and (d.rate or 0) >= 4096 end
function M.mounted(d: any): boolean
    for _, v in (if d then d.volumes else nil) or {} do
        if #(v.mounts or {}) > 0 then return true end
    end
    return false
end
function M.size(d: any): number
    local sum = 0
    for _, v in (if d then d.volumes else nil) or {} do sum += v.size or 0 end
    return sum
end

-- What each drive is doing ("opening", "ejecting") and why it could not.
local busy = g.signal({})
local errors = g.signal({})
function M.busy(id: string): string return busy.value[id] or "" end
function M.error(id: string): string return errors.value[id] or "" end
-- A drive gone takes its marks with it.
g.watch(function() return #drives.value end, function()
    local here = {}
    for _, d in g.untracked(function() return drives.value end) do here[d.id] = true end
    local function keep(map: any): any
        local out = {}
        for id, v in map do if here[id] then out[id] = v end end
        return out
    end
    busy.value = keep(g.untracked(function() return busy.value end))
    errors.value = keep(g.untracked(function() return errors.value end))
end)
local function mark(id: string, doing: string, problem: string)
    local b = table.clone(g.untracked(function() return busy.value end))
    local e = table.clone(g.untracked(function() return errors.value end))
    b[id] = if doing ~= "" then doing else nil
    e[id] = if problem ~= "" then problem else nil
    busy.value = b
    errors.value = e
end

local function reason(lines: { string }): string
    local text = table.concat(lines, "\n")
    local said = string.lower(text)
    if string.find(said, "busy", 1, true) then return "In use — close what has a file open on it" end
    if string.find(said, "not authorized", 1, true) or string.find(said, "dismissed", 1, true) then return "Not allowed" end
    local last = ""
    for _, l in lines do
        local t = string.match(l, "^%s*(.-)%s*$") or ""
        if t ~= "" then last = t end
    end
    return if last ~= "" then (string.gsub(last, "^Error [^:]*:%s*", "")) else "It did not answer"
end

local function run(id: string, command: { string }, env: { [string]: string }?)
    local complaint = {}
    g.process {
        command = command,
        env = env,
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function(code: number) mark(id, "", if code == 0 then "" else reason(complaint)) end,
    }
end

-- Mounted if it is not, then shown in the file manager, as its own service.
function M.open(d: any, env: { [string]: string }?)
    if not d or g.untracked(function() return M.busy(d.id) end) ~= "" then return end
    local volume = d.volumes[1]
    if not volume then return end
    mark(d.id, "opening", "")
    run(d.id, { "sh", "-c",
        'dev="$1"; launch="$2"; at=$(findmnt -n -o TARGET --source "$dev" | head -n 1); '
        .. 'if [ -z "$at" ]; then udisksctl mount -b "$dev" >/dev/null || exit 1; '
        .. 'at=$(findmnt -n -o TARGET --source "$dev" | head -n 1); fi; '
        .. '[ -n "$at" ] && exec "$launch" --id xdg-open -- xdg-open "$at"',
        "open", volume.device, paths.script("launch") }, env)
end

-- Unmounting waits for the last of the writing; then the power goes, so the
-- drive leaves the list when it really is safe to pull.
function M.eject(d: any)
    if not d or g.untracked(function() return M.busy(d.id) end) ~= "" then return end
    local command = { "sh", "-c",
        'disk="$1"; power="$2"; shift 2; '
        .. 'for dev in "$@"; do udisksctl unmount -b "$dev" >/dev/null || exit 1; done; '
        .. 'case "$power" in loop) exec udisksctl loop-delete -b "$disk" ;; yes) exec udisksctl power-off -b "$disk" ;; esac',
        "eject", d.device,
        if string.sub(d.device, 1, 9) == "/dev/loop" then "loop" elseif d.power_off then "yes" else "no" }
    for _, v in d.volumes do
        if #(v.mounts or {}) > 0 then table.insert(command, v.device) end
    end
    mark(d.id, "ejecting", "")
    run(d.id, command)
end

function M.bytes(value: number): string
    if value >= 1e9 then return string.format(if value >= 10e9 then "%.0f GB" else "%.1f GB", value / 1e9) end
    if value >= 1e6 then return string.format("%d MB", math.floor(value / 1e6 + 0.5)) end
    if value >= 1e3 then return string.format("%d KB", math.floor(value / 1e3 + 0.5)) end
    return string.format("%d B", math.floor(value + 0.5))
end

return M
