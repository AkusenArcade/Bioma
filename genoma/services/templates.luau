--!strict
-- The palette outside the shell: niri's borders, GTK, Qt, the terminals
-- (services/Templates.qml at 8ed8892).
--
-- The templates are Noctalia's (config/templates/README.md) and name
-- colours the way matugen does; Bioma's palette has four roles and derives
-- the rest, so this is the translation, made from the palette's targets the
-- way the shell makes its own surfaces. `scripts/themes` renders and hooks
-- them, rewriting a file and running its hook only when what it renders
-- has changed, or when a template has just been switched on.
--
-- Bioma on Genoma alone renders (M6 step 7a, `start`); beside Quickshell,
-- Quickshell does, and a switch made here is handed to it.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics = require("core/metrics")
local paths = require("core/paths")
local runtime = require("core/runtime")
local theme = require("core/theme")
local timing = require("core/timing")

local M = {}

-- { { id, name, category, installed } }, asked once.
local catalogue = g.signal({})
do
    local out = {}
    g.process {
        command = { paths.script("themes"), "list" },
        on_line = function(line: string) table.insert(out, line) end,
        on_exit = function(code: number)
            if code ~= 0 then return end
            local ok, data = pcall(g.parse_json, table.concat(out, "\n"))
            if ok and type(data) == "table" then catalogue.value = data end
        end,
    }
end

function M.catalogue(): { any } return catalogue.value end
-- By default niri alone: every other application is somebody's own
-- configuration, switched on from APPS in the theme cell.
function M.enabled(): { string } return config.get("theme.templates", { "niri" }) end
function M.is_on(id: string): boolean return table.find(M.enabled(), id) ~= nil end

-- Switched on, a template's hook runs at the next render whatever it finds.
local forced: { string } = {}
-- What the last render refused, by template.
local failures = g.signal({} :: { [string]: string })
function M.failures(): { [string]: string } return failures.value end

function M.set_on(id: string, on: boolean)
    if on == g.untracked(function() return M.is_on(id) end) then return end
    if not g.untracked(runtime.alone) then
        g.process { command = { paths.script("ipc"), "looks", "template", id, if on then "true" else "false" } }
        return
    end
    local list = table.clone(g.untracked(M.enabled))
    if on then
        table.insert(forced, id)
        table.insert(list, id)
    else
        table.remove(list, table.find(list, id) :: number)
        g.process { command = { paths.script("themes"), "undo", id } }
    end
    config.set("theme.templates", list)
end

-- ---- The translation ------------------------------------------------------------

-- "#rrggbb", lower case, as Qt names a colour: whatever form it came in.
local function hex(c: string): string return string.sub(colour.format(colour.parse(c)), 1, 7) end
local function rgb(c: colour.RGB): string return hex(colour.format(c)) end
local function hsl(c: string): (number, number, number) return colour.hsl(colour.parse(c)) end
local function readable_on(c: string, dark: string, light: string): string
    return if colour.luminance(c) > 0.5 then dark else light
end
local function hued(hue: number, like: string): string
    local _, s, l = hsl(like)
    return rgb(colour.hsla(hue, math.max(0.45, s), math.min(0.75, math.max(0.45, l)), 1))
end

-- In the templates' own order, so that the same palette always says the
-- same thing.
local NAMES = {
    "background", "on_background", "surface", "on_surface", "surface_variant", "on_surface_variant",
    "surface_container_lowest", "surface_container_low", "surface_container", "surface_container_high",
    "surface_container_highest", "inverse_surface", "hover", "outline", "outline_variant", "rim", "shadow",
    "primary", "on_primary", "primary_container", "on_primary_container",
    "secondary", "on_secondary", "secondary_container", "on_secondary_container",
    "tertiary", "on_tertiary", "tertiary_container", "on_tertiary_container",
    "error", "on_error", "error_container", "on_error_container",
    "terminal_background", "terminal_foreground", "terminal_cursor", "terminal_cursor_text",
    "terminal_selection_bg", "terminal_selection_fg",
    "terminal_normal_black", "terminal_normal_red", "terminal_normal_green", "terminal_normal_yellow",
    "terminal_normal_blue", "terminal_normal_magenta", "terminal_normal_cyan", "terminal_normal_white",
    "terminal_bright_black", "terminal_bright_red", "terminal_bright_green", "terminal_bright_yellow",
    "terminal_bright_blue", "terminal_bright_magenta", "terminal_bright_cyan", "terminal_bright_white",
}

local STATE_DARK = { calm = "#6EE7A6", active = "#F2C14E", alert = "#FF6B5D" }
local STATE_LIGHT = { calm = "#2E9C6A", active = "#B37414", alert = "#C43A2E" }

local colors = g.computed(function(): { [string]: string }
    local bg, fg = theme.target("background"), theme.target("text")
    local p, s = theme.target("primary"), theme.target("secondary")
    local dark = theme.target_is_dark()
    local states = if dark then config.get("theme.state.dark", STATE_DARK) else config.get("theme.state.light", STATE_LIGHT)
    local defaults = if dark then STATE_DARK else STATE_LIGHT
    local e = states.alert or defaults.alert
    local calm = states.calm or defaults.calm
    local warm = states.active or defaults.active
    local function lift(amount: number): string return hex(theme.lift_away(bg, amount, dark)) end
    local function brighter(c: string): string return hex(theme.lift_away(c, 0.08, dark)) end
    local function mix(a: string, b: string, t: number): string return colour.qt_mix(colour.parse(a), colour.parse(b), t) end
    -- A grey has no hue (-1); it turns from red like any other.
    local sh, ss, sl = hsl(s)
    -- Kept whole until it is named: Qt mixes the colour, not its bytes.
    local whole = colour.hsla((math.max(0, sh) + 0.12) % 1, ss, sl, 1)
    local t = rgb(whole)
    local function mix_whole(b: string, by: number): string return colour.qt_mix(whole, colour.parse(b), by) end
    local outline = hex(theme.structural_with(bg, p, if dark then 0.32 else 0.72))
    local rim = hex(theme.structural_with(bg, p, if dark then 0.55 else 0.50))
    local ink = if dark then hex(bg) else "#101010"
    local paper = if dark then "#f4f4f4" else hex(bg)
    return {
        background = hex(bg), on_background = hex(fg),
        surface = hex(bg), on_surface = hex(fg),
        surface_variant = lift(0.07), on_surface_variant = mix(fg, bg, 0.3),
        surface_container_lowest = lift(0.01), surface_container_low = lift(0.03),
        surface_container = lift(0.045), surface_container_high = lift(0.07),
        surface_container_highest = lift(0.095),
        inverse_surface = hex(fg), hover = lift(0.06),
        outline = outline, outline_variant = mix(outline, bg, 0.5),
        rim = rim,
        shadow = "#000000",

        primary = hex(p), on_primary = readable_on(p, ink, paper),
        primary_container = mix(p, bg, 0.72), on_primary_container = mix(p, fg, 0.5),
        secondary = hex(s), on_secondary = readable_on(s, ink, paper),
        secondary_container = mix(s, bg, 0.72), on_secondary_container = mix(s, fg, 0.5),
        tertiary = t, on_tertiary = readable_on(t, ink, paper),
        tertiary_container = mix_whole(bg, 0.72), on_tertiary_container = mix_whole(fg, 0.5),
        error = hex(e), on_error = readable_on(e, ink, paper),
        error_container = mix(e, bg, 0.72), on_error_container = mix(e, fg, 0.5),

        -- The terminal's sixteen: the state colours where a terminal means a
        -- state, the palette's own light for the rest.
        terminal_background = hex(bg), terminal_foreground = hex(fg),
        terminal_cursor = hex(p), terminal_cursor_text = hex(bg),
        terminal_selection_bg = mix(p, bg, 0.65), terminal_selection_fg = hex(fg),
        terminal_normal_black = lift(0.1), terminal_normal_red = hex(e),
        terminal_normal_green = hex(calm), terminal_normal_yellow = hex(warm),
        terminal_normal_blue = hued(0.6, p), terminal_normal_magenta = hued(0.85, p),
        terminal_normal_cyan = hued(0.5, s), terminal_normal_white = mix(fg, bg, 0.15),
        terminal_bright_black = lift(0.25), terminal_bright_red = brighter(e),
        terminal_bright_green = brighter(calm), terminal_bright_yellow = brighter(warm),
        terminal_bright_blue = brighter(hued(0.6, p)),
        terminal_bright_magenta = brighter(hued(0.85, p)),
        terminal_bright_cyan = brighter(hued(0.5, s)), terminal_bright_white = hex(fg),
    }
end)
-- niri's template also carries the shell's corners to the windows (20 at
-- 100 % of RADIUS), the focus ring's width, and an invoked cell's shadow to
-- the focused window.
local function window_radius(): number return math.floor(20 * metrics.radius_percent() / 100 + 0.5) end
local function focus_width(): number return config.get("niri.focus_ring", 2) end
local function window_shadow(): string return theme.shadow_of(theme.target_is_dark()) end

-- Everything a render depends on, as one string: a render follows a change.
local signature = g.computed(function(): string
    local c = colors.value
    local parts = {}
    for _, name in NAMES do table.insert(parts, c[name]) end
    table.insert(parts, table.concat(M.enabled(), ","))
    table.insert(parts, tostring(window_radius()))
    table.insert(parts, tostring(focus_width()))
    table.insert(parts, window_shadow())
    table.insert(parts, tostring(theme.target_is_dark()))
    return table.concat(parts, " ")
end)

-- ---- Rendering --------------------------------------------------------------------

local rendering = false
local again = false
local function render()
    if rendering then
        again = true
        return
    end
    rendering = true
    local force = table.clone(forced)
    for id in g.untracked(function() return failures.value end) do table.insert(force, id) end
    forced = {}
    local request = g.untracked(function()
        return g.to_json({
            colors = colors.value,
            mode = if theme.target_is_dark() then "dark" else "light",
            vars = { window_radius = window_radius(), window_shadow = window_shadow(), focus_width = focus_width() },
            enabled = g.array(table.clone(M.enabled())),
            -- A hook that failed ran against a file that is now written,
            -- so the file will not change again to run it: it is asked again.
            force = g.array(force),
        })
    end)
    local out = {}
    local p = g.process {
        command = { paths.script("themes"), "render" },
        on_line = function(line: string) table.insert(out, line) end,
        on_exit = function()
            rendering = false
            local ok, report = pcall(g.parse_json, table.concat(out, "\n"))
            if ok and type(report) == "table" then
                local found, changed = {}, {}
                for _, outcome in report do
                    if outcome.changed then table.insert(changed, tostring(outcome.id)) end
                    if not outcome.ok or (outcome.error or "") ~= "" then
                        found[outcome.id] = outcome.error or ""
                        print("Bioma: the " .. tostring(outcome.id) .. " template — " .. tostring(outcome.error))
                    end
                end
                failures.value = found
                if #changed > 0 then print("Bioma: the palette rewritten for " .. table.concat(changed, ", ")) end
            end
            if again then
                again = false
                render()
            end
        end,
    }
    p:write(request)
    p:close_input()
end

local started = false
function M.start()
    if started then return end
    started = true
    -- Once the shell has settled, then whenever what is rendered changes; a
    -- slider dragged across its travel changes the radius many times, and
    -- the files follow when it rests.
    local settled = false
    local debounce: any = nil
    g.after(timing.seconds.settle, function()
        settled = true
        render()
    end)
    g.watch(function() return signature.value end, function()
        if not settled then return end
        if debounce then debounce:stop() end
        debounce = g.after(timing.seconds.blur_settle, function()
            debounce = nil
            render()
        end)
    end)
end

return M
