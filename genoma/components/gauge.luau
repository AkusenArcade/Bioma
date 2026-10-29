--!strict
-- A travel with a start and an end: a track, an arc that follows the value,
-- and a node at its head (components/Gauge.qml at 11bb81e).
--
-- Not a dial and not a vital: a scale the user moves, so it keeps the
-- primary for its whole run — red at full volume would say "past
-- threshold", and turning the sound up is not an alarm (STYLE_GUIDE §3).
-- Three limit cases, three drawings: muted, the value goes and a cut stays
-- across the track (not red, and not zero either); zero, the arc closed and
-- the node at the top, no cut; over, the excess restarting as a thinner arc
-- further out, in the same gradient.
--
-- The handoff's 64-unit box, scaled: track at r 24, node r 3.4, the outer
-- arc at r 30.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")

local M = {}

-- `t`: size(), fraction() (the travel, 0…1), overflow() (what is above it,
-- as a fraction of a turn), muted(), and optionally track_units (3
-- contracted, 1.5 in the capsule) and node_units (3.4).
function M.new(t: { [string]: any }): any
    local track_units = t.track_units or 3
    local node_units = t.node_units or 3.4
    local function unit(): number return t.size() / 64 end
    local function stroke(): number return math.max(1, track_units * unit()) end
    local function over_stroke(): number return math.max(1, track_units * 0.7 * unit()) end
    local function ring(): number return 2 * 24 * unit() + stroke() end
    local function outer(): number return 2 * 30 * unit() + over_stroke() end
    local function top(): string return theme.gradient_top(theme.primary()) end
    local function bottom(): string return theme.gradient_bottom(theme.primary()) end
    local function lit(): number return if t.muted() then 0 else 1 end

    -- The arc answers the wheel, so it follows the value rather than
    -- stepping to it: a jump between two frames reads as a flicker.
    local sweep = g.animated(g.untracked(t.fraction))
    g.watch(t.fraction, function(v: number) sweep:set(v, "content_fade") end)
    local function head(): number return math.min(1, sweep.value) end

    local function centred(node: { [any]: any }): any
        node.overlay = true
        return g.capsule(node)
    end

    return g.box {
        width = t.size,
        height = t.size,
        justify = "center",
        align = "center",
        -- The road, not the value: never in the gradient, firmer when muted,
        -- as then it is the only ring left.
        centred {
            width = ring,
            height = ring,
            stroke = stroke,
            rim_top = function() return colour.alpha(theme.line(), if t.muted() then 0.9 else 0.75) end,
            rim_bottom = function() return colour.alpha(theme.line(), if t.muted() then 0.9 else 0.75) end,
        },
        -- The cut: the extra sign muting has and zero does not.
        g.thread {
            overlay = true,
            width = t.size,
            height = t.size,
            from_x = function() return t.size() / 2 - 10 * unit() end,
            from_y = function() return t.size() / 2 - 10 * unit() end,
            to_x = function() return t.size() / 2 + 10 * unit() end,
            to_y = function() return t.size() / 2 + 10 * unit() end,
            stroke = stroke,
            fill = function() return colour.alpha(theme.text(), 0.5) end,
            node = 0,
            opacity = function() return if t.muted() then 1 else 0 end,
            transition = { opacity = "transition" },
        },
        -- The value, in one light over the dial; muted, the arc and the node
        -- go together.
        centred {
            width = ring,
            height = ring,
            stroke = stroke,
            rim_top = top,
            rim_bottom = bottom,
            arc = head,
            opacity = lit,
            transition = { opacity = "transition" },
        },
        centred {
            width = outer,
            height = outer,
            stroke = over_stroke,
            rim_top = top,
            rim_bottom = bottom,
            arc = function() return math.clamp(t.overflow(), 0, 1) end,
            present = function() return t.overflow() > 0 end,
            opacity = lit,
            transition = { opacity = "transition", arc = "content_fade" },
        },
        -- The node, the thread's own sign where something attaches: here the
        -- head of the travel; past the end it stays at the top.
        centred {
            width = function() return 2 * node_units * unit() end,
            height = function() return 2 * node_units * unit() end,
            fill = top,
            fill_bottom = bottom,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            orbit = 0,
            orbit_radius = function() return 24 * unit() end,
            angle = head,
            opacity = lit,
            transition = { opacity = "transition" },
        },
    }
end

return M
