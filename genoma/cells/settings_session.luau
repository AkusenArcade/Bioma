--!strict
-- Settings → Session (cells/settings/SettingsSession.qml at 11bb81e): when
-- the session locks, and the machine sleeps, by itself.
--
-- Settings writing straight into the override, which the lock and the
-- session are bound to: a choice here is the behaviour changing, not a
-- preview of it. Locking or suspending on request is not here, because it
-- is not a setting: the key and the System cell always do it.
--
-- The idle times are a handful of stops rather than a slider: nobody means
-- thirteen minutes, and a figure that travels under the finger is a figure
-- that has to be read.
--
-- The last well is the power profile following the plug, there only on a
-- machine with a battery and a daemon to ask: elsewhere there is no plug
-- to follow. Choosing a profile by hand stays in the System cell.
local config = require("core/config")
local theme = require("core/theme")
local page = require("components/page")
local segmented = require("components/segmented")
local switch = require("components/switch")
local power = require("services/power")
local session = require("services/session")
local system = require("services/system_monitor")

local M = {}

-- `t`: metrics(), width(), height().
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end

    local function idle_minutes(): number return config.get("lock.idle_minutes", 10) end
    local function before_sleep(): boolean return config.get("lock.before_sleep", true) == true end
    local function sleep_minutes(): number return config.get("sleep.idle_minutes", 0) end

    local function stops(options: { { any } }, current: () -> number, path: string): any
        local list = {}
        for _, o in options do table.insert(list, { key = tostring(o[1]), label = o[2] }) end
        return segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            options = function() return list end,
            current = function() return tostring(current()) end,
            on_choose = function(key: string) config.set(path, tonumber(key)) end,
        }
    end

    -- A profile setting's row: what it is for, and the choice beside it.
    local function profile_row(label: string, path: string): any
        local function value(): string return config.get(path, "keep") end
        return p.row(label, segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            button_padding = function() return 10 * f() end,
            options = function()
                return {
                    { key = "keep", label = "Keep" },
                    { key = "saver", label = "Saver" },
                    { key = "balanced", label = "Balanced" },
                    { key = "performance", label = "Performance", dimmed = not power.performance_available() },
                }
            end,
            current = value,
            on_choose = function(key: string) config.set(path, key) end,
        })
    end

    local function sleeps(): boolean return session.available("suspend") end

    return p.column {
        -- Minutes without input before the session locks. `0` is never.
        section("LOCK AFTER", nil, {
            stops({ { 0, "Never" }, { 5, "5 min" }, { 10, "10 min" }, { 15, "15 min" }, { 30, "30 min" } },
                idle_minutes, "lock.idle_minutes"),
            line(function()
                local n = idle_minutes()
                return if n > 0 then "After " .. n .. " minutes without input, the session locks."
                    else "The session never locks by itself. The key and the System cell still do."
            end),
        }),
        -- Minutes without input before the machine suspends. `0`, the
        -- default, is never. Longer stops than the lock's: sleeping is the
        -- heavier of the two, and it comes after.
        section("SLEEP AFTER", nil, {
            stops({ { 0, "Never" }, { 15, "15 min" }, { 30, "30 min" }, { 60, "1 h" }, { 120, "2 h" } },
                sleep_minutes, "sleep.idle_minutes"),
            line(function()
                local n = sleep_minutes()
                if n <= 0 then return "The machine never sleeps by itself. The System cell still suspends it." end
                if not sleeps() then
                    return "There is no suspend command, so nothing happens. It is session.suspend in the configuration."
                end
                local after = if n >= 60 then (n / 60) .. (if n == 60 then " hour" else " hours") else n .. " minutes"
                return "After " .. after .. " without input, the machine suspends. A video playing keeps it awake."
            end, function()
                return if sleep_minutes() > 0 and not sleeps() then theme.alert() else theme.text()
            end),
        }),
        -- Before a suspend, so the machine never wakes on the desktop it
        -- went to sleep with.
        section("BEFORE SLEEP", switch.new {
            on = before_sleep,
            factor = f,
            on_toggle = function(value: boolean) config.set("lock.before_sleep", value) end,
        }, {
            line(function()
                return if before_sleep() then "The session locks before the machine suspends, so it wakes locked."
                    else "The machine suspends as it is, and wakes on the open desktop."
            end),
        }),
        -- The profile the machine switches to when the plug changes.
        section("POWER PROFILE", nil, {
            profile_row("ON BATTERY", "power.on_battery"),
            profile_row("PLUGGED IN", "power.on_mains"),
            line(function()
                local battery = config.get("power.on_battery", "keep")
                local mains = config.get("power.on_mains", "keep")
                if battery == "keep" and mains == "keep" then
                    return "The profile is left alone, on battery and plugged in. It is chosen in the System cell."
                end
                local unplugged = if battery == "keep" then "On battery the profile is left alone"
                    else "On battery the machine switches to " .. battery
                local plugged = if mains == "keep" then "plugged in, it is left alone" else "plugged in, to " .. mains
                return unplugged .. "; " .. plugged .. ". A profile chosen by hand holds until the plug next changes."
            end),
        }, function() return power.present() and system.has_battery() end),
    }
end

return M
