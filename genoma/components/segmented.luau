--!strict
-- A segmented control (components/Segmented.qml): two or three options,
-- one of them chosen.
--
-- The selection slides to the chosen option at the transition timing; it
-- does not vanish on one side and appear on the other. That, the switch's
-- knob and the slider's travel are the movements that answer a gesture.
-- The chosen option carries the primary gradient and takes the colour of
-- the fill it sits on: a control, not a surface, so it never takes the rim.
--
-- Not yet: the keyboard's mark and Left/Right (shell-wide travel, to come).
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local typography = require("core/typography")
local metrics_mod = require("core/metrics")

local M = {}

-- `t`: options() ({ { key, label } } or { { key, icon } }; `dimmed` to
-- show one that cannot be chosen), current(), on_choose(key), metrics(),
-- and optionally font_size(), button_height(), icon_size(), icon_padding().
function M.new(t: { [string]: any }): any
    local function f(): number return t.metrics().factor end
    local function font_size(): number return if t.font_size then t.font_size() else math.round(12 * f()) end
    local function button_height(): number return if t.button_height then t.button_height() else 26 * f() end
    local function icon_size(): number return if t.icon_size then t.icon_size() else 14 * f() end
    local function icon_padding(): number return if t.icon_padding then t.icon_padding() else 8 * f() end
    local function pad(): number return 3 * f() end
    local function gap(): number return 2 * f() end

    -- Every option measured at the chosen one's weight, so the pill does not
    -- resize on selection: a second animation over the one meant to be seen.
    local function width_of(option: any): number
        if option.icon then return icon_size() + icon_padding() * 2 end
        return g.text_width {
            text = option.label or "",
            font = typography.technical(),
            size = font_size(),
            weight = typography.weight_title,
            tracking = 0.04,
        } + 14 * f() * 2
    end

    -- Where the chosen one starts, and how wide it is.
    local function selection(): (number, number)
        local x = 0
        for _, option in t.options() do
            local w = width_of(option)
            if option.key == t.current() then return x, w end
            x += w + gap()
        end
        return 0, 0
    end
    local function track_width(): number
        local w = 0
        for i, option in t.options() do w += width_of(option) + (if i > 1 then gap() else 0) end
        return w + pad() * 2
    end
    local function track_height(): number return button_height() + pad() * 2 end

    return g.capsule {
        role = "group",
        width = track_width,
        height = track_height,
        radius = function() return metrics_mod.radius_for(track_height(), t.metrics()) end,
        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
        rim_top = theme.line,
        rim_bottom = theme.line,
        g.capsule {
            overlay = true,
            attach = "corner",
            present = function() local _, w = selection(); return w > 0 end,
            offset_x = function() local x = selection(); return pad() + x end,
            offset_y = pad,
            width = function() local _, w = selection(); return w end,
            height = button_height,
            radius = function() return metrics_mod.radius_for(button_height(), t.metrics()) end,
            fill = function() return theme.gradient_top(theme.primary()) end,
            fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            transition = { offset_x = "transition", width = "transition" },
        },
        g.each {
            overlay = true,
            attach = "corner",
            offset_x = pad,
            offset_y = pad,
            direction = "row",
            gap = gap,
            items = t.options,
            key = function(option: any) return option.key end,
            row = function(option: () -> any)
                local function chosen(): boolean return option().key == t.current() end
                local function dimmed(): boolean return option().dimmed == true end
                local function ink(): string
                    if chosen() then return theme.background() end
                    return if dimmed() then theme.text_faint() else theme.text_muted()
                end
                return g.box {
                    role = "button",
                    width = function() return width_of(option()) end,
                    height = button_height,
                    align = "center",
                    justify = "center",
                    on_click = function()
                        local o = g.untracked(option)
                        if o.dimmed ~= true then t.on_choose(o.key) end
                    end,
                    g.text {
                        present = function() return option().icon == nil end,
                        text = function() return option().label or "" end,
                        color = ink,
                        font = typography.technical,
                        size = font_size,
                        weight = typography.weight_title,
                        tracking = 0.04,
                    },
                    g.icon {
                        present = function() return option().icon ~= nil end,
                        width = icon_size,
                        height = icon_size,
                        icon = function() return option().icon or "" end,
                        color = ink,
                    },
                }
            end,
        },
    }
end

return M
