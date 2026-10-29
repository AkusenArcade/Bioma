--!strict
-- A positioned container (structure/Tissue.qml): anchor, orientation,
-- padding, opacity and the ordered list of its cells. It has no opinion about
-- what a cell shows.
--
-- The percentage a tissue declares is a ceiling, not a reservation: the
-- tissue is as long as its visible cells need, up to that ceiling, so tissues
-- on one membrane cannot collide. Room is handed out by precedence first and
-- anchor order second, and a cell that does not fit is not placed at all: it
-- waits, and takes its place back the moment its neighbours need less.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local registry = require("cells/registry")
local cell_mod = require("structure/cell")

local M = {}

local HUGE = math.huge

-- `ctx`: block(), metrics(), output, edge, output_width(), anchor_side(),
-- slot_length(), padding(), fill_opacity(), horizontal(), window_line(),
-- and `floating` for a tissue with no membrane.
function M.new(ctx: { [string]: any })
    local t: { [string]: any } = {}
    t.anchor_side = ctx.anchor_side
    t.padding = ctx.padding
    t.horizontal = ctx.horizontal

    -- The cells, built once per load from the block's list. A cell whose
    -- type is not ported yet is left out, as QML leaves out a block it
    -- cannot build.
    t.cells = {}
    for index, entry in g.untracked(ctx.block).cells or {} do
        if entry.enabled ~= false then
            local kind = registry.type_of(entry.type)
            if kind then
                local i = index
                local c = cell_mod.new(kind, {
                    block = function() return (ctx.block().cells or {})[i] or entry end,
                    metrics = ctx.metrics,
                    output = ctx.output,
                    edge = ctx.edge,
                    floating = ctx.floating,
                    output_width = ctx.output_width,
                })
                table.insert(t.cells, c)
            end
        end
    end

    -- A cell counts for what the tissue measures while it is shown or open.
    local function counts(c: any): boolean
        return c.shown() or c.open.value
    end

    local function gap(): number return ctx.padding() * 2 end

    function t.tallest(): number
        local out = ctx.metrics().cell_height
        for _, c in t.cells do
            if counts(c) then out = math.max(out, c.contracted_height()) end
        end
        return out
    end

    function t.widest(): number
        local out = ctx.metrics().cell_height
        for _, c in t.cells do
            if counts(c) then out = math.max(out, c.contracted_width()) end
        end
        return out
    end

    function t.thickness(): number
        return (if ctx.horizontal() then t.tallest() else t.widest()) + ctx.padding() * 2
    end

    -- Equal share among the elastic cells, each capped by its own limit, the
    -- remainder redistributed: with one elastic cell, what the others left.
    local elastic_share = g.computed(function(): number
        local slot = ctx.slot_length()
        if slot <= 0 then return HUGE end
        local fixed, counted, elastic = 0, 0, {}
        for _, c in t.cells do
            if counts(c) then
                counted += 1
                if c.elastic() then table.insert(elastic, c.contracted_width()) else fixed += c.contracted_width() end
            end
        end
        if #elastic == 0 then return 0 end
        local free = math.max(0, slot - ctx.padding() * 2 - gap() * (counted - 1) - fixed)
        table.sort(elastic)
        local left = #elastic
        for _, asked in elastic do
            if asked > free / left then return free / left end
            free -= asked
            left -= 1
        end
        return HUGE
    end)

    -- What one cell may occupy: an elastic one the space the others leave,
    -- capped by its own limit, never under its minimum or what it can draw.
    function t.grant_for(c: any): number
        if not c.elastic() or not ctx.horizontal() then return c.contracted_width() end
        return math.max(c.min_width(), c.least_width(), math.min(c.contracted_width(), elastic_share.value))
    end

    local function axis_for(c: any): number
        return if ctx.horizontal() then t.grant_for(c) else c.contracted_height()
    end

    -- Which cells are placed, and how long they run together.
    local placement = g.computed(function(): { [string]: any }
        local slot = ctx.slot_length()
        local ceiling = if slot > 0 then slot - ctx.padding() * 2 else HUGE
        local order = {}
        if ctx.anchor_side() == "end" then
            for i = #t.cells, 1, -1 do table.insert(order, t.cells[i]) end
        else
            for _, c in t.cells do table.insert(order, c) end
        end
        local placed, used = {}, 0
        for _, level in { 2, 1, 0 } do
            for _, c in order do
                if counts(c) and c.precedence() == level then
                    local along = axis_for(c)
                    local before = if next(placed) then gap() else 0
                    if used + before + along <= ceiling + 0.5 then
                        used += before + along
                        placed[c] = true
                    end
                end
            end
        end
        return { cells = placed, length = used }
    end)

    function t.placed(c: any): boolean
        return c.shown() and placement.value.cells[c] == true
    end

    function t.content_length(): number return placement.value.length end

    function t.length(): number
        local slot = ctx.slot_length()
        return math.min(if slot > 0 then slot else HUGE, t.content_length() + ctx.padding() * 2)
    end

    function t.width(): number return if ctx.horizontal() then t.length() else t.thickness() end
    function t.height(): number return if ctx.horizontal() then t.thickness() else t.length() end

    -- How far its open cells reach past it.
    function t.reach(): number
        local out = 0
        for _, c in t.cells do out = math.max(out, c.reach()) end
        return out
    end

    -- A tissue with nothing to show is not an empty tray.
    function t.visible(): boolean return t.content_length() > 0 end

    -- Concentric by construction.
    function t.radius(): number return metrics_mod.radius_for(t.thickness(), ctx.metrics()) end
    function t.cell_radius(): number return metrics_mod.inner_radius(t.radius(), ctx.padding()) end

    -- Fixed order, variable position: where each placed cell begins along
    -- the tissue. One that is not placed waits where it would enter, taking
    -- no room, so it fades in at its place instead of sliding there from
    -- the tissue's start.
    local offsets = g.computed(function(): { [any]: number }
        local out, offset = {}, ctx.padding()
        for _, c in t.cells do
            out[c] = offset
            if placement.value.cells[c] then offset += axis_for(c) + gap() end
        end
        return out
    end)

    -- How far an open cell's panel hangs: from the cell's outer edge to the
    -- line the windows begin on, so every panel on the membrane hangs from
    -- that same line whatever its cell's height.
    local opens_away = ctx.edge == "top" or ctx.edge == "left"
    local function origin_gap(position: { [string]: any }): number
        -- A floating tissue hangs from nothing: the gap between the shapes
        -- of one open cell.
        if ctx.floating then return ctx.metrics().gap end
        local y = position.y()
        local outer = if opens_away then y + ctx.padding() + ctx.metrics().cell_height else y + ctx.padding()
        return math.max(0, if opens_away then ctx.window_line() - outer else outer - ctx.window_line())
    end

    local function place_of(c: any, position: { [string]: any }): { [string]: any }
        return {
            x = function(): number
                local along = offsets.value[c] or ctx.padding()
                if ctx.horizontal() then return along end
                -- Centred across the column.
                return ctx.padding() + (t.widest() - c.contracted_width()) / 2
            end,
            y = function(): number
                local along = offsets.value[c] or ctx.padding()
                if ctx.horizontal() then return ctx.padding() + (t.tallest() - c.contracted_height()) / 2 end
                return along
            end,
            width = function(): number return t.grant_for(c) end,
            placed = function(): boolean return t.placed(c) end,
            radius = t.cell_radius,
            origin = ctx.anchor_side,
            gap = function(): number return origin_gap(position) end,
        }
    end

    -- One continuous fill behind the cells, following the tissue's radius:
    -- a plain background, as Tissue.qml draws it (the band punched out under
    -- the cells was tried and, at a 2 px margin, is an outline).
    function t.node(position: { [string]: any }): any
        local band: { [any]: any } = {
            overlay = true,
            attach = "corner",
            offset_x = position.x,
            offset_y = position.y,
            width = t.width,
            height = t.height,
            radius = t.radius,
            present = t.visible,
            fill = function() return colour.alpha(theme.elevated(), ctx.fill_opacity()) end,
            transition = { offset_x = "reflow", offset_y = "reflow", width = "reflow", height = "reflow" },
        }
        for _, c in t.cells do
            table.insert(band, c.node(place_of(c, position)))
        end
        return g.capsule(band)
    end

    return t
end

return M
