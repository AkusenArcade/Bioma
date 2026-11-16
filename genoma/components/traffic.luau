--!strict
-- The traffic through a connection, as particles carried along a lane
-- (Genoma's `g.emitter`): what comes in runs from the far end, where the
-- network is, toward the near one; what goes out runs back. How many run
-- is what the traffic says, on osmosis's logarithmic scale from an idle
-- link to a fast one; a quiet link has none, and nothing runs.
--
-- `t`: width(), factor(), inbound() and outbound() (bytes a second),
-- present() optional.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local performance = require("core/performance")

local M = {}

local QUIET = 4 * 1024 -- below this a link is at rest
local CEILING = 100 * 1024 * 1024 -- a fast link's whole lane

-- Particles a second for so many bytes a second.
function M.rate(bytes: number): number
    if bytes < QUIET then return 0 end
    local along = math.clamp(math.log(bytes / QUIET) / math.log(CEILING / QUIET), 0, 1)
    return 0.8 + (24 - 0.8) * along
end

function M.new(t: { [string]: any }): any
    local function f(): number return t.factor() end
    -- Two lanes a hair apart, so the ways never cross: in above, out below.
    local function height(): number return 8 * f() end
    local function lane(inbound: boolean): () -> number
        return function() return height() / 2 + (if inbound then -1.5 else 1.5) * f() end
    end
    -- Performance mode's motion lever holds it still.
    local function rate(bytes: () -> number): () -> number
        return function()
            if performance.still() then return 0 end
            return M.rate(bytes())
        end
    end
    local function flow(inbound: boolean): any
        return g.emitter {
            overlay = true,
            attach = "corner",
            width = t.width,
            height = height,
            from_x = function() return if inbound then t.width() else 0 end,
            from_y = lane(inbound),
            to_x = function() return if inbound then 0 else t.width() end,
            to_y = lane(inbound),
            rate = rate(if inbound then t.inbound else t.outbound),
            -- A particle crosses in about a second, whatever the traffic.
            lifetime = 1.1,
            spread = function() return 0.6 * f() end,
            particle_size = function() return 2.5 * f() end,
            size_end = function() return 1.5 * f() end,
            trail = 0.08,
            fill = theme.primary,
            color_end = function() return colour.alpha(theme.primary(), 0) end,
        }
    end
    return g.box {
        present = t.present,
        width = t.width,
        height = height,
        flow(true),
        flow(false),
    }
end

return M
