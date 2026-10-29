--!strict
-- The machine, in a few facts (services/Machine.qml at 11bb81e): host,
-- system, kernel, niri, processor, graphics, memory, disk, uptime. Read
-- once, the first time someone looks; the uptime again each minute while
-- the system cell is open.
local g = require("@genoma")

local M = {}

local facts = g.signal({ gpus = {} } :: { [string]: any })
local uptime = g.signal(0)
local asked = false

local function first(text: string?, pattern: string): string?
    if not text then return nil end
    return string.match(text, pattern)
end

local function set(key: string, value: any)
    local next = table.clone(g.untracked(function() return facts.value end))
    next[key] = value
    facts.value = next
end

local function read_uptime()
    g.process {
        command = { "cat", "/proc/uptime" },
        on_line = function(line: string) uptime.value = tonumber(string.match(line, "^(%S+)")) or 0 end,
    }
end

function M.ask()
    if asked then return end
    asked = true
    local lines: { string } = {}
    g.process {
        command = { "sh", "-c",
            "cat /proc/sys/kernel/hostname; cat /proc/sys/kernel/osrelease; "
            .. "sed -n 's/^PRETTY_NAME=\"\\?\\([^\"]*\\)\"\\?$/\\1/p' /etc/os-release; echo --; "
            .. "grep -m1 '^model name' /proc/cpuinfo; grep -c '^processor' /proc/cpuinfo; "
            .. "grep -m1 '^MemTotal' /proc/meminfo; echo --; "
            .. "lspci -mm 2>/dev/null | grep -Ei '\"(VGA compatible controller|3D controller|Display controller)\"'; echo --; "
            .. "df -h --output=used,size / | tail -1; echo --; niri --version 2>/dev/null" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function()
            local parts: { { string } } = { {} }
            for _, l in lines do
                if l == "--" then table.insert(parts, {}) else table.insert(parts[#parts], l) end
            end
            local base, cpu, gpu, disk, niri = parts[1] or {}, parts[2] or {}, parts[3] or {}, parts[4] or {}, parts[5] or {}
            local out: { [string]: any } = { host = base[1] or "", kernel = base[2] or "", os = base[3] or "Linux" }
            local model = first(cpu[1], "^model name%s*:%s*(.*)$")
            if model then
                local name = string.gsub(model, "%(R%)", "")
                name = string.gsub(name, "%(TM%)", "")
                name = string.gsub(name, "%s+%d+%-Core Processor", "")
                name = string.gsub(name, "%s+", " ")
                name = string.match(name, "^%s*(.-)%s*$") or name
                local threads = tonumber(cpu[2] or "") or 0
                out.cpu = if threads > 0 then name .. " · " .. threads .. " threads" else name
            end
            local kb = tonumber(first(cpu[3], "^MemTotal:%s*(%d+)") or "")
            if kb then out.memory = math.floor(kb / 1048576 + 0.5) .. " GB" end
            out.gpus = {}
            for _, line in gpu do
                local quoted = {}
                for q in string.gmatch(line, '"([^"]*)"') do table.insert(quoted, q) end
                if #quoted >= 3 then
                    table.insert(out.gpus, string.match(quoted[3], "%[([^%]]+)%]") or quoted[3])
                end
            end
            local used, size = string.match(disk[1] or "", "^%s*(%S+)%s+(%S+)%s*$")
            out.disk = if used then used .. " of " .. size else ""
            out.niri = first(niri[1], "niri%s+(%S+)") or ""
            facts.value = out
        end,
    }
    read_uptime()
end

-- The uptime, each minute while someone is looking.
local ticking: any = nil
function M.watch(on: boolean)
    if ticking then ticking:stop() end
    ticking = nil
    if on then
        read_uptime()
        ticking = g.timer { every = 60, on_tick = read_uptime }
    end
end

local function uptime_text(seconds: number): string
    local minutes = math.floor(seconds / 60)
    local days, hours, rest = minutes // 1440, (minutes % 1440) // 60, minutes % 60
    if days > 0 then return days .. " d " .. hours .. " h" end
    if hours > 0 then return hours .. " h " .. rest .. " min" end
    return rest .. " min"
end

-- { label, value, human }: human values in the expressive face, the rest in
-- the technical one. A fact not known is left out.
function M.rows(): { any }
    local f = facts.value
    local out = {
        { label = "HOST", value = f.host, human = true },
        { label = "SYSTEM", value = f.os, human = true },
        { label = "KERNEL", value = f.kernel, human = false },
        { label = "NIRI", value = f.niri, human = false },
        { label = "CPU", value = f.cpu, human = true },
    }
    for _, gpu in f.gpus or {} do table.insert(out, { label = "GPU", value = gpu, human = true }) end
    table.insert(out, { label = "MEMORY", value = f.memory, human = false })
    table.insert(out, { label = "DISK", value = f.disk, human = false })
    table.insert(out, { label = "UP", value = if uptime.value > 0 then uptime_text(uptime.value) else nil, human = false })
    local kept = {}
    for _, r in out do
        if r.value and r.value ~= "" then table.insert(kept, r) end
    end
    return kept
end

return M
