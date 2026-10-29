--!strict
-- The loader (components/Sweep.qml): a segment travelling inside a track.
--
-- The one moving thing in the shell that measures nothing, allowed because
-- the movement is the information: "no value yet". So it is drawn only
-- while the wait it is bound to lasts, never on a timer. The geometry is
-- assets/icons/loader.svg's, in its 24-unit space: track `3,8.5 18×7 r3.5`
-- at stroke 1.5, segment `5.2,10.7 6×2.6 r1.3`, travel 7.6, there and back
-- in Timing.loader (docs/design/icons/LOADER.md).
local g = require("@genoma")
local theme = require("core/theme")
local timing = require("core/timing")

local M = {}

-- `t`: size (logical units), running() and colour() (muted text when
-- omitted: a wait is not a warning, so never a state colour), present().
function M.new(t: { [string]: any }): any
    local size = t.size or 16
    local unit = size / 24
    local colour = t.colour or theme.text_muted
    return g.box {
        width = size,
        height = size,
        present = t.present,
        justify = "center",
        align = "center",
        g.capsule {
            width = 18 * unit,
            height = 7 * unit,
            stroke = 1.5 * unit,
            rim_top = colour,
            rim_bottom = colour,
            justify = "start",
            padding_x = 1.2 * unit,
            g.capsule {
                width = 6 * unit,
                height = 2.6 * unit,
                fill = colour,
                -- Stopped, it holds still at the left end, the file's own
                -- resting state.
                sway = function() return if t.running() then timing.seconds.loader else 0 end,
                sway_range = 7.6 * unit,
            },
        },
    }
end

return M
