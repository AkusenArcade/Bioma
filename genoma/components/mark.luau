--!strict
-- Bioma's mark drawing itself (assets/icons/mark.svg, on its 24 grid): the
-- capsule from the middle of its top round to where it began, then the
-- thread from the middle out to both sides, and a node budding at each end
-- as the thread reaches it. The way Genoma's own mark comes in the
-- showcase, which is this capsule with a strand in place of the thread.
--
-- `t.size()` the side of the mark's 24 grid, logical units; `t.drawn()`
-- true draws it, false takes it back. The timing names: `t.draw` the
-- capsule, `t.thread` the thread, `t.node` the nodes.
local g = require("@genoma")
local theme = require("core/theme")

local M = {}

-- The mark's drawing, in its 24 grid.
local X0, Y0, W0, H0, LINE = 6.6, 2.6, 10.8, 18.8, 1.5
local LEFT, RIGHT, MIDDLE = 2.6, 21.4, 12
local NODE = 1.5

local function fmt(n: number): string return string.format("%.2f", n) end

function M.new(t: { [string]: any }): any
    local function k(): number return t.size() / 24 end
    local function drawn(): number return if t.drawn() then 1 else 0 end

    -- The capsule from the middle of its top, clockwise, closing where it
    -- began.
    local function capsule_d(): string
        local s = k()
        local x0, y0, w, h = X0 * s, Y0 * s, W0 * s, H0 * s
        local r = w / 2
        local cx = x0 + r
        return table.concat({
            "M", fmt(cx), fmt(y0),
            "A", fmt(r), fmt(r), "0 0 1", fmt(x0 + w), fmt(y0 + r),
            "L", fmt(x0 + w), fmt(y0 + h - r),
            "A", fmt(r), fmt(r), "0 0 1", fmt(x0), fmt(y0 + h - r),
            "L", fmt(x0), fmt(y0 + r),
            "A", fmt(r), fmt(r), "0 0 1", fmt(cx), fmt(y0),
        }, " ")
    end
    -- Half the thread, from the middle out to `to`.
    local function half_d(to: number): () -> string
        return function()
            local s = k()
            return "M " .. fmt(MIDDLE * s) .. " " .. fmt(MIDDLE * s) .. " L " .. fmt(to * s) .. " " .. fmt(MIDDLE * s)
        end
    end

    -- One light from above, as every lit shape: the primary's two tones down
    -- the mark's height, in each stroke's own units (all share the grid).
    local function paint(): { number }
        return { 1, 0, 1, 0, 0, 1, 0, 0, 0, Y0 * k(), 0, (Y0 + H0) * k() }
    end
    local function stops(): { any }
        local p = theme.primary()
        return { { 0, theme.gradient_top(p) }, { 1, theme.gradient_bottom(p) } }
    end

    -- `hidden`: a line of no length still shows its round cap, a dot where
    -- it will start; the thread's halves wait unseen until they leave.
    local function stroke(d: () -> string, timing: string, hidden: boolean?): any
        return g.path {
            opacity = if hidden then drawn else nil,
            overlay = true,
            attach = "corner",
            width = t.size,
            height = t.size,
            d = d,
            stroke = function() return LINE * k() end,
            cap = "round",
            join = "round",
            stroke_paint = paint,
            stroke_stops = stops,
            trim_end = drawn,
            transition = { trim_end = timing, opacity = if hidden then timing else nil },
        }
    end
    -- A node grows out of the thread's end, its middle kept where it is.
    local function node(x: number): any
        local function d(): number return if t.drawn() then NODE * 2 * k() else 0 end
        return g.capsule {
            overlay = true,
            attach = "corner",
            width = d,
            height = d,
            offset_x = function() return x * k() - d() / 2 end,
            offset_y = function() return MIDDLE * k() - d() / 2 end,
            fill = function() return theme.primary() end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            transition = { width = t.node, height = t.node, offset_x = t.node, offset_y = t.node },
        }
    end

    local function strokes(): any
        return g.box {
            overlay = true,
            attach = "corner",
            width = t.size,
            height = t.size,
            stroke(capsule_d, t.draw),
            stroke(half_d(LEFT), t.thread, true),
            stroke(half_d(RIGHT), t.thread, true),
            node(LEFT),
            node(RIGHT),
        }
    end

    -- Drawn twice: softened beneath, a light the line gives off, and sharp
    -- over it.
    return g.box {
        width = t.size,
        height = t.size,
        g.box {
            overlay = true,
            attach = "corner",
            opacity = 0.5,
            blur_radius = function() return 1.6 * k() end,
            strokes(),
        },
        g.box { overlay = true, attach = "corner", strokes() },
    }
end

return M
