--!strict
-- This month, on the wall (organisms/calendar/CalendarOrganism.qml at
-- 2cafc17). See docs/design/ORGANISMS.md §04.
--
-- The clock cell's month, alone and read-only: no arrows, no navigation, a
-- calendar on the wall and not a planner. Today is the only lit day. Six
-- weeks always: the panel never changes height from one month to the next.
local g = require("@genoma")
local clock = require("@genoma/clock")
local theme = require("core/theme")
local typography = require("core/typography")

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December" }
local WEEKDAYS = { "M", "T", "W", "T", "F", "S", "S" }

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function today(): any
            local _ = clock.hour -- a new day comes with a new hour
            return os.date("*t") :: any
        end
        -- Six weeks from the Monday on or before the first.
        local days = g.computed(function(): { any }
            local d = today()
            local first = os.time({ year = d.year, month = d.month, day = 1, hour = 12 })
            local lead = ((os.date("*t", first) :: any).wday + 5) % 7
            local out = {}
            for i = 0, 41 do
                local day = os.date("*t", os.time({ year = d.year, month = d.month, day = 1 - lead + i, hour = 12 })) :: any
                table.insert(out, { day = day.day, in_month = day.month == d.month, today = day.month == d.month and day.day == d.day })
            end
            return out
        end)
        local function spacing(): number return 10 * f() end
        local function weekday_height(): number return 22 * f() end
        local function header_height(): number return math.round(19 * f()) * 1.3 end
        local function cell_width(): number return o.width() / 7 end
        local function cell_height(): number
            return math.max(0, (o.height() - header_height() - spacing() - weekday_height()) / 6)
        end
        local function technical(text: () -> string, color: any, size: () -> number, weight: any): any
            return g.text {
                text = text, color = color, font = typography.technical, size = size,
                weight = weight or typography.weight_secondary, tabular = true,
            }
        end

        local function week(row: number): any
            local cells: { [any]: any } = { direction = "row" }
            for column = 1, 7 do
                local index = row * 7 + column
                local function day(): any return days.value[index] end
                table.insert(cells, g.box {
                    width = cell_width,
                    height = cell_height,
                    align = "center",
                    justify = "center",
                    -- Today is lit the way a chosen control is: the disc with
                    -- the light's gradient, the figure dark on it.
                    g.capsule {
                        overlay = true,
                        present = function() return day().today end,
                        width = function() return 28 * f() end,
                        height = function() return 28 * f() end,
                        fill = function() return theme.gradient_top(theme.primary()) end,
                        fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                        rim_top = "#00000000",
                        rim_bottom = "#00000000",
                    },
                    technical(function() return tostring(day().day) end, function()
                        local d = day()
                        if d.today then return theme.background() end
                        return if d.in_month then theme.text() else theme.text_faint()
                    end, function() return m().font_secondary end, function()
                        return if day().today then typography.weight_title else typography.weight_secondary
                    end),
                })
            end
            return g.box(cells)
        end

        return {
            node = function()
                local weekdays: { [any]: any } = { direction = "row" }
                for _, letter in WEEKDAYS do
                    table.insert(weekdays, g.box {
                        width = cell_width,
                        height = weekday_height,
                        align = "center",
                        justify = "center",
                        technical(function() return letter end, theme.text_faint, function() return m().font_meta end),
                    })
                end
                local grid: { [any]: any } = { direction = "column" }
                for row = 0, 5 do table.insert(grid, week(row)) end
                return g.box {
                    width = o.width,
                    height = o.height,
                    direction = "column",
                    align = "start",
                    gap = spacing,
                    -- The month's name is language; the year is a figure.
                    g.box {
                        height = header_height,
                        direction = "row",
                        align = "end",
                        gap = function() return 10 * f() end,
                        g.text {
                            text = function() return MONTHS[today().month] end,
                            color = theme.text,
                            font = typography.expressive,
                            size = function() return math.round(19 * f()) end,
                            weight = 700,
                        },
                        technical(function() return tostring(today().year) end, theme.text_muted, function() return m().font_secondary end),
                    },
                    g.box {
                        direction = "column",
                        g.box(weekdays),
                        g.box(grid),
                    },
                }
            end,
        }
    end,
}
