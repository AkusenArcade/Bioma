--!strict
-- The day where the user is: the sun's path across it, what is left of the
-- light, and the moon (organisms/photoperiod/PhotoperiodOrganism.qml at
-- 2cafc17). See docs/design/ORGANISMS.md.
--
-- The sky of the weather's place, worked out here from where it is: the
-- horizon, the sun's path through today with the light still to come
-- filled under it, the moon's path and the moon with its phase, and the
-- times the sun crosses the horizon. It changes a minute at a time, which
-- is how fast the sky does. Blank until the place is found.
--
-- Drawn with a shader (organisms/photoperiod.wgsl), Genoma having no
-- canvas: the paths are sampled into columns here.
local g = require("@genoma")
local clock = require("@genoma/clock")
local colour = require("core/colour")
local config = require("core/config")
local theme = require("core/theme")
local typography = require("core/typography")
local weather = require("services/weather")
local sky_mod = require("organisms/sky")

local SOURCE = require("core/paths").root .. "/genoma/organisms/photoperiod.wgsl"
local NS, NM = 56, 47
local NONE = -2000

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function located(): boolean
            return config.get("weather.latitude", nil) ~= nil and config.get("weather.located_for", "") == weather.city()
        end
        -- The weather service is asked only to find the place.
        local holding = false
        g.effect(function()
            local want = not located()
            if want ~= holding then
                holding = want
                g.untracked(function() weather.hold(want) end)
            end
        end)
        local function blank(): boolean return not located() end
        local function latitude(): number return if located() then config.get("weather.latitude", 0) else 0 end
        local function longitude(): number return if located() then config.get("weather.longitude", 0) else 0 end
        local function reason(): string
            if weather.city() == "" then return "Type a city under Settings → Organisms → Weather → City." end
            return if weather.problem() ~= "" then weather.problem() else "Looking for the place…"
        end

        -- Today from solar midnight, sampled every five minutes; two days of
        -- the sun for what crosses next.
        local sky = g.computed(function(): any
            if blank() then return nil end
            local _ = clock.minute
            local lat, lon = latitude(), longitude()
            local now = os.time() * 1000
            local step = 5 * 60 * 1000
            local day = 24 * 3600 * 1000
            local solar_midnight = -lon / 15 * 3600 * 1000
            local start = now - ((now - solar_midnight) % day + day) % day
            local sun = sky_mod.path(sky_mod.sun, start, start + 2 * day, step, lat, lon)
            local today = {}
            for i = 1, day // step + 1 do today[i] = sun[i] end
            return {
                now = now,
                sun = today,
                sun_now = sky_mod.sun(now, lat, lon),
                moon = sky_mod.path(sky_mod.moon, start, start + day + 50 * 60 * 1000, step, lat, lon),
                moon_now = sky_mod.moon(now, lat, lon),
                light = sky_mod.moon_light(now),
                crossings = sky_mod.crossings(sun),
                today_crossings = sky_mod.crossings(today),
            }
        end)
        local function daylight(): boolean local s = sky.value return s ~= nil and sky_mod.daylight(s.sun_now.altitude) end
        local function next_crossing(): any
            local s = sky.value
            if not s then return nil end
            for _, c in s.crossings do if c.time > s.now then return c end end
            return nil
        end
        local function day_minutes(): number
            local s = sky.value
            if not s then return 0 end
            local minutes = 0
            for i = 2, #s.sun do
                local a, b = s.sun[i - 1].altitude + 0.833, s.sun[i].altitude + 0.833
                local span = (s.sun[i].time - s.sun[i - 1].time) / 60000
                if a > 0 and b > 0 then minutes += span
                elseif a > 0 or b > 0 then minutes += span * math.max(a, b) / math.abs(a - b) end
            end
            return math.round(minutes)
        end
        local function duration(minutes: number): string
            local h, mm = minutes // 60, minutes % 60
            return if h > 0 then string.format("%d H %02d M", h, mm) else mm .. " M"
        end
        local function hhmm(ms: number): string
            local d = os.date("*t", ms // 1000) :: any
            return string.format("%02d:%02d", d.hour, d.min)
        end
        local function headline(): string
            if not sky.value then return "" end
            if next_crossing() == nil then return if daylight() then "MIDNIGHT SUN" else "POLAR NIGHT" end
            return if daylight() then "LIGHT LEFT" else "SUNRISE IN"
        end
        local function remaining(): string
            local c = next_crossing()
            if not c then return "" end
            return duration(math.max(0, math.round((c.time - sky.value.now) / 60000)))
        end

        -- ---- The picture ----
        local function header_height(): number return m().font_label * 1.4 end
        local function footer_height(): number return math.round(14 * f()) * 1.4 end
        local function picture_top(): number return header_height() + 10 * f() end
        local function picture_height(): number return o.height() - footer_height() - 8 * f() - picture_top() end
        local function margin(): number return 9 * f() end
        local function horizon(): number return math.round(picture_height() * 0.74) end
        local function facing(): number return if latitude() >= 0 then 180 else 0 end
        local function px(bearing: number): number
            local along = ((bearing - facing() + 540) % 360) / 360
            return margin() + along * (o.width() - 2 * margin())
        end
        -- The picture's geometry, worked out once for the sky and the size:
        -- not again when a colour moves. Kept in the same binding as the
        -- palette, every palette change re-ran a thousand samples through
        -- functions that each read the sizes again, 200 ms of the main
        -- thread (Akusen, 2026-11-03: the wallpaper's crossfade stuttered).
        local geometry = g.computed(function(): any
            local s = sky.value
            local w, mg, hz, ph, unit = o.width(), margin(), horizon(), picture_height(), f()
            local face = facing()
            local span = w - 2 * mg
            local above = (hz - mg) / 90
            local below = (ph - hz - 2 * unit) / 90
            local function x_of(bearing: number): number return mg + (((bearing - face + 540) % 360) / 360) * span end
            local function y_of(altitude: number): number
                return if altitude >= 0 then hz - altitude * above else hz - altitude * below
            end
            -- A path into n columns across the picture: each segment that
            -- does not wrap round the edge fills the columns under it.
            local function columns(samples: { any }, n: number, keep: (any) -> boolean): { number }
                local out = table.create(n, NONE)
                local step = span / (n - 1)
                for i = 2, #samples do
                    local a, b = samples[i - 1], samples[i]
                    if keep(a) and keep(b) then
                        local xa, xb = x_of(a.bearing), x_of(b.bearing)
                        if math.abs(xb - xa) < w / 2 then
                            local ya, yb = y_of(a.altitude), y_of(b.altitude)
                            local lo, hi = math.min(xa, xb), math.max(xa, xb)
                            local first = math.max(0, math.ceil((lo - mg) / step))
                            local last = math.min(n - 1, math.floor((hi - mg) / step))
                            for k = first, last do
                                local x = mg + k * step
                                local t = if hi > lo then (x - xa) / (xb - xa) else 0
                                out[k + 1] = ya + (yb - ya) * t
                            end
                        end
                    end
                end
                return out
            end
            local out: { [string]: any } = { horizon = hz, margin = mg, unit = unit, north = latitude() >= 0 }
            if not s then return out end
            out.sun = { x_of(s.sun_now.bearing), y_of(s.sun_now.altitude), if s.sun_now.altitude >= 0 then 1 else 0 }
            out.moon = { x_of(s.moon_now.bearing), y_of(s.moon_now.altitude), if s.moon_now.altitude >= 0 then 1 else 0.45 }
            out.phase = s.light.phase
            out.sun_cols = columns(s.sun, NS, function() return true end)
            out.moon_cols = columns(s.moon, NM, function(p: any) return p.altitude >= 0 end)
            -- The day runs the way the sun goes from rising to setting.
            local c = s.today_crossings
            local forward = true
            if #c >= 2 then
                local lat, lon = latitude(), longitude()
                forward = x_of(sky_mod.sun(c[1].time, lat, lon).bearing) < x_of(sky_mod.sun(c[2].time, lat, lon).bearing)
            end
            out.forward = forward
            return out
        end)
        local function values(): { number }
            local geo = geometry.value
            local out = table.create(128, 0)
            out[1] = geo.horizon
            local function put(at: number, hex: string)
                local c = colour.parse(hex)
                out[at + 1], out[at + 2], out[at + 3], out[at + 4] = c.r, c.g, c.b, c.a
            end
            put(8, theme.primary())
            put(12, theme.text())
            put(16, theme.line())
            out[21] = geo.margin
            out[22] = 1
            out[23] = geo.unit
            out[24] = if geo.north then 1 else -1
            if not geo.sun then
                out[2], out[3], out[5], out[6] = -100, -100, -100, -100
                for i = 25, 128 do out[i] = NONE end
                return out
            end
            out[2], out[3], out[4] = geo.sun[1], geo.sun[2], geo.sun[3]
            out[5], out[6], out[7] = geo.moon[1], geo.moon[2], geo.moon[3]
            out[8] = geo.phase
            for i = 1, NS do out[24 + i] = geo.sun_cols[i] end
            for i = 1, NM do out[80 + i] = geo.moon_cols[i] end
            out[128] = if geo.forward then 1 else 0
            return out
        end

        local function meta(text: () -> string, color: any, weight: number?): any
            return g.text { text = text, color = color, font = typography.technical, size = function() return m().font_meta end,
                weight = weight or typography.weight_secondary, tracking = typography.label_tracking, tabular = true }
        end

        return {
            present = function() return true end,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    -- The place's name, and the light left or the time to it.
                    g.box {
                        overlay = true,
                        attach = "corner",
                        width = o.width,
                        height = header_height,
                        direction = "row",
                        align = "center",
                        justify = "between",
                        g.text {
                            text = function() local p = weather.place() return if p ~= "" then p else "Photoperiod" end,
                            color = theme.text, font = typography.expressive,
                            size = function() return math.round(15 * f()) end, weight = 700,
                            max_width = function() return o.width() * 0.5 end,
                        },
                        g.box {
                            present = function() return not blank() end,
                            direction = "row",
                            align = "center",
                            gap = function() return 8 * f() end,
                            meta(headline, theme.text, typography.weight_label),
                            g.text { present = function() return remaining() ~= "" end, text = remaining,
                                color = function() return theme.gradient_top(theme.primary()) end,
                                color_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                                font = typography.technical, size = function() return m().font_label end,
                                weight = typography.weight_value, tabular = true },
                        },
                    },
                    g.shader {
                        overlay = true,
                        attach = "corner",
                        offset_y = picture_top,
                        src = SOURCE,
                        width = o.width,
                        height = picture_height,
                        values = values,
                    },
                    -- The times the sun crosses the horizon today, under where
                    -- it does.
                    g.each {
                        overlay = true,
                        attach = "corner",
                        items = function()
                            local s = sky.value
                            local out = {}
                            if s then for i, c in s.today_crossings do table.insert(out, { i = i, time = c.time }) end end
                            return out
                        end,
                        key = function(c: any) return tostring(c.i) end,
                        row = function(c: () -> any)
                            local function x(): number return px(sky_mod.sun(c().time, latitude(), longitude()).bearing) end
                            return g.box {
                                overlay = true,
                                attach = "corner",
                                offset_x = function() return math.clamp(x() - 22 * f(), 0, o.width() - 44 * f()) end,
                                offset_y = function() return picture_top() + picture_height() - m().font_meta * 1.3 end,
                                width = function() return 44 * f() end,
                                align = "center",
                                meta(function() return hhmm(c().time) end, theme.text_muted),
                            }
                        end,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = blank,
                        offset_x = function() return 14 * f() end,
                        offset_y = function() return picture_top() + horizon() / 2 - 14 * f() end,
                        width = function() return o.width() - 28 * f() end,
                        align = "center",
                        g.text { text = reason, color = theme.text_muted, font = typography.expressive,
                            size = function() return math.round(14 * f()) end, italic = true, wrap = true,
                            text_align = "center", max_width = function() return o.width() - 28 * f() end },
                    },
                    -- The moon's phase, and the day's length.
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not blank() end,
                        offset_y = function() return o.height() - footer_height() end,
                        width = o.width,
                        height = footer_height,
                        direction = "row",
                        align = "center",
                        justify = "between",
                        g.box {
                            direction = "row",
                            align = "center",
                            gap = function() return 8 * f() end,
                            g.text { text = function() local s = sky.value return if s then sky_mod.phase_name(s.light.phase) else "" end,
                                color = theme.text_muted, font = typography.expressive, size = function() return math.round(14 * f()) end },
                            meta(function() local s = sky.value return if s then math.round(s.light.fraction * 100) .. " %" else "" end, theme.text_muted),
                        },
                        meta(function() return "DAY " .. duration(day_minutes()) end, theme.text_muted),
                    },
                }
            end,
        }
    end,
}
