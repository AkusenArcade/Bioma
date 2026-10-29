--!strict
-- A list longer than its room: where it is scrolled to, the wheel that
-- moves it, and the mark down its side (components/Scroller.qml).
--
-- The mark exists only while the list moves. At rest the interface does not
-- speak, and a bar that stays is a figure nobody asked for, so it fades in
-- under the hand and goes when the list stops; a list that fits shows
-- nothing. It is not a control: it reports where in the list the eye is.
local g = require("@genoma")
local theme = require("core/theme")
local timing = require("core/timing")

local M = {}

-- `t`: viewport() and content() (heights, logical units), step() (a wheel
-- notch, a row), factor(). Returns `offset()`, `wheel(dx, dy)` for the
-- well's on_wheel, `reveal(top, height)` to bring a stretch into view,
-- `to(y)`, and `bar(x)`, the mark to place in the well at that x.
function M.new(t: { [string]: any }): any
    local offset = g.signal(0)
    local moving = g.signal(false)
    local rest: any = nil

    local function room(): number return math.max(0, t.content() - t.viewport()) end
    local function longer(): boolean return t.content() > t.viewport() + 0.5 end

    local function to(y: number)
        local clamped = math.clamp(y, 0, g.untracked(room))
        if clamped == g.untracked(function() return offset.value end) then return end
        offset.value = clamped
        moving.value = true
        if rest then rest:stop() end
        rest = g.after(timing.seconds.reflow + timing.seconds.content_fade * 2, function() moving.value = false end)
    end

    -- A notch is a row; a touchpad's movement is followed as it comes.
    local function wheel(_: number, dy: number)
        local discrete = dy == math.floor(dy) and math.abs(dy) <= 3
        local now = g.untracked(function() return offset.value end)
        to(now + (if discrete then dy * g.untracked(t.step) else dy))
    end

    local function reveal(top: number, height: number)
        local now = g.untracked(function() return offset.value end)
        local view = g.untracked(t.viewport)
        if top < now then to(top)
        elseif top + height > now + view then to(top + height - view) end
    end

    -- Content that shrinks under the scroll brings it back within reach.
    g.watch(room, function(r: number)
        if g.untracked(function() return offset.value end) > r then offset.value = r end
    end)

    local function bar(x: () -> number): any
        local function width(): number return 3 * t.factor() end
        -- As long as the share of the list in view, and never so short that
        -- it stops reading as a bar.
        local function length(): number
            return math.max(width() * 4, t.viewport() * t.viewport() / math.max(1, t.content()))
        end
        return g.capsule {
            overlay = true,
            attach = "corner",
            present = longer,
            offset_x = x,
            offset_y = function()
                local r = room()
                local along = if r > 0 then offset.value / r else 0
                -- The well scrolls its children; the mark stays in place by
                -- riding the scroll back.
                return offset.value + along * (t.viewport() - length())
            end,
            width = width,
            height = length,
            fill = theme.line,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            opacity = function() return if moving.value then 1 else 0 end,
            transition = { opacity = "content_fade", offset_y = "reflow" },
        }
    end

    return {
        offset = function() return offset.value end,
        wheel = wheel,
        reveal = reveal,
        to = to,
        bar = bar,
    }
end

return M
