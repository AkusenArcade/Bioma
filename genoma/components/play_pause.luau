--!strict
-- Play and pause as one shape (Genoma's `d` morph): the two bars of pause
-- and the triangle of play are the same outline, two strokes of three
-- points each, so one becomes the other point by point when the player
-- starts or stops — the left bar is the triangle's upright side, the right
-- one folds into its point. At rest each is its icon (assets/icons play,
-- pause), to the pixel: the same points, the same stroke.
--
-- `t`: size(), playing(), colour().
local g = require("@genoma")

local M = {}

-- The icons' own figures, in their 24 grid.
local PLAY_STROKE, PAUSE_STROKE = 1.5, 2.6

function M.new(t: { [string]: any }): any
    local function unit(): number return t.size() / 24 end
    local function outline(): string
        local u = unit()
        local function p(x: number, y: number): string return string.format("%.3f %.3f", x * u, y * u) end
        if t.playing() then
            return "M" .. p(9, 5) .. " L" .. p(9, 12) .. " L" .. p(9, 19)
                .. " M" .. p(15, 5) .. " L" .. p(15, 12) .. " L" .. p(15, 19)
        end
        return "M" .. p(8.5, 5.5) .. " L" .. p(8.5, 12) .. " L" .. p(8.5, 18.5)
            .. " M" .. p(8.5, 5.5) .. " L" .. p(18, 12) .. " L" .. p(8.5, 18.5)
    end
    -- The stroke goes with the shape: a path's width is not a transition
    -- of its own.
    local weight = g.animated(if g.untracked(t.playing) then PAUSE_STROKE else PLAY_STROKE)
    g.watch(t.playing, function(playing: boolean)
        weight:set(if playing then PAUSE_STROKE else PLAY_STROKE, "morph")
    end)
    return g.path {
        width = t.size,
        height = t.size,
        d = outline,
        stroke = function() return weight.value * unit() end,
        color = t.colour,
        cap = "round",
        join = "round",
        transition = { d = "morph" },
    }
end

return M
