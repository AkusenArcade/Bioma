--!strict
-- What Bioma on Genoma answers from outside, as `shell.qml`'s IpcHandlers
-- answer on Quickshell: the same targets, functions and replies, so a
-- keybind reaches whichever runtime runs through `scripts/ipc` (M6 step 7a).
-- `cell`, `organisms` and `setup` are answered in shell.luau, beside what
-- they act on.
--
--     scripts/ipc <target> <function> [argument…]
local g = require("@genoma")
local config = require("core/config")

local M = {}

-- The output a call means: the one niri has focused.
local function focused(): string?
    local niri = require("services/niri")
    local name = g.untracked(niri.focused_output)
    return if name ~= "" then name else nil
end

function M.register()
    g.ipc("actions", {
        run = function(name: string): string
            local actions = require("services/actions")
            for _, macro in g.untracked(actions.macros) do
                if macro.name == name then
                    actions.run(name)
                    return "running " .. name
                end
            end
            return 'no quick action "' .. tostring(name) .. '"'
        end,
        list = function(): string
            local actions = require("services/actions")
            local names = {}
            for _, macro in g.untracked(actions.macros) do table.insert(names, macro.name) end
            return table.concat(names, "\n")
        end,
        ring = function(): string
            local focus = require("structure/focus")
            return if focus.invoke("actions", focused()) then "toggled actions" else "no ring"
        end,
        write = function(): string
            require("cells/settings").open_on("actions")
            local focus = require("structure/focus")
            return if focus.invoke("settings", focused()) then "settings on actions" else "no settings"
        end,
    })

    g.ipc("audio", {
        up = function(step: string?): string
            local audio = require("services/audio")
            local n = tonumber(step or "") or 0
            audio.step_volume(if n > 0 then n / 100 else config.get("audio.step", 0.05))
            return g.untracked(audio.volume_percent) .. "%"
        end,
        down = function(step: string?): string
            local audio = require("services/audio")
            local n = tonumber(step or "") or 0
            audio.step_volume(-(if n > 0 then n / 100 else config.get("audio.step", 0.05)))
            return g.untracked(audio.volume_percent) .. "%"
        end,
        set = function(percent: string): string
            local audio = require("services/audio")
            audio.set_volume(math.max(0, tonumber(percent) or 0) / 100)
            return g.untracked(audio.volume_percent) .. "%"
        end,
        mute = function(): string
            local audio = require("services/audio")
            audio.toggle_mute()
            return if g.untracked(audio.muted) then "muted" else "audible"
        end,
        micMute = function(): string
            local audio = require("services/audio")
            audio.toggle_input_mute()
            return if g.untracked(audio.input_muted) then "muted" else "audible"
        end,
    })

    -- What the clipboard keeps (`hash`, as history.json names it).
    g.ipc("clipboard", {
        remove = function(hash: string): string
            local clipboard = require("services/clipboard")
            for _, e in g.untracked(clipboard.entries) do
                if tostring(e.hash) == hash then
                    clipboard.remove(e)
                    return "removed"
                end
            end
            return "no entry"
        end,
        clear = function(): string
            require("services/clipboard").clear()
            return "cleared"
        end,
    })

    g.ipc("looks", {
        icons = function(id: string): string
            local looks = require("services/looks")
            looks.set_icons(id or "")
            return g.untracked(looks.icon_theme)
        end,
        cursor = function(id: string, size: string?): string
            local looks = require("services/looks")
            looks.set_cursor(id or "", tonumber(size or "") or 0)
            return g.untracked(looks.cursor_theme) .. " " .. g.untracked(looks.cursor_size)
        end,
        template = function(id: string, on: string): string
            local templates = require("services/templates")
            templates.set_on(id or "", on == "true")
            return if g.untracked(function() return templates.is_on(id) end) then "on" else "off"
        end,
        -- The glass's strength, a step written into niri's configuration.
        blur = function(strength: string): string
            require("services/looks").set_blur(tonumber(strength) or 0)
            return tostring(g.untracked(require("core/metrics").blur_strength))
        end,
    })

    g.ipc("media", {
        toggle = function(): string
            local media = require("services/media")
            media.play_pause()
            return if g.untracked(media.playing) then "playing" else "paused"
        end,
        next = function(): string require("services/media").next() return "next" end,
        previous = function(): string require("services/media").previous() return "previous" end,
        stop = function(): string require("services/media").pause() return "paused" end,
    })

    -- A sound by name, at the volume set: `play alert`.
    g.ipc("sounds", {
        play = function(name: string): string
            require("services/sounds").play(name or "")
            return "playing " .. tostring(name) .. " at " .. tostring(config.get("sounds.volume", 0.6))
        end,
    })

    g.ipc("timer", {
        start = function(minutes: string?): string
            local time = require("services/time")
            local n = tonumber(minutes or "") or 0
            if n > 0 then
                time.reset()
                time.set_length(n * 60)
            end
            time.start()
            return if g.untracked(time.running) then math.floor(g.untracked(time.left) / 60 + 0.5) .. " min" else "stopped"
        end,
        toggle = function(): string
            local time = require("services/time")
            if g.untracked(time.running) then time.pause() else time.start() end
            return if g.untracked(time.running) then "running" else "paused"
        end,
        stop = function(): string
            require("services/time").reset()
            return "stopped"
        end,
    })

    local function performance_status(): string
        local performance = require("core/performance")
        return if g.untracked(performance.active) then "on, " .. g.untracked(performance.reason) else "off"
    end
    g.ipc("performance", {
        on = function(): string require("core/performance").on() return performance_status() end,
        off = function(): string require("core/performance").off() return performance_status() end,
        toggle = function(): string require("core/performance").toggle() return performance_status() end,
        status = performance_status,
    })

    g.ipc("capture", {
        region = function(): string
            local capture = require("services/capture")
            capture.pending_action = "still"
            capture.select_region()
            return "region"
        end,
        screen = function(): string
            local capture = require("services/capture")
            local output = focused()
            capture.pending_action = "still"
            capture.capture_output(output)
            return output or ""
        end,
        window = function(): string
            local capture = require("services/capture")
            local niri = require("services/niri")
            local window = g.untracked(niri.focused_window)
            capture.pending_action = "still"
            capture.capture_window(if window then window.id else 0)
            return g.untracked(niri.focused_title)
        end,
        colour = function(): string
            require("services/capture").pick_colour()
            return "picking"
        end,
        stop = function(): string
            local capture = require("services/capture")
            if not g.untracked(capture.recording) then return "not recording" end
            capture.stop_recording()
            return "stopped"
        end,
        dictate = function(): string
            local dictation = require("services/dictation")
            if g.untracked(dictation.listening) then
                dictation.stop()
                return "transcribing"
            end
            if g.untracked(dictation.active) then return "busy" end
            local capture = require("services/capture")
            if g.untracked(capture.recording) or g.untracked(capture.pending_video) ~= "" then
                return "a recording is in progress"
            end
            if not g.untracked(dictation.available) then return "whisper-cli or its model is missing" end
            dictation.start()
            return "listening"
        end,
        cancel = function(): string
            local dictation = require("services/dictation")
            if not g.untracked(dictation.active) then return "not dictating" end
            dictation.cancel()
            return "cancelled"
        end,
    })
end

return M
