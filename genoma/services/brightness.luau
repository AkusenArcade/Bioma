--!strict
-- Display brightness (services/Brightness.qml at 8ed8892).
--
-- Two backends and, above all, a capability check:
--   backlight  /sys/class/backlight, written through brightnessctl: laptops
--              and any panel the kernel drives directly;
--   ddc        DDC/CI over I²C through ddcutil: external monitors, each
--              addressed by its own bus.
-- With neither, `available` is false and every control does nothing: a
-- control that cannot change anything is not offered.
--
-- Over DDC, detection is slow (3.5 s here) and a bus is fast (0.1 s to read,
-- 0.3 s to write), so displays are detected once and addressed by bus from
-- then on. Nothing is polled: each display is read once after detection,
-- and after that this service's own writes are what moves the value.
local g = require("@genoma")
local config = require("core/config")

local M = {}

-- auto | backlight | ddc | off
local function configured(): string return config.get("brightness.backend", "auto") end

local backlight = g.signal(nil :: { device: string, value: number, max: number }?)
-- { index, bus, connector, model, value, max }; value -1 until read.
local displays = g.signal({} :: { any })
local last_error = g.signal("")
function M.error(): string return last_error.value end

function M.backend(): string
    local c = configured()
    if c == "off" then return "off" end
    if backlight.value and (c == "auto" or c == "backlight") then return "backlight" end
    if #displays.value > 0 and (c == "auto" or c == "ddc") then return "ddc" end
    return "none"
end
function M.available(): boolean
    local b = M.backend()
    return b == "backlight" or b == "ddc"
end
function M.displays(): { any } return displays.value end

local function display_for(connector: string): any
    for _, d in displays.value do if d.connector == connector then return d end end
    return nil
end
-- Which display the bare `brightness` and `set` mean: the configured
-- connector, else the first.
function M.display(): any
    local wanted = config.get("brightness.display", "")
    if wanted ~= "" then
        local chosen = display_for(wanted)
        if chosen then return chosen end
    end
    return displays.value[1]
end

-- A monitor's own words for itself; the connector always exists.
function M.describe(entry: any): string
    if not entry then return "" end
    return if entry.model and entry.model ~= "" then entry.model .. " (" .. entry.connector .. ")" else entry.connector
end

function M.brightness(): number
    local b = M.backend()
    if b == "backlight" then
        local l = backlight.value
        return if l and l.max > 0 then l.value / l.max else 0
    end
    local d = M.display()
    if b == "ddc" and d and d.value >= 0 then return d.value / d.max end
    return 0
end
-- Whether `brightness` is a reading yet: over DDC the first answer comes
-- seconds after start, and going from nothing to what it is is not a change.
function M.known(): boolean
    local b = M.backend()
    if b == "backlight" then return backlight.value ~= nil end
    if b == "ddc" then
        local d = M.display()
        return d ~= nil and d.value >= 0
    end
    return false
end
-- -1 while that display has not answered, which is not 0.
function M.brightness_for(connector: string): number
    local d = display_for(connector)
    return if d and d.value >= 0 then d.value / d.max else -1
end

-- ---- Probing ---------------------------------------------------------------------

-- A machine can expose more than one backlight, and only one of them
-- drives the panel. The kernel hangs that one under the panel's own DRM
-- connector (…/card2-eDP-2/amdgpu_bl2), and that connector says it is
-- connected; one beside it may drive nothing at all — a hybrid laptop's
-- `nvidia_0`, last in the listing, took every write while the panel stayed
-- where it was (2026-11-04). So: a backlight of a connected connector, else
-- any other, else `acpi_video`, the generic fallback and the worse of them
-- all; the first found among equals.
local function rank(device: string, connected: boolean): number
    if connected then return 3 end
    if string.sub(device, 1, 10) == "acpi_video" then return 1 end
    return 2
end
local chosen_rank = 0
g.process {
    command = { "sh", "-c", "for d in /sys/class/backlight/*/; do "
        .. '[ -e "$d/brightness" ] || continue; '
        .. 'status="$(cat "$(readlink -f "$d")/../status" 2>/dev/null)"; '
        .. 'printf \'%s %s %s %s\\n\' "$(basename "$d")" "$(cat "$d/brightness")" "$(cat "$d/max_brightness")" "${status:-none}"; '
        .. "done" },
    on_line = function(line: string)
        local device, value, max, status = string.match(line, "^(%S+)%s+(%d+)%s+(%d+)%s+(%S+)")
        if not device or tonumber(max) == 0 then return end
        local r = rank(device, status == "connected")
        if r <= chosen_rank then return end
        chosen_rank = r
        backlight.value = { device = device, value = tonumber(value) :: number, max = tonumber(max) :: number }
    end,
}

local reads: { string } = {}
local reading = false
local function read_next()
    if reading or #reads == 0 then return end
    local connector = table.remove(reads, 1)
    local d = g.untracked(function() return display_for(connector) end)
    if not d then read_next() return end
    reading = true
    g.process {
        command = { "ddcutil", "--bus", tostring(d.bus), "getvcp", "10", "--brief" },
        on_line = function(line: string)
            -- `getvcp --brief` answers: VCP 10 C <current> <max>
            local current, max = string.match(line, "^%s*VCP%s+%S+%s+%S+%s+(%d+)%s+(%d+)")
            if not current or tonumber(max) == 0 then return end
            local list = table.clone(g.untracked(function() return displays.value end))
            for i, e in list do
                if e.connector == connector then
                    local copy = table.clone(e)
                    copy.value, copy.max = tonumber(current), tonumber(max)
                    list[i] = copy
                end
            end
            displays.value = list
        end,
        on_exit = function()
            reading = false
            read_next()
        end,
    }
end

-- `detect --brief` has no `Model:` line, and its monitor field is
-- MFG:MODEL:SERIAL with any part possibly empty.
do
    local found = {}
    g.process {
        command = { "sh", "-c", "command -v ddcutil >/dev/null 2>&1 || exit 0; "
            .. "ddcutil detect --brief 2>/dev/null | awk '"
            .. "/^Display[ \\t]+[0-9]+/ { idx=$2; bus=\"\"; conn=\"\"; model=\"\" } "
            .. "/I2C bus:/ { bus=$3; sub(/^\\/dev\\/i2c-/, \"\", bus) } "
            .. "/DRM connector:/ { conn=$3; sub(/^card[0-9]+-/, \"\", conn) } "
            .. "/Monitor:/ { split($2, m, \":\"); model=m[2] } "
            .. "/^$/ { if (idx != \"\") { print idx \"\\t\" bus \"\\t\" conn \"\\t\" model; idx=\"\" } } "
            .. "END { if (idx != \"\") print idx \"\\t\" bus \"\\t\" conn \"\\t\" model }'" },
        on_line = function(line: string)
            local parts = string.split(line, "\t")
            local index, bus = tonumber(parts[1]), tonumber(parts[2])
            if not index or not bus then return end
            local connector = string.match(parts[3] or "", "^%s*(.-)%s*$") or ""
            table.insert(found, {
                index = index, bus = bus,
                connector = if connector ~= "" then connector else "display-" .. index,
                model = string.match(parts[4] or "", "^%s*(.-)%s*$") or "",
                value = -1, max = 100,
            })
        end,
        on_exit = function()
            displays.value = found
            for _, d in found do table.insert(reads, d.connector) end
            read_next()
        end,
    }
end

-- ---- Writing ---------------------------------------------------------------------
--
-- A write takes a third of a second, so a control being dragged neither
-- queues every value nor waits for each: the latest target per display is
-- held, and the next write starts when the previous one finishes.
local targets: { [string]: number } = {}
local writing = false
local write_next: () -> ()

local function finished(code: number, said: { string })
    writing = false
    if code ~= 0 and #said > 0 then
        last_error.value = said[#said]
        print("Brightness: " .. said[#said])
    elseif code == 0 then
        last_error.value = ""
    end
    if g.untracked(M.backend) == "ddc" then write_next() end
end

write_next = function()
    if writing then return end
    local connector, fraction = next(targets)
    if not connector then return end
    targets[connector] = nil
    local d = g.untracked(function() return display_for(connector) end)
    if not d then write_next() return end
    local value = math.clamp(math.round(fraction * d.max), 0, d.max)
    writing = true
    local said = {}
    g.process {
        command = { "ddcutil", "--bus", tostring(d.bus), "setvcp", "10", tostring(value) },
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number) finished(code, said) end,
    }
end

function M.set_for(connector: string, fraction: number)
    if g.untracked(M.backend) ~= "ddc" then return end
    local clamped = math.clamp(fraction, 0, 1)
    targets[connector] = clamped
    -- The reported value moves at once and the hardware follows.
    local list = table.clone(g.untracked(function() return displays.value end))
    for i, e in list do
        if e.connector == connector then
            local copy = table.clone(e)
            copy.value = math.round(clamped * copy.max)
            list[i] = copy
        end
    end
    displays.value = list
    write_next()
end

local function set_backlight(fraction: number)
    local l = g.untracked(function() return backlight.value end)
    if not l then return end
    local percent = math.clamp(math.round(fraction * 100), 1, 100)
    backlight.value = { device = l.device, value = math.round(fraction * l.max), max = l.max }
    local said = {}
    g.process {
        command = { "brightnessctl", "--class=backlight", "--device", l.device, "set", percent .. "%" },
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number) finished(code, said) end,
    }
end

function M.set(fraction: number)
    local b = g.untracked(M.backend)
    if b == "backlight" then
        set_backlight(fraction)
    elseif b == "ddc" then
        local d = g.untracked(M.display)
        if d then M.set_for(d.connector, fraction) end
    end
end

function M.step(delta: number) M.set(math.clamp(g.untracked(M.brightness) + delta, 0, 1)) end

return M
