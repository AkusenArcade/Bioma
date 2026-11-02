--!strict
-- The disks: how full each is (services/Storage.qml at 2cafc17).
--
-- One `df` a minute while something holds it, the virtual filesystems left
-- out, one row per device (the shortest mount of a device named twice, as
-- btrfs subvolumes are). Fill is used over what the user can use, as df's
-- own percentage is.
local g = require("@genoma")

local M = {}

local holders = g.signal(0)
function M.hold(on: boolean)
    holders.value = math.max(0, g.untracked(function() return holders.value end) + (if on then 1 else -1))
end

local disks = g.signal({} :: { any })
local loaded = g.signal(false)
function M.disks(): { any } return disks.value end
function M.loaded(): boolean return loaded.value end

local VIRTUAL = {}
for _, k in { "tmpfs", "devtmpfs", "efivarfs", "overlay", "squashfs", "ramfs", "fuse.portal", "fuse.gvfsd-fuse",
    "nsfs", "proc", "sysfs", "cgroup2", "autofs" } do VIRTUAL[k] = true end
local SYSTEM = { ["/boot"] = true, ["/efi"] = true, ["/boot/efi"] = true }

local function name_of(mount: string): string
    if mount == "/" then return "System" end
    if mount == "/home" then return "Home" end
    if SYSTEM[mount] then return "Boot" end
    local parts = {}
    for part in string.gmatch(mount, "[^/]+") do table.insert(parts, part) end
    return parts[#parts] or mount
end

local function parse(lines: { string })
    local by = {}
    for i = 2, #lines do
        local parts = {}
        for word in string.gmatch(lines[i], "%S+") do table.insert(parts, word) end
        if #parts >= 6 then
            local source, fstype = parts[1], parts[2]
            local total, used, avail = tonumber(parts[3]) or 0, tonumber(parts[4]) or 0, tonumber(parts[5]) or 0
            local mount = table.concat(parts, " ", 6)
            if not VIRTUAL[fstype] and string.sub(source, 1, 1) == "/" and total > 0 then
                local device = string.gsub(source, "%[.*%]$", "")
                local known = by[device]
                if not known or #known.mount > #mount then
                    local usable = used + avail
                    by[device] = {
                        device = device, mount = mount, name = name_of(mount), fstype = fstype, size = total,
                        used = used, fill = if usable > 0 then used / usable else 0, system = SYSTEM[mount] == true,
                    }
                end
            end
        end
    end
    local out = {}
    for _, d in by do table.insert(out, d) end
    table.sort(out, function(a: any, b: any) return a.size > b.size end)
    g.batch(function()
        disks.value = out
        loaded.value = true
    end)
end

local function read()
    local lines = {}
    g.process {
        command = { "df", "-B1", "--output=source,fstype,size,used,avail,target" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function() parse(lines) end,
    }
end

g.effect(function()
    if holders.value <= 0 then return end
    g.untracked(read)
    g.timer { every = 60, on_tick = read }
end)

function M.bytes(value: number): string
    local units = { "B", "KB", "MB", "GB", "TB", "PB" }
    local unit = 1
    while value >= 1000 and unit < #units do
        value /= 1000
        unit += 1
    end
    return string.format(if value < 10 and unit > 1 then "%.1f %s" else "%.0f %s", value, units[unit])
end

return M
