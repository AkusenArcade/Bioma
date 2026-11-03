--!strict
-- When the session locks (services/Locker.qml at 8ed8892). The lock screen
-- is not here: it is a process of its own, started through `scripts/lock`,
-- which stands guard over it. This only decides when (Akusen, 2026-09-23):
--
--   - when asked: `loginctl lock-session`, the System cell's LOCK, anything
--     on the machine, which logind turns into a `Lock` signal on this
--     session. Mod+Alt+L runs the script directly;
--   - before a suspend: a delay inhibitor holds it back until the lock has
--     covered the screens;
--   - after a time idle, `lock.idle_minutes`.
--
-- Bioma on Genoma alone runs it (M6 step 7a, `start`); beside Quickshell,
-- Quickshell's Locker does, and this is not started.
local g = require("@genoma")
local idle = require("@genoma/idle")
local config = require("core/config")
local paths = require("core/paths")
local timing = require("core/timing")

local M = {}

local function idle_minutes(): number return config.get("lock.idle_minutes", 10) end
local function before_sleep(): boolean return config.get("lock.before_sleep", true) end

-- Whether the session is locked, as logind has it: the lock screen sets it
-- once every screen is covered.
local locked = g.signal(false)
function M.locked(): boolean return locked.value end

-- In a session of its own, so it outlives the shell: a lock that died with
-- the shell's next reload would unlock the session.
function M.lock()
    g.process { command = { "setsid", "-f", paths.script("lock") } }
end

-- ---- This session -----------------------------------------------------------

local session = g.signal("")
local function ask_locked()
    local path = g.untracked(function() return session.value end)
    if path == "" then return end
    g.dbus.get {
        bus = "system",
        destination = "org.freedesktop.login1",
        path = path,
        interface = "org.freedesktop.login1.Session",
        property = "LockedHint",
        reply = function(ok: boolean, value: any) if ok then locked.value = value == true end end,
    }
end

-- ---- Before a suspend --------------------------------------------------------
--
-- Held while nothing is happening and let go once the lock is up: logind
-- waits for a delay inhibitor (its InhibitDelayMaxSec, five seconds by
-- default) before it suspends. What holds it is `cat` reading the shell's
-- end of a pipe: when the shell goes, however it goes, so does the
-- inhibitor.
local inhibitor: any = nil
local function hold(on: boolean)
    if on == (inhibitor ~= nil) then return end
    if on then
        inhibitor = g.process {
            command = { "systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Bioma",
                "--why=Locking the screen before sleep", "cat" },
            on_exit = function() inhibitor = nil end,
        }
    else
        local p = inhibitor
        inhibitor = nil
        p:close_input()
    end
end

local guard: any = nil
local function going_to_sleep()
    if not g.untracked(before_sleep) then return end
    if g.untracked(function() return locked.value end) then
        hold(false)
        return
    end
    M.lock()
    -- If the lock never comes up, the suspend is not held for ever: logind
    -- would stop waiting anyway, and the guard in `scripts/lock` has put
    -- hyprlock on the screens by then.
    if guard then guard:stop() end
    guard = g.after(timing.seconds.settle, function()
        guard = nil
        hold(false)
    end)
end
local function woke_up()
    if guard then guard:stop() end
    guard = nil
    if g.untracked(before_sleep) then hold(true) end
end

-- ---- Starting -----------------------------------------------------------------

local started = false
function M.start()
    if started then return end
    started = true
    g.dbus.call {
        bus = "system",
        destination = "org.freedesktop.login1",
        path = "/org/freedesktop/login1",
        interface = "org.freedesktop.login1.Manager",
        method = "GetSession",
        signature = "s",
        args = { "auto" },
        reply = function(ok: boolean, path: any)
            if not ok or type(path) ~= "string" then
                print("Bioma: logind does not know this session — lock on request and before sleep are off")
                return
            end
            session.value = path
            g.dbus.watch {
                bus = "system",
                sender = "org.freedesktop.login1",
                path = path,
                interface = "org.freedesktop.login1.Session",
                member = "Lock",
                on_signal = function() M.lock() end,
            }
            g.dbus.watch {
                bus = "system",
                sender = "org.freedesktop.login1",
                path = path,
                interface = "org.freedesktop.DBus.Properties",
                member = "PropertiesChanged",
                on_signal = function() ask_locked() end,
            }
            g.dbus.watch {
                bus = "system",
                sender = "org.freedesktop.login1",
                path = "/org/freedesktop/login1",
                interface = "org.freedesktop.login1.Manager",
                member = "PrepareForSleep",
                on_signal = function(starting: any) if starting == true then going_to_sleep() else woke_up() end end,
            }
            ask_locked()
            if g.untracked(before_sleep) then hold(true) end
        end,
    }
    -- The setting moved: the inhibitor follows it.
    local was_before_sleep: boolean? = nil
    g.watch(before_sleep, function(on: boolean)
        local first = was_before_sleep == nil
        was_before_sleep = on
        if first or g.untracked(function() return session.value end) == "" then return end
        if on and guard == nil then hold(true) elseif not on then hold(false) end
    end)
    -- The lock is up while a suspend waits: it may go ahead.
    g.watch(function() return locked.value end, function(on: boolean)
        if on and guard then
            guard:stop()
            guard = nil
            hold(false)
        end
    end)

    -- After a time idle, respecting inhibitors: a video playing full screen
    -- is not somebody who walked away.
    g.effect(function()
        local minutes = idle_minutes()
        g.untracked(function() idle:watch("lock", if minutes > 0 then math.max(1, minutes) * 60 else 0) end)
    end)
    local was_idle = false
    g.watch(function() return idle:is_idle("lock") end, function(on: boolean)
        local began = on and not was_idle
        was_idle = on
        if began and not g.untracked(function() return locked.value end) then M.lock() end
    end)

end

return M
