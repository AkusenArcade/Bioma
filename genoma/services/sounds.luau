--!strict
-- Bioma's sound effects (services/Sounds.qml at 8ed8892): the desktop
-- appearing after login, a notification, a cell opening and closing, a
-- measured value turning red.
--
-- The sounds are Bioma's own, synthesised by tools/sounds into
-- assets/sounds. Each is played by a `pw-play` of its own, which costs
-- nothing between sounds and starts under the first frame of a cell
-- growing. One switch per kind of event on the Sounds page
-- (`sounds.login`, `.notifications`, `.cells`, `.alerts`) and one volume
-- for all of them, under the system's (Akusen, 2026-10-17).
--
-- Bioma on Genoma alone plays them (M6 step 7a); beside Quickshell, `play`
-- is handed to Quickshell, and the events are its own cells'.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local runtime = require("core/runtime")
local theme = require("core/theme")

local M = {}

local function volume(): number return math.clamp(config.get("sounds.volume", 0.6), 0, 1) end
local function enabled(kind: string): boolean return config.get("sounds." .. kind, true) == true end

-- ---- Playing ---------------------------------------------------------------------

-- When each sound last started.
local last: { [string]: number } = {}
local function since(name: string): number return g.now() - (last[name] or 0) end

local function file(path: string)
    g.process { command = { "setsid", "-f", "pw-play", "--media-role", "Notification",
        "--volume", tostring(g.untracked(volume)), "-P", '{ application.name = "Bioma" }', path } }
end

function M.play(name: string)
    if not g.untracked(runtime.alone) then
        g.process { command = { paths.script("ipc"), "sounds", "play", name } }
        return
    end
    if g.untracked(volume) <= 0 then return end
    -- The same sound twice inside a breath is one sound.
    if since(name) < 0.06 then return end
    last[name] = g.now()
    file(paths.root .. "/assets/sounds/" .. name .. ".wav")
end

-- A cell's panel opening or closing. Two cells trading places would play
-- both: the opening is what was asked for, so a close waits a breath and
-- is dropped if an opening comes inside it, before or after.
local closing: any = nil
local CLOSE_WAIT = 0.09
function M.cell(open: boolean)
    if not g.untracked(runtime.alone) or not g.untracked(function() return enabled("cells") end) then return end
    if open then
        if closing then closing:stop() end
        closing = nil
        M.play("open")
    elseif since("open") > CLOSE_WAIT then
        if closing then closing:stop() end
        closing = g.after(CLOSE_WAIT, function()
            closing = nil
            M.play("close")
        end)
    end
end

-- ---- Notifications -----------------------------------------------------------------
--
-- When one appears. The freedesktop hints decide whose sound it is:
-- `suppress-sound` means the sender plays its own or wants none;
-- `sound-file` and `sound-name` are the sender's own, which the server
-- plays. Only a notification with none of them gets Bioma's.

-- A sound named from the freedesktop sound theme, where the specification
-- says it lives. Nothing found is silence: the sender asked for its own.
local function named(name: string)
    local home = g.env("XDG_DATA_HOME") or ((g.env("HOME") or "") .. "/.local/share")
    local command = { "setsid", "-f", "sh", "-c",
        "v=$1; shift; for f; do [ -f \"$f\" ] && exec pw-play --media-role Notification --volume \"$v\" -P '{ application.name = \"Bioma\" }' \"$f\"; done",
        "sound", tostring(g.untracked(volume)) }
    local dirs = { home }
    for dir in string.gmatch(g.env("XDG_DATA_DIRS") or "/usr/local/share:/usr/share", "[^:]+") do table.insert(dirs, dir) end
    for _, dir in dirs do
        for _, extension in { "oga", "ogg", "wav" } do
            table.insert(command, dir .. "/sounds/freedesktop/stereo/" .. name .. "." .. extension)
        end
    end
    g.process { command = command }
end

function M.notification(n: any)
    if not g.untracked(runtime.alone) then return end
    if not g.untracked(function() return enabled("notifications") end) or g.untracked(volume) <= 0 then return end
    if type(n) ~= "table" or n.suppress_sound == true then return end
    local path = string.gsub(tostring(n.sound_file or ""), "^file://", "")
    if path ~= "" then
        file(path)
        return
    end
    local name = tostring(n.sound_name or "")
    if name ~= "" and string.match(name, "^[%w%._%-]+$") then
        named(name)
        return
    end
    M.play("notification")
end

-- ---- Login ------------------------------------------------------------------------
--
-- Once per session, when the desktop first appears: the shell restarts far
-- more often than anybody logs in, so the session remembers it was greeted
-- in a mark in its runtime directory, which goes when the session ends.
local function greet()
    g.process {
        command = { "sh", "-c", 'm="${XDG_RUNTIME_DIR:-/tmp}/bioma-greeted"; [ -e "$m" ] && exit 1; : > "$m"' },
        on_exit = function(code: number)
            if code == 0 and g.untracked(function() return enabled("login") end) then M.play("login") end
        end,
    }
end

-- ---- Values turning red ----------------------------------------------------------
--
-- A measured value crossing into the alert colour: the load at which a
-- vitals ring turns red, and a battery that far gone while it runs on
-- itself. It sounds on the way in, once; a value that falls back has to rest
-- under the threshold for `sounds.alert_gap` seconds before it can sound
-- again. Watched here rather than in the cells, so two vitals cells do not
-- sound twice and a value is watched with no cell showing it.
local cooled: { [string]: number } = {}
local armed = false
local function redden(key: string, red: boolean)
    if not red then
        cooled[key] = g.now()
        return
    end
    if not armed or not g.untracked(function() return enabled("alerts") end) then return end
    local gap = math.max(0, config.get("sounds.alert_gap", 300))
    if cooled[key] and g.now() - cooled[key] < gap then return end
    -- Two values turning red together are one alarm.
    if since("alert") < 1.5 then return end
    M.play("alert")
end

local started = false
function M.start()
    if started then return end
    started = true
    greet()
    local monitor = require("services/system_monitor")
    local alert = theme.threshold_alert
    local reds = {
        cpu = function() return monitor.cpu_percent() / 100 >= alert end,
        ram = function() return monitor.ram_percent() / 100 >= alert end,
        gpu = function() return monitor.gpu_present() and monitor.gpu_percent() / 100 >= alert end,
        battery = function()
            return monitor.has_battery() and monitor.discharging() and 1 - monitor.battery_level() >= alert
        end,
    }
    for key, red in reds do
        local before: boolean? = nil
        g.watch(red, function(on: boolean)
            local was = before
            before = on
            if was ~= nil and was ~= on then redden(key, on) end
        end)
    end
    -- Nothing sounds while the session starts: the first samples are the
    -- shell loading itself, and a login that begins with an alarm is a
    -- poor welcome.
    g.after(15, function() armed = true end)
end

return M
