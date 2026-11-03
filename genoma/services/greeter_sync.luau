--!strict
-- Keeps the greeter's copy of the desktop current (services/GreeterSync.qml
-- at 8ed8892).
--
-- The greeter runs as another user before anyone is logged in, from a copy
-- in /var/lib/bioma-greeter (scripts/greeter-sync). This watches what the
-- copy is made of (the configuration, the wallpaper's state, the palette,
-- niri's outputs, keyboard and cursor, the person's picture) and runs the
-- sync a moment after any of it changes, and once when the shell starts,
-- so a new version of Bioma reaches the greeter too. Without the directory
-- there is no greeter to keep: the sync finds nowhere to write and stops.
--
-- Bioma on Genoma alone runs it (M6 step 7a, `start`); beside Quickshell,
-- Quickshell's does.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local theme = require("core/theme")
local timing = require("core/timing")

local M = {}

local home = g.env("HOME") or ""
local config_home = g.env("XDG_CONFIG_HOME") or (home .. "/.config")
local function directory(): string
    return g.env("BIOMA_GREETER_DIR") or config.get("greeter.directory", "/var/lib/bioma-greeter")
end

-- Whether the last sync went through: false with the directory missing,
-- the ordinary state of a machine without Bioma's greeter.
local synced = g.signal(false)
function M.synced(): boolean return synced.value end

local running, again = false, false
local function sync()
    if running then
        again = true
        return
    end
    running = true
    g.process {
        command = { paths.script("greeter-sync"), g.untracked(directory) },
        on_exit = function(code: number)
            running = false
            synced.value = code == 0
            if again then
                again = false
                sync()
            end
        end,
    }
end

-- Changes come in bursts (a new wallpaper rewrites its state and then the
-- palette), and one copy after the last of them is enough.
local settle: any = nil
local function schedule()
    if settle then settle:stop() end
    settle = g.after(timing.seconds.settle, function()
        settle = nil
        sync()
    end)
end

local started = false
function M.start()
    if started then return end
    started = true
    local watched = {
        config_home .. "/bioma/override.json",
        config_home .. "/bioma/wallpaper.json",
        config_home .. "/bioma/generated/palette.json",
        config_home .. "/niri/outputs.kdl",
        config_home .. "/niri/bioma-keyboard.kdl",
        config_home .. "/niri/bioma-cursor.kdl",
        "/var/lib/AccountsService/icons/" .. (g.env("USER") or ""),
    }
    for _, path in watched do
        local file = g.file { path = path }
        local first = true
        g.watch(function() return file.text end, function()
            if first then first = false return end
            schedule()
        end)
    end
    -- The palette on screen, when it is one of the person's: edited, it
    -- changes no other file. Followed to whichever one is chosen.
    g.effect(function()
        local path = theme.user_palettes .. "/" .. theme.manual_palette() .. ".json"
        local file = g.file { path = path }
        local first = true
        g.watch(function() return file.text end, function()
            if first then first = false return end
            schedule()
        end)
    end)
    schedule()
end

return M
