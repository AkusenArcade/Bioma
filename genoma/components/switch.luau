--!strict
-- A switch (components/Switch.qml): off, a well with a knob in the faint
-- text; on, the primary's light with a knob in the background colour, the
-- knob travelling between them.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")

local M = {}

-- `t`: on(), factor(), on_toggle(on), and settling() for a change on its
-- way (a radio powering up): faint and deaf until it has arrived.
function M.new(t: { [string]: any }): any
    local function f(): number return t.factor() end
    local function w(): number return 42 * f() end
    local function h(): number return 24 * f() end
    local function knob(): number return 16 * f() end
    local function inset(): number return (h() - knob()) / 2 end
    return g.capsule {
        role = "button",
        name = "Switch",
        width = w,
        height = h,
        radius = function() return metrics_mod.shaped(h() / 2) end,
        fill = function()
            return if t.on() then theme.gradient_top(theme.primary())
                else colour.alpha(theme.lift(theme.background(), -0.01), 0.9)
        end,
        fill_bottom = function()
            return if t.on() then theme.gradient_bottom(theme.primary())
                else colour.alpha(theme.lift(theme.background(), -0.01), 0.9)
        end,
        rim_top = function() return if t.on() then "#00000000" else theme.line() end,
        rim_bottom = function() return if t.on() then "#00000000" else theme.line() end,
        opacity = function() return if t.settling and t.settling() then 0.6 else 1 end,
        on_click = function()
            if t.settling and g.untracked(t.settling) then return end
            t.on_toggle(not g.untracked(t.on))
        end,
        transition = { fill = "transition", fill_bottom = "transition", rim_top = "transition", rim_bottom = "transition", opacity = "transition" },
        g.capsule {
            overlay = true,
            attach = "corner",
            width = knob,
            height = knob,
            radius = function() return metrics_mod.shaped(knob() / 2) end,
            offset_x = function() return if t.on() then w() - knob() - inset() else inset() end,
            offset_y = inset,
            fill = function() return if t.on() then theme.background() else colour.alpha(theme.text(), 0.45) end,
            transition = { offset_x = "transition", fill = "transition" },
        },
    }
end

return M
