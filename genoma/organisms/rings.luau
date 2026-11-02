--!strict
-- Growth rings: the machine's life, a ring a day (organisms/rings/
-- RingsOrganism.qml at 2cafc17). See docs/design/ORGANISMS.md.
--
-- One ring for every day since the system was installed, the pith at the
-- centre and today at the bark; each as dark as that day was spent at the
-- machine, a full day being ten hours. Days nobody counted are bare wood,
-- grouped by month (or week) where a ring is too thin to be seen alone,
-- and the boundaries between months or years drawn. Under it the host's
-- name, the system's age, and today's time at the machine.
--
-- Drawn with a shader (organisms/rings.wgsl), Genoma having no canvas.
--
-- Not yet: the session's own active time and AWAY, which only Bioma on
-- Quickshell knows while it counts (services/activity.luau): today's is
-- said instead; each ring's own small wobble.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local activity = require("services/activity")
local machine = require("services/machine")

local SOURCE = require("core/paths").root .. "/genoma/organisms/rings.wgsl"
local FULL_DAY = 10 * 60
local MAX_BANDS = 250

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        activity.hold(true)
        machine.ask()
        local function figures(): boolean return o.entry().figures ~= false end
        local function gap(): number return 14 * f() end
        local function caption_height(): number return m().font_label * 1.3 + 6 * f() + m().font_label * 1.3 end
        local function disc(): number
            return math.max(0, math.min(o.width(), o.height() - (if figures() then gap() + caption_height() else 0)))
        end
        local function disc_x(): number return (o.width() - disc()) / 2 end

        -- The first day: the system's birth, or an earlier day counted.
        local function birth(): string
            if machine.born() <= 0 then return "" end
            local born = activity.date_key(machine.born())
            local first = nil
            for key in activity.days() do if not first or key < first then first = key end end
            return if first and first < born then first else born
        end
        local function present(): boolean return activity.loaded() and birth() ~= "" end
        local function seconds_of(key: string): number
            local y, mo, d = string.match(key, "^(%d+)-(%d+)-(%d+)$")
            return os.time({ year = tonumber(y) :: number, month = tonumber(mo) :: number, day = tonumber(d) :: number, hour = 12 })
        end
        local lived = g.computed(function(): { any }
            local b = birth()
            if b == "" then return {} end
            local days = activity.days()
            local today = activity.today()
            local out = {}
            local t = seconds_of(b)
            local last = seconds_of(today)
            while t <= last + 3600 do
                local key = activity.date_key(t)
                table.insert(out, { key = key, minutes = days[key] or 0, known = days[key] ~= nil })
                t += 86400
            end
            return out
        end)
        local function age(): string
            local b = birth()
            if b == "" then return "" end
            local by, bm, bd = string.match(b, "^(%d+)-(%d+)-(%d+)$")
            local now = os.date("*t") :: any
            local years = now.year - tonumber(by)
            local months = now.month - tonumber(bm)
            local days = now.day - tonumber(bd)
            if days < 0 then
                months -= 1
                days += (os.date("*t", os.time({ year = now.year, month = now.month, day = 0, hour = 12 })) :: any).day
            end
            if months < 0 then
                years -= 1
                months += 12
            end
            local parts = {}
            if years > 0 then table.insert(parts, years .. " Y") end
            if months > 0 then table.insert(parts, months .. " MO") end
            if days > 0 or #parts == 0 then table.insert(parts, days .. " D") end
            return table.concat(parts, " ")
        end
        local function duration(minutes: number): string
            local h, mm = minutes // 60, minutes % 60
            return if h > 0 then string.format("%d H %02d M", h, mm) else mm .. " M"
        end

        local function values(): { number }
            local out = table.create(16 + 4 * MAX_BANDS, 0)
            local function put(at: number, hex: string)
                local c = colour.parse(hex)
                out[at + 1], out[at + 2], out[at + 3], out[at + 4] = c.r, c.g, c.b, c.a
            end
            put(0, theme.primary())
            put(4, theme.text())
            local days = lived.value
            local fa = f()
            out[10] = fa
            local pith = 3 * fa
            out[11] = pith
            if #days == 0 then return out end
            local outer = disc() / 2 / 1.07 - 2 * fa
            local width = (outer - pith) / #days
            local visible = 3 * fa
            -- How much of the date names a unit of bare wood: a day, a month,
            -- a year, by how thin a ring is.
            local span = if width >= visible then 10 elseif width * 30.44 >= visible then 7 else 4
            local today = activity.today()
            local bands = {}
            local unit, units = "", -1
            for i, day in days do
                local from = pith + (i - 1) * width
                local to = from + width
                local is_today = day.key == today
                local is_bare = not day.known and not is_today
                local own = string.sub(day.key, 1, span)
                if own ~= unit then
                    unit = own
                    units += 1
                end
                local last = bands[#bands]
                if is_bare and span < 10 and last and last.bare and last.unit == unit then
                    last.to = to
                else
                    if last then last.ends = last.unit ~= unit end
                    table.insert(bands, { from = from, to = to, bare = is_bare, today = is_today, minutes = day.minutes,
                        unit = unit, index = units, ends = true })
                end
            end
            -- Too many to draw one by one: the oldest are merged, as the wood
            -- near the pith is too thin to tell apart anyway.
            while #bands > MAX_BANDS do
                local a, b = bands[1], bands[2]
                a.to = b.to
                a.minutes = math.max(a.minutes, b.minutes)
                a.bare = a.bare and b.bare
                a.ends = b.ends
                table.remove(bands, 2)
            end
            out[9] = #bands
            for k, band in bands do
                local base = 16 + 4 * (k - 1)
                local fill = if band.bare then -(if band.index % 2 == 0 then 0.05 else 0.08)
                    else 0.14 + 0.5 * math.min(1, band.minutes / FULL_DAY)
                local line, w = 0, fa
                if band.today then
                    line, w = 1, 1.8 * fa
                elseif band.ends then
                    line = if band.bare then -0.16 else 0.55
                end
                out[base + 1], out[base + 2], out[base + 3], out[base + 4] = band.to, fill, line, w
            end
            return out
        end

        local function meta(text: () -> string, color: any, size: () -> number, weight: number?): any
            return g.text { text = text, color = color, font = typography.technical, size = size,
                weight = weight or typography.weight_secondary, tracking = typography.label_tracking, tabular = true }
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
                        offset_x = disc_x,
                        src = SOURCE,
                        width = disc,
                        height = disc,
                        values = values,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = figures,
                        offset_x = disc_x,
                        offset_y = function() return disc() + gap() end,
                        width = disc,
                        direction = "column",
                        align = "start",
                        gap = function() return 6 * f() end,
                        g.box {
                            width = disc,
                            direction = "row",
                            align = "center",
                            justify = "between",
                            g.text { text = machine.host, color = theme.text, font = typography.expressive,
                                size = function() return m().font_label end, max_width = function() return disc() * 0.6 end },
                            meta(age, theme.text_muted, function() return m().font_meta end),
                        },
                        g.box {
                            direction = "row",
                            align = "end",
                            gap = function() return 8 * f() end,
                            meta(function() return "TODAY ACTIVE TIME" end, theme.text, function() return m().font_meta end, typography.weight_label),
                            g.text { text = function() return duration(activity.today_minutes()) end,
                                color = function() return theme.gradient_top(theme.primary()) end,
                                color_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                                font = typography.technical, size = function() return m().font_label end,
                                weight = typography.weight_value, tabular = true },
                        },
                    },
                }
            end,
        }
    end,
}
