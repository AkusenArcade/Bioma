--!strict
-- A tissue with no membrane (structure/Float.qml): anchored to a corner or
-- centred, over the windows, ceding nothing. The three levels are unchanged;
-- what is missing is the edge, so the tissue is placed by an anchor and a
-- pair of margins instead, and its cells' panels hang a shape's gap away.
--
-- A host is a floating surface with nothing in it: it exists so that a cell
-- nobody has given a place to has somewhere to be. Asked for by name, the
-- cell appears in the middle of the monitor (Akusen, 2026-09-22).
--
-- A cell that comes to the pointer (the quick actions) is summoned around
-- the point the pointer was found at (structure/focus.luau, `seek`).
--
-- Not yet: `"anchor": "pointer"` on a declared block; a tissue holding its
-- place while the pointer is on what it opened; the floating shadow; a
-- summoned cell growing into place rather than fading in.
local g = require("@genoma")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local timing = require("core/timing")
local registry = require("cells/registry")
local tissue_mod = require("structure/tissue")
local focus = require("structure/focus")
local niri = require("services/niri")

local M = {}

-- `block()` is the floating block, read reactively; `point` where the
-- pointer was found, for a cell summoned there. Returns the tree and the
-- tissue.
local function build(block: () -> { [string]: any }, output: string, size: { width: number, height: number },
                     point: { x: number, y: number }?)
    local first = g.untracked(block)
    local function metrics() return metrics_mod.step(block().scale or "normal") end
    local function anchor(): string return block().anchor or "centre" end
    local function has(word: string): boolean return string.find(anchor(), word, 1, true) ~= nil end
    local at_bottom = string.find(first.anchor or "centre", "bottom", 1, true) ~= nil
    local at_left = string.find(first.anchor or "centre", "left", 1, true) ~= nil
    local at_right = string.find(first.anchor or "centre", "right", 1, true) ~= nil

    -- A margin the block writes is measured from the screen's edge and is
    -- obeyed. Otherwise a tissue anchored to an edge sits on the line the
    -- windows begin on, past the strip a membrane there would take.
    local function margin(side: string): number
        local m = (block().margins or {})[side]
        local s = metrics()
        if m ~= nil then return m * s.factor end
        if side == "top" or side == "bottom" then
            return s.margin_edge + s.cell_height + s.tissue_padding * 2 + niri.window_gap() + niri.strut_for(side)
        end
        return s.margin_edge
    end

    local t = tissue_mod.new({
        block = block,
        metrics = metrics,
        output = output,
        edge = if at_bottom then "bottom" else "top",
        floating = true,
        output_width = function() return size.width end,
        anchor_side = function()
            local b = block()
            if b.anchor_side then return b.anchor_side end
            return if has("left") then "start" elseif has("right") then "end" else "centre"
        end,
        -- No ceiling: nothing shares this surface.
        slot_length = function() return 0 end,
        padding = function()
            local p = block().padding
            if p ~= nil then return math.clamp(p, 2, 12) * metrics().factor end
            return metrics().tissue_padding
        end,
        fill_opacity = function()
            local o = block().opacity
            return if o ~= nil then o else config.get("tissue.opacity", 0.5)
        end,
        horizontal = function() return (block().orientation or "vertical") == "horizontal" end,
        window_line = function() return 0 end,
    })

    -- How far a cell draws past its own pill on every side, from its centre:
    -- the quick actions' ring. A pointer too near the edge for the whole of
    -- it moves the centre inward until it fits, rather than leaving part of
    -- the ring off the screen.
    local function surround(axis: string): number
        local out = 0
        for _, c in t.cells do
            local s = c.spec.surround
            if s then out = math.max(out, s()[axis]) end
        end
        return out
    end
    -- What the tissue measured while it held something: once empty it keeps
    -- that size, so its last cell, still leaving, does not slide to a new
    -- place.
    local held = { width = 0, height = 0 }
    local function measured(axis: string): number
        if t.visible() then held[axis] = if axis == "width" then t.width() else t.height() end
        return held[axis]
    end
    -- Centred on the point, and kept on the screen.
    local function around(axis: string, at: number, extent: number): number
        local edge = metrics().margin_edge
        local own = measured(if axis == "x" then "width" else "height")
        local s = surround(axis)
        if s > 0 then return math.clamp(at, edge + s, math.max(edge + s, extent - edge - s)) - own / 2 end
        return math.clamp(at - own / 2, edge, math.max(edge, extent - own - edge))
    end

    local position = {
        x = function(): number
            if point then return around("x", point.x, size.width) end
            if at_left then return margin("left") end
            if at_right then return size.width - measured("width") - margin("right") end
            return (size.width - measured("width")) / 2
        end,
        -- Centred, the whole composition is centred: the tissue moves up by
        -- half of what hangs below it.
        y = function(): number
            if point then return around("y", point.y, size.height) end
            if has("top") then return margin("top") end
            if has("bottom") then return size.height - measured("height") - margin("bottom") end
            if at_left or at_right then return (size.height - measured("height")) / 2 end
            return (size.height - measured("height") - t.reach()) / 2
        end,
    }
    return t.node(position), t
end

function M.new(block: () -> { [string]: any }, output: string, size: { width: number, height: number }): any
    local tree = build(block, output, size)
    return g.box { width = size.width, height = size.height, tree }
end

-- The host on `output`: the middle of the screen, empty until something is
-- asked for.
function M.host(output: string, size: { width: number, height: number }): any
    local summoned = g.signal("")
    local current: any = nil

    local host = {}
    function host.summoned(): string return g.untracked(function() return summoned.value end) end
    -- Where the next summoned cell is centred: nil for the middle.
    local point: { x: number, y: number }? = nil
    function host.summon(domain: string): boolean
        if not registry.type_of(domain) then return false end
        point = nil
        summoned.value = domain
        return true
    end
    -- Around the point the pointer was found at; the middle when it was not
    -- (no x, no y).
    function host.summon_at(domain: string, x: number?, y: number?): boolean
        if not registry.type_of(domain) then return false end
        point = if x and y then { x = x, y = y } else nil
        summoned.value = domain
        return true
    end
    -- It leaves the way any invoked cell does, and is let go once it has.
    function host.retire()
        if current then
            current.open.value = false
            current.visibility.set_invoked(false)
        else
            summoned.value = ""
        end
    end
    focus.offer_host(output, host)

    -- A row of a keyed list is handed its item as a getter.
    local function row(item: () -> string): any
        local domain = g.untracked(item)
        local block = {
            anchor = "centre",
            orientation = "horizontal",
            cells = { { type = domain, enabled = true, visibility = { type = "invoked" } } },
        }
        local tree, t = build(function() return block end, output, size, point)
        local c = t.cells[1]
        current = c
        if c then
            -- Arriving is opening, for a cell with a panel; one whose content
            -- is itself claims the attention, so a press outside still sends
            -- it off. After the row is mounted, not while it is.
            g.after(0, function()
                c.visibility.set_invoked(true)
                if c.has_panel then c.open.value = true else focus.opened(c) end
            end)
            g.watch(function() return c.shown() end, function(shown: boolean)
                if shown then return end
                g.after(c.withdrawal() + math.max(timing.seconds.close, timing.seconds.reflow), function()
                    if g.untracked(c.shown) then return end
                    focus.withdraw(c)
                    if current == c then current = nil end
                    summoned.value = ""
                end)
            end)
        end
        return tree
    end

    return g.box {
        width = size.width,
        height = size.height,
        g.each {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            items = function() return if summoned.value ~= "" then { summoned.value } else {} end,
            key = function(domain: string) return domain end,
            row = row,
        },
    }
end

return M
