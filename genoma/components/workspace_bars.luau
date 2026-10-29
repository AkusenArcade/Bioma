--!strict
-- The workspaces mark (components/WorkspaceBars.qml): stacked bars that
-- shift one step when the workspace changes.
--
-- It does not count workspaces; what it says is narrower: the command
-- arrived, which matters exactly when the change came from the keyboard and
-- the eye was not on the membrane. Four bars on a pitch of 9.5 in the 24
-- grid, clipped to the live area of 20, so a shift of one pitch lands on an
-- identical arrangement: the mark moves, and stays itself. The clip is on
-- the mark, never on the cell around it.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")

local M = {}

-- `size()` the mark's side, `base()` its colour (the primary). Returns the
-- node and `shift(steps)`.
function M.new(size: () -> number, base: (() -> string)?)
    local tint = base or theme.primary
    local offset = g.signal(0)
    local moving = g.signal(false)

    local function unit(): number return size() / 24 end
    -- The bars are a few pixels across, so their static edges land on whole
    -- pixels; the shift stays fluid, or it would step.
    local function snap(v: number): number return math.round(v) end
    local function margin(): number return 2 * unit() end
    local function pitch(): number return 9.5 * unit() end

    -- One light across the whole mark rather than one per bar: the colour at
    -- a height of the 24 grid, top lighter, bottom darker.
    local function light(at: number): string
        local b = tint()
        return colour.mix(theme.gradient_top(b), theme.gradient_bottom(b), math.clamp(at / size(), 0, 1))
    end

    local bars = {}
    for _, grid_y in { -6, 3.5, 13, 22.5 } do
        local y = grid_y
        table.insert(bars, g.capsule {
            overlay = true,
            attach = "corner",
            width = function() return snap(16 * unit()) end,
            height = function() return snap(7.5 * unit()) end,
            radius = function() return snap(3 * unit()) end,
            -- 1.4 of the grid is under a pixel at 16: a hairline, rounded to it.
            stroke = function() return math.max(1, math.round(1.4 * unit())) end,
            offset_x = function() return snap(4 * unit()) - margin() end,
            offset_y = function() return snap(y * unit()) - margin() + offset.value end,
            rim_top = function() return light(snap(y * unit()) + offset.value) end,
            rim_bottom = function() return light(snap(y * unit()) + snap(7.5 * unit()) + offset.value) end,
            transition = { offset_y = function() return if moving.value then "shift" else "instant" end },
        })
    end

    local clip: { [any]: any } = {
        overlay = true,
        attach = "corner",
        offset_x = margin,
        offset_y = margin,
        width = function() return size() - margin() * 2 end,
        height = function() return size() - margin() * 2 end,
        radius = 0,
        clip = true,
    }
    for i, bar in bars do clip[i] = bar end

    local node = g.box {
        width = size,
        height = size,
        g.capsule(clip),
    }

    -- The bars slide one pitch and are put back without animation: the
    -- pattern repeats, so the return is invisible.
    local back: any = nil
    local function shift(steps: number)
        if steps == 0 then return end
        if back then back:stop() end
        moving.value = false
        offset.value = 0
        g.after(0, function()
            moving.value = true
            offset.value = -steps * g.untracked(pitch)
            back = g.after(require("core/timing").seconds.transition, function()
                moving.value = false
                offset.value = 0
            end)
        end)
    end

    return node, shift
end

return M
