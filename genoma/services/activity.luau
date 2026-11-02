--!strict
-- The time spent at this machine, day by day (services/Activity.qml at
-- 2cafc17): minutes present, kept in ~/.config/bioma/activity.json, which
-- the growth rings organism draws.
--
-- Present is neither idle nor locked. Idle is what the compositor says
-- through ext-idle-notify (`@genoma/idle`), no input for
-- `activity.idle_minutes`, and it respects inhibitors, as the lock does: a
-- video playing full screen is somebody watching, not somebody gone. The
-- minutes that passed before idle was declared were counted as they went,
-- and are taken back when it is. Locked is logind's LockedHint.
--
-- Only one of the two shells may write the file: whichever draws the growth
-- rings. While a Quickshell rings organism is configured, Bioma on
-- Quickshell counts and this one only reads, and read again when it changes
-- (genoma/PORT.md, "Who acts on the desktop"). Nothing is counted, and
-- nothing written about the user, while no rings organism holds it.
local g = require("@genoma")
local config = require("core/config")

local M = {}

local home = g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")
local PATH = home .. "/bioma/activity.json"

local holders = g.signal(0)
function M.hold(on: boolean)
    holders.value = math.max(0, g.untracked(function() return holders.value end) + (if on then 1 else -1))
end

-- Whether this shell counts: it holds the service and no rings organism of
-- Quickshell's would count too.
local function counting(): boolean
    if holders.value <= 0 then return false end
    for _, entry in config.get("organisms", {}) do
        if type(entry) == "table" and entry.type == "rings" and entry.runtime ~= "genoma" then return false end
    end
    return true
end

-- Read from the load, not from inside the effect below: made there, it
-- would be the effect's, and go with its next run.
local file = g.file { path = PATH }
local days = g.signal({} :: { [string]: number })
local loaded = g.signal(false)
-- What this shell wrote last: reading it back is not news.
local written: string? = nil
g.effect(function()
    if holders.value <= 0 then return end
    local text = file.text
    g.untracked(function()
        if text ~= nil and text == written then return end
        local ok, data = pcall(g.parse_json, text or "")
        days.value = if ok and type(data) == "table" and type(data.days) == "table" then data.days else {}
        loaded.value = true
    end)
end)

function M.days(): { [string]: number } return days.value end
function M.loaded(): boolean return loaded.value end
function M.date_key(seconds: number): string return os.date("%Y-%m-%d", seconds) :: string end
function M.today(): string
    local _ = require("@genoma/clock").hour
    return M.date_key(os.time())
end
function M.today_minutes(): number return days.value[M.today()] or 0 end

local function add(minutes: number)
    if minutes == 0 then return end
    local next = table.clone(g.untracked(function() return days.value end))
    local today = M.date_key(os.time())
    next[today] = math.max(0, (next[today] or 0) + minutes)
    days.value = next
    written = g.to_json({ days = next }, true)
    file:write(written)
end

-- ---- Presence ---------------------------------------------------------------------

local idle = require("@genoma/idle")
local function idle_minutes(): number return math.max(1, config.get("activity.idle_minutes", 5)) end
g.effect(function()
    local wanted = if counting() then idle_minutes() * 60 else 0
    g.untracked(function() idle:after(wanted) end)
end)

-- logind's word on the session: the lock screen sets it.
local locked = g.signal(false)
local function ask_locked()
    g.dbus.get {
        bus = "system",
        destination = "org.freedesktop.login1",
        path = "/org/freedesktop/login1/session/auto",
        interface = "org.freedesktop.login1.Session",
        property = "LockedHint",
        reply = function(ok: boolean, value: any) locked.value = ok and value == true end,
    }
end
g.effect(function()
    if not counting() then return end
    g.untracked(function()
        g.dbus.watch {
            bus = "system",
            sender = "org.freedesktop.login1",
            interface = "org.freedesktop.DBus.Properties",
            member = "PropertiesChanged",
            on_signal = function() ask_locked() end,
        }
        ask_locked()
    end)
end)

local function present(): boolean return counting() and loaded.value and not idle.idle and not locked.value end
function M.present(): boolean return present() end

-- Minutes counted since presence last began: what idle may take back.
local streak = 0
-- When somebody last came back to the machine (the end of idle, an unlock,
-- the shell starting), in seconds; 0 while nobody is.
local since = g.signal(0)
g.watch(present, function(on: boolean)
    streak = 0
    since.value = if on then os.time() else 0
end)
g.watch(function() return idle.idle end, function(now_idle: boolean)
    if now_idle and g.untracked(counting) then
        -- The quiet minutes before idle was declared were not presence.
        add(-math.min(streak, g.untracked(idle_minutes)))
        streak = 0
    end
end)

g.effect(function()
    if not present() then return end
    g.untracked(function()
        local last = os.time()
        g.timer {
            every = 60,
            on_tick = function()
                -- A suspend that did not lock stops the beat without telling
                -- anyone: a tick that comes much later than a minute was a
                -- sleep, and somebody waking the machine is coming back.
                local now = os.time()
                local slept = now - last > 150
                last = now
                if slept then
                    streak = 0
                    since.value = now
                    return
                end
                streak += 1
                add(1)
            end,
        }
    end)
end)

-- Minutes since then, turning with the clock.
function M.session_minutes(): number
    local s = since.value
    if s <= 0 then return 0 end
    local _ = require("@genoma/clock").minute
    return math.max(0, (os.time() - s) // 60)
end

-- Whether this shell knows the session: it counts it.
function M.counting(): boolean return counting() end

return M
