--!strict
-- Geometry (core/Metrics.qml): logical units, the figures of
-- docs/design/tokens.css at the `normal` step. Scale is a discrete step set
-- and a membrane's property; hairlines do not take it — Genoma's `crisp`
-- lands them on whole physical pixels.
local config = require("core/config")

local M = {}

M.cell_height = 40
M.row_height = 30
M.field_height = 40
M.radius_panel = 20
M.radius_well = 10
M.pill_ceiling = 110
M.organism_unit = 200
M.thread = 1.3
M.node_size = 2.5
M.rim_width = 1

-- The three margins a person may move (appearance.edge, .gap, and the
-- tissue's padding, clamped so it stays a margin rather than a tray).
function M.margin_edge(): number return config.get("appearance.edge", 12) end
function M.gap_shape(): number return config.get("appearance.gap", 24) end
function M.margin_tissue(): number return math.clamp(config.get("tissue.padding", 2), 2, 12) end

-- How round the shell is, 0…100 of every surface's own radius.
function M.radius_percent(): number return math.clamp(config.get("appearance.radius", 100), 0, 100) end
function M.shaped(radius: number): number return radius * M.radius_percent() / 100 end

-- The glass's strength in ten steps, as niri is given it (services/Looks.qml).
M.blur_steps = {
    { passes = 1, offset = 1.5 }, { passes = 2, offset = 1.5 }, { passes = 2, offset = 3 },
    { passes = 3, offset = 2 }, { passes = 3, offset = 3 }, { passes = 3, offset = 4.5 },
    { passes = 4, offset = 3 }, { passes = 4, offset = 4.5 }, { passes = 5, offset = 3.5 },
    { passes = 5, offset = 5 },
}
function M.blur_strength(): number
    return math.clamp(math.floor(config.get("cell.blurStrength", 5) + 0.5), 1, #M.blur_steps)
end
-- The glass the shell draws itself, matched to niri's.
function M.blur_radius(): number
    local s = M.blur_steps[M.blur_strength()]
    return math.min(64, 20 * s.offset * 2 ^ s.passes / 24)
end

M.factors = { compact = 0.85, normal = 1.0, comfortable = 1.15 }

function M.factor(name: string?): number
    return M.factors[name or "normal"] or 1.0
end

-- Everything a membrane, a tissue or a cell needs at one step. Density
-- values scale; hairlines do not. Font sizes are whole pixels.
function M.step(name: string?): { [string]: any }
    local f = M.factor(name)
    return {
        name = if M.factors[name or ""] then name else "normal",
        factor = f,
        cell_height = M.cell_height * f,
        row_height = M.row_height * f,
        field_height = M.field_height * f,
        margin_edge = M.margin_edge() * f,
        tissue_padding = M.margin_tissue() * f,
        gap = M.gap_shape() * f,
        radius_panel = M.shaped(M.radius_panel * f),
        radius_well = M.shaped(M.radius_well * f),
        pill_ceiling = M.pill_ceiling * f,
        thread = M.thread,
        node_size = M.node_size,
        rim_width = M.rim_width,
        blur_radius = M.blur_radius() * f,
        organism_unit = M.organism_unit * f,
        font_value = math.floor(20 * f + 0.5),
        font_label = math.floor(15 * f + 0.5),
        font_secondary = math.floor(13 * f + 0.5),
        font_meta = math.floor(11 * f + 0.5),
        font_title = math.floor(14.5 * f + 0.5),
    }
end

-- What a band needs to hold these widths: the cells, the band showing
-- between each pair (twice the padding), and the margin on both sides.
function M.room_for(widths: { number }, m: { [string]: any }?): number
    local s = m or M.step("normal")
    local total = s.tissue_padding * 2
    for i, w in widths do
        total += (if i > 1 then s.tissue_padding * 2 else 0) + w * s.factor
    end
    return total
end

-- A pill up to the ceiling, the panel radius above it.
function M.radius_for(height: number, m: { [string]: any }?): number
    local s = m or M.step("normal")
    return if height <= s.pill_ceiling then M.shaped(height / 2) else s.radius_panel
end

-- Concentric by construction.
function M.inner_radius(outer: number, inset: number): number
    return math.max(0, outer - inset)
end

return M
