--!strict
-- One edge of one monitor (structure/Membrane.qml). Tissues anchored to it
-- share its length; `reserve_space`, `auto_hide` and `scale` govern every
-- tissue and cell on it.
--
-- The surface is the size of the output for the whole session and reserves
-- only its strip: resizing a layer surface draws its content once at each
-- size (Akusen saw the bar twice, 2026-09-22). Its input and its blur are
-- the cells' shapes and nothing else, which Genoma takes from the nodes.
local g = require("@genoma")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local tissue_mod = require("structure/tissue")

local M = {}

-- Growth moves away from the anchor, so the anchor has to be known: from
-- the block's place in the list (the three-tissue default reads left,
-- centre, right), unless it says otherwise.
local function anchor_for(index: number, entry: { [string]: any }, count: number): string
    if entry.anchor then return entry.anchor end
    if entry.growth == "symmetric" then return "centre" end
    if index == 1 then return "start" end
    if index == count then return "end" end
    return "centre"
end

-- `block()` is the membrane's configuration block, `output` its monitor,
-- `size` the output's logical size. Returns the surface's tree and what the
-- surface needs to be told (anchor, reserve, namespace).
function M.new(block: () -> { [string]: any }, output: string, size: { width: number, height: number })
    local m: { [string]: any } = {}
    local first = g.untracked(block)
    local edge = first.edge or "top"
    local horizontal = edge == "top" or edge == "bottom"
    m.edge = edge

    local function metrics() return metrics_mod.step(block().scale or "normal") end

    local function tissue_thickness(): number
        local s = metrics()
        return s.cell_height + s.tissue_padding * 2
    end

    -- The strip the membrane occupies: the edge margin is a frame, not a
    -- surface, but the windows must not cover it either.
    function m.strip(): number return metrics().margin_edge + tissue_thickness() end

    -- Only horizontal edges may reserve, and an auto-hiding one never does.
    function m.reserving(): boolean
        local b = block()
        return b.reserve_space == true and horizontal and b.auto_hide ~= true
    end

    -- Where the compositor starts drawing windows: past the strip by niri's
    -- `gaps` and the edge's strut, which come with the niri service (step
    -- 3). Until then the line is the strip's own edge.
    local function window_inset(): number return 0 end
    local function window_line(): number
        if edge == "top" or edge == "left" then return m.strip() + window_inset() end
        return (if horizontal then size.height else size.width) - m.strip() - window_inset()
    end

    local membrane_length = if horizontal then size.width else size.height
    local function usable(): number return math.max(0, membrane_length - metrics().margin_edge * 2) end

    -- The tissues, built once per load.
    local entries = first.tissues or {}
    local tissues = {}
    for index, entry in entries do
        local i = index
        local function tblock() return (block().tissues or {})[i] or entry end
        local anchor = anchor_for(i, entry, #entries)
        local t = tissue_mod.new({
            block = tblock,
            metrics = metrics,
            output = output,
            edge = edge,
            output_width = function() return size.width end,
            anchor_side = function() return anchor end,
            slot_length = function() return (tblock().percentage or 0) / 100 * usable() end,
            padding = function()
                local p = tblock().padding
                if p ~= nil then return math.clamp(p, 2, 12) * metrics().factor end
                return metrics().tissue_padding
            end,
            fill_opacity = function()
                local o = tblock().opacity
                return if o ~= nil then o else config.get("tissue.opacity", 0.5)
            end,
            window_line = window_line,
            horizontal = function()
                local o = tblock().orientation
                if o then return o == "horizontal" end
                return horizontal
            end,
        })
        t.anchor = anchor
        table.insert(tissues, t)
    end

    local function along(t: any): number return if horizontal then t.width() else t.height() end

    local function run_length(side: string): number
        local total = 0
        for _, t in tissues do
            if t.visible() and t.anchor == side then total += along(t) + metrics().margin_edge end
        end
        return total
    end

    -- Tissues of one anchor stack in declared order; the centred ones are
    -- centred as a group, then clamped between what the corner tissues hold.
    -- The margin is measured to the cell, not the band, so the outermost
    -- cell lines up with the edge of the windows.
    local function offset_for(t: any, index: number): number
        local margin = metrics().margin_edge
        local outer = math.max(0, margin - t.padding())
        local start_run, end_run, centre_total, centre_before = 0, 0, 0, 0
        for i, other in tissues do
            if other.visible() then
                local length = along(other)
                if other.anchor == "start" and i < index then start_run += length + margin
                elseif other.anchor == "end" and i > index then end_run += length + margin end
                if other.anchor == "centre" then
                    centre_total += length + (if centre_total > 0 then margin else 0)
                    if i < index then centre_before += length + margin end
                end
            end
        end
        local own = along(t)
        if t.anchor == "start" then return outer + start_run end
        if t.anchor == "end" then return membrane_length - outer - end_run - own end
        local group = (membrane_length - centre_total) / 2
        local left = margin + run_length("start")
        local right = membrane_length - margin - run_length("end")
        if group < left then group = left end
        if group + centre_total > right then group = math.max(left, right - centre_total) end
        return group + centre_before
    end

    -- The distance from the screen edge: a thin frame the tissue never
    -- touches, and an expansion grows away from it.
    local function cross_offset(): number
        if edge == "top" or edge == "left" then return metrics().margin_edge end
        local across = if horizontal then size.height else size.width
        return across - metrics().margin_edge - tissue_thickness()
    end

    local root: { [any]: any } = {
        width = size.width,
        height = size.height,
    }
    for i, t in tissues do
        local index = i
        local position = {
            x = function() return if horizontal then offset_for(t, index) else cross_offset() end,
            y = function() return if horizontal then cross_offset() else offset_for(t, index) end,
        }
        table.insert(root, t.node(position))
    end
    m.tree = g.box(root)
    m.tissues = tissues
    return m
end

return M
