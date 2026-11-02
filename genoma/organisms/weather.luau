--!strict
-- The weather where the user is: now, and the next five hours (organisms/
-- weather/WeatherOrganism.qml at 2cafc17). See docs/design/ORGANISMS.md §05.
--
-- The temperature measures the weather, not the machine, so it is primary
-- and never takes a state colour. It is always there: without a reading
-- young enough to trust it is blank rather than absent, the glyph unlit, no
-- figures, and in the well why, or where the city is typed (Akusen,
-- 2026-10-05).
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local weather = require("services/weather")

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        -- The service asks only while an organism holds it.
        weather.hold(true)
        local function blank(): boolean return not weather.fresh() end
        local function now(): any return if blank() then nil else weather.current() end
        local function missing(): string
            if weather.city() == "" then return "No city set" end
            return if weather.problem() ~= "" then "No forecast" else "Asking…"
        end
        local function reason(): string
            if weather.city() == "" then return "Type a city under Settings → Organisms → Weather → City." end
            return if weather.problem() ~= "" then weather.problem() else "The forecast is on its way."
        end
        local function degrees(v: number?): string return if v == nil then "" else math.round(v) .. "°" end
        local function technical(text: () -> string, color: any, size: () -> number, weight: any, bottom: any?): any
            return g.text { text = text, color = color, color_bottom = bottom, font = typography.technical, size = size,
                weight = weight or typography.weight_secondary, tabular = true }
        end
        local function lit_icon(name: () -> string, size: () -> number, lit: () -> boolean): any
            return g.icon {
                width = size, height = size, icon = name,
                gradient_top = function() return if lit() then theme.gradient_top(theme.primary()) else theme.text_faint() end,
                gradient_bottom = function() return if lit() then theme.gradient_bottom(theme.primary()) else theme.text_faint() end,
            }
        end

        local function hour(item: () -> any): any
            return g.box {
                width = function() return o.width() / 5 end,
                direction = "column",
                align = "center",
                gap = function() return 2 * f() end,
                technical(function() return string.format("%02d", item().hour) end, theme.text_faint, function() return m().font_meta end),
                lit_icon(function() return weather.glyph_for(item().code, item().day) end, function() return 20 * f() end, function() return true end),
                technical(function() return degrees(item().temperature) end, theme.text, function() return m().font_secondary end),
            }
        end

        return {
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    direction = "column",
                    align = "start",
                    justify = "between",
                    g.box {
                        direction = "column",
                        align = "start",
                        gap = function() return 6 * f() end,
                        -- The place's name is language.
                        g.text {
                            text = function() local p = weather.place() return if p ~= "" then p else "Weather" end,
                            color = theme.text,
                            font = typography.expressive,
                            size = function() return math.round(15 * f()) end,
                            weight = 700,
                            max_width = o.width,
                        },
                        g.box {
                            direction = "row",
                            align = "center",
                            gap = function() return 14 * f() end,
                            lit_icon(function()
                                local n = now()
                                return if n then weather.glyph_for(n.code, n.day) else "weather-cloudy"
                            end, function() return 44 * f() end, function() return not blank() end),
                            technical(function() local n = now() return if n then degrees(n.temperature) else "" end,
                                function() return theme.gradient_top(theme.primary()) end,
                                function() return math.round(40 * f()) end, typography.weight_value,
                                function() return theme.gradient_bottom(theme.primary()) end),
                            g.box {
                                direction = "column",
                                align = "start",
                                gap = function() return 2 * f() end,
                                g.text {
                                    text = function() local n = now() return if n then weather.words_for(n.code) else missing() end,
                                    color = theme.text_muted,
                                    font = typography.expressive,
                                    size = function() return math.round(15 * f()) end,
                                },
                                g.box {
                                    present = function() return not blank() end,
                                    technical(function()
                                        local n = now()
                                        return if n then degrees(n.high) .. " · " .. degrees(n.low) else ""
                                    end, theme.text_muted, function() return m().font_secondary end),
                                },
                            },
                        },
                    },
                    -- The next hours, in a well: the hour, what it will be
                    -- like, how warm.
                    g.capsule {
                        width = o.width,
                        height = function() return 64 * f() end,
                        radius = function() return 10 * f() end,
                        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                        rim_top = "#00000000",
                        rim_bottom = "#00000000",
                        align = "center",
                        justify = "center",
                        g.text {
                            present = blank,
                            text = reason,
                            color = theme.text_muted,
                            font = typography.expressive,
                            size = function() return math.round(14 * f()) end,
                            italic = true,
                            wrap = true,
                            text_align = "center",
                            max_width = function() return o.width() - 28 * f() end,
                        },
                        g.each {
                            present = function() return not blank() end,
                            direction = "row",
                            items = weather.hours,
                            key = function(h: any) return tostring(h.hour) end,
                            row = hour,
                        },
                    },
                }
            end,
        }
    end,
}
