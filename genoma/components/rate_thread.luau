--!strict
-- A thread the bytes run along (components/RateThread.qml at 11bb81e): its
-- light moves as fast as they come, on a logarithmic scale (a download
-- goes from a few kilobytes a second to a hundred megabytes), and stops
-- when they stop: a stalled download is a still thread.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local paths = require("core/paths")
local theme = require("core/theme")

local M = {}

local SOURCE = paths.root .. "/genoma/components/rate_thread.wgsl"

-- `t`: width(), rate() (bytes a second), factor(), running().
function M.new(t: { [string]: any }): any
    local function speed(): number
        local r = t.rate()
        if r < 1024 then return 0 end
        return (6 + 40 * math.log10(1 + r / 65536)) * t.factor()
    end
    local function moving(): boolean return speed() > 0 and (t.running == nil or t.running()) end
    local function push(out: { number }, hex: string)
        local c = colour.parse(hex)
        table.insert(out, c.r)
        table.insert(out, c.g)
        table.insert(out, c.b)
        table.insert(out, c.a)
    end
    return g.shader {
        src = SOURCE,
        width = t.width,
        height = function() return 6 * t.factor() end,
        values = function()
            local out = { if moving() then speed() else 0, 2 * t.factor(), metrics_mod.thread, 0 }
            push(out, theme.line())
            push(out, theme.primary())
            return out
        end,
        follow = 0,
        clock = moving,
    }
end

return M
