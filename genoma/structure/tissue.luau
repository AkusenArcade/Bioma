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

    -- The cells, kept by their domain (Tissue.qml, `build`): a cell whose
    -- block is still in the list keeps its instance and reads the new block,
    -- only what arrived is built and only what left is let go. Adding a cell
    -- to a band must not close the settings cell that added it. Keyed by
    -- the domain and how many of it came before, so two of a kind stay two.
    -- A cell whose type is not ported yet is left out, as QML leaves out a
    -- block it cannot build.
    local function entries(): { any }
        local out, seen = {}, {}
        for _, entry in ctx.block().cells or {} do
            if type(entry) == "table" and entry.enabled ~= false and registry.type_of(entry.type) then
                local domain = registry.canonical(entry.type)
                seen[domain] = (seen[domain] or 0) + 1
                table.insert(out, { key = domain .. "#" .. seen[domain], entry = entry })
            end
        end
        return out
    end
    local mapped = g.map(entries, function(item: any) return item.key end, function(item: () -> any)
        local first = g.untracked(item)
        local key = first.key
        -- The last block it was handed: a timer of a cell already let go
        -- may still ask once.
        local last = first.entry
        local c = cell_mod.new(registry.type_of(first.entry.type), {
            block = function()
                local now = item()
                if now then last = now.entry end
                return last
            end,
            metrics = ctx.metrics,
            output = ctx.output,
            edge = ctx.edge,
            floating = ctx.floating,
            output_width = ctx.output_width,
        })
        c.key = key
        return c
    end)
    function t.cells(): { any } return mapped() end

    -- A cell counts for what the tissue measures while it is shown or open.
    local function counts(c: any): boolean
        return c.shown() or c.open.value
    end

    local function gap(): number return ctx.padding() * 2 end

    function t.tallest(): number
        local out = ctx.metrics().cell_height
        for _, c in t.cells() do
            if counts(c) then out = math.max(out, c.contracted_height()) end
        end
        return out
    end

    function t.widest(): number
        local out = ctx.metrics().cell_height
        for _, c in t.cells() do
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
        for _, c in t.cells() do
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
            local list = t.cells()
            for i = #list, 1, -1 do table.insert(order, list[i]) end
        else
            for _, c in t.cells() do table.insert(order, c) end
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
        for _, c in t.cells() do out = math.max(out, c.reach()) end
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
        for _, c in t.cells() do
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
            -- Exact, never rounded here: Genoma lands the drawing on the
            -- screen's physical pixels and keeps a centred cell centred,
            -- which a whole logical unit at scale 1.5 does not (a 1.7 margin
            -- rounded to 2 left 3 pixels above a cell and 2 below). Centred
            -- across the tissue as it would be with this cell in it: one not
            -- placed was centred on a column that no longer counted it, so the
            -- launcher alone in a floating column came in from the left and
            -- left that way, sliding between the two (Tissue.qml leaves such a
            -- cell where it stands).
            x = function(): number
                local along = offsets.value[c] or ctx.padding()
                if ctx.horizontal() then return along end
                local across = math.max(t.widest(), c.contracted_width())
                return ctx.padding() + (across - c.contracted_width()) / 2
            end,
            y = function(): number
                local along = offsets.value[c] or ctx.padding()
                if ctx.horizontal() then
                    local across = math.max(t.tallest(), c.contracted_height())
                    return ctx.padding() + (across - c.contracted_height()) / 2
                end
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
    -- A floating tissue's last cell still fading or withdrawing: the band
    -- stays, with nothing of its own drawn, so the cell is seen leaving
    -- (a summoned cell, the quick actions' ring going home).
    local function lingering(): boolean
        if not ctx.floating then return false end
        for _, c in t.cells() do
            if c.drawn and c.drawn() then return true end
        end
        return false
    end

    function t.node(position: { [string]: any }): any
        -- A tissue on a membrane reflows, and that movement is the design
        -- moment the PRD calls it. A floating one does not: what it holds
        -- arrives and leaves whole, and a band that animated its own size
        -- dragged the cell inside it across the screen (Tissue.qml,
        -- `animates`): the launcher slid in from the right.
        local function moving(): string
            return if ctx.floating then "instant" else "reflow"
        end
        local band: { [any]: any } = {
            overlay = true,
            attach = "corner",
            offset_x = position.x,
            offset_y = position.y,
            width = t.width,
            height = t.height,
            radius = t.radius,
            present = function() return t.visible() or lingering() end,
            -- Only on a membrane. A floating tissue holds nothing but its
            -- cells and has no band to show: its fill was a second layer
            -- between a cell and the blurred desktop (Akusen, 2026-09-29).
            fill = function()
                if ctx.floating then return "#00000000" end
                return if t.visible() then colour.alpha(theme.elevated(), ctx.fill_opacity()) else "#00000000"
            end,
            transition = {
                offset_x = moving, offset_y = moving, width = moving, height = moving,
            },
        }
        table.insert(band, g.each {
            overlay = true,
            attach = "corner",
            width = t.width,
            height = t.height,
            items = t.cells,
            key = function(c: any) return c.key end,
            row = function(item: () -> any)
                local c = g.untracked(item)
                return c.node(place_of(c, position))
            end,
        })
        return g.capsule(band)
    end

    return t
end

return M
