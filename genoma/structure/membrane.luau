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
local niri = require("services/niri")
local timing = require("core/timing")
local theme = require("core/theme")
local colour = require("core/colour")
local performance = require("core/performance")
local focus_mode = require("core/focus_mode")

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
    -- `gaps` and the edge's strut.
    local function window_inset(): number return niri.window_gap() + niri.strut_for(edge) end
    local function window_line(): number
        if edge == "top" or edge == "left" then return m.strip() + window_inset() end
        return (if horizontal then size.height else size.width) - m.strip() - window_inset()
    end

    -- Read through, never kept: the surface is fluid, and the compositor
    -- may give it another area while it runs (another membrane took or let
    -- go of its strip); the tree follows instead of being built again.
    local function membrane_length(): number return if horizontal then size.width else size.height end
    local function width(): number return size.width end
    local function height(): number return size.height end
    local function usable(): number return math.max(0, membrane_length() - metrics().margin_edge * 2) end

    -- The tissues, each kept by its place in the list for as long as the
    -- list has that place, reading its own block out of it (Membrane.qml's
    -- `places`): a tissue rebuilt is every cell in it rebuilt, and the
    -- settings cell open in one closed under the press that changed it.
    local function entries(): { any } return block().tissues or {} end
    local tissues = g.map(function()
        local places = {}
        for i in entries() do table.insert(places, i) end
        return places
    end, function(place: number) return tostring(place) end, function(item: () -> number)
        local i = g.untracked(item)
        local first = entries()[i] or {}
        local function tblock() return entries()[i] or first end
        local function anchor(): string return anchor_for(i, tblock(), #entries()) end
        local t = tissue_mod.new({
            block = tblock,
            metrics = metrics,
            output = output,
            edge = edge,
            output_width = function() return size.width end,
            anchor_side = anchor,
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
        t.place = i
        return t
    end)

    local function along(t: any): number return if horizontal then t.width() else t.height() end

    local function run_length(side: string): number
        local total = 0
        for _, t in tissues() do
            if t.visible() and t.anchor() == side then total += along(t) + metrics().margin_edge end
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
        for i, other in tissues() do
            if other.visible() then
                local length = along(other)
                if other.anchor() == "start" and i < index then start_run += length + margin
                elseif other.anchor() == "end" and i > index then end_run += length + margin end
                if other.anchor() == "centre" then
                    centre_total += length + (if centre_total > 0 then margin else 0)
                    if i < index then centre_before += length + margin end
                end
            end
        end
        local own = along(t)
        if t.anchor() == "start" then return outer + start_run end
        if t.anchor() == "end" then return membrane_length() - outer - end_run - own end
        local group = (membrane_length() - centre_total) / 2
        local left = margin + run_length("start")
        local right = membrane_length() - margin - run_length("end")
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

    local function position_of(t: any): { [string]: any }
        local index = t.place
        return {
            -- On a whole pixel, as Qt aligns what it centres: an icon is
            -- drawn on whole pixels to stay sharp, the shapes round it are
            -- not, and a tissue centred on half a pixel left every icon half
            -- a pixel off its ring (Akusen, 2026-10-29, the dock).
            x = function() return math.floor((if horizontal then offset_for(t, index) else cross_offset()) + 0.5) end,
            y = function() return if horizontal then cross_offset() else offset_for(t, index) end,
        }
    end

    -- ---- Auto-hide (Membrane.qml) ---------------------------------------
    --
    -- An auto-hiding membrane keeps its surface: two units at the edge catch
    -- the pointer, and reaching them brings the whole content out. Once out,
    -- the whole strip is the membrane's, so a hand travelling from the edge
    -- to a cell crosses nothing that belongs to nobody; it goes again a
    -- moment after the hand has left, and never while a cell on it is open.
    -- A cell opened by its key on a hidden membrane brings the membrane out
    -- with it.
    local REVEAL = 2
    local function auto_hide(): boolean return block().auto_hide == true end
    local revealed = g.signal(not g.untracked(auto_hide))
    local band_hovered = g.signal(false)
    local function hovered(): boolean
        if band_hovered.value then return true end
        for _, t in tissues() do
            for _, c in t.cells() do
                if c.hovered.value then return true end
            end
        end
        return false
    end
    local function any_open(): boolean
        for _, t in tissues() do
            for _, c in t.cells() do
                if c.open.value then return true end
            end
        end
        return false
    end
    local hiding: any = nil
    local function stay()
        if hiding then hiding:stop() end
        hiding = nil
    end
    local function go_later()
        stay()
        hiding = g.after(timing.seconds.auto_hide, function()
            hiding = nil
            if g.untracked(auto_hide) and not g.untracked(any_open) and not g.untracked(hovered) then
                revealed.value = false
            end
        end)
    end
    -- Switched on under the hand, or holding something open, it goes when
    -- the hand leaves rather than while it is being used.
    g.watch(auto_hide, function(on: boolean)
        if not on then
            stay()
            revealed.value = true
        elseif g.untracked(hovered) or g.untracked(any_open) then
            go_later()
        else
            revealed.value = false
        end
    end)
    g.watch(hovered, function(on: boolean)
        if not g.untracked(auto_hide) then return end
        if on then stay() else go_later() end
    end)
    g.watch(any_open, function(open: boolean)
        if not g.untracked(auto_hide) then return end
        if open then
            stay()
            revealed.value = true
        elseif not g.untracked(hovered) then
            go_later()
        end
    end)
    m.revealed = function(): boolean return revealed.value end

    -- The whole content slides out, all but the reveal strip's width.
    local function hidden_by(): number return if revealed.value then 0 else m.strip() - REVEAL end
    local function slide_x(): number
        if horizontal then return 0 end
        return if edge == "left" then -hidden_by() else hidden_by()
    end
    local function slide_y(): number
        if not horizontal then return 0 end
        return if edge == "top" then -hidden_by() else hidden_by()
    end
    -- A strip along the edge, `thickness` deep.
    local function strip_box(thickness: () -> number, extra: { [any]: any }): any
        local box: { [any]: any } = {
            overlay = true,
            attach = "corner",
            offset_x = function()
                return if edge == "right" then size.width - thickness() else 0
            end,
            offset_y = function()
                return if edge == "bottom" then size.height - thickness() else 0
            end,
            width = function() return if horizontal then size.width else thickness() end,
            height = function() return if horizontal then thickness() else size.height end,
        }
        for k, v in extra do box[k] = v end
        return g.box(box)
    end

    -- ---- The halo ------------------------------------------------------
    --
    -- A membrane that reserves nothing lies over the windows, and its cells
    -- were read against whatever a window drew under them. While it is out,
    -- each of its tissues takes the light down around itself: the palette's
    -- background, the tissue's own shape blurred outward, the window left
    -- clean where there is no cell (Akusen, 2026-09-28). It takes no
    -- pointer and is not blurred: blur is declared for the cells alone.
    local function over_windows(): boolean return not m.reserving() end
    local function halo_opacity(): number return math.clamp(config.get("scrim.opacity", 0.85), 0, 1) end
    local function halo_reach(): number return math.max(0, config.get("scrim.reach", 32)) * metrics().factor end
    local function halos_shown(): boolean
        return over_windows() and halo_opacity() > 0 and halo_reach() > 0 and not performance.flat()
    end

    -- ---- Focus mode (core/focus_mode.luau) --------------------------------
    --
    -- The whole membrane folds over its own edge, a page turned toward the
    -- viewer until it is seen edge-on, and fades as it goes; it unfolds
    -- again on a spring when the mode ends, or while one of its cells has
    -- been asked for at its place, holding that cell alone. Depth, not a
    -- scale: the lit border and the radii stay exact at every angle
    -- (Genoma PRD §8.4, STYLE_GUIDE "Depth"). Its strip is given back as
    -- the fold starts (shell.luau).
    local function folded(): boolean
        if not focus_mode.active() then return false end
        for _, t in tissues() do
            for _, c in t.cells() do
                if c.speaks_in_focus() then return false end
            end
        end
        return true
    end
    local function fold_curve(): string return if folded() then "fold" else "unfold" end
    local turn = ({ top = -90, bottom = 90, left = 90, right = -90 })[edge]

    local root: { [any]: any } = {
        width = width,
        height = height,
        -- Out, the strip is the membrane's: under the cells, so a press on
        -- a cell is the cell's.
        strip_box(m.strip, {
            present = function() return auto_hide() and revealed.value and not focus_mode.active() end,
            on_hover = function(on: boolean) band_hovered.value = on end,
        }),
        g.box {
            overlay = true,
            attach = "corner",
            width = width,
            height = height,
            offset_x = slide_x,
            offset_y = slide_y,
            pivot_x = if edge == "left" then 0 elseif edge == "right" then 1 else 0.5,
            pivot_y = if edge == "top" then 0 elseif edge == "bottom" then 1 else 0.5,
            perspective = function() return math.max(size.width, size.height) end,
            rotate_x = function() return if horizontal and folded() then turn else 0 end,
            rotate_y = function() return if not horizontal and folded() then turn else 0 end,
            opacity = function() return if folded() then 0 else 1 end,
            transition = {
                offset_x = "reveal",
                offset_y = "reveal",
                rotate_x = fold_curve,
                rotate_y = fold_curve,
                opacity = function() return if folded() then "fold" else "grow" end,
            },
            g.each {
                overlay = true,
                attach = "corner",
                width = width,
                height = height,
                present = halos_shown,
                opacity = function() return if revealed.value then 1 else 0 end,
                transition = { opacity = "reveal" },
                items = tissues,
                key = function(t: any) return tostring(t.place) end,
                row = function(item: () -> any)
                    local t = g.untracked(item)
                    local position = position_of(t)
                    return g.capsule {
                        overlay = true,
                        attach = "corner",
                        offset_x = position.x,
                        offset_y = position.y,
                        width = t.width,
                        height = t.height,
                        radius = t.radius,
                        present = t.visible,
                        halo = halo_reach,
                        fill = function() return colour.alpha(theme.background(), halo_opacity()) end,
                        rim_top = "#00000000",
                        rim_bottom = "#00000000",
                    }
                end,
            },
            g.each {
                overlay = true,
                attach = "corner",
                width = width,
                height = height,
                items = tissues,
                key = function(t: any) return tostring(t.place) end,
                row = function(item: () -> any)
                    local t = g.untracked(item)
                    return t.node(position_of(t))
                end,
            },
        },
        -- Hidden, the two units at the edge are all that takes the pointer,
        -- above the content that slid out under them.
        strip_box(function() return REVEAL end, {
            present = function() return auto_hide() and not revealed.value and not focus_mode.active() end,
            on_hover = function(on: boolean) if on then revealed.value = true end end,
        }),
    }
    m.tree = g.box(root)
    m.tissues = tissues
    return m
end

return M
