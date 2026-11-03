--!strict
-- Quick actions: macros somebody writes on the Settings page and runs from
-- the ring that comes to the pointer (services/Actions.qml at 11bb81e).
--
-- Bioma on Genoma alone runs a macro itself (M6 step 7a). Beside
-- Quickshell, running one is Quickshell's (genoma/PORT.md, "Who acts on the
-- desktop"): a step changes the volume, the settings, a monitor, and those
-- are its. So a chosen macro is handed to it by name, `actions run`,
-- exactly as a key of its own would hand it.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local runtime = require("core/runtime")
local apps = require("core/apps")

local M = {}

function M.macros(): { any }
    local list = config.get("actions.macros", {})
    local out = {}
    if type(list) ~= "table" then return out end
    for _, macro in list do
        if type(macro) == "table" and type(macro.name) == "string" then table.insert(out, macro) end
    end
    return out
end

-- As many as the ring holds, and as many as the page makes: one ring, not
-- pages of them (Akusen, 2026-10-24: "eight are enough"). A longer list
-- written by hand is kept, and the rest run from their key.
M.ring_size = 8

function M.ring(): { any }
    local out = {}
    for i, macro in M.macros() do
        if i > M.ring_size then break end
        table.insert(out, macro)
    end
    return out
end

-- Drawn for the actions, in the set's own grammar (docs/design/icons): what
-- a macro is for, not what it does.
M.icons = {
    "action-work", "action-game", "action-stream", "action-music", "action-relax", "action-focus",
    "action-night", "action-call", "action-code", "action-design", "action-home", "action-travel",
}
M.default_icon = "action-work"

function M.icon_of(macro: any): string
    local name = macro and macro.icon
    for _, icon in M.icons do
        if icon == name then return name end
    end
    return M.default_icon
end

M.icon_labels = {
    ["action-work"] = "Work", ["action-game"] = "Game", ["action-stream"] = "Stream", ["action-music"] = "Music",
    ["action-relax"] = "Relax", ["action-focus"] = "Focus", ["action-night"] = "Night", ["action-call"] = "Call",
    ["action-code"] = "Code", ["action-design"] = "Design", ["action-home"] = "Home", ["action-travel"] = "Travel",
}

-- The whole list, written as it is changed on the Settings page.
function M.write_list(list: { any }) config.set("actions.macros", list) end

-- ---- What a settings step may hold ----------------------------------------------
--
-- Two groups, the two pages a person thinks of as how the desktop looks and
-- how it sounds. Left out on purpose: the layout (a preset step does that),
-- the monitors and the keys (niri's files), and whatever is somebody's data
-- rather than a choice.
M.groups = {
    { key = "appearance", label = "APPEARANCE", paths = {
        "appearance.radius", "appearance.edge", "appearance.gap", "tissue.padding", "tissue.opacity",
        "cell.opacity", "cell.blur", "cell.blurStrength", "scrim.opacity", "timing.speed",
        "theme.source", "theme.palette", "theme.matugen" } },
    { key = "sounds", label = "SOUNDS", paths = {
        "sounds.volume", "sounds.login", "sounds.notifications", "sounds.cells", "sounds.alerts" } },
}
function M.group_of(key: string): any
    for _, group in M.groups do if group.key == key then return group end end
    return nil
end

-- The values as the shell reads them now, the default and the override
-- together: a value equal to the default left out would not be put back.
function M.capture(keys: { string }): { [string]: any }
    local values = {}
    for _, key in keys do
        local group = M.group_of(key)
        if group then
            for _, path in group.paths do
                local value = config.get(path, nil)
                if value ~= nil then values[path] = if type(value) == "table" then table.clone(value) else value end
            end
        end
    end
    return values
end

-- What a captured step holds, in a line.
function M.summary(step: any): string
    local values = step.values or {}
    local groups = step.groups or {}
    local parts = {}
    if table.find(groups, "appearance") then
        local matugen = values["theme.matugen"] or {}
        local scheme = string.gsub(string.gsub(matugen.scheme or "", "^scheme%-", ""), "%-", " ")
        table.insert(parts, if values["theme.source"] == "matugen"
            then "colours from the wallpaper" .. (if scheme ~= "" then " (" .. scheme .. ")" else "")
            else "palette " .. tostring(values["theme.palette"] or "default"))
        if values["appearance.radius"] ~= nil then table.insert(parts, "radius " .. tostring(values["appearance.radius"]) .. "%") end
        if values["cell.blur"] ~= nil then table.insert(parts, if values["cell.blur"] then "blur on" else "blur off") end
    end
    if table.find(groups, "sounds") then
        local on = 0
        for _, k in { "login", "notifications", "cells", "alerts" } do
            if values["sounds." .. k] ~= false then on += 1 end
        end
        table.insert(parts, if values["sounds.volume"] ~= nil
            then "sounds at " .. math.round(values["sounds.volume"] * 100) .. "%, " .. on .. " of 4 on"
            else on .. " of 4 sounds on")
    end
    if #parts == 0 then return "Nothing captured" end
    local line = table.concat(parts, ", ")
    return string.upper(string.sub(line, 1, 1)) .. string.sub(line, 2)
end

local function last_part(path: string?): string
    if not path or path == "" then return "" end
    local parts = string.split(path, "/")
    return parts[#parts]
end

-- The kinds of step: how the page names each, the step a press on it adds,
-- and the line it reads as. What each does is `RUNS`, below.
M.kinds = {
    launch = { label = "LAUNCH", fresh = function() return { type = "launch", app = "" } end,
        describe = function(step: any)
            local entry = if step.app and step.app ~= "" then apps.entry_for(step.app) else nil
            return if entry then entry.name elseif step.app and step.app ~= "" then step.app else "No application"
        end },
    open = { label = "OPEN FILE", fresh = function() return { type = "open", path = "" } end,
        describe = function(step: any) local n = last_part(step.path) return if n ~= "" then n else "No file" end },
    volume = { label = "VOLUME", fresh = function() return { type = "volume", percent = 50 } end,
        describe = function(step: any) return math.round(step.percent or 50) .. "%" end },
    brightness = { label = "BRIGHTNESS", fresh = function() return { type = "brightness", percent = 70 } end,
        describe = function(step: any) return math.round(step.percent or 70) .. "%" end },
    settings = { label = "SETTINGS",
        fresh = function() return { type = "settings", groups = g.array({ "appearance" }), values = M.capture({ "appearance" }) } end,
        describe = function(step: any) return M.summary(step) end },
    monitor = { label = "MONITOR", fresh = function() return { type = "monitor", output = "", on = false } end,
        describe = function(step: any)
            return (if step.output and step.output ~= "" then step.output else "No monitor") .. (if step.on then " on" else " off")
        end },
    preset = { label = "PRESET", fresh = function() return { type = "preset", name = "" } end,
        describe = function(step: any) return if step.name and step.name ~= "" then step.name else "No preset" end },
    wallpaper = { label = "WALLPAPER", fresh = function() return { type = "wallpaper", path = "" } end,
        describe = function(step: any) local n = last_part(step.path) return if n ~= "" then n else "No wallpaper" end },
    quiet = { label = "DO NOT DISTURB", fresh = function() return { type = "quiet", on = true } end,
        describe = function(step: any) return if step.on then "On" else "Off" end },
    profile = { label = "POWER PROFILE", fresh = function() return { type = "profile", profile = "balanced" } end,
        describe = function(step: any)
            local names = { saver = "Power saver", balanced = "Balanced", performance = "Performance" }
            return names[step.profile or ""] or "Balanced"
        end },
    performance = { label = "PERFORMANCE MODE", fresh = function() return { type = "performance", on = true } end,
        describe = function(step: any) return if step.on then "On" else "Off" end },
    timer = { label = "TIMER", fresh = function() return { type = "timer", minutes = 25 } end,
        describe = function(step: any) return math.round(step.minutes or 25) .. " min" end },
    wait = { label = "WAIT", fresh = function() return { type = "wait", seconds = 2 } end,
        describe = function(step: any) return tostring(step.seconds or 2) .. " s" end },
    command = { label = "COMMAND", fresh = function() return { type = "command", command = "" } end,
        describe = function(step: any) return if step.command and step.command ~= "" then step.command else "No command" end },
}
-- In the order the page offers them.
M.order = { "launch", "open", "volume", "brightness", "settings", "monitor", "preset", "wallpaper", "quiet", "profile", "performance", "timer", "wait", "command" }

function M.label_of(step: any): string
    local kind = step and M.kinds[step.type]
    return if kind then kind.label else "UNKNOWN"
end
function M.describe(step: any): string
    local kind = step and M.kinds[step.type]
    return if kind then kind.describe(step) else "Unknown step \"" .. tostring(step and step.type or "") .. "\""
end

local function ask(...: string)
    g.process { command = { paths.script("ipc"), "actions", ... } }
end

local function expand(path: string): string
    local home = g.env("HOME") or ""
    local out = string.gsub(path, "^~(/?)", home .. "%1")
    out = string.gsub(out, "^%$HOME(/?)", home .. "%1")
    return out
end

local function entry_of(id: string?): any
    if not id or id == "" then return nil end
    return apps.entry_for(id)
end

-- What each kind of step does. Nothing returned when it is done, a reason
-- when it could not be, or { until, timeout } when the next step waits.
local RUNS: { [string]: (any) -> any } = {
    launch = function(step: any): any
        local entry = entry_of(step.app)
        if not entry then return 'no application "' .. tostring(step.app or "") .. '"' end
        apps.run(entry, require("services/proxy").environment())
        return nil
    end,
    open = function(step: any): any
        if not step.path or step.path == "" then return "no file to open" end
        require("services/files").open(expand(step.path))
        return nil
    end,
    volume = function(step: any): any
        local audio = require("services/audio")
        if not g.untracked(audio.sink) then return "no output to set" end
        audio.set_volume(math.clamp(step.percent or 50, 0, 100) / 100)
        return nil
    end,
    brightness = function(step: any): any
        require("services/brightness").set(math.clamp(step.percent or 70, 1, 100) / 100)
        return nil
    end,
    settings = function(step: any): any
        local pairs_ = {}
        for path, value in step.values or {} do table.insert(pairs_, { path, value }) end
        if #pairs_ == 0 then return "nothing captured" end
        config.set_many(pairs_)
        return nil
    end,
    monitor = function(step: any): any
        local monitors = require("services/monitors")
        if not g.untracked(function() return monitors.output_of(step.output or "") end) then
            return 'no monitor "' .. tostring(step.output or "") .. '"'
        end
        if not monitors.power(step.output, step.on == true) then return tostring(step.output) .. " is the last monitor on" end
        return { until_ = function() return not monitors.switching() end, timeout = 5 }
    end,
    preset = function(step: any): any
        if not require("core/presets").apply(step.name or "") then return 'no preset "' .. tostring(step.name or "") .. '"' end
        return nil
    end,
    wallpaper = function(step: any): any
        if not step.path or step.path == "" then return "no wallpaper chosen" end
        require("services/wallpaper").set_path(step.path)
        return nil
    end,
    quiet = function(step: any): any
        require("services/notifications").set_quiet(step.on == true)
        return nil
    end,
    profile = function(step: any): any
        local power = require("services/power")
        if not g.untracked(power.present) then return "no power profiles on this machine" end
        power.set(step.profile or "balanced")
        return nil
    end,
    -- The shell's own mode, the same the key and the cell turn on; off by a
    -- step, it stays off while a game holds it, as off by hand does.
    performance = function(step: any): any
        local performance = require("core/performance")
        if step.on == true then performance.on() else performance.off() end
        return nil
    end,
    timer = function(step: any): any
        local time = require("services/time")
        local minutes = math.max(1, math.round(step.minutes or 25))
        time.reset()
        time.set_length(minutes * 60)
        time.start()
        return nil
    end,
    wait = function(step: any): any
        local until_at = g.now() + math.max(0, step.seconds or 2)
        return { until_ = function() return g.now() >= until_at end, timeout = 600 }
    end,
    -- A user service of its own, like an application: the command neither
    -- inherits the shell's nice nor dies with it.
    command = function(step: any): any
        local line = string.match(step.command or "", "^%s*(.-)%s*$") or ""
        if line == "" then return "no command" end
        g.process { command = { paths.script("launch"), "--id", "bioma-action", "--", "sh", "-c", step.command } }
        return nil
    end,
}

-- ---- Running -----------------------------------------------------------------

local running = g.signal("")
function M.running(): string return running.value end
local queue: { any } = {}
local index = 0
local holding: (() -> boolean)? = nil
local deadline = 0
local ticker: any = nil

local function stop_ticking()
    if ticker then ticker:stop() end
    ticker = nil
end

-- Said, because a macro that stops halfway looks exactly like one that did
-- all it was asked: the desktop is in some state either way.
local function fail(reason: string)
    local name = g.untracked(function() return running.value end)
    stop_ticking()
    holding = nil
    queue = {}
    running.value = ""
    print('Bioma: the quick action "' .. name .. '" stopped — ' .. reason)
    g.process { command = { "notify-send", "--app-name=Bioma", "--icon=dialog-warning", name .. " stopped",
        string.upper(string.sub(reason, 1, 1)) .. string.sub(reason, 2) } }
end

local advance: () -> ()
advance = function()
    if holding then
        if not (holding :: () -> boolean)() then
            if g.now() > deadline then fail("step " .. index .. " took too long") end
            return
        end
        holding = nil
        stop_ticking()
    end
    while index < #queue do
        index += 1
        local step = queue[index]
        local run = step and RUNS[step.type]
        if not run then
            fail("step " .. index .. " is of a kind this Bioma does not know")
            return
        end
        local ok, answer = pcall(run, step)
        if not ok then answer = tostring(answer) end
        if type(answer) == "string" then
            fail("step " .. index .. ": " .. answer)
            return
        end
        if type(answer) == "table" and answer.until_ then
            holding = answer.until_
            deadline = g.now() + (answer.timeout or 10)
            -- Only while a step waits: a pause, a monitor being switched.
            ticker = g.timer { every = 0.05, on_tick = advance }
            return
        end
    end
    queue = {}
    running.value = ""
end

-- A macro asked for while another runs takes its place: the second press is
-- the newer wish. True when there is one by that name.
function M.run(name: string): boolean
    if not g.untracked(runtime.alone) then
        ask("run", name)
        return true
    end
    local macro = nil
    for _, m in g.untracked(M.macros) do if m.name == name then macro = m end end
    if not macro then return false end
    print('Bioma: running the quick action "' .. name .. '"')
    stop_ticking()
    holding = nil
    queue = {}
    for _, step in macro.steps or {} do table.insert(queue, table.clone(step)) end
    index = 0
    running.value = name
    advance()
    return true
end

-- With nothing written yet, the ring's one capsule opens Settings on the
-- page where macros are written.
function M.write()
    if not g.untracked(runtime.alone) then ask("write") return end
    require("cells/settings").open_on("actions")
    local niri = require("services/niri")
    local focused = g.untracked(niri.focused_output)
    require("structure/focus").invoke("settings", if focused ~= "" then focused else nil)
end

return M
