--!strict
-- What is coming, on the wall (organisms/agenda/AgendaOrganism.qml at
-- 2cafc17). See docs/design/ORGANISMS.md §16.
--
-- The calendars the clock cell reads, from now on: the appointment on now
-- or the next one large in a well at the top, then the days after it, a
-- line each, as many as the panel holds. Read-only. The one thing that
-- moves is the appointment going on: a thread filling as it runs, a minute
-- at a time, in the primary. With no calendar it is blank and says where
-- one is added; with nothing ahead it says so.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local calendar = require("services/calendar")
local organisms = require("structure/organisms")

local DAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December" }

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function blank(): boolean return not calendar.active() end
        local function ahead(): { any }
            local now, out = calendar.now(), {}
            for _, e in calendar.events() do
                if e["end"] > now or (e["end"] == e.start and e.start >= now) then table.insert(out, e) end
            end
            return out
        end
        -- A timed appointment on now, or else the first thing to come;
        -- today's all-day events are the day's context, not what is next.
        local function lead(): any
            local on = calendar.ongoing()
            if #on > 0 then return on[1] end
            local now, today_end = calendar.now(), calendar.today_end()
            for _, e in ahead() do
                if (e.allDay and e.start >= today_end) or (not e.allDay and e.start > now) then return e end
            end
            return nil
        end
        local function lead_on(): boolean
            local l = lead()
            return l ~= nil and not l.allDay and l.start <= calendar.now()
        end
        local function twenty_four(): boolean return organisms.cell_option("clock", "format", "24h") == "24h" end
        local function hhmm(ms: number): string
            local d = os.date("*t", ms // 1000) :: any
            local h = if twenty_four() then string.format("%02d", d.hour) else tostring(if d.hour % 12 == 0 then 12 else d.hour % 12)
            return h .. string.format(":%02d", d.min)
        end
        local function day_name(start: number): string
            local difference = math.round((start - calendar.today_start()) / 86400000)
            if difference == 0 then return "Today" end
            if difference == 1 then return "Tomorrow" end
            local d = os.date("*t", start // 1000) :: any
            return DAYS[d.wday] .. " " .. d.day .. " " .. MONTHS[d.month]
        end
        -- How far off, in the machine's voice.
        local function until_(start: number): string
            local minutes = math.max(0, math.round((start - calendar.now()) / 60000))
            if start >= calendar.today_end() then return string.upper(day_name(calendar.day_start(start))) end
            if minutes < 60 then return "IN " .. minutes .. " MIN" end
            local hours, rest = minutes // 60, minutes % 60
            return if rest > 0 then string.format("IN %d H %02d", hours, rest) else "IN " .. hours .. " H"
        end
        local function all_day_span(e: any): string
            local days = math.round((calendar.day_start(e["end"]) - calendar.day_start(e.start)) / 86400000)
            return if days > 1 then days .. " DAYS" else "ALL DAY"
        end
        local function technical(text: () -> string, color: any, size: () -> number, weight: any): any
            return g.text { text = text, color = color, font = typography.technical, size = size,
                weight = weight or typography.weight_secondary, tracking = typography.label_tracking, tabular = true }
        end
        local function expressive(text: () -> string, color: any, size: number, weight: number?, max: (() -> number)?): any
            return g.text { text = text, color = color, font = typography.expressive,
                size = function() return math.round(size * f()) end, weight = weight, max_width = max }
        end
        local function well_height(): number return 118 * f() end
        local function day_height(): number return 26 * f() end
        local function row_height(): number return 28 * f() end
        local function list_top(): number return well_height() + 14 * f() end

        -- Day headings and rows, cut where the panel ends: a whole row or
        -- none, and never a day with no row under it.
        local lines = g.computed(function(): { any }
            if blank() then return {} end
            local room = o.height() - list_top()
            local out, used, day = {}, 0, -1
            local l = lead()
            for _, e in ahead() do
                if not (l and e.uid == l.uid and e.start == l.start) then
                    local start = math.max(calendar.day_start(e.start), calendar.today_start())
                    local heading = start ~= day
                    local needed = row_height() + (if heading then day_height() else 0)
                    if used + needed > room then break end
                    if heading then
                        table.insert(out, { kind = "day", start = start, key = "d" .. start })
                        day = start
                    end
                    table.insert(out, { kind = "event", event = e, key = "e" .. tostring(e.uid) .. e.start })
                    used += needed
                end
            end
            return out
        end)

        local function line(item: () -> any): any
            local function is_day(): boolean return item().kind == "day" end
            local function event(): any return item().event end
            return g.box {
                width = o.width,
                height = function() return if is_day() then day_height() else row_height() end,
                direction = "row",
                align = function() return if is_day() then "end" else "center" end,
                g.box {
                    present = is_day,
                    expressive(function() return if is_day() then day_name(item().start) else "" end, theme.text_muted, 13, 700),
                },
                g.box {
                    present = function() return not is_day() end,
                    width = function() return 76 * f() end,
                    technical(function()
                        local e = event()
                        if not e then return "" end
                        if e.allDay then return "ALL DAY" end
                        if e.start < calendar.today_start() then return "…" end
                        return hhmm(e.start)
                    end, function()
                        local e = event()
                        return if e and not e.allDay and e.start <= calendar.now() then theme.primary() else theme.text_muted()
                    end, function()
                        local e = event()
                        return math.round((if e and e.allDay then 11 else 13) * f())
                    end),
                },
                g.box {
                    present = function() return not is_day() end,
                    expressive(function() local e = event() return if e then e.title else "" end, theme.text, 15, nil,
                        function() return o.width() - 76 * f() end),
                },
            }
        end

        return {
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    direction = "column",
                    align = "start",
                    g.capsule {
                        width = o.width,
                        height = well_height,
                        radius = function() return 10 * f() end,
                        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                        rim_top = "#00000000",
                        rim_bottom = "#00000000",
                        align = "center",
                        justify = "center",
                        -- Blank: where a calendar comes from.
                        g.box {
                            present = function() return blank() or lead() == nil end,
                            direction = "column",
                            align = "center",
                            gap = function() return 4 * f() end,
                            expressive(function() return if blank() then "No calendar" else "Nothing coming up" end, theme.text_muted, 19, 700),
                            g.text {
                                text = function()
                                    return if blank() then "Add one from the clock: open it, then + Calendar."
                                        else "Nothing in the next " .. calendar.days() .. " days."
                                end,
                                color = theme.text_muted,
                                font = typography.expressive,
                                size = function() return math.round(14 * f()) end,
                                italic = true,
                                wrap = true,
                                text_align = "center",
                                max_width = function() return o.width() - 28 * f() end,
                            },
                        },
                        g.box {
                            present = function() return not blank() and lead() ~= nil end,
                            width = function() return o.width() - 32 * f() end,
                            height = function() return well_height() - 32 * f() end,
                            direction = "column",
                            align = "start",
                            gap = function() return 4 * f() end,
                            technical(function()
                                local l = lead()
                                if not l then return "" end
                                return if lead_on() then "NOW" else until_(l.start)
                            end, function() return if lead_on() then theme.primary() else theme.text_muted() end,
                                function() return math.round(11 * f()) end),
                            expressive(function() local l = lead() return if l then l.title else "" end, theme.text, 22, 700,
                                function() return o.width() - 32 * f() end),
                            g.box {
                                direction = "row",
                                align = "center",
                                gap = function() return 12 * f() end,
                                technical(function()
                                    local l = lead()
                                    if not l then return "" end
                                    if l.allDay then return all_day_span(l) end
                                    return hhmm(l.start) .. " – " .. hhmm(l["end"])
                                end, function() return theme.gradient_top(theme.primary()) end,
                                    function() return math.round(17 * f()) end, typography.weight_value),
                                expressive(function()
                                    local l = lead()
                                    if not l then return "" end
                                    local place = string.match(l.location or "", "^[^\n]*") or ""
                                    return if place ~= "" then place else (l.calendar or "")
                                end, theme.text_faint, 14, nil, function() return o.width() * 0.5 end),
                            },
                            g.box { grow = 1 },
                            -- While it is on, how much of it has gone, a
                            -- minute at a time.
                            g.capsule {
                                present = lead_on,
                                width = function() return o.width() - 32 * f() end,
                                height = function() return 3 * f() end,
                                fill = function() return colour.alpha(theme.line(), 0.6) end,
                                rim_top = "#00000000",
                                rim_bottom = "#00000000",
                                justify = "start",
                                g.capsule {
                                    width = function()
                                        local l = lead()
                                        if not l or not lead_on() then return 0 end
                                        local done = math.min(1, (calendar.now() - l.start) / math.max(60000, l["end"] - l.start))
                                        return (o.width() - 32 * f()) * done
                                    end,
                                    height = function() return 3 * f() end,
                                    fill = theme.primary,
                                    rim_top = "#00000000",
                                    rim_bottom = "#00000000",
                                },
                            },
                        },
                    },
                    g.box { height = function() return 14 * f() end },
                    g.each {
                        direction = "column",
                        align = "start",
                        items = function() return lines.value end,
                        key = function(l: any) return l.key end,
                        row = line,
                    },
                }
            end,
        }
    end,
}
