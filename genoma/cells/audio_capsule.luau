--!strict
-- The level, opened (cells/audio/AudioCapsule.qml at 11bb81e): the dial at
-- its large size, the figure and the slider. It is what the expansion hangs
-- from the cell on a membrane, and what the cell is when it is summoned.
--
-- Here the figure is allowed: the capsule exists because someone asked to
-- see the level, and a figure answering that question is not the interface
-- speaking unprompted.
local g = require("@genoma")
local theme = require("core/theme")
local typography = require("core/typography")
local audio = require("services/audio")
local gauge = require("components/gauge")
local slider = require("components/slider")

local M = {}

-- `metrics()`. Returns the node and content_width().
function M.new(metrics: () -> { [string]: any }): { [string]: any }
    local function f(): number return metrics().factor end
    local function dial(): number return 56 * f() end
    local function figure(): number return 62 * f() end
    local function track(): number return 168 * f() end
    local function gap(): number return 20 * f() end
    local function content_width(): number return dial() + figure() + track() + gap() * 2 end

    local function node(): any
        return g.box {
            direction = "row",
            align = "center",
            gap = gap,
            gauge.new {
                size = dial,
                track_units = 1.5,
                node_units = 4,
                fraction = function() return math.min(1, audio.volume()) end,
                overflow = function() return math.max(0, audio.volume() - 1) end,
                muted = audio.muted,
            },
            g.box {
                width = figure,
                g.text {
                    text = function() return audio.volume_percent() .. "%" end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return metrics().font_value end,
                    weight = typography.weight_value,
                    tabular = true,
                    opacity = function() return if audio.muted() then 0.45 else 1 end,
                },
            },
            slider.new {
                width = track,
                factor = f,
                value = function() return math.min(1, audio.volume()) end,
                dimmed = audio.muted,
                on_move = audio.set_volume,
            },
        }
    end

    return { node = node, content_width = content_width }
end

return M
