--!strict
-- Light on the glass: the optional effects of Settings → Appearance →
-- EFFECTS. Each is a switch, off unless it is turned on: the design's
-- surfaces are flat (STYLE_GUIDE §4, "no glow, anywhere"), and these are
-- the person's to choose (Akusen, 2026-11-18). Each still says something:
--
--   pointer light   a soft light under the pointer, on the shape it is
--                   over and only there: the datum is where the pointer
--                   is. Still pointer, still light; elsewhere, none.
--   inner light     the glass catching light from above, inside its
--                   edge: static, drawn once, nothing at rest.
--   alert glow      a cell in alert glows in the alert colour, the
--                   further past its threshold the stronger (alarm()).
--
-- The lock screen and the greeter dress their glass the same way
-- (an Appearance setting reaches them too).
local g = require("@genoma")
local config = require("core/config")
local colour = require("core/colour")
local theme = require("core/theme")
local paths = require("core/paths")

local M = {}

local SHADER = paths.root .. "/genoma/components/light.wgsl"
local CLEAR = "#00000000"

function M.pointer_on(): boolean return config.get("appearance.pointer_light", false) == true end
function M.inner_on(): boolean return config.get("appearance.inner_light", false) == true end
function M.glow_on(): boolean return config.get("appearance.alert_glow", false) == true end
-- How strong the light at the pointer is, a percentage of the drawn one
-- (Appearance → LIGHT AT THE POINTER's slider).
M.STRENGTH = { from = 25, to = 300, step = 5, fallback = 100 }
function M.pointer_strength(): number
    return math.clamp(config.get("appearance.pointer_light_strength", M.STRENGTH.fallback), M.STRENGTH.from, M.STRENGTH.to)
end
-- How it looks: "soft", a plain glow, or "bioluminescent", a living
-- pattern in the background's own hue that the hand stirs (light.wgsl).
function M.pointer_style(): string
    return if config.get("appearance.pointer_light_style", "soft") == "bioluminescent" then "bioluminescent" else "soft"
end

-- White, as light is; stronger over a light palette's glass, which is
-- already near it.
local function white(dark: number, light: number): string
    return colour.alpha("#ffffff", if theme.is_dark() then dark else light)
end

-- The light at the pointer, over a glass shape's content and under what
-- buds out of it: under the content, the wells and rows with a fill of
-- their own hid it, and it stopped at their edges. It takes no hit of its
-- own (Genoma: a shader that reads the pointer leaves the hit to what is
-- under it), so what is under it keeps its hover and its press.
-- `t`: width(), height(), radius(),
-- factor(), and lit(), when it is wanted (the pointer on the shape): a
-- shader that reads the pointer is drawn again at every move, so it is
-- there only while it can be seen.
function M.pointer(t: { [string]: any }): any
    return g.shader {
        name = "Light",
        overlay = true,
        attach = "corner",
        width = t.width,
        height = t.height,
        present = function() return M.pointer_on() and (t.lit == nil or t.lit()) end,
        src = SHADER,
        follow = 0,
        values = function()
            local w, h = t.width(), t.height()
            local r = math.min(t.radius(), w / 2, h / 2)
            if M.pointer_style() == "bioluminescent" then
                -- In the glass's own hue, two steps away from it: the light
                -- is the glass's, not an accent's (Akusen, 2026-11-18).
                local bg = theme.background()
                local first, second = colour.parse(theme.lift(bg, 0.45)), colour.parse(theme.lift(bg, 0.8))
                local a = math.min(1, (if theme.is_dark() then 0.6 else 0.8) * M.pointer_strength() / 100)
                return { r, first.r, first.g, first.b, a, 64 * t.factor(), 1, second.r, second.g, second.b }
            end
            local c = colour.parse(white(0.1, 0.42))
            local a = math.min(1, c.a * M.pointer_strength() / 100)
            return { r, c.r, c.g, c.b, a, 46 * t.factor(), 0, 0, 0, 0 }
        end,
    }
end

-- The glass catching light from above: a pale inner glow along the top
-- edge, fading down. Sets it on a capsule's props.
function M.inner(props: { [any]: any }, factor: () -> number)
    props.inner_shadow = function() return if M.inner_on() then white(0.17, 0.6) else CLEAR end
    props.inner_blur = function() return 12 * factor() end
    props.inner_y = function() return 6 * factor() end
    local tr = props.transition or {}
    tr.inner_shadow = "colour"
    props.transition = tr
end

-- Both lights on a glass shape written inline: its props, returned.
-- `pointer`, when the shape answers the pointer, is what M.pointer takes.
function M.glass(props: { [any]: any }, factor: () -> number, pointer: { [string]: any }?): { [any]: any }
    M.inner(props, factor)
    if pointer then table.insert(props, M.pointer(pointer)) end
    return props
end

-- Both lights on any glass shape, its measures read from its own props
-- (width, height, radius: numbers or functions): what buds out of a panel
-- (a theme's source and palette, the vitals' pods, the clock's sides) is
-- glass as the panel is, and lit the same. `lit()` while it can be seen.
local function read(v: any): number
    if type(v) == "function" then return v() end
    return if type(v) == "number" then v else 0
end
function M.dress(props: { [any]: any }, factor: () -> number, lit: (() -> boolean)?): { [any]: any }
    return M.glass(props, factor, {
        width = function() return read(props.width) end,
        height = function() return read(props.height) end,
        radius = function() return read(props.radius) end,
        factor = factor,
        lit = lit,
    })
end

-- A cell in alert: a glow outside its pill, in `tint` (the alert colour
-- unless it says another), as strong as `alarm()` says, 0 to 1. Nothing
-- when off or calm. Sets it on a capsule's props.
function M.glow(props: { [any]: any }, alarm: () -> number, tint: () -> string?, factor: () -> number)
    local function amount(): number
        if not M.glow_on() then return 0 end
        return math.clamp(alarm(), 0, 1)
    end
    props.shadow = function()
        local a = amount()
        if a <= 0 then return CLEAR end
        return colour.alpha(tint() or theme.alert(), 0.35 + 0.4 * a)
    end
    props.shadow_blur = function() return (6 + 10 * amount()) * factor() end
    props.shadow_spread = function() return amount() * factor() end
    local tr = props.transition or {}
    tr.shadow = "colour"
    tr.shadow_blur = "colour"
    tr.shadow_spread = "colour"
    props.transition = tr
end

return M
