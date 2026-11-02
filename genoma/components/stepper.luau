--!strict
-- A simulation stepped while something moves (what FrameAnimation is to the
-- organisms on Quickshell: the lava lamp's wax, osmosis's drops, the
-- cytoplasm's streaming, the nucleus's drops). Genoma runs no script at the
-- frame, so the step runs thirty times a second and the shader node eases
-- its numbers between steps (`follow`), which is what the eye sees move.
-- Nothing runs while nothing moves.
local g = require("@genoma")

local M = {}

M.rate = 30
-- What a shader's numbers are given to ease over: one step.
M.follow = 1 / M.rate

-- `t`: running() (whether to step at all), step(dt). A long gap (the
-- organism just came back) is taken as a short step, so it resumes rather
-- than leaps.
function M.new(t: { [string]: any })
    g.effect(function()
        if not t.running() then return end
        local last = g.now()
        g.timer {
            every = 1 / M.rate,
            on_tick = function()
                local now = g.now()
                t.step(math.min(now - last, 0.05))
                last = now
            end,
        }
    end)
end

return M
