--!strict
-- Adipose: the disks, as fat cells (organisms/adipose/AdiposeOrganism.qml
-- at 2cafc17). See docs/design/ORGANISMS.md.
--
-- Each disk is a cell, as large as the disk is next to the largest; inside
-- it a drop of fat as full as the disk, and the nucleus pressed flat
-- against the membrane on the side away from it, as an adipocyte's is.
-- Colour is the fill's state: calm, active past 85%, alert past 95%; or the
-- theme's own with `colour: "theme"`. Up to four disks, the boot partition
-- only when asked for. Drawn with a shader (organisms/adipose.wgsl), Genoma
-- having no canvas.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local storage = require("services/storage")

local SOURCE = require("core/paths").root .. "/genoma/organisms/adipose.wgsl"

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        storage.hold(true)
        local function disks(): { any }
            local out = {}
            for _, d in storage.disks() do
                if (o.entry().system == true or not d.system) and #out < 4 then table.insert(out, d) end
            end
            return out
        end
        local function present(): boolean return storage.loaded() and #disks() > 0 end
        local function tint(fill: number): string
            if o.entry().colour == "theme" then return theme.primary() end
            if fill >= 0.95 then return theme.alert() end
            if fill >= 0.85 then return theme.active() end
            return theme.calm()
        end
        local function single(): boolean return #disks() == 1 end
        local function caption_height(): number return if single() then 0 else 40 * f() end
        local function column(): number
            return if single() then math.min(o.height(), o.width() / 2) else o.width() / math.max(1, #disks())
        end
        local function largest(): number
            local most = 0
            for _, d in disks() do most = math.max(most, d.size) end
            return most
        end
        local function reach(): number
            return math.min(column(), o.height() - caption_height()) / 2 - (if single() then 10 else 6) * f()
        end
        local function radius_of(d: any): number
            if largest() <= 0 then return reach() end
            return reach() * math.max(0.5, math.sqrt(d.size / largest()))
        end
        local function angle_of(d: any): number
            local h = 0
            for i = 1, #d.device do h = (h * 31 + string.byte(d.device, i)) % 9973 end
            return h / 9973 * math.pi * 2
        end
        local function percent(d: any): string return math.round(d.fill * 100) .. "%" end

        local function values(): { number }
            local out = table.create(8 + 16 * 4, 0)
            local ink = colour.parse(theme.text())
            out[1], out[2], out[3], out[4] = ink.r, ink.g, ink.b, ink.a
            local list = disks()
            out[5] = if present() then #list else 0
            out[6] = f()
            for k, d in list do
                local b = 8 + 16 * (k - 1)
                local cx, cy = column() * (k - 1) + column() / 2, (o.height() - caption_height()) / 2
                local r = radius_of(d)
                local inner = r - 2 * f()
                local angle = angle_of(d)
                local ax, ay = math.cos(angle), math.sin(angle)
                local drop = inner * math.sqrt(math.clamp(d.fill, 0, 1))
                local shift = (inner - drop) * 0.35
                local room = inner - (drop - shift)
                local whole = math.max(2.5 * f(), 0.13 * r)
                local depth = math.max(1.2 * f(), math.min(whole, room / 2 - 1 * f()))
                local breadth = math.min(whole * whole / depth, r * 0.6)
                local distance = inner - depth
                local t = colour.parse(tint(d.fill))
                local row = { cx, cy, r, cx - ax * shift, cy - ay * shift, drop, t.r, t.g, t.b, t.a,
                    cx + ax * distance, cy + ay * distance, angle, depth, breadth }
                for i, v in row do out[b + i] = v end
            end
            return out
        end

        local function tech(text: () -> string, color: any, size: () -> number, weight: number?, bottom: any?): any
            return g.text { text = text, color = color, color_bottom = bottom, font = typography.technical, size = size,
                weight = weight or typography.weight_secondary, tabular = true }
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
                        height = o.height,
                        values = values,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not present() end,
                        width = o.width,
                        height = o.height,
                        align = "center",
                        justify = "center",
                        g.text { text = "No disks", color = theme.text_faint, font = typography.expressive,
                            size = function() return math.round(14 * f()) end, italic = true },
                    },
                    -- One disk: its name, its fill and how much, beside it.
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return present() and single() end,
                        offset_x = function() return column() + 14 * f() end,
                        height = o.height,
                        direction = "column",
                        align = "start",
                        justify = "center",
                        gap = function() return 6 * f() end,
                        g.text { text = function() local d = disks()[1] return if d then d.name else "" end, color = theme.text,
                            font = typography.expressive, size = function() return m().font_label end,
                            max_width = function() return o.width() - column() - 14 * f() end },
                        tech(function() local d = disks()[1] return if d then percent(d) else "" end,
                            function() local d = disks()[1] return theme.gradient_top(tint(if d then d.fill else 0)) end,
                            function() return math.round(40 * f()) end, typography.weight_value,
                            function() local d = disks()[1] return theme.gradient_bottom(tint(if d then d.fill else 0)) end),
                        tech(function()
                            local d = disks()[1]
                            return if d then storage.bytes(d.used) .. " OF " .. storage.bytes(d.size) else ""
                        end, theme.text_muted, function() return m().font_meta end),
                    },
                    -- Several: each one's name and fill under it.
                    g.each {
                        overlay = true,
                        attach = "corner",
                        items = function()
                            if single() then return {} end
                            local out = {}
                            for i, d in disks() do table.insert(out, { i = i, d = d }) end
                            return out
                        end,
                        key = function(it: any) return it.d.device end,
                        row = function(it: () -> any)
                            return g.box {
                                overlay = true,
                                attach = "corner",
                                offset_x = function() return column() * (it().i - 1) + 4 * f() end,
                                offset_y = function() return o.height() - caption_height() + 6 * f() end,
                                width = function() return column() - 8 * f() end,
                                direction = "column",
                                align = "center",
                                gap = function() return 3 * f() end,
                                g.text { text = function() return it().d.name end, color = theme.text, font = typography.expressive,
                                    size = function() return m().font_secondary end, max_width = function() return column() - 8 * f() end },
                                g.box {
                                    direction = "row",
                                    gap = function() return 6 * f() end,
                                    tech(function() return percent(it().d) end, function() return theme.gradient_top(tint(it().d.fill)) end,
                                        function() return m().font_meta end, typography.weight_value,
                                        function() return theme.gradient_bottom(tint(it().d.fill)) end),
                                    g.box { present = function() return #disks() == 2 end,
                                        tech(function() return storage.bytes(it().d.size) end, theme.text_muted, function() return m().font_meta end) },
                                },
                            }
                        end,
                    },
                }
            end,
        }
    end,
}
