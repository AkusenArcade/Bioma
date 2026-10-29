--!strict
-- The connection between two shapes of one open cell (components/
-- Thread.qml): a 1.3 px line with a node at each end, touching the edge of
-- both shapes. It draws itself out of its origin node, which is what makes
-- an expansion read as growing out of what it came from.
--
-- On Genoma a shape buds out of its origin, the neck narrowing to a thread
-- (Genoma PRD §8.2); this is the thread that stays once it has parted
-- (Akusen, 2026-10-29), and is taken back first when the shape is.
local g = require("@genoma")
local theme = require("core/theme")
local metrics_mod = require("core/metrics")

local M = {}

-- `t`: vertical (bool), length(), shown() (drawn out while true),
-- reversed (the origin at the far end: the bottom, or the right),
-- timing() (the name to draw out with), plus any placing props (overlay,
-- attach, offset_x, offset_y, present) passed through.
function M.new(t: { [string]: any }): any
    local d = metrics_mod.node_size * 2
    local node: { [any]: any } = {
        width = function() return if t.vertical then d else t.length() end,
        height = function() return if t.vertical then t.length() else d end,
        stroke = metrics_mod.thread,
        crisp = true,
        node = d,
        fill = theme.line,
        color = theme.node,
        -- How much of it is drawn, from its origin out to the tip.
        growth = function() return if t.shown() then 1 else 0 end,
        transition = { growth = function() return if t.shown() then t.timing() else "thread_close" end },
    }
    local function far(): number return t.length() end
    if t.vertical then
        node.from_x = d / 2
        node.to_x = d / 2
        node.from_y = function() return if t.reversed then far() else 0 end
        node.to_y = function() return if t.reversed then 0 else far() end
    else
        node.from_y = d / 2
        node.to_y = d / 2
        node.from_x = function() return if t.reversed then far() else 0 end
        node.to_x = function() return if t.reversed then 0 else far() end
    end
    for _, key in { "overlay", "attach", "offset_x", "offset_y", "present" } do
        if t[key] ~= nil then node[key] = t[key] end
    end
    return g.thread(node)
end

return M
