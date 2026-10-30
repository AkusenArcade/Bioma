--!strict
-- Settings → Sounds (cells/settings/SettingsSounds.qml at 11bb81e): one
-- switch for each kind of event, and one volume for all of them.
--
-- Laid out as the Session page is, in wells with a line in Spectral saying
-- what the current choice does. A sound switched on plays once, and the
-- volume plays the notification when the hand stops: a sound is chosen by
-- hearing it, not by reading its name. The sounds are Quickshell's to play
-- while the two run side by side (`qs ipc call sounds play`); the switches
-- and the volume are written to the shared configuration.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local paths = require("core/paths")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local switch = require("components/switch")
local slider = require("components/slider")

local M = {}

local function play(name: string)
    g.process { command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "sounds", "play", name } }
end

-- `t`: metrics(), width(), height().
function M.new(t: { [string]: any }): any
    local function m(): any return t.metrics() end
    local function f(): number return m().factor end
    local function inset(): number return 14 * f() end
    local function header(): number return 28 * f() end
    local function inner(): number return t.width() - inset() * 2 end

    local function volume(): number return config.get("sounds.volume", 0.6) end

    local function line(text: () -> string): any
        return g.text {
            text = text,
            color = theme.text,
            font = typography.expressive,
            size = function() return m().font_secondary end,
            max_width = inner,
            wrap = true,
        }
    end

    -- A well: its label, perhaps its control on the same line, then what it
    -- means.
    local function section(label: string, trailing: any?, body: { any }): any
        local well: { [any]: any } = {
            width = t.width,
            padding = inset,
            direction = "column",
            align = "start",
            gap = function() return 6 * f() end,
            radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
            fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            g.box {
                width = inner,
                height = header,
                direction = "row",
                align = "center",
                justify = "between",
                g.text {
                    text = label,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tracking = typography.label_tracking,
                },
                trailing or g.box {},
            },
        }
        for _, node in body do table.insert(well, node) end
        return g.capsule(well)
    end

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
        config.set("sounds.volume", math.round(fraction * 20) / 20)
        if preview then preview:stop() end
        preview = g.after(timing.seconds.debounce, function()
            preview = nil
            play("notification")
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

    return g.box {
        width = t.width,
        direction = "column",
        align = "start",
        gap = function() return 10 * f() end,
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
