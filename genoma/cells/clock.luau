--!strict
-- The time (cells/clock/Clock.qml at 7e62c5c). One of the two things the
-- shell says at rest, and human language, so in the expressive face. The
-- minute dial beside it is the only movement: the hour filling and starting
-- again empty (what is left of a timer, while one runs), and round its rim
-- the second hand.
--
-- Not yet: the expansion (ClockExpansion.qml: the month, other places, the
-- timer and the alarm, the day's appointments), whose fields wait for
-- Genoma's text field. Until it comes the cell opens nothing.
local g = require("@genoma")
local clock = require("@genoma/clock")
local theme = require("core/theme")
local typography = require("core/typography")
local time = require("services/time")
local dial = require("components/dial")

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function twenty_four(): boolean return cell.option("format", "24h") == "24h" end
        local function size(): number return 19 * f() end

        local function reading(): string
            local h = clock.hour
            if not twenty_four() then
                h = if h % 12 == 0 then 12 else h % 12
                return string.format("%d:%02d", h, clock.minute)
            end
            return string.format("%02d:%02d", h, clock.minute)
        end

        local function text_width(): number
            return g.text_width { text = reading(), font = typography.expressive(), size = size(),
                weight = typography.weight_value, tabular = true }
        end

        return {
            -- The dial is round and sits against the trailing cap.
            padding_leading = 16,
            padding_trailing = 12,
            -- Conditional, it is there when the hour strikes, for that minute.
            condition = function() return if clock.minute == 0 then 1 else 0 end,
            content_width = function() return text_width() + 8 * f() + 26 * f() end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = function() return 8 * f() end,
                    -- Tabular figures, or the width dances every minute.
                    g.text {
                        font = typography.expressive,
                        size = size,
                        weight = typography.weight_value,
                        tabular = true,
                        color = theme.text,
                        text = reading,
                    },
                    -- The size of the vitals' indicators.
                    dial.new {
                        size = function() return 26 * f() end,
                        fraction = function()
                            if time.running() then return time.fraction_left() end
                            return (clock.minute * 60 + clock.second) / 3600
                        end,
                        orbit = function() return clock.second / 60 end,
                    },
                }
            end,
        }
    end,
}
