--!strict
-- What every settings page is built from (the `Section`, `Line` and row
-- components each page of cells/settings/ declares for itself).
--
-- A page is wells, one per thing a person decides, each with its label in
-- the technical face, perhaps its control on the same line, then a line in
-- Spectral saying what the current choice does: a page of bare rows says
-- nothing a person can check against (Akusen, 2026-09-29).
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")

local M = {}

-- `t`: metrics(), width(). The helpers are measured from both.
function M.new(t: { [string]: any }): any
    local p = {}
    local function m(): any return t.metrics() end
    local function f(): number return m().factor end
    function p.factor(): number return f() end
    function p.inset(): number return 14 * f() end
    function p.header(): number return 28 * f() end
    -- The width inside a well.
    function p.inner(): number return t.width() - p.inset() * 2 end

    -- What a person reads, so the human voice. `color` for a line that
    -- warns.
    function p.line(text: () -> string, color: (() -> string)?): any
        return g.text {
            text = text,
            color = color or theme.text,
            font = typography.expressive,
            size = function() return m().font_secondary end,
            max_width = p.inner,
            wrap = true,
        }
    end

    -- A small label in the technical face, faint: what a row is for.
    function p.label(text: string | () -> string): any
        return g.text {
            text = text,
            color = theme.text_faint,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end

    -- A row inside a well: what it is for on the left, its control on the
    -- right.
    function p.row(label: string | () -> string, control: any): any
        return g.box {
            width = p.inner,
            direction = "row",
            align = "center",
            justify = "between",
            p.label(label),
            control,
        }
    end

    -- A well: its label, perhaps its control on the same line, then what
    -- it means. `present` for a well that is there only sometimes.
    function p.section(label: string | () -> string, trailing: any?, body: { any }, present: (() -> boolean)?): any
        local well: { [any]: any } = {
            present = present,
            width = t.width,
            padding = p.inset,
            direction = "column",
            align = "start",
            gap = function() return 6 * f() end,
            radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
            fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            g.box {
                width = p.inner,
                height = p.header,
                direction = "row",
                align = "center",
                justify = "between",
                g.text {
                    text = label,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tracking = typography.label_tracking,
                },
                trailing or g.box {},
            },
        }
        for _, node in body do table.insert(well, node) end
        return g.capsule(well)
    end

    -- The page itself: its wells in a column, ten apart.
    function p.column(wells: { any }): any
        local out: { [any]: any } = {
            width = t.width,
            direction = "column",
            align = "start",
            gap = function() return 10 * f() end,
        }
        for _, node in wells do table.insert(out, node) end
        return g.box(out)
    end

    return p
end

return M
