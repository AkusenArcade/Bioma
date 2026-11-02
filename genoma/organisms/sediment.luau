--!strict
-- Sediment: the files used lately, laid down in strata (organisms/sediment/
-- SedimentOrganism.qml at 2cafc17). See docs/design/ORGANISMS.md.
--
-- One layer per file, the newest on top, each as thick as it is recent: a
-- file used a moment ago is a deep bed, one from last week a thin line.
-- A file used again is deposited on top, and the rest settle under it.
-- Names where a layer is thick enough to hold one. 8, 16 or 32 layers.
-- Drawn with a shader (organisms/sediment.wgsl), Genoma having no canvas.
--
-- Not yet: a name elided in its middle.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local recent = require("services/recent")

local SOURCE = require("core/paths").root .. "/genoma/organisms/sediment.wgsl"
local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        recent.hold(true)
        local function present(): boolean return #recent.files() > 0 end
        local function depth(): number
            local d = o.entry().depth
            return if d == 8 or d == 16 or d == 32 then d else 16
        end
        local function names(): boolean return o.entry().names ~= false end
        local function figures(): boolean return o.entry().figures ~= false end
        local function gap(): number return 14 * f() end
        local function caption_height(): number return m().font_label * 1.3 end
        local function column(): number return math.max(0, o.height() - (if figures() then gap() + caption_height() else 0)) end

        -- The age the thickness is read from, every ten minutes.
        local now = g.signal(os.time())
        g.effect(function()
            if not present() then return end
            g.timer { every = 600, on_tick = function() now.value = os.time() end }
        end)
        local function shown(): { any }
            local out = {}
            for i, file in recent.files() do
                if i > depth() then break end
                table.insert(out, file)
            end
            return out
        end
        local function weight(at: number): number
            local hours = math.max(0, (now.value - at) / 3600)
            return (1 + hours / 6) ^ -0.7
        end
        local layers = g.computed(function(): { any }
            local list = shown()
            local least = 2 * f()
            local total = 0
            local weights = {}
            for i, file in list do
                weights[i] = weight(file.at)
                total += weights[i]
            end
            local room = math.max(0, column() - least * #list)
            local out, y = {}, 0
            for i, file in list do
                local h = least + (if total > 0 then weights[i] / total * room else 0)
                table.insert(out, { file = file, y = y, h = h })
                y += h
            end
            return out
        end)
        local function seed(key: string): number
            local h = 0
            for i = 1, #key do h = (h * 31 + string.byte(key, i)) % 9973 end
            return h / 9973 * math.pi * 2
        end
        local function age(at: number): string
            local minutes = math.max(0, math.round((now.value - at) / 60))
            if minutes < 60 then return minutes .. " M" end
            local hours = math.round(minutes / 60)
            if hours < 48 then return hours .. " H" end
            return math.round(hours / 24) .. " D"
        end
        local function values(): { number }
            local out = table.create(8 + 3 * 32, 0)
            local c = colour.parse(theme.primary())
            out[1], out[2], out[3], out[4] = c.r, c.g, c.b, c.a
            local list = layers.value
            out[5] = #list
            out[6] = f()
            out[7] = column()
            for k, l in list do
                local b = 8 + 3 * (k - 1)
                out[b + 1], out[b + 2], out[b + 3] = l.y, l.h, seed(l.file.path)
            end
            return out
        end
        local function today(): number
            local d = os.date("*t", now.value) :: any
            local midnight = os.time({ year = d.year, month = d.month, day = d.day, hour = 0 })
            local n = 0
            for _, file in recent.files() do if file.at >= midnight then n += 1 end end
            return n
        end
        local function oldest(): string
            local list = shown()
            if #list == 0 then return "" end
            local d = os.date("*t", list[#list].at) :: any
            return "SINCE " .. d.day .. " " .. MONTHS[d.month]
        end

        return {
            present = present,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    g.shader {
                        overlay = true,
                        attach = "corner",
                        src = SOURCE,
                        width = o.width,
                        height = column,
                        values = values,
                        follow = function() return require("core/timing").seconds.open end,
                    },
                    g.each {
                        overlay = true,
                        attach = "corner",
                        items = function()
                            if not names() then return {} end
                            local out = {}
                            for i, l in layers.value do
                                if l.h >= 22 * f() then table.insert(out, { i = i, l = l }) end
                            end
                            return out
                        end,
                        key = function(it: any) return it.l.file.path end,
                        row = function(it: () -> any)
                            return g.box {
                                overlay = true,
                                attach = "corner",
                                offset_x = function() return 12 * f() end,
                                offset_y = function() return it().l.y end,
                                width = function() return o.width() - 24 * f() end,
                                height = function() return it().l.h end,
                                direction = "row",
                                align = "center",
                                justify = "between",
                                transition = { offset_y = "reflow", height = "reflow" },
                                g.text { text = function() return it().l.file.name end, color = theme.text,
                                    font = typography.expressive, size = function() return math.round(13 * f()) end,
                                    max_width = function() return o.width() - 24 * f() - 50 * f() end },
                                g.text { text = function() return age(it().l.file.at) end, color = theme.text_muted,
                                    font = typography.technical, size = function() return m().font_meta end, tabular = true },
                            }
                        end,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not present() end,
                        width = o.width,
                        height = column,
                        align = "center",
                        justify = "center",
                        g.text { text = "No recent files", color = theme.text_faint, font = typography.expressive,
                            size = function() return math.round(14 * f()) end, italic = true },
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return figures() and present() end,
                        offset_y = function() return column() + gap() end,
                        width = o.width,
                        direction = "row",
                        align = "center",
                        justify = "between",
                        g.box {
                            direction = "row",
                            align = "end",
                            gap = function() return 8 * f() end,
                            g.text { text = "TODAY", color = theme.text, font = typography.technical,
                                size = function() return m().font_meta end, weight = typography.weight_label,
                                tracking = typography.label_tracking },
                            g.text { text = function() return tostring(today()) end,
                                color = function() return theme.gradient_top(theme.primary()) end,
                                color_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                                font = typography.technical, size = function() return m().font_label end,
                                weight = typography.weight_value, tabular = true },
                        },
                        g.text { text = function() return #shown() .. " FILES · " .. oldest() end, color = theme.text_muted,
                            font = typography.technical, size = function() return m().font_meta end, tabular = true },
                    },
                }
            end,
        }
    end,
}
