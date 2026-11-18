--!strict
-- The clock, opened (cells/clock/ClockExpansion.qml at 7e62c5c): the month
-- in the middle, budding out of the time it belongs to; other places on one
-- side and a timer and an alarm on the other, each budding out of the
-- month and tied to it by a thread.
--
-- Human language where it is language (the month's name, a city's name over
-- its time, in Spectral) and the machine's voice where it is counting (the
-- days, the offsets, the timer's figure, in Orbitron with tabular figures,
-- so nothing dances as it changes).
--
-- Once there is a calendar, the day's appointments bud out of the month on
-- the side away from the cell: the day chosen in the month, today until
-- another is. A calendar is added from the accounts in GNOME Online
-- Accounts, or by pasting an iCalendar address.
--
-- The keys: Left and Right turn the month and Enter brings today back;
-- while a place or a calendar is being added, typing goes to its field,
-- Enter takes the first match (or reads the address) and Escape gives up.
-- Not yet: the shell-wide keyboard travel, the lists' scroll bars.
local g = require("@genoma")
local light = require("components/light")
local clock = require("@genoma/clock")
local theme = require("core/theme")
local performance = require("core/performance")
local colour = require("core/colour")
local typography = require("core/typography")
local metrics_mod = require("core/metrics")
local time = require("services/time")
local calendar = require("services/calendar")
local field = require("components/field")
local switch = require("components/switch")
local thread = require("components/thread")
local timing = require("core/timing")

local M = {}

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December" }
local WEEKDAYS = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" }

function M.new(cell: any, twenty_four: () -> boolean)
    local function m(): { [string]: any } return cell.metrics() end
    local function f(): number return m().factor end
    local function gap(): number return m().gap end
    local function calendar_width(): number return 300 * f() end
    local function side_width(): number return 250 * f() end
    local function panel_height(): number return 320 * f() end
    local function padding(): number return 14 * f() end
    local function inner(width: () -> number): () -> number
        return function() return width() - padding() * 2 end
    end

    local function hhmm(hours: number, minutes: number): string
        if twenty_four() then return string.format("%02d:%02d", hours, minutes) end
        return string.format("%d:%02d", if hours % 12 == 0 then 12 else hours % 12, minutes)
    end

    -- The machine's voice: Orbitron, tabular, tracked.
    local function technical(size: () -> number, weight: number?, t: { [any]: any }): any
        t.font = typography.technical
        t.size = size
        t.weight = weight or typography.weight_label
        t.tabular = true
        t.tracking = typography.label_tracking
        return g.text(t)
    end
    local function meta(): number return m().font_meta end

    -- ---- Pieces -------------------------------------------------------------

    -- A pill to press: lit, the primary's tint and rim.
    local function pill(label: () -> string, lit: () -> boolean, on_click: () -> ()): any
        local hovered = g.signal(false)
        return g.capsule {
            role = "button",
            height = function() return 24 * f() end,
            padding_x = function() return 11 * f() end,
            radius = function() return metrics_mod.radius_for(24 * f(), m()) end,
            align = "center",
            justify = "center",
            fill = function() return if lit() then colour.alpha(theme.primary(), 0.16) else "#00000000" end,
            rim_top = function()
                return if lit() then theme.primary() elseif hovered.value then theme.text() else theme.line()
            end,
            rim_bottom = function()
                return if lit() then theme.primary() elseif hovered.value then theme.text() else theme.line()
            end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = on_click,
            technical(meta, nil, {
                text = label,
                color = function() return if lit() then theme.text() else theme.text_muted() end,
            }),
        }
    end

    -- The dashed chip that adds something, and is the way back out of the
    -- field it opened while that is open.
    local function add_chip(label: () -> string, lit: () -> boolean, on_click: () -> (), morph: string?): any
        return g.capsule {
            morph = morph,
            id = if morph then morph .. " chip" else nil,
            role = "button",
            height = function() return 26 * f() end,
            padding_x = function() return 14 * f() end,
            radius = function() return metrics_mod.radius_for(26 * f(), m()) end,
            align = "center",
            justify = "center",
            rim_top = function() return if lit() then theme.primary() else colour.alpha(theme.line(), 0.7) end,
            rim_bottom = function() return if lit() then theme.primary() else colour.alpha(theme.line(), 0.7) end,
            dash = 3,
            dash_gap = 3,
            on_click = on_click,
            technical(meta, nil, {
                text = label,
                color = function() return if lit() then theme.primary() else theme.text() end,
            }),
        }
    end

    -- The way out of a field a chip opened into: a cross at its end.
    local function give_up(on_click: () -> ()): any
        local hovered = g.signal(false)
        return g.box {
            role = "button",
            name = "Cancel",
            width = function() return 16 * f() end,
            height = function() return 16 * f() end,
            justify = "center",
            align = "center",
            opacity = function() return if hovered.value then 1 else theme.tool_rest end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = on_click,
            g.icon {
                width = function() return 9 * f() end,
                height = function() return 9 * f() end,
                icon = "close",
                color = theme.text,
            },
        }
    end

    local function chevron(left: boolean, on_click: () -> ()): any
        local hovered = g.signal(false)
        return g.box {
            role = "button",
            name = if left then "Previous month" else "Next month",
            width = function() return 24 * f() end,
            height = function() return 24 * f() end,
            justify = "center",
            align = "center",
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = on_click,
            g.icon {
                width = function() return 11 * f() end,
                height = function() return 11 * f() end,
                icon = "chevron-right",
                -- Pointing back: the same drawing, turned over.
                rotate_y = if left then 180 else 0,
                color = function() return if hovered.value then theme.primary() else theme.text() end,
            },
        }
    end

    -- ---- The day's appointments: their state, which the month reads ----------------

    local adding_calendar = g.signal(false)
    local chosen_day = g.signal(calendar.today_start())
    local function agenda_shown(): boolean return calendar.active() or adding_calendar.value end

    -- ---- The month ------------------------------------------------------------

    local view_year = g.signal(0)
    local view_month = g.signal(0)
    local function today()
        local t = os.date("*t") :: any
        g.batch(function()
            view_year.value = t.year
            view_month.value = t.month
            chosen_day.value = calendar.today_start()
        end)
    end
    today()
    local function turn(step: number)
        local y, mo = g.untracked(function() return view_year.value end), g.untracked(function() return view_month.value end) + step
        while mo < 1 do mo += 12; y -= 1 end
        while mo > 12 do mo -= 12; y += 1 end
        g.batch(function()
            view_year.value = y
            view_month.value = mo
        end)
    end

    -- The days something is on, by their midnight: every day an event
    -- touches, so a trip of three days marks all three.
    local busy = g.computed(function(): { [number]: boolean }
        local out = {}
        for _, e in calendar.events() do
            local last = if e["end"] > e.start then e["end"] - 1 else e.start
            local day = calendar.day_start(e.start)
            local n = 0
            while day <= last and n < 62 do
                out[day] = true
                day = calendar.day_start(day, 1)
                n += 1
            end
        end
        return out
    end)

    -- Six weeks from the Monday on or before the first: every month fits,
    -- and the grid keeps its height from one month to the next.
    local days = g.computed(function(): { any }
        local today_ms = calendar.today_start()
        local first = calendar.midnight(view_year.value, view_month.value, 1)
        local wday = (os.date("*t", first // 1000) :: any).wday -- Sunday is 1
        local lead = (wday + 5) % 7
        local start = calendar.day_start(first, -lead)
        local out = {}
        for i = 0, 41 do
            local day = calendar.day_start(start, i)
            local t = os.date("*t", day // 1000) :: any
            table.insert(out, {
                day = t.day,
                start = day,
                in_month = t.month == view_month.value,
                today = day == today_ms,
                busy = busy.value[day] == true,
            })
        end
        return out
    end)

    local function cell_width(): number return inner(calendar_width)() / 7 end

    local function day_cell(i: number): any
        local function d(): any return days.value[i] end
        -- The day whose appointments hang below.
        local function chosen(): boolean
            return agenda_shown() and not adding_calendar.value and d().start == chosen_day.value
        end
        return g.box {
            width = cell_width,
            height = function() return 32 * f() end,
            justify = "center",
            align = "center",
            on_click = function()
                if g.untracked(agenda_shown) and not g.untracked(function() return adding_calendar.value end) then
                    chosen_day.value = g.untracked(d).start
                end
            end,
            -- When it is not today: the rim alone, in the primary.
            g.capsule {
                overlay = true,
                present = function() return chosen() and not d().today end,
                width = function() return 26 * f() end,
                height = function() return 26 * f() end,
                rim_top = theme.primary,
                rim_bottom = theme.primary,
            },
            -- Today is lit as a chosen control is: the disc with the light,
            -- the figure dark on it.
            g.capsule {
                overlay = true,
                present = function() return d().today end,
                width = function() return 26 * f() end,
                height = function() return 26 * f() end,
                fill = function() return theme.gradient_top(theme.primary()) end,
                fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            },
            technical(function() return m().font_secondary end, nil, {
                weight = function() return if d().today then typography.weight_title else typography.weight_label end,
                text = function() return tostring(d().day) end,
                color = function()
                    local x = d()
                    return if x.today then theme.background() elseif x.in_month then theme.text() else theme.text_faint()
                end,
            }),
            -- Something is on: a point under the figure. Form, not a count.
            g.capsule {
                overlay = true,
                attach = "corner",
                present = function() return d().busy end,
                width = function() return 4 * f() end,
                height = function() return 4 * f() end,
                offset_x = function() return (cell_width() - 4 * f()) / 2 end,
                offset_y = function() return 32 * f() - 8 * f() end,
                fill = function()
                    local x = d()
                    return if x.today then theme.background() elseif x.in_month then theme.text_muted() else theme.text_faint()
                end,
            },
        }
    end

    local function month(): any
        local header = {}
        for _, name in WEEKDAYS do
            table.insert(header, g.box {
                width = cell_width,
                height = function() return 22 * f() end,
                justify = "center",
                align = "center",
                technical(meta, nil, { text = name, color = theme.text_faint }),
            })
        end
        local rows = {}
        for r = 0, 5 do
            local row: { [any]: any } = { direction = "row" }
            for c = 1, 7 do table.insert(row, day_cell(r * 7 + c)) end
            table.insert(rows, g.box(row))
        end
        local column: { [any]: any } = {
            direction = "column",
            gap = function() return 8 * f() end,
            width = inner(calendar_width),
            -- The month and the year, with the way to the next and back; the
            -- name itself brings today's month back.
            g.box {
                width = inner(calendar_width),
                height = function() return 30 * f() end,
                direction = "row",
                align = "center",
                justify = "between",
                chevron(true, function() turn(-1) end),
                g.text {
                    role = "button",
                    text = function() return MONTHS[view_month.value] .. " " .. view_year.value end,
                    font = typography.expressive,
                    size = function() return m().font_title end,
                    weight = typography.weight_title,
                    color = theme.text,
                    on_click = today,
                },
                chevron(false, function() turn(1) end),
            },
        }
        local weekdays: { [any]: any } = { direction = "row" }
        for _, h in header do table.insert(weekdays, h) end
        local grid_column: { [any]: any } = { direction = "column", g.box(weekdays) }
        for _, r in rows do table.insert(grid_column, r) end
        table.insert(column, g.box(grid_column))
        -- With no calendar yet, the way to one: it opens the agenda below,
        -- asking for an address.
        table.insert(column, g.box {
            width = inner(calendar_width),
            justify = "center",
            present = function() return not agenda_shown() end,
            add_chip(function() return "+ CALENDAR" end, function() return false end,
                function() adding_calendar.value = true end),
        })
        return g.box(column)
    end

    -- ---- Other places -------------------------------------------------------------

    local adding = g.signal(false)
    local place_text = g.signal("")
    local place_node, place_field = field.new {
        text = place_text,
        width = function() return inner(side_width)() - 28 * f() - 22 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        placeholder = "A city or a zone",
        taking = function() return adding.value end,
    }
    -- The places and the field take turns, the content never under a
    -- shape that moves (Akusen, 2026-11-16). Opening, the places fade out
    -- first, then the chip opens into the field over the room they left.
    -- Closing, the field closes into its chip while the places are back
    -- but unseen, and once it has they fade in.
    local listing = g.signal(true)
    local leaving = g.signal(false)
    local function open_place()
        if g.untracked(function() return leaving.value or adding.value end) then return end
        leaving.value = true
        g.after(timing.seconds.content_fade, function()
            if g.untracked(function() return leaving.value and not adding.value end) then adding.value = true end
        end)
    end
    g.watch(function() return adding.value end, function(on: boolean)
        if on then
            listing.value = false
            time.ask_known()
            place_field.set("")
        else
            leaving.value = true
            listing.value = true
            g.after(timing.seconds.open, function()
                if not g.untracked(function() return adding.value end) then leaving.value = false end
            end)
        end
    end)

    local matches = g.computed(function(): { string }
        local wanted = string.gsub(string.lower(string.match(place_text.value, "^%s*(.-)%s*$") or ""), " ", "_")
        if #wanted < 2 then return {} end
        local out = {}
        local zones = time.zones()
        for _, zone in time.known() do
            if string.find(string.lower(zone), wanted, 1, true) and not table.find(zones, zone) then
                table.insert(out, zone)
                if #out == 6 then break end
            end
        end
        return out
    end)

    local function add_first()
        local found = g.untracked(function() return matches.value end)
        if #found > 0 then
            time.add_zone(found[1])
            adding.value = false
        end
    end

    -- A day apart says so: the time alone would be read as today's.
    local function day_shift(here: any): string
        if not here then return "" end
        local local_t = os.date("*t") :: any
        local a = local_t.year * 10000 + local_t.month * 100 + local_t.day
        local b = here.year * 10000 + here.month * 100 + here.day
        return if b > a then "TOMORROW" elseif b < a then "YESTERDAY" else ""
    end

    local function place_row(item: () -> string): any
        local hovered = g.signal(false)
        local function zone(): string return item() end
        local function here(): any
            local _ = clock.minute
            return time.in_zone(zone())
        end
        return g.capsule {
            width = inner(side_width),
            height = function() return 52 * f() end,
            radius = 0,
            direction = "row",
            align = "center",
            justify = "between",
            padding_x = function() return 4 * f() end,
            on_hover = function(on: boolean) hovered.value = on end,
            g.box {
                direction = "column",
                align = "start",
                g.text {
                    text = function() return time.city_of(zone()) end,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    weight = typography.weight_title,
                    color = theme.text,
                },
                g.text {
                    text = function()
                        local h = here()
                        return if h then hhmm(h.hour, h.min) else "…"
                    end,
                    font = typography.expressive,
                    size = function() return m().font_title + 3 * f() end,
                    weight = typography.weight_value,
                    tabular = true,
                    color = theme.text,
                },
            },
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 6 * f() end,
                g.box {
                    direction = "column",
                    align = "end",
                    technical(meta, nil, { text = function() return time.utc_label(zone()) end, color = theme.text_muted }),
                    technical(meta, nil, {
                        present = function() return day_shift(here()) ~= "" end,
                        text = function() return day_shift(here()) end,
                        color = theme.text_faint,
                    }),
                },
                -- The cross shows under the pointer.
                g.box {
                    role = "button",
                    name = "Remove",
                    width = function() return 16 * f() end,
                    height = function() return 16 * f() end,
                    justify = "center",
                    align = "center",
                    opacity = function() return if hovered.value then 1 else theme.tool_rest end,
                    on_click = function() time.remove_zone(g.untracked(zone)) end,
                    g.icon {
                        width = function() return 9 * f() end,
                        height = function() return 9 * f() end,
                        icon = "close",
                        color = theme.text,
                    },
                },
            },
        }
    end

    local function match_row(item: () -> string): any
        local hovered = g.signal(false)
        return g.capsule {
            role = "button",
            width = inner(side_width),
            height = function() return 30 * f() end,
            radius = 0,
            direction = "row",
            align = "center",
            justify = "between",
            padding_x = function() return 8 * f() end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function()
                time.add_zone(g.untracked(item))
                adding.value = false
            end,
            g.text {
                text = function() return time.city_of(item()) end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                color = function() return if hovered.value then theme.primary() else theme.text() end,
            },
            technical(meta, nil, {
                text = function() return string.match(item(), "^([^/]+)") or "" end,
                color = theme.text_faint,
            }),
        }
    end

    local function places(): any
        return g.box {
            width = inner(side_width),
            height = inner(panel_height),
            direction = "column",
            justify = "between",
            g.box {
                direction = "column",
                gap = function() return 4 * f() end,
                g.each {
                    present = function() return listing.value end,
                    opacity = function() return if leaving.value then 0 else 1 end,
                    transition = { opacity = "content_fade" },
                    direction = "column",
                    gap = function() return 4 * f() end,
                    items = time.zones,
                    key = function(z: string) return z end,
                    row = place_row,
                },
                g.box {
                    present = function() return listing.value and #time.zones() == 0 end,
                    opacity = function() return if leaving.value then 0 else 1 end,
                    transition = { opacity = "content_fade" },
                    width = inner(side_width),
                    height = function() return 52 * f() end,
                    justify = "center",
                    align = "center",
                    g.text {
                        text = "No other places",
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        color = theme.text_faint,
                    },
                },
                -- Adding one: a field, and what the system knows that matches.
                -- The chip that asked for it opens into it (one shape, Genoma's
                -- `morph`), and it closes back into the chip.
                g.capsule {
                    morph = "clock place",
                    present = function() return adding.value end,
                    width = inner(side_width),
                    height = function() return 34 * f() end,
                    radius = function() return metrics_mod.radius_for(34 * f(), m()) end,
                    stroke = 1.5,
                    rim_top = theme.primary,
                    rim_bottom = theme.primary,
                    padding_x = function() return 14 * f() end,
                    align = "center",
                    justify = "between",
                    direction = "row",
                    place_node,
                    give_up(function() adding.value = false end),
                },
                g.each {
                    present = function() return adding.value end,
                    direction = "column",
                    items = function() return matches.value end,
                    key = function(z: string) return z end,
                    row = match_row,
                },
            },
            g.box {
                width = inner(side_width),
                justify = "center",
                present = function() return not adding.value and #time.zones() < 5 end,
                add_chip(function() return "+ PLACE" end, function() return false end,
                    open_place, "clock place"),
            },
        }
    end

    -- ---- The timer and the alarm --------------------------------------------------

    local function clock_figure(seconds: number): string
        local h = seconds // 3600
        local mm = (seconds % 3600) // 60
        local ss = seconds % 60
        return if h > 0 then string.format("%d:%02d:%02d", h, mm, ss) else string.format("%02d:%02d", mm, ss)
    end

    local function value_size(): number return m().font_value end

    local function timers(): any
        local presets = {}
        for _, minutes in { 5, 10, 25, 60 } do
            local n = minutes
            table.insert(presets, pill(function() return if n < 60 then tostring(n) else "1 H" end,
                function() return not time.running() and time.length() == n * 60 end,
                function() time.set_length(n * 60) end))
        end
        local preset_row: { [any]: any } = { direction = "row", gap = function() return 6 * f() end }
        for _, p in presets do table.insert(preset_row, p) end
        local function alarm(): any return time.alarm() end
        -- The wheel: up is more.
        local function step_of(dy: number): number return if dy < 0 then 1 else -1 end
        return g.box {
            width = inner(side_width),
            direction = "column",
            align = "center",
            gap = function() return 10 * f() end,
            g.box {
                width = inner(side_width),
                technical(meta, nil, { text = "TIMER", color = theme.text_faint }),
            },
            -- The figure is what the wheel turns while the timer is still: a
            -- minute a notch.
            technical(value_size, typography.weight_value, {
                text = function() return clock_figure(time.left()) end,
                color = function() return if time.running() then theme.text() else theme.text_muted() end,
                on_wheel = function(_, dy: number)
                    if not g.untracked(time.running) and dy ~= 0 then
                        time.set_length(g.untracked(time.length) + step_of(dy) * 60)
                    end
                end,
            }),
            -- What is left of it: a live value, so it may move.
            g.capsule {
                width = inner(side_width),
                height = function() return 14 * f() end,
                radius = 0,
                justify = "start",
                align = "center",
                opacity = function() return if time.running() then 1 else 0.45 end,
                -- Stopped as one picture: the track must not show through its head.
                isolate = true,
                transition = { opacity = "transition" },
                g.capsule {
                    overlay = true,
                    width = inner(side_width),
                    height = function() return 3 * f() end,
                    fill = function() return colour.alpha(theme.line(), 0.55) end,
                },
                g.capsule {
                    overlay = true,
                    attach = "corner",
                    offset_y = function() return (14 * f() - 3 * f()) / 2 end,
                    width = function() return inner(side_width)() * time.fraction_left() end,
                    height = function() return 3 * f() end,
                    fill = function() return theme.gradient_top(theme.primary()) end,
                    fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                },
                g.capsule {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return inner(side_width)() * time.fraction_left() - 7 * f() end,
                    width = function() return 14 * f() end,
                    height = function() return 14 * f() end,
                    fill = function() return theme.gradient_top(theme.primary()) end,
                    fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                },
            },
            g.box(preset_row),
            g.box {
                direction = "row",
                gap = function() return 8 * f() end,
                pill(function()
                    return if time.running() then "PAUSE" elseif time.paused() then "RESUME" else "START"
                end, function() return true end, function()
                    if g.untracked(time.running) then time.pause() else time.start() end
                end),
                pill(function() return "RESET" end, function() return false end, time.reset),
            },
            g.box { height = function() return 6 * f() end },
            g.box {
                width = inner(side_width),
                height = function() return 22 * f() end,
                direction = "row",
                align = "center",
                justify = "between",
                technical(meta, nil, { text = "ALARM", color = theme.text_faint }),
                switch.new {
                    factor = f,
                    on = function() return alarm().on == true end,
                    on_toggle = function(on: boolean)
                        local a = g.untracked(alarm)
                        time.set_alarm(a.hour, a.minute, on)
                    end,
                },
            },
            -- The hour and the minute, each turned by the wheel over it.
            g.box {
                direction = "row",
                technical(value_size, typography.weight_value, {
                    text = function() return string.format("%02d", alarm().hour) end,
                    color = function() return if alarm().on then theme.text() else theme.text_muted() end,
                    on_wheel = function(_, dy: number)
                        local a = g.untracked(alarm)
                        if dy ~= 0 then time.set_alarm(a.hour + step_of(dy), a.minute, a.on) end
                    end,
                }),
                technical(value_size, typography.weight_value, { text = ":", color = theme.text_muted }),
                technical(value_size, typography.weight_value, {
                    text = function() return string.format("%02d", alarm().minute) end,
                    color = function() return if alarm().on then theme.text() else theme.text_muted() end,
                    on_wheel = function(_, dy: number)
                        local a = g.untracked(alarm)
                        if dy ~= 0 then time.set_alarm(a.hour, a.minute + step_of(dy) * 5, a.on) end
                    end,
                }),
            },
        }
    end

    -- ---- The day's appointments ------------------------------------------------------

    local function agenda_height(): number return 236 * f() end
    local function event_row(): number return 34 * f() end
    local calendar_text = g.signal("")
    local calendar_node, calendar_field = field.new {
        text = calendar_text,
        width = function() return inner(calendar_width)() - 28 * f() - 22 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        placeholder = "Or an iCal address",
        taking = function() return adding_calendar.value and not calendar.checking() end,
    }
    -- The day and the new calendar take turns as the places and their field
    -- do: the day fades, the chip opens into the address field, and what
    -- the accounts offer fades in round it once it is there. Closing, that
    -- fades first, the field closes into its chip, and the day fades in.
    local day_listing = g.signal(true)
    local day_leaving = g.signal(false)
    local offer_shown = g.signal(false)
    local function open_calendar()
        if g.untracked(function() return day_leaving.value or adding_calendar.value end) then return end
        day_leaving.value = true
        g.after(timing.seconds.content_fade, function()
            if g.untracked(function() return day_leaving.value and not adding_calendar.value end) then
                adding_calendar.value = true
            end
        end)
    end
    local function close_calendar()
        if not g.untracked(function() return adding_calendar.value end) then return end
        offer_shown.value = false
        g.after(timing.seconds.content_fade, function() adding_calendar.value = false end)
    end
    g.watch(function() return adding_calendar.value end, function(on: boolean)
        if on then
            adding.value = false
            calendar_field.set("")
            calendar.discover()
            day_listing.value = false
            offer_shown.value = false
            g.after(timing.seconds.open, function()
                if g.untracked(function() return adding_calendar.value end) then offer_shown.value = true end
            end)
        else
            offer_shown.value = false
            day_leaving.value = true
            day_listing.value = true
            g.after(timing.seconds.open, function()
                if not g.untracked(function() return adding_calendar.value end) then day_leaving.value = false end
            end)
        end
    end)
    g.watch(function() return adding.value end, function(on: boolean)
        if on then adding_calendar.value = false end
    end)
    calendar.on_added(function()
        close_calendar()
        today()
    end)

    local WEEKDAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
    local function day_title(start: number): string
        local difference = math.round((start - calendar.today_start()) / 86400000)
        if difference == 0 then return "Today" end
        if difference == 1 then return "Tomorrow" end
        if difference == -1 then return "Yesterday" end
        local t = os.date("*t", start // 1000) :: any
        return WEEKDAY_NAMES[t.wday] .. " " .. t.day .. " " .. MONTHS[t.month]
    end

    local chosen_events = g.computed(function(): { any }
        return calendar.between(chosen_day.value, calendar.day_start(chosen_day.value, 1))
    end)

    local agenda_scroll = g.signal(0)
    g.watch(function() return chosen_day.value end, function() agenda_scroll.value = 0 end)

    -- The time in the machine's voice, the title in the human one. What is
    -- over is faint; what is on now carries the primary, the only state an
    -- appointment has.
    local function event_line(item: () -> any): any
        local function e(): any return item() end
        local function over(): boolean return e()["end"] <= calendar.now() end
        local function on(): boolean
            local x = e()
            return not x.allDay and x.start <= calendar.now() and calendar.now() < x["end"]
        end
        return g.box {
            width = inner(calendar_width),
            height = event_row,
            direction = "row",
            align = "center",
            g.box {
                width = function() return 70 * f() end,
                technical(meta, nil, {
                    text = function()
                        local x = e()
                        if x.allDay then return "ALL DAY" end
                        if x.start < chosen_day.value then return "…" end
                        local t = os.date("*t", x.start // 1000) :: any
                        return hhmm(t.hour, t.min)
                    end,
                    color = function()
                        return if on() then theme.primary() elseif over() then theme.text_faint() else theme.text_muted()
                    end,
                }),
            },
            g.text {
                text = function() return e().title or "" end,
                max_width = function() return inner(calendar_width)() - 70 * f() end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                color = function() return if over() then theme.text_faint() else theme.text() end,
            },
        }
    end

    -- A calendar read: its name, and a cross. The cross asks first, and the
    -- second press answers; leaving it withdraws the question.
    local function source_chip(item: () -> any, index: () -> number): any
        local asking = g.signal(false)
        local hovered = g.signal(false)
        local function trouble(): boolean return calendar.trouble_of(index()) ~= "" end
        local function alerting(): boolean return asking.value or trouble() end
        return g.capsule {
            role = "button",
            height = function() return 26 * f() end,
            padding_left = function() return 11 * f() end,
            padding_right = function() return 10 * f() end,
            gap = function() return 8 * f() end,
            radius = function() return metrics_mod.radius_for(26 * f(), m()) end,
            direction = "row",
            align = "center",
            rim_top = function() return if alerting() then theme.alert() elseif hovered.value then theme.text() else theme.line() end,
            rim_bottom = function() return if alerting() then theme.alert() elseif hovered.value then theme.text() else theme.line() end,
            on_hover = function(on: boolean)
                hovered.value = on
                if not on then asking.value = false end
            end,
            on_click = function()
                if g.untracked(function() return asking.value end) then calendar.forget(g.untracked(index)) else asking.value = true end
            end,
            technical(meta, nil, {
                max_width = function() return 110 * f() end,
                text = function() return if asking.value then "FORGET?" else string.upper(item().name or "Calendar") end,
                color = function() return if alerting() then theme.alert() else theme.text() end,
            }),
            g.icon {
                width = function() return 9 * f() end,
                height = function() return 9 * f() end,
                icon = "close",
                color = function() return if asking.value then theme.alert() else theme.text() end,
            },
        }
    end

    local function offered_row(account: any, item: () -> any): any
        local hovered = g.signal(false)
        local function taken(): boolean return calendar.holds(account.goa, item().href) end
        return g.capsule {
            role = "button",
            width = inner(calendar_width),
            height = function() return 30 * f() end,
            radius = 0,
            direction = "row",
            align = "center",
            justify = "between",
            padding_x = function() return 8 * f() end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function()
                if not g.untracked(taken) then calendar.add_from_account(account.goa, g.untracked(item)) end
            end,
            g.text {
                text = function() return item().name or "" end,
                max_width = function() return inner(calendar_width)() - 80 * f() end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                color = function()
                    return if taken() then theme.text_muted() elseif hovered.value then theme.primary() else theme.text()
                end,
            },
            technical(meta, nil, {
                text = function() return if taken() then "ADDED" else "ADD" end,
                color = function()
                    return if taken() then theme.text_faint() elseif hovered.value then theme.primary() else theme.text()
                end,
            }),
        }
    end

    local function account_block(item: () -> any): any
        local function a(): any return item() end
        return g.box {
            direction = "column",
            align = "start",
            width = inner(calendar_width),
            g.box {
                height = function() return 22 * f() end,
                align = "center",
                g.text {
                    text = function() return (a().provider or "") .. " · " .. (a().identity or "") end,
                    max_width = inner(calendar_width),
                    font = typography.expressive,
                    size = meta,
                    color = theme.text_faint,
                },
            },
            g.text {
                present = function() return (a().problem or "") ~= "" end,
                text = function() return a().problem or "" end,
                max_width = inner(calendar_width),
                wrap = true,
                font = typography.expressive,
                size = meta,
                color = theme.alert,
            },
            g.each {
                direction = "column",
                items = function() return a().calendars or {} end,
                key = function(c: any) return c.href end,
                row = function(c: () -> any) return offered_row(g.untracked(a), c) end,
            },
        }
    end

    local function agenda(): any
        local function list_height(): number
            return inner(function() return agenda_height() end)() - 26 * f() - 4 * f() - 26 * f() - 8 * f()
        end
        return g.box {
            width = inner(calendar_width),
            height = function() return agenda_height() - padding() * 2 end,
            direction = "column",
            justify = "between",
            g.box {
                direction = "column",
                gap = function() return 4 * f() end,
                g.box {
                    width = inner(calendar_width),
                    height = function() return 26 * f() end,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    g.text {
                        text = function() return if adding_calendar.value then "A new calendar" else day_title(chosen_day.value) end,
                        max_width = function() return inner(calendar_width)() - 100 * f() end,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        weight = typography.weight_title,
                        color = theme.text,
                    },
                    g.box {
                        present = function() return not adding_calendar.value end,
                        add_chip(function() return "+ CALENDAR" end, function() return false end,
                            open_calendar, "clock calendar"),
                    },
                },
                -- The day.
                g.capsule {
                    present = function() return day_listing.value end,
                    opacity = function() return if day_leaving.value then 0 else 1 end,
                    transition = { opacity = "content_fade", scroll_y = "reflow" },
                    width = inner(calendar_width),
                    height = list_height,
                    radius = 0,
                    clip = true,
                    direction = "column",
                    justify = "start",
                    scroll_y = function() return agenda_scroll.value end,
                    -- Genoma moves it: the wheel, a touchpad, a finger.
                    scroll = "y",
                    on_scroll = function(_, y: number) agenda_scroll.value = y end,
                    g.each {
                        direction = "column",
                        items = function() return chosen_events.value end,
                        key = function(e: any) return tostring(e.uid) .. ":" .. tostring(e.start) end,
                        row = event_line,
                    },
                    -- A calendar that could not be read says so, under what
                    -- was read from the others.
                    g.text {
                        present = function() return calendar.problem() ~= "" end,
                        text = calendar.problem,
                        max_width = inner(calendar_width),
                        wrap = true,
                        font = typography.expressive,
                        size = meta,
                        color = theme.alert,
                    },
                    g.box {
                        present = function() return #chosen_events.value == 0 and calendar.problem() == "" end,
                        width = inner(calendar_width),
                        height = list_height,
                        justify = "center",
                        align = "center",
                        g.text {
                            text = function()
                                return if calendar.read_at() > 0 then "Nothing on the calendar" else "Reading the calendar…"
                            end,
                            font = typography.expressive,
                            size = function() return m().font_secondary end,
                            color = theme.text_faint,
                        },
                    },
                },
                -- A new one: first the calendars of the accounts in Online
                -- Accounts, each switched on with a touch; under the rule, an
                -- address pasted and Enter, read before it is taken.
                g.capsule {
                    present = function() return adding_calendar.value end,
                    width = inner(calendar_width),
                    height = function() return list_height() + 26 * f() + 8 * f() end,
                    radius = 0,
                    clip = true,
                    direction = "column",
                    justify = "start",
                    gap = function() return 6 * f() end,
                    g.text {
                        opacity = function() return if offer_shown.value then 1 else 0 end,
                        transition = { opacity = "content_fade" },
                        present = function() return #calendar.accounts() == 0 end,
                        text = function()
                            return if calendar.discovering() then "Looking in Online Accounts…"
                                else "The calendars of the accounts in Online Accounts appear here."
                        end,
                        max_width = inner(calendar_width),
                        wrap = true,
                        font = typography.expressive,
                        size = meta,
                        color = theme.text_faint,
                    },
                    g.each {
                        opacity = function() return if offer_shown.value then 1 else 0 end,
                        transition = { opacity = "content_fade" },
                        direction = "column",
                        items = calendar.accounts,
                        key = function(a: any) return a.goa end,
                        row = account_block,
                    },
                    g.capsule {
                        opacity = function() return if offer_shown.value then 1 else 0 end,
                        transition = { opacity = "content_fade" },
                        width = inner(calendar_width),
                        height = 1,
                        crisp = true,
                        rim_top = function() return colour.alpha(theme.line(), 0.7) end,
                        rim_bottom = function() return colour.alpha(theme.line(), 0.7) end,
                        dash = 3,
                        dash_gap = 3,
                    },
                    g.capsule {
                        width = inner(calendar_width),
                        height = function() return 34 * f() end,
                        radius = function() return metrics_mod.radius_for(34 * f(), m()) end,
                        stroke = 1.5,
                        rim_top = function()
                            return if calendar.add_problem() ~= "" then theme.alert() else theme.primary()
                        end,
                        rim_bottom = function()
                            return if calendar.add_problem() ~= "" then theme.alert() else theme.primary()
                        end,
                        padding_x = function() return 14 * f() end,
                        align = "center",
                        justify = "between",
                        direction = "row",
                        -- The chip that asked for it opens into it.
                        morph = "clock calendar",
                        calendar_node,
                        give_up(close_calendar),
                    },
                    g.text {
                        present = function() return calendar.checking() or calendar.add_problem() ~= "" end,
                        text = function() return if calendar.checking() then "Reading it…" else calendar.add_problem() end,
                        max_width = inner(calendar_width),
                        wrap = true,
                        font = typography.expressive,
                        size = meta,
                        color = function() return if calendar.checking() then theme.text_muted() else theme.alert() end,
                    },
                },
            },
            -- The calendars read, cut at the panel's edge when they run out
            -- of room.
            g.capsule {
                present = function() return day_listing.value end,
                opacity = function() return if day_leaving.value then 0 else 1 end,
                transition = { opacity = "content_fade" },
                width = inner(calendar_width),
                height = function() return 26 * f() end,
                radius = 0,
                clip = true,
                justify = "start",
                g.each {
                    direction = "row",
                    gap = function() return 6 * f() end,
                    items = calendar.sources,
                    key = function(s: any) return s.id or s.href or s.url or s.name end,
                    row = source_chip,
                },
            },
        }
    end

    -- ---- The side panels, budding out of the month ----------------------------------

    -- Whether the side panel on that side of the month stays on the
    -- screen. A clock in a corner opens its month against the screen's edge,
    -- and the side that would leave it goes to the other side instead, past
    -- its sibling and budding out of it: the month stays where it grew from.
    local function fits(left: boolean): boolean
        if not cell.panel_left then return true end
        local x = cell.panel_left()
        if left then return x - gap() - side_width() >= 0 end
        return x + calendar_width() + gap() + side_width() <= cell.output_width()
    end
    -- Beside the month, or past the other side when it does not fit there
    -- (and that one does).
    local function beside(left: boolean): boolean return fits(left) or not fits(not left) end
    local function past(left: boolean): boolean return not beside(left) end

    -- `attach` the side it hangs on; `t.present` while it is there; `t.next`
    -- for one budding out of another side rather than the month, a step
    -- later; `t.beyond` what buds out of this one in turn.
    local function side(attach: string, content: () -> any, t: { [string]: any }?): any
        local o = t or {}
        local left = attach == "left"
        local step = if o.next then "2" else "1"
        -- They came together, after the month: they go together, before it.
        local function curve(): string return if cell.open.value then "pod_" .. step else "pod_retract_4" end
        local node: { [any]: any } = {
            overlay = true,
            attach = attach,
            present = o.present,
            width = side_width,
            height = panel_height,
            radius = function() return m().radius_panel end,
            offset_x = function()
                if not cell.open.value then return 0 end
                return if left then -gap() else gap()
            end,
            growth = function() return if cell.open.value then 1 else 0 end,
            bud = function() return if cell.open.value then 0 else m().cell_height end,
            blur = performance.blurred,
            fill = function() return colour.alpha(theme.cell(), 0.72) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            padding = padding,
            justify = "start",
            align = "start",
            on_press = function() end,
            on_click = function() end,
            transition = { growth = curve, bud = curve, offset_x = curve },
            g.box {
                opacity = function() return if cell.open.value then 1 else 0 end,
                transition = { opacity = function() return if cell.open.value then "pod_content_" .. step else "content_leave" end },
                content(),
            },
        }
        if o.beyond then
            -- Its thread to the one past it, from its outer edge.
            table.insert(node, thread.new {
                vertical = false,
                overlay = true,
                attach = attach,
                present = o.beyond_present,
                length = gap,
                reversed = left,
                shown = function() return cell.open.value end,
                timing = function() return "pod_thread_2" end,
                closing = function() return "pod_thread_close_4" end,
            })
            table.insert(node, o.beyond)
        end
        return g.capsule(light.dress(node, f, function() return cell.open.value end))
    end

    -- Hung from the month on the side away from the cell, on its own thread:
    -- the month feeds it the day. There only once a calendar is set, or
    -- while the first is being added, so the field has somewhere to be.
    local function below(content: () -> any): any
        local down = cell.edge ~= "bottom"
        local function shown(): boolean return cell.open.value and agenda_shown() end
        local function curve(): string return if shown() then "pod_1" else "pod_retract_4" end
        return g.capsule(light.dress({
            overlay = true,
            attach = if down then "below-center" else "above-center",
            width = calendar_width,
            height = agenda_height,
            radius = function() return m().radius_panel end,
            offset_y = function()
                if not shown() then return 0 end
                return if down then gap() else -gap()
            end,
            growth = function() return if shown() then 1 else 0 end,
            bud = function() return if shown() then 0 else m().cell_height end,
            blur = performance.blurred,
            fill = function() return colour.alpha(theme.cell(), 0.72) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            padding = padding,
            justify = "start",
            align = "start",
            on_press = function() end,
            on_click = function() end,
            transition = { growth = curve, bud = curve, offset_y = curve },
            g.box {
                opacity = function() return if shown() then 1 else 0 end,
                transition = { opacity = function() return if shown() then "pod_content_1" else "content_leave" end },
                content(),
            },
        }, f, function() return cell.open.value end))
    end

    local spec = {}

    spec.panel = {
        width = calendar_width,
        height = panel_height,
        content = month,
        satellites = function()
            local down = cell.edge ~= "bottom"
            local function agenda_out(): boolean return cell.open.value and agenda_shown() end
            -- Each side, beside the month or past the other one.
            local function places_past(): boolean return past(true) end
            local function timers_past(): boolean return past(false) end
            return {
                side("left", places, {
                    present = function() return beside(true) end,
                    beyond = side("left", timers, { present = timers_past, next = true }),
                    beyond_present = timers_past,
                }),
                side("right", timers, {
                    present = function() return beside(false) end,
                    beyond = side("right", places, { present = places_past, next = true }),
                    beyond_present = places_past,
                }),
                below(agenda),
                -- The threads belong to the month: drawn out of its edges, in
                -- the place they keep, while the panels bud out to meet them.
                thread.new {
                    vertical = false,
                    overlay = true,
                    attach = "left",
                    present = function() return beside(true) end,
                    length = gap,
                    reversed = true,
                    shown = function() return cell.open.value end,
                    timing = function() return "pod_thread_1" end,
                    closing = function() return "pod_thread_close_4" end,
                },
                thread.new {
                    vertical = false,
                    overlay = true,
                    attach = "right",
                    present = function() return beside(false) end,
                    length = gap,
                    shown = function() return cell.open.value end,
                    timing = function() return "pod_thread_1" end,
                    closing = function() return "pod_thread_close_4" end,
                },
                thread.new {
                    vertical = true,
                    overlay = true,
                    attach = if down then "below-center" else "above-center",
                    present = agenda_shown,
                    length = gap,
                    reversed = not down,
                    shown = agenda_out,
                    timing = function() return "pod_thread_1" end,
                    closing = function() return "pod_thread_close_4" end,
                },
            }
        end,
    }

    -- Opened, it shows today's month.
    g.watch(function() return cell.open.value end, function(open: boolean)
        if open then
            today()
        else
            adding.value = false
            adding_calendar.value = false
        end
    end)

    function spec.on_key(name: string, typed: string?, mods: { [string]: boolean }): boolean
        if g.untracked(function() return adding_calendar.value end) then
            if name == "Escape" then
                close_calendar()
                return true
            end
            if name == "Return" or name == "KP_Enter" then
                calendar.add(g.untracked(function() return calendar_text.value end))
                return true
            end
            local before = g.untracked(function() return calendar_text.value end)
            local taken = calendar_field.key(name, typed, mods)
            if g.untracked(function() return calendar_text.value end) ~= before then calendar.clear_add_problem() end
            return taken
        end
        if g.untracked(function() return adding.value end) then
            if name == "Escape" then
                adding.value = false
                return true
            end
            if name == "Return" or name == "KP_Enter" then
                add_first()
                return true
            end
            return place_field.key(name, typed, mods)
        end
        if name == "Left" then turn(-1) return true end
        if name == "Right" then turn(1) return true end
        if name == "Return" or name == "KP_Enter" then today() return true end
        return false
    end

    return spec
end

return M
