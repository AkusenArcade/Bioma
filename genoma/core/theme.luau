--!strict
-- Colour, as an animated singleton (core/Theme.qml), on Genoma's own theme
-- (`@genoma/theme`, which was built from this one).
--
-- Cells bind to these; they never copy a value. That is what lets the theme
-- cell retint the whole desktop live, and it is why every palette change is
-- animated rather than applied: the four roles change in a crossing over
-- `theme` in the timing set, every derived colour is worked out once from
-- the new roles, and every colour the scene draws moves there together, so
-- the whole desktop crosses at once rather than in patches.
--
-- Four interface roles come from a theme source — matugen or a manual
-- palette file. The three state roles never do: they are a semantic code.
-- Everything else is derived here, in HSL, from the four; with the shipped
-- palette the derivations reproduce docs/design/tokens.css.
local g = require("@genoma")
local themes = require("@genoma/theme")
local config = require("core/config")
local colour = require("core/colour")
require("core/timing")

local M = {}

-- ---- Arithmetic the derivations and the cells share ------------------------------

-- Moves a colour away from the background's side, keeping hue and saturation.
local function lifted(hex: string, amount: number, dark_side: boolean): string
    local c = colour.parse(hex)
    local h, s, l = colour.hsl(c)
    local step = if dark_side then amount else -amount
    return colour.format(colour.hsla(math.max(0, h), s, math.clamp(l + step, 0, 1), c.a))
end
local lift_dark = colour.remembered(function(hex: string, amount: number) return lifted(hex, amount, true) end)
local lift_light = colour.remembered(function(hex: string, amount: number) return lifted(hex, amount, false) end)
function M.lift_away(hex: string, amount: number, dark_side: boolean): string
    return if dark_side then lift_dark(hex, amount) else lift_light(hex, amount)
end

function M.shadow_of(dark_side: boolean): string return colour.alpha("#000000", if dark_side then 0.45 else 0.22) end

-- ---- State roles (fixed, never from the theme source) ------------------------

local state_dark = { calm = "#6EE7A6", active = "#F2C14E", alert = "#FF6B5D" }
local state_light = { calm = "#2E9C6A", active = "#B37414", alert = "#C43A2E" }

local function state_of(role: string, dark_side: boolean): string
    local set = if dark_side then config.get("theme.state.dark", state_dark) else config.get("theme.state.light", state_light)
    return set[role] or (if dark_side then state_dark else state_light)[role]
end

-- ---- The outline family ------------------------------------------------------
--
-- Line, node and rim at three lightnesses of the background's hue, always:
-- the outline belongs to the ground it is drawn on, and the primary never
-- gives it its hue. A background with no hue has an outline with none, a
-- grey; on a tinted one the primary still lends the family some of its
-- strength, never its colour (Akusen, 2026-11-16: under 5 % of saturation
-- the family took the primary's hue, and a black background's borders
-- turned with every change of the primary).

local function tinted(bg: string): (boolean, number, number)
    local bh, bs = colour.hsl(colour.parse(bg))
    return bh >= 0 and bs > 0, bh, bs
end

local function hue_of(bg: string, _accent: string): number
    local has, bh = tinted(bg)
    return if has then bh else 0
end

local function saturation_of(bg: string, accent: string): number
    local has, _, bs = tinted(bg)
    if not has then return 0 end
    local _, as = colour.hsl(colour.parse(accent))
    return math.max(math.min(bs + 0.04, 0.40), math.min(as * 0.33, 0.28))
end

function M.structural_with(bg: string, accent: string, lightness: number): string
    return colour.format(colour.hsla(hue_of(bg, accent), saturation_of(bg, accent), lightness, 1))
end

-- ---- The theme -------------------------------------------------------------------

local t = themes.new {
    roles = {
        background = "#12160F",
        text = "#EAF1E6",
        primary = "#B9DE6B",
        secondary = "#3FBFA0",
    },
    dark = function(c) return colour.luminance(c.background) < 0.5 end,
    derive = {
        calm = function(c) return state_of("calm", c.dark) end,
        active = function(c) return state_of("active", c.dark) end,
        alert = function(c) return state_of("alert", c.dark) end,

        surface = function(c) return M.lift_away(c.background, 0.045, c.dark) end,
        cell = function(c) return M.lift_away(c.background, 0.075, c.dark) end,
        well_surface = function(c) return M.lift_away(c.background, 0.02, c.dark) end,

        -- Only for a secondary label nobody presses, or an option not
        -- chosen. Three steps a person can still read: muted about 7:1 on
        -- the glass, faint about 4.5:1, the floor for small text (WCAG 2.2).
        -- Faint was 0.38, 3.1:1, and most of it was labels that say what a
        -- row is for (Akusen, 2026-11-04, Piano UI 1); muted moved up with
        -- it to stay a step apart.
        text_muted = function(c) return colour.alpha(c.text, 0.70) end,
        text_faint = function(c) return colour.alpha(c.text, 0.54) end,
        -- What the keyboard has reached, or what is the chosen one in a
        -- list: a fill, never an outline. At 12% it was 1.3:1 against the
        -- glass, too faint to find; 22% keeps text on it at 7:1, and a row
        -- with an icon also rings the icon in the primary (Akusen,
        -- 2026-11-04, Piano UI 3).
        selection = function(c) return colour.alpha(c.primary, 0.22) end,
        border = function(c) return colour.alpha(c.text, if c.dark then 0.09 else 0.14) end,
        shadow = function(c) return M.shadow_of(c.dark) end,
        shadow_float = function(c) return colour.alpha("#000000", if c.dark then 0.60 else 0.30) end,

        line = function(c) return M.structural_with(c.background, c.primary, if c.dark then 0.32 else 0.72) end,
        node = function(c) return M.structural_with(c.background, c.primary, if c.dark then 0.43 else 0.62) end,
        rim = function(c) return M.structural_with(c.background, c.primary, if c.dark then 0.55 else 0.50) end,
    },
}

local function token(name: string): () -> string
    return function(): string return t.colour(name) end
end

-- ---- Interface roles ---------------------------------------------------

-- In transit, which is what cells bind to.
M.background = token("background")
M.text = token("text")
M.primary = token("primary")
M.secondary = token("secondary")

-- Where the palette is going: the theme cell's chips arrive at the
-- destination rather than chase the shell's transition.
M.target = t.target

-- While a palette is being edited the desktop follows the hand, not a
-- quarter of a second behind it: the editor shows its draft at once
-- (M.show) and the file it writes behind the hand is not followed until the
-- hand rests (services/palettes.luau). Not kept across a reload: left on,
-- no palette file would be followed again.
M.immediate = t.immediate

-- A palette shown before it is on disk: the editor's draft. Only its roles
-- are taken.
function M.show(palette: { [string]: any }?)
    if not palette then return end
    local roles = {}
    for _, role in t.roles() do
        if type(palette[role]) == "string" then roles[role] = palette[role] end
    end
    t.set(roles)
end

-- ---- Light or dark -------------------------------------------------------

M.is_dark = t.is_dark

-- ---- State roles -------------------------------------------------------------

M.calm = token("calm")
M.active = token("active")
M.alert = token("alert")

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

function M.lift(hex: string, amount: number): string return M.lift_away(hex, amount, M.is_dark()) end

M.surface = token("surface")
M.elevated = M.surface
M.cell = token("cell")
M.well_surface = token("well_surface")
M.text_muted = token("text_muted")
M.text_faint = token("text_faint")
M.selection = token("selection")
M.border = token("border")
M.shadow = token("shadow")
M.shadow_float = token("shadow_float")
M.line = token("line")
M.node = token("node")
M.rim = token("rim")

-- The outline of something that is pressed or typed into: a field, a chip,
-- an outlined button, a segmented or switch track. `node`, which reads at
-- 3.5:1 on the glass where `line` read at 2.2:1, under the 3:1 a control's
-- edge needs (Akusen, 2026-11-04, Piano UI 2). Threads, separators and
-- surfaces keep `line`. One place to take it back.
M.control_edge = M.node
-- A row's tools (the trash, a cross, a row's pencil) at rest: there to be
-- found and reached, quieter than under the pointer. They were 0, so they
-- could be neither discovered nor reached without a pointer (Akusen,
-- 2026-11-04, Piano UI 5). An opacity, the same for every tool.
M.tool_rest = 0.45

-- ---- Gradients -----------------------------------------------------------------
--
-- One light source from above, the same across the shell: two tones of one
-- hue, the top lighter, the bottom darker and more saturated.

M.gradient_angle = 165

M.gradient_top = colour.remembered(function(hex: string, _: nil): string
    local c = colour.parse(hex)
    local h, s, l = colour.hsl(c)
    return colour.format(colour.hsla(math.max(0, h), math.min(1, s + 0.14), math.min(1, l + 0.16), c.a))
end) :: (string) -> string

M.gradient_bottom = colour.remembered(function(hex: string, _: nil): string
    local c = colour.parse(hex)
    local h, s, l = colour.hsl(c)
    return colour.format(colour.hsla(math.max(0, h), math.max(0, s - 0.15), math.max(0, l - 0.15), c.a))
end) :: (string) -> string

-- ---- The source ----------------------------------------------------------------

local home = (g.env("XDG_CONFIG_HOME") or (g.env("HOME") or "") .. "/.config")
M.matugen_path = home .. "/bioma/generated/palette.json"
M.user_palettes = home .. "/bioma/palettes"
M.shipped_palettes = g.dir .. "/../config/palettes"

-- The picture matugen's palette was made from, as its file says.
M.generated_image = g.state("theme.generated_image", "")

-- The file the source names, followed: matugen's, or a manual palette
-- looked for among the user's own first, then the shipped ones. Read where
-- the theme follows it, so a new source or palette replaces the watch.
t.source {
    path = function(): string
        if config.get("theme.source", "manual") == "matugen" then return M.matugen_path end
        local name = config.get("theme.palette", "default")
        local own = M.user_palettes .. "/" .. name .. ".json"
        local probe = g.file { path = own, watch = false }
        return if probe.text then own else M.shipped_palettes .. "/" .. name .. ".json"
    end,
    map = function(palette: any): { [string]: string }
        -- The hand leads while a palette is edited; what was written a
        -- moment ago would pull the desktop back.
        if g.untracked(function() return M.immediate.value end) then return {} end
        if type(palette.image) == "string" and palette.image ~= "" then M.generated_image.value = palette.image end
        return palette
    end,
}

-- ---- What the theme cell shows ----------------------------------------------------
--
-- The palette at rest: seven roles, of the destination rather than the
-- transit, so a chip bound to them moves once per change and not on every
-- frame of the crossing. The state colours are not among them.

function M.target_is_dark(): boolean return colour.luminance(M.target("background")) < 0.5 end
-- A state colour for the palette at rest: what the state roles will be once
-- the crossing is over (the desktop's theme file, services/desktop_theme).
function M.target_state(role: string): string return state_of(role, M.target_is_dark()) end

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
