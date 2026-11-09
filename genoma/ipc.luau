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

    -- niri's settings, as the Niri page writes them; a thing is named by
    -- `file#start#kind`, start counted from 0.
    local function item(id: string): any
        local file, start, kind = string.match(id or "", "^(.*)#(%d+)#([%w%-]+)$")
        if not file then return nil end
        for _, i in g.untracked(require("services/niri_config").items) do
            if i.file == file and i.start - 1 == tonumber(start) and i.kind == kind then return i end
        end
        return nil
    end
    local function number(text: string?): number return tonumber(text or "") or 0 end
    g.ipc("niri", {
        gaps = function(value: string): string require("services/niri_settings").set_gaps(number(value)) return value end,
        focusRing = function(value: string): string require("services/niri_settings").set_focus_ring(number(value)) return value end,
        followsMouse = function(on: string): string
            require("services/niri_settings").set_follows_mouse(on == "true")
            return if on == "true" then "on" else "off"
        end,
        addWorkspace = function(): string require("services/niri_settings").add_workspace() return "added" end,
        renameWorkspace = function(id: string, name: string): string
            local ws = item(id)
            if not ws then return "no such workspace" end
            require("services/niri_settings").rename_workspace(ws, name)
            return name
        end,
        workspaceOutput = function(id: string, output: string?): string
            local ws = item(id)
            if not ws then return "no such workspace" end
            require("services/niri_settings").set_workspace_output(ws, output or "")
            return output or ""
        end,
        moveWorkspace = function(id: string, delta: string): string
            local ws = item(id)
            if not ws then return "no such workspace" end
            require("services/niri_settings").move_workspace(ws, number(delta))
            return "moved"
        end,
        removeWorkspace = function(id: string): string
            local ws = item(id)
            if not ws then return "no such workspace" end
            require("services/niri_settings").remove_workspace(ws)
            return "removed"
        end,
        -- `command` is a JSON list of words, or with `sh` one shell line.
        addStartup = function(command: string, sh: string): string
            if sh == "true" then
                require("services/niri_settings").add_startup(command, true)
                return "added"
            end
            local ok, words = pcall(g.parse_json, command)
            if not ok or type(words) ~= "table" then return "not JSON" end
            require("services/niri_settings").add_startup(words, false)
            return "added"
        end,
        startupOn = function(id: string, on: string): string
            local line = item(id)
            if not line then return "no such line" end
            require("services/niri_settings").set_startup_on(line, on == "true")
            return if on == "true" then "on" else "off"
        end,
        removeStartup = function(id: string): string
            local line = item(id)
            if not line then return "no such line" end
            require("services/niri_settings").remove_startup(line)
            return "removed"
        end,
        ruleOpacity = function(id: string, value: string): string
            local rule = item(id)
            if not rule then return "no such rule" end
            local v = number(value)
            require("services/niri_settings").set_rule_opacity(rule, if v < 0 then nil else v)
            return value
        end,
        ruleWidth = function(id: string, fraction: string): string
            local rule = item(id)
            if not rule then return "no such rule" end
            local v = number(fraction)
            require("services/niri_settings").set_rule_width(rule, if v < 0 then nil else v)
            return fraction
        end,
        ruleWorkspace = function(id: string, name: string?): string
            local rule = item(id)
            if not rule then return "no such rule" end
            require("services/niri_settings").set_rule_workspace(rule, if name and name ~= "" then name else nil)
            return name or ""
        end,
        removeRule = function(id: string): string
            local rule = item(id)
            if not rule then return "no such rule" end
            require("services/niri_settings").remove_rule(rule)
            return "removed"
        end,
        addRule = function(app_id: string): string require("services/niri_settings").add_rule(app_id or "") return app_id or "" end,
        -- Every window's opacity in focus and out of it, 0 to 1; "clear" gives
        -- it back to niri's own rules.
        focusedOpacity = function(value: string): string
            if value == "clear" then require("services/niri_settings").clear_opacity() return "cleared" end
            require("services/niri_settings").set_focused_opacity(number(value))
            return value
        end,
        unfocusedOpacity = function(value: string): string
            if value == "clear" then require("services/niri_settings").clear_opacity() return "cleared" end
            require("services/niri_settings").set_unfocused_opacity(number(value))
            return value
        end,
        error = function(): string return g.untracked(require("services/niri_settings").error) end,
    })

    -- The monitors' layout, as the Monitors page writes it.
    g.ipc("monitors", {
        place = function(positions: string): string
            local ok, parsed = pcall(g.parse_json, positions)
            if not ok or type(parsed) ~= "table" then return "not JSON" end
            require("services/monitors").place(parsed)
            return "placing"
        end,
        power = function(name: string, on: string): string
            local yes = on == "true"
            return if require("services/monitors").power(name, yes) then (if yes then "on" else "off")
                else "the last monitor stays on"
        end,
        primary = function(name: string?): string
            require("services/monitors").make_primary(name or "")
            return if name and name ~= "" then name else "none"
        end,
        vrr = function(name: string, mode: string): string require("services/monitors").set_vrr(name, mode) return mode end,
        games = function(on: string): string
            require("services/monitors").set_games(on == "true")
            return if on == "true" then "on" else "off"
        end,
        error = function(): string return g.untracked(require("services/monitors").error) end,
    })

    -- niri's keybinds, as the Keybinds page writes them.
    g.ipc("keybinds", {
        rekey = function(id: string, key: string): string
            local keybinds = require("services/keybinds")
            for _, b in g.untracked(keybinds.binds) do
                if b.id == id then
                    keybinds.rekey(b, key)
                    return key
                end
            end
            return "no such bind"
        end,
        remove = function(id: string): string
            local keybinds = require("services/keybinds")
            for _, b in g.untracked(keybinds.binds) do
                if b.id == id then
                    keybinds.remove(b)
                    return "removed"
                end
            end
            return "no such bind"
        end,
        add = function(key: string, action: string, title: string?): string
            local ok, parsed = pcall(g.parse_json, action)
            if not ok or type(parsed) ~= "table" then return "not JSON" end
            require("services/keybinds").add(key, { name = parsed.name, args = parsed.args or {} }, title or "")
            return key
        end,
        error = function(): string return g.untracked(require("services/keybinds").error) end,
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

    g.ipc("brightness", {
        up = function(step: string?): string
            local brightness = require("services/brightness")
            local n = tonumber(step or "") or 0
            brightness.step((if n > 0 then n else 5) / 100)
            return math.round(g.untracked(brightness.brightness) * 100) .. "%"
        end,
        down = function(step: string?): string
            local brightness = require("services/brightness")
            local n = tonumber(step or "") or 0
            brightness.step(-(if n > 0 then n else 5) / 100)
            return math.round(g.untracked(brightness.brightness) * 100) .. "%"
        end,
        set = function(percent: string): string
            local brightness = require("services/brightness")
            brightness.set(math.max(0, tonumber(percent) or 0) / 100)
            return math.round(g.untracked(brightness.brightness) * 100) .. "%"
        end,
    })

    -- The Structure page's layouts.
    g.ipc("presets", {
        list = function(): string
            local presets = require("core/presets")
            local active = g.untracked(presets.active)
            local out = {}
            for _, preset in g.untracked(presets.all) do
                table.insert(out, (if preset.name == active then "* " else "  ") .. preset.name)
            end
            return table.concat(out, "\n")
        end,
        current = function(): string
            local presets = require("core/presets")
            local active = g.untracked(presets.active)
            if active ~= "" then return active .. (if g.untracked(presets.changed) then " (changed)" else "") end
            return if g.untracked(presets.empty) then "(empty)" else "(unsaved)"
        end,
        apply = function(name: string): string
            return if require("core/presets").apply(name or "") then "applied " .. name else 'no preset "' .. tostring(name) .. '"'
        end,
        save = function(name: string): string
            local trimmed = string.match(name or "", "^%s*(.-)%s*$") or ""
            return if require("core/presets").save_as(name or "") then "saved " .. trimmed else "a preset needs a name"
        end,
        create = function(): string
            require("core/presets").blank()
            return "empty"
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

    -- Focus mode (core/focus_mode.luau): the membranes folded, the
    -- organisms away, the cells only when asked for.
    local function focus_status(): string
        return if g.untracked(require("core/focus_mode").active) then "on" else "off"
    end
    g.ipc("focus", {
        on = function(): string require("core/focus_mode").on() return focus_status() end,
        off = function(): string require("core/focus_mode").off() return focus_status() end,
        toggle = function(): string require("core/focus_mode").toggle() return focus_status() end,
        status = focus_status,
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
