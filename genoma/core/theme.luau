--!strict
-- Colour, as an animated singleton (core/Theme.qml).
--
-- Cells bind to these; they never copy a value. That is what lets the theme
-- cell retint the whole desktop live, and it is why every palette change is
-- animated rather than applied: the four roles move over `theme` in the
-- timing set, and every derived colour is computed from the roles in
-- transit, so the whole desktop crosses together rather than in patches.
--
-- Four interface roles come from a theme source — matugen or a manual
-- palette file. The three state roles never do: they are a semantic code.
-- Everything else is derived here, in HSL, from the four; with the shipped
-- palette the derivations reproduce docs/design/tokens.css.
local g = require("@genoma")
local config = require("core/config")
local colour = require("core/colour")
require("core/timing")

local M = {}

-- ---- Interface roles ---------------------------------------------------

local roles = {
    background = g.animated("#12160F"),
    text = g.animated("#EAF1E6"),
    primary = g.animated("#B9DE6B"),
    secondary = g.animated("#3FBFA0"),
}

-- In transit, which is what cells bind to.
function M.background(): string return roles.background.value end
function M.text(): string return roles.text.value end
function M.primary(): string return roles.primary.value end
function M.secondary(): string return roles.secondary.value end

-- Where the palette is going: the theme cell's chips arrive at the
-- destination rather than chase the shell's transition.
-- A signal of its own: an animated value's target is a plain field, and a
-- binding that read it was never told it moved.
local targets = g.signal({
    background = roles.background.target,
    text = roles.text.target,
    primary = roles.primary.target,
    secondary = roles.secondary.target,
})
function M.target(role: string): string return targets.value[role] end

-- While a palette is being edited the desktop follows the hand, not a
-- quarter of a second behind it (services/Palettes.qml).
M.immediate = g.state("theme.immediate", false)

-- ---- Light or dark -------------------------------------------------------

function M.is_dark(): boolean return colour.luminance(M.background()) < 0.5 end

-- ---- State roles (fixed, never from the theme source) ------------------------

local state_dark = { calm = "#6EE7A6", active = "#F2C14E", alert = "#FF6B5D" }
local state_light = { calm = "#2E9C6A", active = "#B37414", alert = "#C43A2E" }

local function state(role: string): string
    local set = if M.is_dark() then config.get("theme.state.dark", state_dark) else config.get("theme.state.light", state_light)
    return set[role] or (if M.is_dark() then state_dark else state_light)[role]
end
function M.calm(): string return state("calm") end
function M.active(): string return state("active") end
function M.alert(): string return state("alert") end

-- Load is measured, so it speaks in state colours: three states, two
-- boundaries, no dead zone.
M.threshold_calm = 0.30
M.threshold_alert = 0.80
function M.state_for(load: number): string
    if load >= M.threshold_alert then return M.alert() end
    if load >= M.threshold_calm then return M.active() end
    return M.calm()
end

-- ---- Derived surfaces -------------------------------------------------------

-- Moves a colour away from the background's side, keeping hue and saturation.
function M.lift_away(hex: string, amount: number, dark: boolean): string
    local c = colour.parse(hex)
    local h, s, l = colour.hsl(c)
    local step = if dark then amount else -amount
    return colour.format(colour.hsla(math.max(0, h), s, math.clamp(l + step, 0, 1), c.a))
end
function M.lift(hex: string, amount: number): string return M.lift_away(hex, amount, M.is_dark()) end

function M.surface(): string return M.lift(M.background(), 0.045) end
function M.elevated(): string return M.lift(M.background(), 0.045) end
function M.cell(): string return M.lift(M.background(), 0.075) end
function M.well_surface(): string return M.lift(M.background(), 0.02) end

-- Only for a secondary label nobody presses, or an option not chosen.
function M.text_muted(): string return colour.alpha(M.text(), 0.56) end
function M.text_faint(): string return colour.alpha(M.text(), 0.38) end
function M.border(): string return colour.alpha(M.text(), if M.is_dark() then 0.09 else 0.14) end

function M.shadow_of(dark: boolean): string return colour.alpha("#000000", if dark then 0.45 else 0.22) end
function M.shadow(): string return M.shadow_of(M.is_dark()) end
function M.shadow_float(): string return colour.alpha("#000000", if M.is_dark() then 0.60 else 0.30) end

-- ---- The outline family ------------------------------------------------------
--
-- Line, node and rim at three lightnesses of the background's hue, the
-- primary's when the background has none.

local function hue_of(bg: string, accent: string): number
    local bh, bs = colour.hsl(colour.parse(bg))
    local ah = colour.hsl(colour.parse(accent))
    return if bs > 0.05 and bh >= 0 then bh else math.max(0, ah)
end

local function saturation_of(bg: string, accent: string): number
    local _, bs = colour.hsl(colour.parse(bg))
    local _, as = colour.hsl(colour.parse(accent))
    return math.max(math.min(bs + 0.04, 0.40), math.min(as * 0.33, 0.28))
end

function M.structural_with(bg: string, accent: string, lightness: number): string
    return colour.format(colour.hsla(hue_of(bg, accent), saturation_of(bg, accent), lightness, 1))
end
function M.structural(lightness: number): string return M.structural_with(M.background(), M.primary(), lightness) end

function M.line(): string return M.structural(if M.is_dark() then 0.32 else 0.72) end
function M.node(): string return M.structural(if M.is_dark() then 0.43 else 0.62) end
function M.rim(): string return M.structural(if M.is_dark() then 0.55 else 0.50) end

-- ---- Gradients -----------------------------------------------------------------
--
-- One light source from above, the same across the shell: two tones of one
-- hue, the top lighter, the bottom darker and more saturated.

M.gradient_angle = 165

function M.gradient_top(hex: string): string
    local c = colour.parse(hex)
    local h, s, l = colour.hsl(c)
    return colour.format(colour.hsla(math.max(0, h), math.min(1, s + 0.14), math.min(1, l + 0.16), c.a))
end

function M.gradient_bottom(hex: string): string
    local c = colour.parse(hex)
    local h, s, l = colour.hsl(c)
    return colour.format(colour.hsla(math.max(0, h), math.max(0, s - 0.15), math.max(0, l - 0.15), c.a))
end

-- ---- The source ----------------------------------------------------------------

local home = (g.env("XDG_CONFIG_HOME") or (g.env("HOME") or "") .. "/.config")
M.matugen_path = home .. "/bioma/generated/palette.json"
M.user_palettes = home .. "/bioma/palettes"
M.shipped_palettes = g.dir .. "/../config/palettes"

-- The picture matugen's palette was made from, as its file says.
M.generated_image = g.state("theme.generated_image", "")

local function apply(text: string?)
    if not text then return end
    local ok, palette = pcall(g.parse_json, text)
    if not ok or type(palette) ~= "table" then return end
    local how = if M.immediate.value then nil else "theme"
    for role, value in roles do
        if type(palette[role]) == "string" then value:set(palette[role], how) end
    end
    g.untracked(function()
        local next_targets = {}
        for role in roles do
            next_targets[role] = if type(palette[role]) == "string" then palette[role] else targets.value[role]
        end
        targets.value = next_targets
    end)
    if palette.image then M.generated_image.value = palette.image end
end

-- The file the source names, watched: matugen's, or a manual palette looked
-- for among the user's own first, then the shipped ones. A new source or
-- palette replaces the watch (what an effect makes, its next run disposes).
g.effect(function()
    local file
    if config.get("theme.source", "manual") == "matugen" then
        file = g.file { path = M.matugen_path }
    else
        local name = config.get("theme.palette", "default")
        local own = M.user_palettes .. "/" .. name .. ".json"
        local probe = g.file { path = own, watch = false }
        file = g.file { path = if probe.text then own else M.shipped_palettes .. "/" .. name .. ".json" }
    end
    g.effect(function() apply(file.text) end)
end)

-- ---- What the theme cell shows ----------------------------------------------------
--
-- The palette at rest: seven roles, of the destination rather than the
-- transit, so a chip bound to them moves once per change and not on every
-- frame of the crossing. The state colours are not among them.

function M.target_is_dark(): boolean return colour.luminance(M.target("background")) < 0.5 end

function M.target_roles(): { string }
    local bg, p = M.target("background"), M.target("primary")
    local dark = M.target_is_dark()
    return {
        bg,
        M.lift_away(bg, 0.045, dark),
        M.structural_with(bg, p, if dark then 0.32 else 0.72),
        M.structural_with(bg, p, if dark then 0.55 else 0.50),
        p,
        M.target("secondary"),
        M.target("text"),
    }
end

-- ---- The palettes on offer ----------------------------------------------------------
--
-- A manual palette is a data file: dropped into config/palettes/ it is
-- offered. The name comes from inside the file. The user's own, in
-- ~/.config/bioma/palettes/, come after Bioma's, and one with a shipped
-- one's file name takes its place.

function M.source(): string return config.get("theme.source", "manual") end
function M.manual_palette(): string return config.get("theme.palette", "default") end

local shipped_folder = g.folder { path = M.shipped_palettes }
local user_folder = g.folder { path = M.user_palettes }

local function json_files(entries: { any }): { any }
    local out = {}
    for _, e in entries do
        local base = string.match(e.name, "^(.*)%.json$")
        if base and not e.dir then table.insert(out, { file = base, path = e.path }) end
    end
    return out
end

local function parsed(reader: any): { [string]: any }
    local text = reader.text
    if not text then return {} end
    local ok, palette = pcall(g.parse_json, text)
    return if ok and type(palette) == "table" then palette else {}
end

-- { { file, name, own, colours } }. One reader per file, made by the effect
-- that lists them, so a file that goes takes its reader with it.
local palettes = g.signal({})
g.effect(function()
    local own_list = json_files(user_folder.entries)
    local own = {}
    for _, f in own_list do own[f.file] = true end
    local wanted = {}
    for _, f in json_files(shipped_folder.entries) do
        if not own[f.file] then table.insert(wanted, { file = f.file, own = false, reader = g.file { path = f.path, watch = false } }) end
    end
    for _, f in own_list do
        table.insert(wanted, { file = f.file, own = true, reader = g.file { path = f.path } })
    end
    g.effect(function()
        local out = {}
        for _, w in wanted do
            local data = parsed(w.reader)
            table.insert(out, { file = w.file, name = data.name or w.file, own = w.own, colours = data })
        end
        g.untracked(function() palettes.value = out end)
    end)
end)
function M.palettes(): { any } return palettes.value end

function M.palette_name(): string
    local chosen = M.manual_palette()
    for _, p in palettes.value do
        if p.file == chosen then return p.name end
    end
    return chosen
end

return M
