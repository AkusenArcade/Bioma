--!strict
-- The first run (services/Setup.qml at 2cafc17): what a new user meets the
-- first time the shell starts. See docs/design/SETUP.md.
--
-- Setup is the settings cell in another form, steps where the categories
-- stand, so this holds what the steps know and do, and the cell draws it
-- (cells/settings.luau). One service, because the settings cell exists once
-- per monitor and the walk-through is one.
--
-- It opens by itself when the shell starts with no override at all;
-- `setup.pending` is written at once, so the walk-through survives its own
-- first write, and Escape means *later*. DONE and SKIP write `setup.done`,
-- and it opens again only when asked for: SETUP on the Structure page.
--
-- What it finds out comes from scripts that only read: `install --report`,
-- `polkit-agent report`, `greeter-setup status` and `setup-scan list`,
-- asked when it opens and again after each action. What it does to the
-- machine (niri's configuration, the login screen, another shell stopped,
-- a service enabled, the polkit agent handed over) is Bioma on Quickshell's
-- to do while the two run side by side (`qs ipc call setup …`, genoma/
-- PORT.md, "Who acts on the desktop"), and asked of it.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local runtime = require("core/runtime")
local presets = require("core/presets")
local timing = require("core/timing")
local monitors = require("services/monitors")
local keybinds = require("services/keybinds")
local focus = require("structure/focus")

local M = {}

-- ---- Where it is ----------------------------------------------------------------

-- Kept across reloads: choosing a layout rewrites the membranes, every
-- surface is built again, and a walk-through held in this load's signals
-- closed half done with all it had chosen (Akusen, 2026-11-04). A table
-- does not outlive its load, so what each step chose is kept as JSON.
local active = g.state("setup.active", false)
local output = g.state("setup.output", "")
local step = g.state("setup.step", "welcome")
local kept_outcomes = g.state("setup.outcomes", "{}")
local outcomes = g.signal((function(): { [string]: string }
    local ok, t = pcall(g.parse_json, g.untracked(function() return kept_outcomes.value end))
    return if ok and type(t) == "table" then t else {}
end)())
g.watch(function() return outcomes.value end, function(t: { [string]: string })
    kept_outcomes.value = g.to_json(t)
end)

function M.active(): boolean return active.value end
function M.output(): string return output.value end
function M.step(): string return step.value end
function M.done(): boolean return config.get("setup.done", false) ~= false end
function M.pending(): boolean return config.get("setup.pending", false) == true end

-- ---- What the machine has ---------------------------------------------------------

local report_read = g.signal(false)
local required = g.signal({} :: { any })
local optional = g.signal({} :: { any })
local disabled = g.signal({} :: { string })
local niri_state = g.signal({} :: { [string]: string })
local niri_config = g.signal("")
local other_agent = g.signal(true)
local polkit_sources = g.signal({} :: { any })
local manager = g.signal("")
local bioma_greeter = g.signal(false)
local greeter_read = g.signal(false)
local conflicts = g.signal({} :: { any })

function M.report_read(): boolean return report_read.value end
function M.required(): { any } return required.value end
function M.optional(): { any } return optional.value end
function M.disabled(): { string } return disabled.value end
function M.niri_state(): { [string]: string } return niri_state.value end
function M.niri_config(): string return niri_config.value end
function M.conflicts(): { any } return conflicts.value end
function M.polkit_sources(): { any } return polkit_sources.value end
function M.manager(): string return manager.value end
function M.bioma_greeter(): boolean return bioma_greeter.value end
function M.greeter_read(): boolean return greeter_read.value end

function M.missing(): { any }
    local out = {}
    for _, entry in required.value do if not entry.ok then table.insert(out, entry) end end
    return out
end

-- Bioma's own agent is wanted unless it was switched off. An agent is
-- there when another program runs one, or Bioma's own registered.
function M.polkit_wanted(): boolean return config.get("polkit.agent", true) ~= false end
function M.polkit_agent(): boolean
    local ok, polkit = pcall(require, "services/polkit")
    return other_agent.value or (ok and (polkit.registered() or polkit.held_elsewhere()))
end

-- Another agent started at login races Bioma's at every start: named by
-- its program.
function M.polkit_rival(): string
    if not M.polkit_wanted() or #polkit_sources.value == 0 then return "" end
    local name = polkit_sources.value[1].name
    local short = string.gsub(string.gsub(name, "%-authentication%-agent%-1$", ""), "%-agent$", "")
    return if short ~= "" then short else name
end

function M.system_wanted(): boolean
    return report_read.value and (#M.missing() > 0 or #disabled.value > 0 or not M.polkit_agent() or M.polkit_rival() ~= "")
end
function M.niri_set(): boolean
    local s = niri_state.value
    return s.binds == "ok" and s.include == "ok" and s["include-binds"] == "ok"
end
function M.autostart_set(): boolean return niri_state.value.autostart == "ok" end

function M.manager_name(): string
    local unit = string.gsub(manager.value, "%.service$", "")
    if unit == "none" or unit == "" then return "TEXT LOGIN" end
    return string.upper(unit)
end

-- ---- The steps -------------------------------------------------------------------
--
-- CONFLICTS and SYSTEM exist when they have something to say.
local steps = g.computed(function(): { any }
    local out = {
        { key = "welcome", label = "WELCOME", glyph = "mark", hint = "what this is", width = 520 },
        { key = "layout", label = "LAYOUT", glyph = "structure", hint = "where everything goes", width = 640 },
        { key = "look", label = "LOOK", glyph = "theme", hint = "palette and wallpaper", width = 520 },
        { key = "niri", label = "NIRI", glyph = "window", hint = "keys and autostart", width = 520 },
        { key = "login", label = "LOGIN", glyph = "lock", hint = "the login screen", width = 520 },
    }
    if #conflicts.value > 0 then
        table.insert(out, { key = "conflicts", label = "CONFLICTS", glyph = "bell", hint = "another shell is running", width = 640 })
    end
    if M.system_wanted() then
        table.insert(out, { key = "system", label = "SYSTEM", glyph = "screen", hint = "what is missing", width = 600 })
    end
    table.insert(out, { key = "keys", label = "KEYS", glyph = "keyboard", hint = "where to start", width = 520 })
    return out
end)
function M.steps(): { any } return steps.value end

function M.step_index(): number
    for i, s in steps.value do
        if s.key == step.value then return i end
    end
    return 1
end
function M.last(): boolean return M.step_index() == #steps.value end

-- A step that stops existing while it is shown (the last conflict stopped)
-- hands over to the one that came after it.
-- Kept too: a reload reads the report again, and until it has, a step that
-- depends on it (SYSTEM) is not in the list yet.
local shown_index = g.state("setup.shown_index", 1)
g.watch(function() return steps.value end, function(list: { any })
    local now = g.untracked(function() return step.value end)
    for i, s in list do
        if s.key == now then
            shown_index.value = i
            return
        end
    end
    if g.untracked(function() return report_read.value end) or not g.untracked(function() return active.value end) then
        step.value = list[math.min(g.untracked(function() return shown_index.value end), #list)].key
    end
end)

-- What each visited step chose, said in its capsule's line.
function M.outcome(key: string): string return outcomes.value[key] or "" end
function M.note(key: string, line: string)
    local now = g.untracked(function() return outcomes.value end)
    if now[key] == line then return end
    local next = table.clone(now)
    next[key] = line
    outcomes.value = next
end

-- ---- Acting, through Quickshell -------------------------------------------------

local progress = g.signal({} :: { [string]: any })
function M.progress(): { [string]: any } return progress.value end
function M.niri_error(): string return progress.value.niriError or "" end
function M.login_error(): string return progress.value.loginError or "" end
function M.niri_busy(): boolean return progress.value.niriBusy == true end
function M.login_busy(): boolean return progress.value.loginBusy == true end
function M.handing_over(): boolean return progress.value.handingOver == true end
function M.hand_over_error(): string return progress.value.handOverError or "" end
function M.restart_at_end(): boolean return progress.value.restartAtEnd == true end
function M.stopping(pid: string): boolean return table.find(progress.value.stopping or {}, pid) ~= nil end
function M.stop_error(pid: string): string return (progress.value.stopErrors or {})[pid] or "" end
function M.enabling(unit: string): boolean return table.find(progress.value.enabling or {}, unit) ~= nil end
function M.enable_error(unit: string): string return (progress.value.enableErrors or {})[unit] or "" end

local refresh: () -> ()
local function quickshell(args: { string }, on_line: ((string) -> ())?, on_exit: (() -> ())?)
    local command = { paths.script("ipc"), "setup" }
    for _, a in args do table.insert(command, a) end
    g.process { command = command, on_line = on_line, on_exit = on_exit }
end

-- Asked again while something is under way: the action is Quickshell's
-- script, and only it knows when it has finished. Nothing is asked once
-- nothing is.
local watching = false
local function busy(p: { [string]: any }): boolean
    return p.niriBusy == true or p.loginBusy == true or p.handingOver == true
        or #(p.stopping or {}) > 0 or #(p.enabling or {}) > 0
end
local function follow()
    if watching then return end
    watching = true
    local function ask()
        local text = ""
        quickshell({ "progress" }, function(line: string) text ..= line end, function()
            local ok, p = pcall(g.parse_json, text)
            if ok and type(p) == "table" then progress.value = p end
            if ok and type(p) == "table" and busy(p) then
                g.after(0.5, ask)
            else
                watching = false
                refresh()
            end
        end)
    end
    g.after(0.3, ask)
end
local function act(args: { string })
    quickshell(args, nil, follow)
end

-- ---- Acting itself, once the switch is made (Setup.qml at 8ed8892) -----------

local function alone(): boolean return g.untracked(runtime.alone) end
-- One field of the progress at a time; tables copied, as a signal holds them.
local function mark(key: string, value: any)
    local next = table.clone(g.untracked(function() return progress.value end))
    next[key] = value
    progress.value = next
end
local function mark_in(key: string, item: string, value: any)
    local next_list = table.clone(g.untracked(function() return progress.value end)[key] or {})
    if type(value) == "boolean" then
        local at = table.find(next_list, item)
        if value and not at then table.insert(next_list, item) end
        if not value and at then table.remove(next_list, at) end
    else
        next_list[item] = value
    end
    mark(key, next_list)
end
-- A program run for the setup: its error lines kept, its end answered.
local function run(command: { string }, done: (number, { string }) -> ())
    local said = {}
    g.process {
        command = command,
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number) done(code, said) end,
    }
end
local function last_line(lines: { string }, otherwise: string): string
    for i = #lines, 1, -1 do
        local l = string.match(lines[i], "^%s*(.-)%s*$") or ""
        if l ~= "" then return l end
    end
    return otherwise
end

function M.set_up_niri(autostart: boolean)
    if not alone() then act({ "niri", tostring(autostart) }) return end
    if g.untracked(M.niri_busy) then return end
    mark("niriError", "")
    mark("niriBusy", true)
    local command = { paths.script("install"), "--niri-only" }
    if autostart then table.insert(command, "--autostart") end
    run(command, function(code: number, said: { string })
        mark("niriBusy", false)
        if code ~= 0 then
            -- The first line niri refused, under the script's own sentence.
            local first = nil
            for _, line in said do
                local l = string.match(line, "^%s*(.-)%s*$") or ""
                if l ~= "" and string.sub(l, 1, 12) ~= "niri refused" then first = l break end
            end
            mark("niriError", first or "niri refused the configuration.")
        end
        refresh()
    end)
end

function M.set_greeter(enable: boolean)
    if enable == g.untracked(function() return bioma_greeter.value end) then return end
    if not alone() then act({ "greeter", tostring(enable) }) return end
    if g.untracked(M.login_busy) then return end
    mark("loginError", "")
    mark("loginBusy", true)
    run({ "pkexec", paths.script("greeter-setup"), if enable then "enable" else "disable" }, function(code: number, said: { string })
        mark("loginBusy", false)
        -- pkexec: 126 when the password was not given, 127 when nothing
        -- could ask for it.
        if code == 126 then
            mark("loginError", "The password was not given, so nothing changed.")
        elseif code == 127 then
            mark("loginError", "Nothing could ask for the password. Run the command below in a terminal.")
        elseif code ~= 0 then
            mark("loginError", last_line(said, "It did not complete."))
        end
        refresh()
    end)
end

function M.stop(conflict: any)
    if not alone() then act({ "stop", conflict.pid, conflict.name, conflict.from }) return end
    if g.untracked(function() return M.stopping(conflict.pid) end) then return end
    mark_in("stopping", conflict.pid, true)
    if conflict.what == "notifications" then mark("restartAtEnd", true) end
    run({ paths.script("setup-scan"), "stop", conflict.pid, conflict.name, conflict.from }, function(code: number, said: { string })
        mark_in("stopping", conflict.pid, false)
        mark_in("stopErrors", conflict.pid, if code ~= 0 then last_line(said, "It could not be stopped.") else nil)
        refresh()
    end)
end

function M.enable_service(unit: string)
    if not alone() then act({ "enable", unit }) return end
    if g.untracked(function() return M.enabling(unit) end) then return end
    mark_in("enabling", unit, true)
    run({ "pkexec", "systemctl", "enable", "--now", unit }, function(code: number)
        mark_in("enabling", unit, false)
        mark_in("enableErrors", unit, if code == 126 then "not given" elseif code == 127 then "no agent"
            elseif code ~= 0 then "failed" else nil)
        refresh()
    end)
end

function M.use_bioma_agent()
    if not alone() then act({ "takeover" }) return end
    if g.untracked(M.handing_over) then return end
    mark("handingOver", true)
    mark("handOverError", "")
    run({ paths.script("polkit-agent"), "takeover" }, function(_: number, said: { string })
        local reason = ""
        for _, line in said do
            if string.sub(line, 1, 6) == "error\t" then reason = string.sub(line, 7) break end
        end
        mark("handingOver", false)
        mark("handOverError", reason)
        -- The other agent has let go of the session: Bioma's asks again.
        require("services/polkit").retry()
        refresh()
    end)
end
function M.keep_other_agent() config.set("polkit.agent", false) end

-- The command a person runs when nothing can ask for the password.
function M.login_command(enable: boolean): string
    return "pkexec " .. paths.script("greeter-setup") .. " " .. (if enable then "enable" else "disable")
end

-- The one command that installs what is missing: pacman for the
-- repositories, paru for the AUR. Bioma never runs a package manager.
function M.install_command(): string
    local repo, aur = {}, {}
    for _, entry in M.missing() do
        local package = entry.package or ""
        local name = string.gsub(package, "^AUR ", "")
        if name ~= "" and not string.find(name, " ") then
            table.insert(if string.sub(package, 1, 4) == "AUR " then aur else repo, name)
        end
    end
    local parts = {}
    if #repo > 0 then table.insert(parts, "sudo pacman -S --needed " .. table.concat(repo, " ")) end
    if #aur > 0 then table.insert(parts, "paru -S --needed " .. table.concat(aur, " ")) end
    return table.concat(parts, " && ")
end

M.dictation_command = "paru -S whisper-cpp ggml-vulkan whisper.cpp-model-large-v3-turbo-q5_0 python-evdev"
function M.dictation_missing(): boolean
    for _, entry in optional.value do
        if not entry.ok and (entry.name == "whisper-cli" or entry.name == "model") then return true end
    end
    return false
end

function M.copy(text: string) g.process { command = { "wl-copy", "--", text } } end

-- ---- Reading ---------------------------------------------------------------------

local function collect(command: { string }, done: ({ string }) -> ())
    local lines = {}
    g.process {
        command = command,
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function() done(lines) end,
    }
end

refresh = function()
    collect({ paths.script("install"), "--report" }, function(lines: { string })
        local req, opt, off, niri, agent = {}, {}, {}, {}, true
        for _, line in lines do
            local f = string.split(line, "\t")
            if f[1] == "required" or f[1] == "optional" then
                table.insert(if f[1] == "required" then req else opt,
                    { ok = f[2] == "ok", name = f[3] or "", what = f[4] or "", package = f[5] or "" })
            elseif f[1] == "service" and f[2] == "disabled" then
                table.insert(off, f[3])
            elseif f[1] == "niri" then
                niri[f[2]] = f[3]
                if f[2] == "config" and f[4] then niri_config.value = f[4] end
            elseif f[1] == "polkit" then
                agent = f[3] == "ok"
            end
        end
        g.batch(function()
            required.value = req
            optional.value = opt
            disabled.value = off
            niri_state.value = niri
            other_agent.value = agent
            report_read.value = true
        end)
    end)
    collect({ paths.script("polkit-agent"), "report" }, function(lines: { string })
        local found = {}
        for _, line in lines do
            local f = string.split(line, "\t")
            if #f >= 3 then
                table.insert(found, { kind = f[1], name = f[2], where = table.concat(f, ":", 3) })
            end
        end
        polkit_sources.value = found
    end)
    collect({ paths.script("greeter-setup"), "status" }, function(lines: { string })
        for _, line in lines do
            local f = string.split(line, "\t")
            if f[1] == "manager" then manager.value = f[2] or "" end
            if f[1] == "greeter" then bioma_greeter.value = f[2] == "bioma" end
        end
        greeter_read.value = true
    end)
    collect({ paths.script("setup-scan"), "list" }, function(lines: { string })
        local found = {}
        for _, line in lines do
            local f = string.split(line, "\t")
            if f[1] and f[1] ~= "" then
                table.insert(found, { pid = f[1], name = f[2] or "", what = f[3] or "", from = if f[4] and f[4] ~= "" then f[4] else "none" })
            end
        end
        conflicts.value = found
    end)
end
M.refresh = refresh
-- A walk-through still under way when this load began (a layout was just
-- chosen): what it reports on is read again, as opening it would.
if g.untracked(function() return active.value end) then refresh() end

-- ---- Moving through it -----------------------------------------------------------

function M.go(key: string) step.value = key end
function M.next()
    local i = g.untracked(M.step_index)
    local list = g.untracked(M.steps)
    if i < #list then step.value = list[i + 1].key end
end
function M.back()
    local i = g.untracked(M.step_index)
    local list = g.untracked(M.steps)
    if i > 1 then step.value = list[i - 1].key end
end

-- `muted`, `active` (wants attention) or `alert` (an action failed): the
-- colour of a step's glyph when it is not the chosen one.
function M.state_of(key: string): string
    if key == "niri" and M.niri_error() ~= "" then return "alert" end
    if key == "login" and M.login_error() ~= "" then return "alert" end
    if key == "conflicts" and #conflicts.value > 0 then return "active" end
    if key == "system" and (#M.missing() > 0 or #disabled.value > 0 or not M.polkit_agent() or M.polkit_rival() ~= "") then
        return "active"
    end
    return "muted"
end

-- ---- Opening and closing -----------------------------------------------------------

local function primary_output(): string
    local p = monitors.primary()
    if p ~= "" then return p end
    local screens = g.outputs()
    return if #screens > 0 then screens[1].name else ""
end

-- Asked for: the settings cell of that output, in its setup form.
function M.open(on: string?)
    local screen = if on and on ~= "" then on else primary_output()
    if not g.untracked(function() return active.value end) then
        step.value = g.untracked(M.steps)[1].key
        refresh()
    end
    g.batch(function()
        output.value = screen
        active.value = true
    end)
    local c = focus.cell_for("settings", screen)
    if not c or not g.untracked(function() return c.open.value end) then focus.invoke("settings", screen) end
end

-- From the beginning, on purpose: the Structure page's SETUP, after it was
-- done. What the last run chose and what failed in it are forgotten.
function M.restart(on: string?)
    if g.untracked(function() return active.value end) then return end
    outcomes.value = {}
    progress.value = {}
    M.open(on)
end

-- The settings cell closed under it (Escape, a press outside): later.
local finishing = false
function M.closed()
    if finishing then return end
    active.value = false
end

-- DONE and SKIP. Skipping changes nothing that was not already changed.
function M.finish()
    finishing = true
    config.set_many({ { "setup.done", true }, { "setup.pending", false } })
    local c = focus.open_cell()
    if c and c.domain == "settings" then focus.dismiss() end
    active.value = false
    finishing = false
    -- A notification daemon was stopped: the server registered before the
    -- name was free, and only a new start claims it.
    if g.untracked(M.restart_at_end) then
        g.process { command = { "setsid", "-f", paths.script("shell"), "restart" } }
    end
end

-- ---- The first start --------------------------------------------------------------
--
-- Decided once, when both layers have been read and the shipped presets are
-- known: a fresh account gets Complete (the base layout with its organisms)
-- and the walk-through, once the shell has settled.
local decided = false
g.effect(function()
    if decided then return end
    local base = config.base_values()
    if next(base) == nil or presets.find("Complete") == nil then return end
    decided = true
    g.untracked(function()
        if not config.override_exists() then
            print("Bioma: first start — the setup opens")
            presets.apply("Complete")
            config.set("setup.pending", true)
        end
        g.after(timing.seconds.settle, function()
            if M.pending() and not M.done() and not active.value then M.open(primary_output()) end
        end)
    end)
end)

-- ---- The keys ------------------------------------------------------------------------
--
-- The seven to know, by the title niri's hotkey overlay shows them under,
-- so what is drawn is what is bound in the user's own file.
local KEY_LIST = {
    { "Bioma: launcher", "Applications, and files by name." },
    { "Bioma: settings", "This, and the whole layout." },
    { "Bioma: theme", "Palette and wallpaper." },
    { "Bioma: capture", "Screenshots, recordings, text from a region." },
    { "Bioma: vitals", "What the machine is doing." },
    { "Bioma: system", "Lock, sleep, log out, shut down." },
    { "Bioma: lock", "The lock screen." },
}
function M.keys(): { any }
    local out = {}
    for _, entry in KEY_LIST do
        local caps = {}
        for _, bind in keybinds.binds() do
            if not bind.shadowed and bind.props and bind.props["hotkey-overlay-title"] == entry[1] then caps = bind.caps end
        end
        table.insert(out, { caps = caps, line = entry[2], name = string.upper((string.gsub(entry[1], "^Bioma: ", ""))) })
    end
    return out
end

return M
