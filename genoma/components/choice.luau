--!strict
-- A choice in a question (components/Choice.qml): Cancel, Close. Outlined
-- in the line colour when plain; filled with the primary's light, or the
-- alert's for one that cannot be undone.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local typography = require("core/typography")
local metrics_mod = require("core/metrics")

local M = {}

-- `t`: label, kind ("plain" | "primary" | "alert"), metrics(), on_click(),
-- marked() (the keyboard's mark is on it).
function M.new(t: { [string]: any }): any
    local kind = t.kind or "plain"
    local filled = kind ~= "plain"
    local function f(): number return t.metrics().factor end
    local function size(): number return math.round(12 * f()) end
    local function base(): string return if kind == "alert" then theme.alert() else theme.primary() end
    local function height(): number return 26 * f() end
    return g.capsule {
        role = "button",
        name = t.label,
        height = height,
        padding_x = function() return 12 * f() end,
        radius = function() return metrics_mod.radius_for(height(), t.metrics()) end,
        align = "center",
        justify = "center",
        fill = function()
            if filled then return theme.gradient_top(base()) end
            return if t.marked and t.marked() then colour.alpha(theme.primary(), 0.12) else "#00000000"
        end,
        fill_bottom = function() return if filled then theme.gradient_bottom(base()) else "#00000000" end,
        rim_top = function() return if filled then "#00000000" else theme.line() end,
        rim_bottom = function() return if filled then "#00000000" else theme.line() end,
        on_click = t.on_click,
        g.text {
            text = t.label,
            font = typography.technical,
            size = size,
            weight = if filled then typography.weight_title else typography.weight_label,
            tracking = 0.04,
            color = function() return if filled then theme.background() else colour.alpha(theme.text(), 0.72) end,
        },
    }
end

return M
