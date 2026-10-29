--!strict
-- Time beyond the one on the clock (services/Time.qml): other places, a
-- timer, an alarm. They outlive the clock's panel, since a timer that
-- stopped when the panel closed would be one nobody could use; the cell
-- only draws them.
--
-- Other places: the offset of each is asked of the system
-- (`TZ=… date +%z`) when the list changes and every half hour, so a change
-- of summer time is caught the same day. The time there is the machine's
-- clock moved by that offset.
--
-- The timer and the alarm end in a critical notification, which stays until
-- it is closed, and the freedesktop alarm sound.
local g = require("@genoma")
local config = require("core/config")

local M = {}

-- ---- Other places ------------------------------------------------------------

function M.zones(): { string } return config.get("clock.zones", {}) end

-- Minutes east of UTC, by zone.
local offsets = g.signal({})

local function refresh_offsets(zones: { string })
    if #zones == 0 then
        offsets.value = {}
        return
    end
    local command = { "bash", "-c", "for z in \"$@\"; do printf '%s %s\\n' \"$z\" \"$(TZ=\"$z\" date +%z)\"; done", "offsets" }
    for _, z in zones do table.insert(command, z) end
    local out = {}
    g.process {
        command = command,
        on_line = function(line: string)
            local zone, sign, hours, minutes = string.match(line, "^(%S+) ([+-])(%d%d)(%d%d)$")
            if zone then
                local total = (tonumber(hours) :: number) * 60 + (tonumber(minutes) :: number)
                out[zone] = if sign == "-" then -total else total
            end
        end,
        on_exit = function() offsets.value = out end,
    }
end

-- On the list, and again every half hour while there is one.
g.effect(function()
    local zones = M.zones()
    g.untracked(function() refresh_offsets(zones) end)
    if #zones > 0 then
        g.timer { every = 30 * 60, on_tick = function() refresh_offsets(g.untracked(M.zones)) end }
    end
end)

-- The wall-clock fields of `at` (seconds since the epoch, now when nil) in a
-- zone: what os.date("*t") would say there. nil until its offset is known.
function M.in_zone(zone: string, at: number?): any
    local offset = offsets.value[zone]
    if offset == nil then return nil end
    local now = at or os.time()
    return os.date("!*t", now + offset * 60)
end

-- `Europe/Rome` → `Rome`, `America/Argentina/Buenos_Aires` → `Buenos Aires`.
function M.city_of(zone: string): string
    local last = string.match(zone, "([^/]+)$") or zone
    return (string.gsub(last, "_", " "))
end

function M.utc_label(zone: string): string
    local offset = offsets.value[zone]
    if offset == nil then return "" end
    if offset == 0 then return "UTC" end
    local sign = if offset < 0 then "−" else "+"
    local hours = math.abs(offset) // 60
    local minutes = math.abs(offset) % 60
    return "UTC" .. sign .. hours .. (if minutes ~= 0 then string.format(":%02d", minutes) else "")
end

function M.add_zone(zone: string)
    local zones = M.zones()
    if table.find(zones, zone) then return end
    local next_zones = table.clone(zones)
    table.insert(next_zones, zone)
    config.set("clock.zones", next_zones)
end

function M.remove_zone(zone: string)
    local next_zones = {}
    for _, z in M.zones() do
        if z ~= zone then table.insert(next_zones, z) end
    end
    config.set("clock.zones", next_zones)
end

-- Every zone the system knows, asked once, for the field that adds one.
local known = g.signal({})
local known_asked = false

function M.ask_known()
    if known_asked then return end
    known_asked = true
    local list = {}
    g.process {
        command = { "timedatectl", "list-timezones" },
        on_line = function(line: string)
            if string.match(line, "%S") then table.insert(list, line) end
        end,
        on_exit = function() known.value = list end,
    }
end
function M.known(): { string } return known.value end

-- ---- Ringing ---------------------------------------------------------------------

local function ring(title: string, body: string)
    -- The alarm is its own sound, so the notification brings none.
    g.process { command = { "notify-send", "-u", "critical", "-a", "Bioma", "-i", "alarm-symbolic",
        "-h", "boolean:suppress-sound:true", title, body } }
    g.process { command = { "pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga" } }
end

-- ---- The timer -------------------------------------------------------------------

-- How long it runs, in seconds, and what is left of it.
local length = g.signal(config.get("clock.timer", 25 * 60))
local left = g.signal(g.untracked(function() return length.value end))
local running = g.signal(false)
-- Where it ends, as a moment on the wall clock: counting down by ticks would
-- drift, and a machine that slept through the end has to know it ended.
local ends_at = 0

local function describe(seconds: number): string
    local minutes = math.round(seconds / 60)
    if minutes < 60 then return if minutes == 1 then "One minute" else minutes .. " minutes" end
    local hours, rest = minutes // 60, minutes % 60
    return hours .. " h" .. (if rest ~= 0 then " " .. rest .. " min" else "")
end

local function current(signal: any): any return g.untracked(function() return signal.value end) end

local function tick()
    local remaining = math.max(0, ends_at - os.time())
    left.value = remaining
    if remaining == 0 and current(running) then
        running.value = false
        ring("Timer", describe(current(length)) .. " are up.")
        left.value = current(length)
    end
end

g.effect(function()
    if running.value then g.timer { every = 1, on_tick = tick } end
end)

function M.length(): number return length.value end
-- The wall-clock second it ends at, while it runs: what drains a ring
-- continuously rather than by its counted seconds.
function M.ends_at(): number return ends_at end
function M.left(): number return left.value end
function M.running(): boolean return running.value end
function M.paused(): boolean
    return not running.value and left.value < length.value and left.value > 0
end
-- How much of it is left, for the dial on the clock.
function M.fraction_left(): number
    return if length.value > 0 then left.value / length.value else 0
end

function M.set_length(seconds: number)
    if current(running) then return end
    local value = math.clamp(math.round(seconds), 60, 24 * 3600)
    g.batch(function()
        length.value = value
        left.value = value
    end)
    config.set("clock.timer", value)
end

function M.start()
    if current(running) or current(left) <= 0 then return end
    ends_at = os.time() + current(left)
    running.value = true
    tick()
end

function M.pause()
    if not current(running) then return end
    tick()
    running.value = false
end

function M.reset()
    g.batch(function()
        running.value = false
        left.value = current(length)
    end)
end

-- ---- The alarm -------------------------------------------------------------------

function M.alarm(): { hour: number, minute: number, on: boolean }
    return config.get("clock.alarm", { hour = 7, minute = 30, on = false })
end

function M.set_alarm(hour: number, minute: number, on: boolean)
    config.set("clock.alarm", { hour = ((hour % 24) + 24) % 24, minute = ((minute % 60) + 60) % 60, on = on })
end

-- At each minute's turn, read whole: at an alarm on the hour, the hour and
-- the minute change together.
local function at_minute()
    local alarm = g.untracked(M.alarm)
    local now = os.date("*t") :: any
    if alarm and alarm.on and now.hour == alarm.hour and now.min == alarm.minute then
        ring("Alarm", string.format("It is %02d:%02d.", alarm.hour, alarm.minute))
    end
end

local function next_minute()
    local now = os.time()
    g.after(60 - now % 60 + 0.05, function()
        at_minute()
        next_minute()
    end)
end
next_minute()


return M
