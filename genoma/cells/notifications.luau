--!strict
-- What something else has to say, said once and then let go
-- (cells/notifications/NotificationCell.qml and NotificationExpansion.qml
-- at 11bb81e). See docs/design/CELLS.md §10, PRD §9.10.
--
-- The only cell where hover is a state rather than a courtesy: the actions
-- live in it, so "interaction suspends disappearance" is not optional here.
-- Time does not run while the pointer is on it, and on exit it resumes where
-- it stopped.
--
-- At rest it is the icon and one line, in the expressive voice. The pointer
-- brings the body and the actions under it, without claiming the attention;
-- a press brings the history, which does. It can also be always there: with
-- nothing being said it is then the bell, and pressed it opens the history.
--
-- Which notifications it shows is `options.show`: "all" (the default, the
-- urgent one first), or "urgent" above "ordinary" in a column, which is how
-- the ordinary ones are seen going past a critical one that does not leave
-- by itself. Adding the second is one config block.
--
-- The body is drawn as plain text, its markup taken off, and cut after
-- three lines.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local dial = require("components/dial")
local choice = require("components/choice")
local switch = require("components/switch")
local scroller_mod = require("components/scroller")
local notifications = require("services/notifications")

local CLEAR = "#00000000"

local function plain(text: string?): string
    local s = string.gsub(text or "", "<[^>]*>", "")
    s = string.gsub(s, "&lt;", "<")
    s = string.gsub(s, "&gt;", ">")
    s = string.gsub(s, "&quot;", '"')
    s = string.gsub(s, "&apos;", "'")
    s = string.gsub(s, "&amp;", "&")
    return s
end

local function first_line(text: string?): string
    local s = plain(text)
    local line = string.match(s, "^[^\n]*") or ""
    return (string.gsub(line, "^%s+", ""):gsub("%s+$", ""))
end

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function icon_size(): number return 20 * f() end
        local function spacing(): number return 10 * f() end
        local function close_size(): number return 14 * f() end
        local function timer_size(): number return 16 * f() end

        local function show(): string
            local wanted = cell.option("show", "all")
            return if wanted == "urgent" or wanted == "ordinary" then wanted else "all"
        end

        -- The ordinary queue on its own is counted by the service.
        local counted = false
        g.effect(function()
            local ordinary = show() == "ordinary"
            if ordinary ~= counted then
                notifications.count_ordinary(if ordinary then 1 else -1)
                counted = ordinary
            end
        end)

        local function shout_id(): number?
            local s = show()
            if s == "urgent" then return notifications.urgent_head() end
            if s == "ordinary" then return notifications.ordinary_head() end
            return notifications.current()
        end
        local function shout(): any return notifications.get(shout_id()) end

        local function resting(): boolean
            -- The block's own word: the cell's visibility is built after
            -- this part of it.
            local rule = cell.block().visibility or {}
            return (rule.type or "always") == "always" and shout() == nil and not notifications.flooding()
        end
        -- A flood is a count of ordinary ones; the urgent cell never says it.
        local function flooding(): boolean
            return show() ~= "urgent" and notifications.flooding() and shout() == nil
        end

        -- What is drawn: the one being said, or, once it has gone and the
        -- cell is on its way out, the last one, so the text and the capsule
        -- leave together. A copy of what it said: the notification itself is
        -- gone a moment later.
        local held = g.signal(nil :: any)
        local function snapshot(n: any): any
            return {
                line = if (n.summary or "") ~= "" then n.summary
                    elseif first_line(n.body) ~= "" then first_line(n.body) else (n.app_name or ""),
                icon = notifications.icon_for(n),
                critical = notifications.is_critical(n),
            }
        end
        local function displayed(): any
            local n = shout()
            if n then return snapshot(n) end
            return if resting() then nil else held.value
        end
        g.watch(shout, function(n: any) if n then held.value = snapshot(n) end end)

        local function critical(): boolean
            local d = displayed()
            return d ~= nil and d.critical == true
        end
        local function line(): string
            if flooding() then return notifications.collapsed() .. " notifications" end
            local d = displayed()
            return if d then d.line else ""
        end

        -- The time left before it goes, drawn as the clock's second hand run
        -- backwards: only for the notification whose clock this is, and kept
        -- while the cell leaves, like the rest of what it says.
        local function live_timed(): boolean
            return not flooding() and shout() ~= nil and shout_id() == notifications.ordinary_head()
                and notifications.lifetime() > 0
        end
        local timed = g.signal(false)
        g.watch(live_timed, function(on: boolean)
            if g.untracked(shout) ~= nil or on then timed.value = on end
        end)
        g.watch(resting, function(on: boolean) if on then timed.value = false end end)
        local function timer_room(): number return if timed.value then timer_size() + spacing() else 0 end

        -- The face drains continuously while the clock runs: a frame as often
        -- as the disc moves a physical pixel or so, none while it stands.
        local tick = g.signal(0)
        local ticking: any = nil
        g.effect(function()
            if ticking then ticking:stop() end
            ticking = nil
            if timed.value and notifications.running() and cell.placed.value then
                local circumference = math.pi * timer_size() * 0.75
                local every = math.max(0.016, notifications.lifetime() / math.max(1, circumference * 2))
                ticking = g.timer { every = every, on_tick = function() tick.value += 1 end }
            end
        end)
        local function left(): number
            local _ = tick.value
            return math.min(notifications.left(), 0.9999)
        end

        local function line_font(): { [string]: any }
            if flooding() then
                return { font = typography.technical(), size = m().font_title, tracking = typography.label_tracking }
            end
            return { font = typography.expressive(), size = m().font_title, tracking = 0 }
        end
        local function line_width(): number
            local fnt = line_font()
            return g.text_width { text = line(), font = fnt.font, size = fnt.size, tracking = fnt.tracking }
        end

        local function leading(): number return if resting() then (m().cell_height - icon_size()) / 2 else 10 * f() end
        local function trailing(): number return if resting() then (m().cell_height - icon_size()) / 2 else 14 * f() end
        local function content_width(): number
            if resting() then return icon_size() end
            return icon_size() + spacing() + line_width() + spacing() + timer_room() + close_size()
        end
        local function available(): number
            return math.max(0, cell.room() - icon_size() - spacing() - spacing() - timer_room() - close_size())
        end

        -- ---- Open ------------------------------------------------------------------
        --
        -- Two things hang under this cell, and which one depends on how it
        -- was asked: the pointer brings the body and the actions, a press
        -- brings the history, and only the press claims the attention.
        local history = g.signal(false)
        local function settle()
            local want = history.value or (cell.touched() and shout() ~= nil)
            if g.untracked(function() return cell.open.value end) ~= want then cell.open.value = want end
        end
        g.watch(function()
            return tostring(history.value) .. tostring(cell.touched()) .. tostring(shout_id())
        end, function() g.untracked(settle) end)
        -- Opened by anything but the pointer (a keybind) is asking for the
        -- history: there is no body to show a hand that is not there.
        g.watch(function() return cell.open.value end, function(open: boolean)
            if not open then
                if g.untracked(function() return history.value end) then history.value = false end
            elseif not g.untracked(cell.touched) then
                history.value = true
            end
        end)
        -- Asked for, the cell is shown for as long as the history is open,
        -- whatever the queue does meanwhile.
        g.watch(function() return history.value end, function(on: boolean)
            if on then cell.visibility.set_invoked(true) end
        end)

        -- The pointer stops the only clock there is, the ordinary head's, and
        -- only from the cell showing it.
        g.effect(function()
            local id = shout_id()
            notifications.hold(cell.touched() and id ~= nil and id == notifications.ordinary_head())
        end)

        -- ---- The notification, under the pointer -------------------------------------

        local function panel_width(): number return 340 * f() end
        local function padding(): number return 14 * f() end
        local function inner(): number return panel_width() - padding() * 2 end
        local function action_height(): number return 26 * f() end
        local function body_size(): number return m().font_secondary end
        local function body_line(): number return body_size() * 19 / 13.5 end

        -- At most three actions: past that the first two, because a row of
        -- five buttons is a dialog.
        local function actions(): { any }
            local n = shout()
            local carried = if n then n.actions or {} else {}
            if #carried > 3 then return { carried[1], carried[2] } end
            return carried
        end

        -- Three lines and then an ellipsis: the rest is in the history, and a
        -- membrane is not a page.
        local function body(): string
            local n = shout()
            local text = plain(if n then n.body else "")
            text = (string.gsub(text, "%s+", " "))
            if text == "" then return "" end
            local room = inner() * 3 * 0.96
            local font, size = typography.expressive(), body_size()
            if g.text_width { text = text, font = font, size = size } <= room then return text end
            local words, out = string.split(text, " "), ""
            for _, w in words do
                local next_text = if out == "" then w else out .. " " .. w
                if g.text_width { text = next_text .. "…", font = font, size = size } > room then break end
                out = next_text
            end
            return out .. "…"
        end
        local function body_lines(): number
            local b = body()
            if b == "" then return 0 end
            local w = g.text_width { text = b, font = typography.expressive(), size = body_size() }
            return math.clamp(math.ceil(w / inner()), 1, 3)
        end
        local function notify_height(): number
            return padding() * 2 + m().font_meta * 1.4 + 4 * f() + m().font_title * 1.4
                + (if body_lines() > 0 then body_lines() * body_line() + 6 * f() else 0)
                + (if #actions() > 0 then action_height() + 10 * f() else 0)
        end

        local function notification_node(): any
            return g.box {
                width = inner,
                direction = "column",
                align = "start",
                present = function() return not history.value end,
                -- Who is speaking, in the machine's voice: a name the system
                -- knows, not a sentence somebody wrote.
                g.text {
                    text = function() local n = shout() return if n then n.app_name or "" else "" end,
                    color = theme.text_faint,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    weight = typography.weight_label,
                    tracking = typography.label_tracking,
                    max_width = inner,
                },
                g.box { width = 1, height = function() return 4 * f() end },
                g.text {
                    text = function() local n = shout() return if n then plain(n.summary) else "" end,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_title end,
                    max_width = inner,
                },
                g.box { width = 1, present = function() return body_lines() > 0 end, height = function() return 6 * f() end },
                g.text {
                    present = function() return body_lines() > 0 end,
                    text = body,
                    color = theme.text_muted,
                    font = typography.expressive,
                    size = body_size,
                    max_width = inner,
                    wrap = true,
                },
                g.box { width = 1, present = function() return #actions() > 0 end, height = function() return 10 * f() end },
                g.each {
                    present = function() return #actions() > 0 end,
                    width = inner,
                    direction = "row",
                    justify = "end",
                    gap = function() return 8 * f() end,
                    items = actions,
                    key = function(a: any) return tostring(a.key) end,
                    -- An action's label was written by the application, but
                    -- it is still a command: the technical voice.
                    row = function(a: () -> any)
                        return choice.new {
                            label = function() local x = a() return if (x.label or "") ~= "" then x.label else x.key end,
                            metrics = m,
                            on_click = function()
                                local id = g.untracked(shout_id)
                                if id then notifications.invoke(id, g.untracked(a).key) end
                            end,
                        }
                    end,
                },
            }
        end

        -- ---- The history, pressed -----------------------------------------------------

        local function row_height(): number return 38 * f() end
        local function header_height(): number return 34 * f() end
        local function well_inset(): number return 10 * f() end
        local function list_margin(): number return 8 * f() end
        local function section_height(): number return 20 * f() end
        local SHOWN_ROWS, SHOWN_SECTIONS = 7, 2

        -- One list: a section's name on the first row of each application's
        -- run, then its notifications.
        local function rows(): { any }
            local out = {}
            for _, group in notifications.grouped() do
                table.insert(out, { section = true, key = "s:" .. group.app_name, name = group.app_name })
                for _, e in group.entries do
                    table.insert(out, { section = false, key = "e:" .. tostring(e.id) .. ":" .. tostring(e.at), entry = e })
                end
            end
            return out
        end
        local function height_of(r: any): number return if r.section then section_height() else row_height() end
        local function list_height(): number
            return math.max(1, math.min(#notifications.history(), SHOWN_ROWS)) * row_height()
                + SHOWN_SECTIONS * section_height()
        end
        local function well_height(): number return list_height() + list_margin() * 2 end
        local function history_height(): number
            return padding() * 2 + header_height() + 8 * f() + well_height() + 8 * f()
        end

        -- "now", "5m": rewritten while the history is open, a minute apart.
        local now = g.signal(g.now())
        local minute: any = nil
        g.watch(function() return history.value and cell.open.value end, function(on: boolean)
            if minute then minute:stop() minute = nil end
            if on then
                now.value = g.now()
                minute = g.timer { every = 30, on_tick = function() now.value = g.now() end }
            end
        end)

        local scroll = scroller_mod.new {
            viewport = list_height,
            content = function()
                local h = 0
                for _, r in rows() do h += height_of(r) end
                return h
            end,
            step = row_height,
            factor = f,
        }

        local function technical(text: any, size: () -> number, colour_of: any): any
            return g.text {
                text = text,
                color = colour_of,
                font = typography.technical,
                size = size,
                tracking = typography.label_tracking,
            }
        end

        local function history_node(): any
            local clear_hovered = g.signal(false)
            local function list_row(item: () -> any, index: () -> number): any
                local function y(): number
                    local at = 0
                    for i, other in rows() do
                        if i >= index() then break end
                        at += height_of(other)
                    end
                    return at
                end
                local function r(): any return item() end
                return g.box {
                    overlay = true,
                    attach = "corner",
                    offset_y = y,
                    width = function() return inner() - well_inset() * 2 - list_margin() * 2 end,
                    height = function() return height_of(r()) end,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    -- Grouped by application: the name on the first of a
                    -- run, so a burst from one application reads as a block.
                    g.box {
                        present = function() return r().section end,
                        g.text {
                            text = function() return r().name or "" end,
                            color = theme.text_faint,
                            font = typography.technical,
                            size = function() return m().font_meta end,
                            weight = typography.weight_label,
                            tracking = typography.label_tracking,
                        },
                    },
                    g.box {
                        present = function() return not r().section end,
                        width = function() return inner() - well_inset() * 2 - list_margin() * 2 end,
                        direction = "row",
                        align = "center",
                        justify = "between",
                        g.text {
                            text = function()
                                local e = r().entry
                                if not e then return "" end
                                return if (e.summary or "") ~= "" then plain(e.summary) else first_line(e.body)
                            end,
                            color = theme.text,
                            font = typography.expressive,
                            size = function() return m().font_secondary end,
                            max_width = function() return inner() - well_inset() * 2 - list_margin() * 2 - 50 * f() end,
                        },
                        g.text {
                            text = function()
                                local e = r().entry
                                return if e then notifications.since(e.at, now.value) else ""
                            end,
                            color = theme.text_muted,
                            font = typography.technical,
                            size = function() return m().font_meta end,
                            tabular = true,
                        },
                    },
                }
            end
            return g.box {
                width = inner,
                direction = "column",
                align = "start",
                present = function() return history.value end,
                g.box {
                    width = inner,
                    height = header_height,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    technical("HISTORY", function() return m().font_label end, theme.text),
                    g.box {
                        direction = "row",
                        align = "center",
                        gap = function() return 8 * f() end,
                        -- Emptying the history is an action, so it wears the
                        -- shape of one.
                        g.capsule {
                            role = "button",
                            name = "Clear",
                            present = function() return #notifications.history() > 0 end,
                            height = function() return 22 * f() end,
                            padding_left = function() return 9 * f() end,
                            padding_right = function() return 14 * f() end,
                            align = "center",
                            radius = function() return metrics_mod.radius_for(22 * f(), m()) end,
                            fill = function() return if clear_hovered.value then colour.alpha(theme.text(), 0.08) else CLEAR end,
                            rim_top = function() return if clear_hovered.value then theme.text() else theme.line() end,
                            rim_bottom = function() return if clear_hovered.value then theme.text() else theme.line() end,
                            on_hover = function(on: boolean) clear_hovered.value = on end,
                            on_click = function() notifications.forget() end,
                            technical("CLEAR", function() return m().font_meta end, theme.text),
                        },
                        g.box { width = function() return 6 * f() end, height = 1 },
                        -- Do not disturb, where it is looked for, and said in
                        -- a word.
                        technical("QUIET", function() return m().font_meta end, theme.text),
                        switch.new { on = notifications.quiet, factor = f, on_toggle = notifications.set_quiet },
                    },
                },
                g.box { width = 1, height = function() return 8 * f() end },
                g.capsule {
                    width = inner,
                    height = well_height,
                    radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                    fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                    align = "center",
                    justify = "center",
                    g.text {
                        overlay = true,
                        present = function() return #notifications.history() == 0 end,
                        text = "Nothing has been said",
                        color = theme.text_muted,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        offset_x = function() return well_inset() + list_margin() end,
                        offset_y = list_margin,
                        width = function() return inner() - well_inset() * 2 - list_margin() * 2 end,
                        height = list_height,
                        clip = true,
                        scroll_y = scroll.offset,
                        transition = { scroll_y = "reflow" },
                        on_wheel = scroll.wheel,
                        g.each {
                            overlay = true,
                            attach = "corner",
                            width = function() return inner() - well_inset() * 2 - list_margin() * 2 end,
                            items = rows,
                            key = function(r: any) return r.key end,
                            row = list_row,
                        },
                        scroll.bar(function() return inner() - well_inset() * 2 - list_margin() * 2 - 7 * f() end),
                    },
                },
            }
        end

        local function panel_height(): number
            return if history.value then history_height() else notify_height()
        end

        -- ---- Contracted ------------------------------------------------------------------

        local function bell(size: () -> number, tint: () -> string): any
            return g.icon { width = size, height = size, icon = "bell", gradient_top = tint, gradient_bottom = tint }
        end
        local function badge_path(): string
            local d = displayed()
            return if flooding() or not d then "" else d.icon
        end
        local function is_svg(p: string): boolean return string.sub(p, -4) == ".svg" end

        local close_hovered = g.signal(false)
        local function contracted(): any
            return g.box {
                direction = "row",
                align = "center",
                -- At rest the bell is centred in whatever the pill was
                -- given, as every contracted glyph is.
                width = function() return if resting() then cell.room() else content_width() end,
                justify = function() return if resting() then "center" else "start" end,
                -- The cell's only content at rest, in the light gradient.
                g.icon {
                    present = resting,
                    width = icon_size,
                    height = icon_size,
                    icon = "bell",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                },
                g.box {
                    present = function() return not resting() end,
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    g.box {
                        width = icon_size,
                        height = icon_size,
                        align = "center",
                        justify = "center",
                        g.icon {
                            present = function() local p = badge_path() return p ~= "" and is_svg(p) end,
                            width = icon_size,
                            height = icon_size,
                            icon = badge_path,
                        },
                        g.image {
                            present = function() local p = badge_path() return p ~= "" and not is_svg(p) end,
                            src = badge_path,
                            width = icon_size,
                            height = icon_size,
                            fit = "contain",
                        },
                        -- Where nothing resolves, and for a flood (the shell
                        -- speaking about itself), the cell's own glyph.
                        g.box {
                            present = function() return badge_path() == "" end,
                            bell(function() return icon_size() * 0.9 end,
                                function() return if critical() then theme.alert() else theme.text_muted() end),
                        },
                    },
                    g.text {
                        text = line,
                        color = theme.text,
                        font = function() return line_font().font end,
                        size = function() return line_font().size end,
                        tracking = function() return line_font().tracking end,
                        max_width = available,
                    },
                    g.box {
                        present = function() return timed.value end,
                        dial.new { size = timer_size, fraction = function() return 0 end, orbit = left, still = true },
                    },
                    -- The way out, always there: a notification that can only
                    -- be answered by a gesture nobody told you about is one
                    -- you cannot put down (Akusen, 2026-09-22).
                    g.box {
                        role = "button",
                        name = "Dismiss",
                        width = close_size,
                        height = close_size,
                        on_hover = function(on: boolean) close_hovered.value = on end,
                        on_click = function(button: number)
                            if button ~= 272 then return end
                            local id = g.untracked(shout_id)
                            if id then notifications.dismiss(id) else cell.open.value = false end
                        end,
                        g.icon {
                            width = close_size,
                            height = close_size,
                            icon = "close",
                            gradient_top = function() return if close_hovered.value then theme.text() else theme.text_faint() end,
                            gradient_bottom = function() return if close_hovered.value then theme.text() else theme.text_faint() end,
                        },
                    },
                },
            }
        end

        return {
            panel = {
                width = panel_width,
                height = function() return panel_height() end,
                content = function()
                    return g.box {
                        width = function() return panel_width() - 20 * f() end,
                        padding_left = function() return padding() - 10 * f() end,
                        padding_right = function() return padding() - 10 * f() end,
                        direction = "column",
                        notification_node(),
                        history_node(),
                    }
                end,
                outline = function()
                    return if not history.value and critical() then theme.alert() else nil
                end,
            },
            condition = function() return if shout() ~= nil or flooding() then 1 else 0 end,
            claims_focus = function() return history.value end,
            engaging = function() return shout() ~= nil or flooding() end,
            outline = function() return if critical() then theme.alert() else nil end,
            padding_leading = leading,
            padding_trailing = trailing,
            content_width = content_width,
            contracted = contracted,
            header_title = function() return if resting() then "NOTIFICATIONS" else "" end,
            header_mark_size = icon_size,
            header_mark = function(size: () -> number)
                return g.icon {
                    present = resting,
                    width = size,
                    height = size,
                    icon = "bell",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                }
            end,
            -- A press asks for the history; the pointer alone brings the body.
            on_click = function() history.value = not g.untracked(function() return history.value end) end,
            -- A critical notification has no clock: the middle button is the
            -- way to say "read", as everywhere else in the shell.
            on_middle = function() notifications.dismiss(g.untracked(shout_id)) end,
            -- Only the history replaces the pill with its header.
            replaces_content = function() return resting() end,
        }
    end,
}
