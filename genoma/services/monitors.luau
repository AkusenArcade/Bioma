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
--
-- Elsewhere (Hyprland, Umbriel) where each output is comes from
-- wlr-output-management (@genoma/displays), followed as it changes, and no
-- niri sections are read. What is asked for there (a position, variable
-- refresh, the primary, the scale) is kept in Bioma's configuration
-- (`monitors.<compositor>`) and written whole as Bioma's own file for that
-- compositor (`bioma-monitors.lua` through scripts/hypr-include,
-- `bioma-monitors.toml` through scripts/umbriel-include); switching one on
-- or off is asked of wlr-output-management, for now, as `niri msg output`
-- does on niri.
local g = require("@genoma")
local compositor = require("@genoma/compositor")
local displays = require("@genoma/displays")
local niri_config = require("services/niri_config")
local kdl = require("services/niri_kdl")
local paths = require("core/paths")
local config = require("core/config")

local M = {}

local running = compositor.name
local on_niri = running == "niri"
-- Off niri: { outputs = { [name] = { x, y, vrr, hdr, scale } }, primary = name }.
local function wished(): any return config.get("monitors." .. running, {}) end

-- Which monitors can show HDR, as their EDID says (scripts/hdr), asked
-- again when the screens change. Only Hyprland and Umbriel are told to
-- turn it on: niri has no HDR.
local hdr_capable = g.signal({} :: { [string]: boolean })
local function read_hdr()
    local out = {}
    g.process {
        command = { paths.script("hdr") },
        on_line = function(line: string)
            local ok, map = pcall(g.parse_json, line)
            if ok and type(map) == "table" then out = map end
        end,
        on_exit = function() hdr_capable.value = out end,
    }
end
if running == "hyprland" or running == "umbriel" then
    g.lasting(function()
        g.watch(function() return #g.outputs() end, function() read_hdr() end)
    end)
end
function M.hdr_supported(name: string): boolean return hdr_capable.value[name] == true end
function M.hdr(name: string): boolean return ((wished().outputs or {})[name] or {}).hdr == true end
-- The white of what is not HDR on an HDR monitor, the desktop itself, in
-- nits: the reference 203 (ITU-R BT.2408) until chosen, as monitors differ
-- in how bright they are without HDR.
M.white_from, M.white_to = 80, 600
local WHITE = 203
function M.white(name: string): number return ((wished().outputs or {})[name] or {}).white or WHITE end

-- What niri reports, one entry per output that is on; and the ones
-- connected but switched off, which it lists with no geometry.
local live = g.signal({})
local dark = g.signal({})
-- Whether niri has answered, or given up on after a while.
local answered = g.signal(false)

-- niri's `output` sections; none on another compositor, whose settings
-- are not niri's even when niri's files are there too.
local function sections(): { any }
    local out = {}
    if compositor.name ~= "niri" then return out end
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
    if not on_niri then
        local w = wished()
        record.primary = w.primary == output.name
        record.vrr = ((w.outputs or {})[output.name] or {}).vrr or "off"
        return record
    end
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
    if not on_niri then
        local named = g.untracked(wished).primary
        for _, screen in screens do
            if screen.name == named then return named end
        end
    end
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
    -- Hyprland's and Umbriel's on-demand is full screen, and wants no rule.
    if not on_niri then return true end
    for _, item in niri_config.items() do
        if item.kind == "rule" and item.vrr then return true end
    end
    return false
end

-- Whether Bioma's own rule for games is the one in place.
-- Bioma's rule for games is niri's: elsewhere on demand is full screen.
function M.games_offered(): boolean return on_niri end

function M.games_rule(): boolean
    if not on_niri then return false end
    for _, item in niri_config.items() do
        if item.kind == "rule" and item.vrr and string.sub(item.file, -#"/bioma-vrr.kdl") == "/bioma-vrr.kdl" then
            return true
        end
    end
    return false
end

-- ---- Writing ----------------------------------------------------------------
--
-- Bioma writes niri's output sections itself, through `niri validate`.

local own_busy = g.signal(false)
local own_error = g.signal("")
function M.busy(): boolean return if on_niri then niri_config.busy() else own_busy.value end
function M.error(): string return if on_niri then niri_config.error() else own_error.value end

-- ---- Off niri: Bioma's own file ------------------------------------------------

local function number_text(v: number): string
    return if v == math.floor(v) then tostring(math.floor(v)) else string.format("%.3f", v)
end

-- The whole file, from what is wished and what each output runs: a
-- Hyprland monitor rule names everything, so its mode and scale are the
-- ones in use.
local function monitors_body(): string
    local w = g.untracked(wished)
    local said = "Written by Bioma's settings cell (MONITORS). Changing the layout there rewrites it."
    local names = {}
    for name in w.outputs or {} do table.insert(names, name) end
    table.sort(names)
    if running == "hyprland" then
        local out = { "-- " .. said, "" }
        local vrr = { off = 0, on = 1, demand = 2 }
        -- The desktop on an HDR monitor is read with Hyprland's piecewise sRGB
        -- curve unless told otherwise, which lifts every shadow; monitors, and
        -- what is drawn for them, are gamma 2.2. Said of every monitor at once:
        -- how the desktop is read is one setting for all, and a monitor that
        -- is not HDR must be written back with the same curve, or it darkens.
        local any_hdr = false
        for _, name in names do
            if w.outputs[name].hdr and M.output_of(name) then any_hdr = true end
        end
        if any_hdr then table.insert(out, "hl.config({ render = { cm_sdr_eotf = \"gamma22force\" } })\n") end
        for _, name in names do
            local o = M.output_of(name)
            local want = w.outputs[name]
            if o and o.mode_width then
                table.insert(out, "hl.monitor({")
                table.insert(out, string.format("    output = %q,", name))
                table.insert(out, string.format("    mode = \"%dx%d@%s\",", o.mode_width, o.mode_height, number_text(o.refresh or 60)))
                table.insert(out, string.format("    position = \"%dx%d\",", math.round(want.x or o.x or 0), math.round(want.y or o.y or 0)))
                table.insert(out, "    scale = " .. number_text(want.scale or o.scale or 1) .. ",")
                table.insert(out, "    vrr = " .. (vrr[want.vrr or "off"] or 0) .. ",")
                if any_hdr then
                    table.insert(out, "    sdr_eotf = \"gamma22\",")
                    -- What is not HDR, the desktop itself: white where
                    -- it is chosen (`white`) and black at none.
                    -- Hyprland's own 80 and 0.2 are dim and grey, the whole
                    -- desktop washed out (Akusen, 2026-11-24). On a monitor
                    -- that is not HDR they change nothing, and are there
                    -- because Hyprland 0.57.2 does not compare sdr_eotf: a
                    -- rule where it alone changed is taken for the same.
                    table.insert(out, "    sdr_max_luminance = " .. (if want.hdr then want.white or WHITE else WHITE) .. ",")
                    table.insert(out, "    sdr_min_luminance = 0.005,")
                end
                -- HDR10 needs ten bits; off, Hyprland picks the colours itself.
                if want.hdr then
                    table.insert(out, "    cm = \"hdr\",")
                    table.insert(out, "    bitdepth = 10,")
                end
                table.insert(out, "})")
            end
        end
        return table.concat(out, "\n") .. "\n"
    end
    local out = { "# " .. said, "" }
    local vrr = { off = "disabled", on = "always", demand = "fullscreen" }
    for _, name in names do
        local want = w.outputs[name]
        table.insert(out, "[output." .. name .. "]")
        if want.x ~= nil and want.y ~= nil then table.insert(out, string.format("position = [%d, %d]", math.round(want.x), math.round(want.y))) end
        if want.scale then table.insert(out, "scale = " .. number_text(want.scale)) end
        if want.vrr then table.insert(out, "vrr = \"" .. (vrr[want.vrr] or "disabled") .. "\"") end
        if want.white then table.insert(out, "sdr_white = " .. want.white) end
        if want.hdr ~= nil then table.insert(out, "hdr = \"" .. (if want.hdr then "on" else "off") .. "\"") end
        table.insert(out, "focus_at_startup = " .. tostring(w.primary == name))
        table.insert(out, "")
    end
    return table.concat(out, "\n")
end

local function write_own()
    if running ~= "hyprland" and running ~= "umbriel" then
        own_error.value = "Bioma does not write this compositor's monitors."
        return
    end
    own_busy.value = true
    local said = {}
    local p = g.process {
        command = { paths.script(if running == "hyprland" then "hypr-include" else "umbriel-include"), "monitors" },
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number)
            own_busy.value = false
            own_error.value = if code == 0 then ""
                else (if running == "hyprland" then "Hyprland" else "Umbriel") .. " refused it" .. (if #said > 0 then ": " .. said[1] else ".")
        end,
    }
    p:write(monitors_body())
    p:close_input()
end

-- One output's wishes changed by `edit`, then the file written. The place
-- of every output is written with it: one left to the compositor is put
-- again beside the one the file names, so a scale chosen on one monitor
-- moved the other (Hyprland, 2026-11-24).
local function wish(edit: (any) -> ())
    local w = table.clone(g.untracked(wished))
    w.outputs = table.clone(w.outputs or {})
    for _, o in g.untracked(function() return live.value end) do
        local entry = table.clone(w.outputs[o.name] or {})
        if entry.x == nil or entry.y == nil then
            entry.x, entry.y = o.x, o.y
            w.outputs[o.name] = entry
        end
    end
    edit(w)
    config.set("monitors." .. running, w)
    write_own()
end


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
    if not on_niri then
        wish(function(w: any)
            for name, p in positions do
                local o = table.clone(w.outputs[name] or {})
                o.x, o.y = p.x, p.y
                w.outputs[name] = o
            end
        end)
        return
    end
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
    local output = M.output_of(name)
    if not output or output.on == on or switching then return true end
    if not on_niri then
        local ok, why = pcall(function() displays:apply({ [name] = { enabled = on } }) end)
        if not ok then own_error.value = tostring(why) end
        return true
    end
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
    if not on_niri then
        wish(function(w: any)
            w.primary = if name ~= "" then name else nil
            if name ~= "" and not w.outputs[name] then w.outputs[name] = {} end
        end)
        return
    end
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
    if not on_niri then
        wish(function(w: any)
            local o = table.clone(w.outputs[name] or {})
            o.vrr = mode
            w.outputs[name] = o
        end)
        return
    end
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

-- The scales offered, and the one an output runs at among them when it is
-- another (niri's own choice, written by hand).
local SCALES = { 1, 1.25, 1.5, 1.75, 2 }
function M.scales(name: string): { number }
    local out = table.clone(SCALES)
    local o = M.output_of(name)
    local now = if o and o.on then o.scale else nil
    if now then
        local listed = false
        for _, v in out do if math.abs(v - now) < 0.005 then listed = true end end
        if not listed then
            table.insert(out, now)
            table.sort(out)
        end
    end
    return out
end

-- One output's scale. Its logical size changes with it, so the monitors
-- beyond its right edge, and below its bottom one, move by as much: what
-- touched it still touches it, and nothing comes to overlap it.
function M.set_scale(name: string, scale: number)
    local me = M.output_of(name)
    if not me or not me.on or math.abs((me.scale or 1) - scale) < 0.005 then return end
    local ratio = (me.scale or 1) / scale
    local dw, dh = me.width * ratio - me.width, me.height * ratio - me.height
    local right, bottom = me.x + me.width, me.y + me.height
    local moved: { [string]: { x: number, y: number } } = {}
    for _, o in g.untracked(M.outputs) do
        if o.name ~= name then
            local x = if o.x >= right - 1 then o.x + dw else o.x
            local y = if o.y >= bottom - 1 then o.y + dh else o.y
            if x ~= o.x or y ~= o.y then moved[o.name] = { x = math.round(x), y = math.round(y) } end
        end
    end
    if not on_niri then
        wish(function(w: any)
            local o = table.clone(w.outputs[name] or {})
            o.scale = scale
            w.outputs[name] = o
            for other, p in moved do
                local entry = table.clone(w.outputs[other] or {})
                entry.x, entry.y = p.x, p.y
                w.outputs[other] = entry
            end
        end)
        return
    end
    apply(function(text: string, output: any): string
        if output.name == name then
            if #output.sections == 0 then
                local added = kdl.with_output(text, output.name, output.x, output.y)
                return kdl.with_scale(added, last_output(added), scale)
            end
            return rewrite(text, output, function(t: string, section: any) return kdl.with_scale(t, section, scale) end)
        end
        local wanted = moved[output.name]
        if not wanted then return text end
        if #output.sections == 0 then return kdl.with_output(text, output.name, wanted.x, wanted.y) end
        return rewrite(text, output, function(t: string, section: any) return kdl.with_position(t, section, wanted.x, wanted.y) end)
    end)
end

-- How bright the desktop's white is on an HDR monitor.
function M.set_white(name: string, nits: number)
    if on_niri or not g.untracked(function() return M.hdr(name) end) then return end
    local v = math.clamp(math.round(nits), M.white_from, M.white_to)
    if v == g.untracked(function() return M.white(name) end) then return end
    wish(function(w: any)
        local o = table.clone(w.outputs[name] or {})
        o.white = v
        w.outputs[name] = o
    end)
end

-- HDR on or off, for one monitor that can show it (Hyprland, Umbriel).
function M.set_hdr(name: string, on: boolean)
    if on_niri or not g.untracked(function() return M.hdr_supported(name) end) then return end
    wish(function(w: any)
        local o = table.clone(w.outputs[name] or {})
        o.hdr = on
        w.outputs[name] = o
    end)
end

-- Bioma's own rule turning variable refresh on for games, written as
-- `bioma-vrr.kdl`; switched off, the file says so and holds no rule.
local games_writing = false
function M.set_games(on: boolean)
    if not on_niri or on == g.untracked(M.games_rule) or games_writing then return end
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

-- The logical size of a display: its mode turned by its transform, over
-- its scale.
local function logical(d: any): (number, number)
    local w, h = d.mode.width, d.mode.height
    local t = d.transform or "normal"
    if string.find(t, "90") or string.find(t, "270") then w, h = h, w end
    local scale = if (d.scale or 0) > 0 then d.scale else 1
    return w / scale, h / scale
end

local function from_displays()
    local on, off = {}, {}
    local heads = displays.heads
    table.sort(heads, function(a, b) return a.name < b.name end)
    for _, d in heads do
        local preferred = nil
        for _, m in d.modes or {} do
            if m.preferred then preferred = m end
        end
        preferred = preferred or (d.modes or {})[1]
        if d.enabled and d.mode then
            local w, h = logical(d)
            table.insert(on, {
                name = d.name,
                description = d.description,
                x = d.x,
                y = d.y,
                width = w,
                height = h,
                scale = d.scale,
                mode_width = d.mode.width,
                mode_height = d.mode.height,
                refresh = d.mode.refresh,
                vrr_supported = d.adaptive_sync ~= nil,
            })
        elseif preferred then
            table.insert(off, {
                name = d.name,
                description = d.description,
                mode_width = preferred.width,
                mode_height = preferred.height,
                refresh = preferred.refresh,
                vrr_supported = d.adaptive_sync ~= nil,
            })
        end
    end
    dark.value = off
    live.value = on
    answered.value = true
end

if on_niri then
    M.refresh = refresh
    refresh()
else
    M.refresh = function() end
    g.lasting(function()
        g.effect(function()
            if not displays.available then return end
            local _ = displays.heads
            g.untracked(from_displays)
        end)
    end)
end

-- Not niri, or niri not answering: the first screen, after a while.
g.after(2, function() answered.value = true end)

-- niri re-reads its configuration on its own, a moment after the file
-- changes; ask once it has.
local settle: any = nil
g.watch(function() return niri_config.items() end, function()
    if not on_niri then return end
    if settle then settle:stop() end
    settle = g.after(0.4, refresh)
end)

return M
