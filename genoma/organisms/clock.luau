--!strict
-- The time, large, the clock cell's face beside it, and the date in words
-- under them (organisms/clock/ClockOrganism.qml at 2cafc17). See
-- docs/design/ORGANISMS.md §01.
--
-- The face is the cell's own: the hour filling and starting again empty, or
-- what is left of a timer while one runs, and round the rim the disc that
-- is where the second hand is. 12 or 24 hours as the clock cell was told,
-- so the desktop does not answer the same question two ways.
local g = require("@genoma")
local clock = require("@genoma/clock")
local theme = require("core/theme")
local typography = require("core/typography")
local time = require("services/time")
local dial = require("components/dial")
local organisms = require("structure/organisms")

local DAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December" }

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function twenty_four(): boolean return organisms.cell_option("clock", "format", "24h") == "24h" end
        local function figures(): string
            local h = clock.hour
            if twenty_four() then return string.format("%02d:%02d", h, clock.minute) end
            return string.format("%d:%02d", if h % 12 == 0 then 12 else h % 12, clock.minute)
        end
        -- In English and spelled out, whatever the system locale.
        local function date(): string
            local _ = clock.hour -- a new day comes with a new hour
            local d = os.date("*t") :: any
            return DAYS[d.wday] .. " " .. d.day .. " " .. MONTHS[d.month]
        end
        return {
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    direction = "column",
                    align = "center",
                    justify = "center",
                    gap = function() return 4 * f() end,
                    g.box {
                        direction = "row",
                        align = "center",
                        gap = function() return 16 * f() end,
                        g.text {
                            text = figures,
                            color = function() return theme.gradient_top(theme.primary()) end,
                            color_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                            font = typography.expressive,
                            size = function() return math.round(72 * f()) end,
                            weight = 500,
                            tabular = true,
                        },
                        g.text {
                            present = function() return not twenty_four() end,
                            text = function() return if clock.hour >= 12 then "PM" else "AM" end,
                            color = theme.text_muted,
                            font = typography.technical,
                            size = function() return o.metrics().font_label end,
                            weight = typography.weight_label,
                            tracking = typography.label_tracking,
                        },
                        -- The size of the vitals organism's rings.
                        dial.new {
                            size = function() return 62 * f() end,
                            fraction = function()
                                if time.running() then return time.fraction_left() end
                                return (clock.minute * 60 + clock.second) / 3600
                            end,
                            orbit = function() return clock.second / 60 end,
                        },
                    },
                    g.text {
                        text = date,
                        color = theme.text_muted,
                        font = typography.expressive,
                        size = function() return math.round(19 * f()) end,
                    },
                }
            end,
        }
    end,
}
