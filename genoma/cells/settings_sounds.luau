--!strict
-- Settings → Sounds (cells/settings/SettingsSounds.qml at 11bb81e): one
-- switch for each kind of event, and one volume for all of them.
--
-- Laid out as the Session page is, in wells with a line in Spectral saying
-- what the current choice does. A sound switched on plays once, and the
-- volume plays the notification when the hand stops: a sound is chosen by
-- hearing it, not by reading its name. The sounds are Quickshell's to play
-- while the two run side by side (`qs ipc call sounds play`), but for the
-- volume's preview, played here at the volume just chosen (as Sounds.qml
-- plays a file): Quickshell would play it at whatever it last read. The
-- switches and the volume are written to the shared configuration.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local theme = require("core/theme")
local timing = require("core/timing")
local switch = require("components/switch")
local slider = require("components/slider")
local page = require("components/page")

local M = {}

local function play(name: string) require("services/sounds").play(name) end

-- `t`: metrics(), width(), height().
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, inner, line, section = p.factor, p.inner, p.line, p.section

    -- While the hand moves the volume is the page's own, and written once
    -- it stops: a write per step rewrote the whole override at every
    -- motion, and a quick drag fell behind the pointer.
    local live = g.signal(nil :: number?)
    local function volume(): number return live.value or config.get("sounds.volume", 0.6) end

    local function event(label: string, kind: string, sound: string, when_on: () -> string, when_off: string): any
        local function on(): boolean return config.get("sounds." .. kind, true) == true end
        return section(label, switch.new {
            on = on,
            factor = f,
            on_toggle = function(value: boolean)
                config.set("sounds." .. kind, value)
                if value then play(sound) end
            end,
        }, { line(function() return if on() then when_on() else when_off end) })
    end

    -- Heard when the hand stops, not at every step of the way.
    local preview: any = nil
    local function moved(fraction: number)
        local v = math.round(fraction * 20) / 20
        if v == g.untracked(volume) then return end
        live.value = v
        if preview then preview:stop() end
        preview = g.after(timing.seconds.debounce, function()
            preview = nil
            local chosen = g.untracked(function() return live.value end)
            if chosen == nil then return end
            config.set("sounds.volume", chosen)
            live.value = nil
            if chosen > 0 then
                g.process { command = {
                    "pw-play", "--media-role", "Notification", "--volume", tostring(chosen),
                    "-P", '{ application.name = "Bioma" }', paths.root .. "/assets/sounds/notification.wav",
                } }
            end
        end)
    end

    local function alerts_on(): string
        local past = math.round(theme.threshold_alert * 100)
        local rest = math.round(math.max(0, config.get("sounds.alert_gap", 300)) / 60)
        return "A low note when a value turns red: the processor, memory or graphics card past " .. past
            .. "%, or the battery under " .. (100 - past) .. "% while it runs on itself. "
            .. (if rest > 0 then "Once, until it has rested " .. rest .. (if rest == 1 then " minute." else " minutes.")
                else "Every time.")
    end

    return p.column {
        section("VOLUME", nil, {
            slider.new { width = inner, factor = f, value = volume, dimmed = function() return false end, on_move = moved },
            line(function()
                local v = volume()
                if v <= 0 then return "Silent: no sound plays, whatever is switched on below." end
                return "The effects play at " .. math.round(v * 100) .. "% of the system volume."
            end),
        }),
        event("LOGIN", "login", "login",
            function() return "A chord when the desktop first appears after logging in. Restarting the shell does not play it again." end,
            "The desktop appears in silence."),
        event("NOTIFICATIONS", "notifications", "notification",
            function() return "Two droplets when a notification appears. One that brings its own sound plays that instead, so the application stays recognisable." end,
            "Notifications appear in silence, their own sounds included."),
        event("CELLS", "cells", "open",
            function() return "A bubble rising when a cell opens, and falling when it closes." end,
            "Cells open and close in silence."),
        event("ALERTS", "alerts", "alert", alerts_on, "Values turn red in silence."),
    }
end

return M
