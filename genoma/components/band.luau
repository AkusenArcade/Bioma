--!strict
-- The audio band (components/Band.qml): small vertical capsules mirrored
-- from the centre, or one of the fluids (components/fluid.luau).
--
-- Two symmetries, not the same one. A bar grows from the middle line, up
-- and down, never from a floor: filling from the bottom is how memory is
-- drawn, and sound is a displacement either side of nothing. And the row is
-- mirrored about its middle: the left wing is the left channel, the right
-- wing the right, the lows meeting at the centre and the highs outside.
--
-- The gradient is the band's, not a bar's: a short bar samples the middle
-- of it, a tall one runs its length. Qt masks one gradient with the bars;
-- here each bar is filled with the stretch of the band's gradient it covers,
-- which is the same picture.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local fluid = require("components/fluid")

local M = {}

-- `t`: left(), right(), count(), bar_width(), pitch(), base(), effect(),
-- width(), height().
function M.new(t: { [string]: any }): any
    local function fluid_form(): boolean return fluid.forms[t.effect()] == true end

    local function value_at(index: number): number
        local half = t.count() // 2
        local mirrored = index < half
        local list = if mirrored then t.left() else t.right()
        local place = if mirrored then half - 1 - index else index - half
        return list[place + 1] or 0
    end

    -- A bar with nothing in it is a dot, not a gap: an instrument with
    -- missing teeth reads as broken rather than quiet.
    -- Hidden under a fluid, a bar reads nothing: sixty readings a second
    -- would otherwise reach bars nobody sees.
    local function height_at(index: number): number
        if fluid_form() then return t.bar_width() end
        return math.max(t.bar_width(), math.clamp(value_at(index), 0, 1) * t.height())
    end
    -- The band's gradient, once per colour rather than once per bar a frame.
    local ends = g.computed(function()
        return { theme.gradient_top(t.base()), theme.gradient_bottom(t.base()) }
    end)

    local bars: { [any]: any } = {
        direction = "row",
        align = "center",
        gap = function() return t.pitch() - t.bar_width() end,
        present = function() return not fluid_form() end,
    }
    -- Fourteen in Bioma's cell; the count is the cell's, fixed at mount.
    for i = 0, g.untracked(t.count) - 1 do
        local function h(): number return height_at(i) end
        local function along(y: number): string
            local e = ends.value
            return colour.mix(e[1], e[2], math.clamp(y / math.max(t.height(), 1), 0, 1))
        end
        table.insert(bars, g.capsule {
            width = t.bar_width,
            height = h,
            fill = function() return along((t.height() - h()) / 2) end,
            fill_bottom = function() return along((t.height() + h()) / 2) end,
            -- The value is the data; the easing is the only thing here that
            -- is not. A bar that snapped between frames would flicker.
            transition = { height = "band", fill = "band", fill_bottom = "band" },
        })
    end

    return g.box {
        width = t.width,
        height = t.height,
        align = "center",
        justify = "center",
        g.box(bars),
        fluid.new {
            left = t.left,
            right = t.right,
            count = t.count,
            bar_width = t.bar_width,
            pitch = t.pitch,
            base = t.base,
            form = t.effect,
            width = t.width,
            height = t.height,
            present = fluid_form,
        },
    }
end

return M
