--!strict
-- The bytes of a transfer as particles carried along a hairline (Genoma's
-- `g.emitter`), where components/rate_thread runs a light: the same
-- hairline in the line colour, the same way (toward the right), and over it
-- particles in the primary. How many run is the rate, on a logarithmic
-- scale (a download goes from a few kilobytes a second to a hundred
-- megabytes); each crosses in about a second whatever the rate. A stalled
-- transfer has none, and the line is still.
--
-- `t`: width(), rate() (bytes a second), factor(), running() optional —
-- the same as rate_thread's, so one takes the other's place.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local performance = require("core/performance")

local M = {}

local QUIET = 1024
local CEILING = 100 * 1024 * 1024

function M.new(t: { [string]: any }): any
    local function f(): number return t.factor() end
    local function height(): number return 6 * f() end
    local function rate(): number
        local r = t.rate()
        if r < QUIET or performance.still() or (t.running ~= nil and not t.running()) then return 0 end
        local along = math.clamp(math.log(r / QUIET) / math.log(CEILING / QUIET), 0, 1)
        return 1 + (16 - 1) * along
    end
    return g.box {
        width = t.width,
        height = height,
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_y = function() return (height() - metrics_mod.thread) / 2 end,
            width = t.width,
            height = metrics_mod.thread,
            radius = 0,
            crisp = true,
            fill = theme.line,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
        g.emitter {
            overlay = true,
            attach = "corner",
            width = t.width,
            height = height,
            from_x = 0,
            from_y = function() return height() / 2 end,
            to_x = t.width,
            to_y = function() return height() / 2 end,
            rate = rate,
            lifetime = 1,
            spread = 0,
            particle_size = function() return 2.6 * f() end,
            trail = 0.1,
            fill = theme.primary,
            color_end = function() return colour.alpha(theme.primary(), 0.25) end,
        },
    }
end

return M
