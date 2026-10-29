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
-- Not yet: `"anchor": "pointer"` and cells summoned at the pointer, which
-- need the pointer's position; a tissue holding its place while the pointer
-- is on what it opened; the floating shadow; a summoned cell growing into
-- place rather than fading in.
local g = require("@genoma")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local timing = require("core/timing")
local registry = require("cells/registry")
local tissue_mod = require("structure/tissue")
local focus = require("structure/focus")

local M = {}

-- `block()` is the floating block, read reactively. Returns the tree and
-- the tissue.
local function build(block: () -> { [string]: any }, output: string, size: { width: number, height: number })
    local first = g.untracked(block)
    local function metrics() return metrics_mod.step(block().scale or "normal") end
    local function anchor(): string return block().anchor or "centre" end
    local function has(word: string): boolean return string.find(anchor(), word, 1, true) ~= nil end
    local at_bottom = string.find(first.anchor or "centre", "bottom", 1, true) ~= nil
    local at_left = string.find(first.anchor or "centre", "left", 1, true) ~= nil
    local at_right = string.find(first.anchor or "centre", "right", 1, true) ~= nil

    -- A margin the block writes is measured from the screen's edge and is
    -- obeyed. Otherwise a tissue anchored to an edge sits on the line the
    -- windows begin on, past the strip a membrane there would take (niri's
    -- gaps and struts come with the niri service).
    local function margin(side: string): number
        local m = (block().margins or {})[side]
        local s = metrics()
        if m ~= nil then return m * s.factor end
        if side == "top" or side == "bottom" then return s.margin_edge + s.cell_height + s.tissue_padding * 2 end
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

    local position = {
        x = function(): number
            if at_left then return margin("left") end
            if at_right then return size.width - t.width() - margin("right") end
            return (size.width - t.width()) / 2
        end,
        -- Centred, the whole composition is centred: the tissue moves up by
        -- half of what hangs below it.
        y = function(): number
            if has("top") then return margin("top") end
            if has("bottom") then return size.height - t.height() - margin("bottom") end
            if at_left or at_right then return (size.height - t.height()) / 2 end
            return (size.height - t.height() - t.reach()) / 2
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
    function host.summon(domain: string): boolean
        if not registry.type_of(domain) then return false end
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
        local tree, t = build(function() return block end, output, size)
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
                g.after(math.max(timing.seconds.close, timing.seconds.reflow), function()
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
