--!strict
-- The monitors, as niri lays them out (services/Monitors.qml): where each
-- output is and what it runs, and which is primary. Moving them, switching
-- them on and off, variable refresh and making one primary are written into
-- niri's configuration once niri has validated them: by Bioma on Genoma
-- alone (M6 step 7a), by Bioma on Quickshell while the two run side by side
-- (genoma/PORT.md, "Who acts on the desktop").
--
-- Two sources, because neither says everything. niri answers where each
-- output is (`niri msg --json outputs`, asked again whenever its
-- configuration changes, and with every load, which a change of screens
-- brings), and the configuration says what was asked for: the `output`
-- sections, and which one is focused at startup.
local g = require("@genoma")
local niri_config = require("services/niri_config")
local kdl = require("services/niri_kdl")
local paths = require("core/paths")
local runtime = require("core/runtime")

local M = {}

-- What niri reports, one entry per output that is on; and the ones
-- connected but switched off, which it lists with no geometry.
local live = g.signal({})
local dark = g.signal({})
-- Whether niri has answered, or given up on after a while.
local answered = g.signal(false)

local function sections(): { any }
    local out = {}
    for _, item in niri_config.items() do
        if item.kind == "output" then table.insert(out, item) end
    end
    return out
end

local function named_by(output: any): { any }
    local out = {}
    for _, section in sections() do
        if kdl.names(section, output.name, output.description) then table.insert(out, section) end
    end
    return out
end

local function with_sections(output: any, on: boolean): any
    local named = named_by(output)
    local record = table.clone(output)
    record.on = on
    record.sections = named
    record.primary = false
    for _, section in named do
        if section.primary then record.primary = true end
    end
    -- niri reads the first section that names it.
    record.vrr = if #named > 0 then named[1].vrr else "off"
    return record
end

local outputs = g.computed(function(): { any }
    local out = {}
    for _, o in live.value do table.insert(out, with_sections(o, true)) end
    return out
end)

function M.outputs(): { any } return outputs.value end
function M.count(): number return #outputs.value end

-- The ones switched off, where their section puts them or beside the
-- others: where niri will put them back when they come on.
function M.off(): { any }
    local right = 0
    for _, o in live.value do right = math.max(right, o.x + o.width) end
    local out = {}
    for _, o in dark.value do
        local record = with_sections(o, false)
        local written = nil
        for _, section in record.sections do
            if section.position then
                written = section.position
                break
            end
        end
        record.x = if written then written.x else right
        record.y = if written then written.y else 0
        record.width, record.height, record.scale = o.mode_width, o.mode_height, 1
        if not written then right += o.mode_width end
        table.insert(out, record)
    end
    return out
end

function M.output_of(name: string): any
    for _, o in outputs.value do
        if o.name == name then return o end
    end
    for _, o in M.off() do
        if o.name == name then return o end
    end
    return nil
end

-- The primary monitor, which is what a block on `primary` means: the one
-- `focus-at-startup` marks, else the first screen.
--
-- Read at once, at the load, from the configuration and the outputs the
-- compositor has described, because the surfaces are decided then: a
-- section naming a monitor by its description rather than its connector is
-- matched against what the compositor says of it.
function M.primary(): string
    local screens = g.outputs()
    for _, section in sections() do
        if section.primary then
            for _, screen in screens do
                if kdl.names(section, screen.name, screen.description) then return screen.name end
            end
        end
    end
    return if #screens > 0 then screens[1].name else ""
end

function M.answered(): boolean return answered.value end

-- Whether any window rule asks for variable refresh: without one, an
-- output set to on-demand never turns it on.
function M.vrr_rule(): boolean
    for _, item in niri_config.items() do
        if item.kind == "rule" and item.vrr then return true end
    end
    return false
end

-- Whether Bioma's own rule for games is the one in place.
function M.games_rule(): boolean
    for _, item in niri_config.items() do
        if item.kind == "rule" and item.vrr and string.sub(item.file, -#"/bioma-vrr.kdl") == "/bioma-vrr.kdl" then
            return true
        end
    end
    return false
end

-- ---- Writing ----------------------------------------------------------------
--
-- Bioma on Genoma alone writes niri's output sections itself, through
-- `niri validate` (M6 step 7a); beside Quickshell it asks Quickshell, which
-- acts on them while the two run side by side.

local writing = g.signal(0)
local said = g.signal("")
function M.busy(): boolean
    if runtime.alone() then return niri_config.busy() end
    return writing.value > 0
end
function M.error(): string
    if runtime.alone() then return niri_config.error() end
    return said.value
end

local function ask(args: { string }, on_answer: ((string) -> ())?)
    local command = { paths.script("ipc"), "monitors" }
    for _, a in args do table.insert(command, a) end
    local lines = {}
    writing.value += 1
    said.value = ""
    g.process {
        command = command,
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function()
            writing.value -= 1
            if on_answer then on_answer(table.concat(lines, "\n")) end
            -- niri's refusal comes once Quickshell has validated the file.
            g.after(1.5, function()
                g.process {
                    command = { paths.script("ipc"), "monitors", "error" },
                    on_line = function(line: string) if line ~= "" then said.value = line end end,
                }
            end)
        end,
    }
end
local function alone(): boolean return g.untracked(runtime.alone) end

-- Every section of one output in one file, rewritten by `edit`, one at a
-- time and scanned again after each: an edit moves every offset after it.
local function rewrite(text: string, output: any, edit: (string, any) -> string): string
    local index = 1
    while true do
        local found = {}
        for _, item in kdl.scan(text).items do
            if item.kind == "output" and kdl.names(item, output.name, output.description) then table.insert(found, item) end
        end
        if index > #found then return text end
        text = edit(text, found[index])
        index += 1
    end
end

-- Where a section for an output that has none goes: beside the last
-- section there is, or into niri's own file.
local function home_for_new(): string
    local list = g.untracked(sections)
    return if #list > 0 then list[#list].file else niri_config.main
end

-- A change applied to every output that needs it, one write per file:
-- change(text, output) → text.
local function apply(change: (string, any) -> string)
    local files, order = {}, {}
    for _, output in g.untracked(M.outputs) do
        local touched = {}
        if #output.sections > 0 then
            for _, section in output.sections do
                if not table.find(touched, section.file) then table.insert(touched, section.file) end
            end
        else
            touched = { home_for_new() }
        end
        for _, file in touched do
            if files[file] == nil then
                local text = niri_config.text_of(file)
                if not text then
                    niri_config.set_error("niri's configuration could not be read.")
                    return
                end
                files[file] = text
                table.insert(order, file)
            end
            files[file] = change(files[file], output)
        end
    end
    for _, file in order do
        if files[file] ~= niri_config.text_of(file) then
            niri_config.write(file, files[file], kdl.outputs_text(files[file]))
        end
    end
end

-- The section just added for an output that had none.
local function last_output(text: string): any
    local last = nil
    for _, item in kdl.scan(text).items do if item.kind == "output" then last = item end end
    return last
end

-- Positions in logical units, `{ ["DP-1"] = { x = 0, y = 0 }, … }`. Only
-- the outputs named are written.
function M.place(positions: { [string]: { x: number, y: number } })
    if not alone() then ask({ "place", g.to_json(positions) }) return end
    apply(function(text: string, output: any): string
        local wanted = positions[output.name]
        if not wanted or (wanted.x == output.x and wanted.y == output.y) then return text end
        if #output.sections == 0 then return kdl.with_output(text, output.name, wanted.x, wanted.y) end
        return rewrite(text, output, function(t: string, section: any) return kdl.with_position(t, section, wanted.x, wanted.y) end)
    end)
end

-- Answered false when refused: the last monitor on stays on.
local switching = false
-- A monitor being switched on or off, until niri has done it.
function M.switching(): boolean return switching end
function M.power(name: string, on: boolean): boolean
    if not on and g.untracked(M.count) <= 1 then return false end
    if not alone() then
        ask({ "power", name, if on then "true" else "false" }, function() M.refresh() end)
        return true
    end
    local output = M.output_of(name)
    if not output or output.on == on or switching then return true end
    switching = true
    g.process {
        command = { "niri", "msg", "output", name, if on then "on" else "off" },
        on_exit = function()
            switching = false
            M.refresh()
        end,
    }
    return true
end

function M.make_primary(name: string)
    if not alone() then ask({ "primary", name }) return end
    apply(function(text: string, output: any): string
        local on = output.name == name
        if #output.sections == 0 then
            if not on then return text end
            local added = kdl.with_output(text, output.name, output.x, output.y)
            return kdl.with_flag(added, last_output(added), "focus-at-startup", true)
        end
        return rewrite(text, output, function(t: string, section: any) return kdl.with_flag(t, section, "focus-at-startup", on) end)
    end)
end

-- `off`, `on` or `demand`, for one output.
function M.set_vrr(name: string, mode: string)
    if not alone() then ask({ "vrr", name, mode }) return end
    apply(function(text: string, output: any): string
        if output.name ~= name or output.vrr == mode then return text end
        if #output.sections == 0 then
            if mode == "off" then return text end
            local added = kdl.with_output(text, output.name, output.x, output.y)
            return kdl.with_vrr(added, last_output(added), mode)
        end
        return rewrite(text, output, function(t: string, section: any) return kdl.with_vrr(t, section, mode) end)
    end)
end

-- Bioma's own rule turning variable refresh on for games, written as
-- `bioma-vrr.kdl`; switched off, the file says so and holds no rule.
local games_writing = false
function M.set_games(on: boolean)
    if not alone() then ask({ "games", if on then "true" else "false" }) return end
    if on == g.untracked(M.games_rule) or games_writing then return end
    games_writing = true
    local body = if on
        then "// Written by Bioma's settings cell (MONITORS). Variable refresh set to on demand\n"
            .. "// turns on for these windows; switching Games off there empties this file.\n"
            .. "window-rule {\n"
            .. '    match app-id=r#"^steam_app_"#\n'
            .. '    match app-id="^gamescope$"\n'
            .. "    variable-refresh-rate true\n"
            .. "}"
        else "// Written by Bioma's settings cell (MONITORS). Games is off: no rule here."
    local complaint = {}
    local p = g.process {
        command = { paths.script("niri-include"), "vrr" },
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function()
            games_writing = false
            local reason = string.match(table.concat(complaint, "\n"), "^%s*(.-)%s*$") or ""
            if reason ~= "" then niri_config.set_error("niri refused it: " .. reason) end
        end,
    }
    p:write(body)
    p:close_input()
end

-- ---- Asking niri --------------------------------------------------------------

local asking = false
local again = false

local function description_of(o: any): string
    return table.concat({ o.make or "", o.model or "", o.serial or "Unknown" }, " ")
end

local function refresh()
    if asking then
        again = true
        return
    end
    asking = true
    local lines = {}
    g.process {
        command = { "niri", "msg", "--json", "outputs" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function()
            asking = false
            local ok, parsed = pcall(g.parse_json, table.concat(lines, "\n"))
            if ok and type(parsed) == "table" then
                local names = {}
                for name in parsed do table.insert(names, name) end
                table.sort(names)
                local on, off = {}, {}
                for _, name in names do
                    local o = parsed[name]
                    if not o.logical then
                        local mode = nil
                        for _, m in o.modes or {} do
                            if m.is_preferred then mode = m end
                        end
                        mode = mode or (o.modes or {})[1]
                        if mode then
                            table.insert(off, {
                                name = name,
                                description = description_of(o),
                                mode_width = mode.width,
                                mode_height = mode.height,
                                refresh = mode.refresh_rate / 1000,
                                vrr_supported = o.vrr_supported == true,
                            })
                        end
                    else
                        -- niri counts modes from 0.
                        local mode = if o.current_mode ~= nil then (o.modes or {})[o.current_mode + 1] else nil
                        table.insert(on, {
                            name = name,
                            description = description_of(o),
                            x = o.logical.x,
                            y = o.logical.y,
                            width = o.logical.width,
                            height = o.logical.height,
                            scale = o.logical.scale,
                            mode_width = if mode then mode.width else o.logical.width,
                            mode_height = if mode then mode.height else o.logical.height,
                            refresh = if mode then mode.refresh_rate / 1000 else 0,
                            vrr_supported = o.vrr_supported == true,
                        })
                    end
                end
                dark.value = off
                live.value = on
            end
            answered.value = true
            if again then
                again = false
                refresh()
            end
        end,
    }
end

M.refresh = refresh
refresh()

-- Not niri, or niri not answering: the first screen, after a while.
g.after(2, function() answered.value = true end)

-- niri re-reads its configuration on its own, a moment after the file
-- changes; ask once it has.
local settle: any = nil
g.watch(function() return niri_config.items() end, function()
    if settle then settle:stop() end
    settle = g.after(0.4, refresh)
end)

return M
