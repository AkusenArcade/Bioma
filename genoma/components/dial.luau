--!strict
-- The clock's face (components/Dial.qml): two fractions of a whole on one
-- small drawing. The sector fills from twelve with `fraction` (the hour, or
-- what is left of a timer while one runs); a small disc travels the rim
-- with `orbit` (the minute), drawing behind it the lit arc since twelve. The
-- rim itself is a track in the line colour: the road the disc runs on, not
-- a value. A dial that measures no load stays primary.
--
-- The graphics card's satellite drawing, in the 64 grid: track at r 24,
-- stroke 1.5, disc 12 across, so at the same box the two are one size.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")

local M = {}

-- `t`: size(), fraction() (0…1), orbit() (0…1, the minute as a fraction of
-- its turn, continuous between the seconds it is set at).
function M.new(t: { [string]: any }): any
    local function unit(): number return t.size() / 64 end
    local function stroke(): number return math.max(1, 1.5 * unit()) end
    local function track(): number return 2 * 24 * unit() + stroke() end
    local function top(): string return theme.gradient_top(theme.primary()) end
    local function bottom(): string return theme.gradient_bottom(theme.primary()) end
    return g.box {
        width = t.size,
        height = t.size,
        justify = "center",
        align = "center",
        g.capsule {
            overlay = true,
            width = track,
            height = track,
            stroke = stroke,
            rim_top = function() return colour.alpha(theme.line(), 0.4) end,
            rim_bottom = function() return colour.alpha(theme.line(), 0.4) end,
        },
        -- One light over the face, revealed by the trail, the sector and the
        -- disc. The trail since twelve runs on between the seconds at the
        -- minute's own rate.
        g.capsule {
            overlay = true,
            width = track,
            height = track,
            stroke = stroke,
            rim_top = top,
            rim_bottom = bottom,
            arc = t.orbit,
            arc_rate = 1 / 60,
        },
        -- Inside the rim with a clear gap past the disc, so the two never
        -- read as one shape. A second moves it by 1/3600 of a turn: the
        -- easing Dial gives it cannot be seen.
        g.capsule {
            overlay = true,
            width = function() return 26 * unit() end,
            height = function() return 26 * unit() end,
            fill = top,
            fill_bottom = bottom,
            arc = function() return t.fraction() % 1 end,
        },
        -- The second hand, continuous (MinuteHand.qml): one turn a minute,
        -- set against the wall clock each second.
        g.capsule {
            overlay = true,
            width = function() return 12 * unit() end,
            height = function() return 12 * unit() end,
            fill = top,
            fill_bottom = bottom,
            orbit = 1 / 60,
            orbit_radius = function() return 24 * unit() end,
            angle = t.orbit,
        },
    }
end

return M
