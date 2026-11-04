--!strict
-- Search and launch (cells/launcher/Launcher.qml and LauncherBody.qml at
-- 2cafc17). See docs/design/CELLS.md §13, PRD §9.13.
--
-- The only cell with **no contracted state** when it is asked for by name:
-- it sits on no membrane, hangs from nothing, and when it appears it is
-- already itself, in the middle of the screen. Put on a membrane by
-- somebody who would rather have a button to aim at, it is a button, and
-- the same body hangs off it the way every other expansion hangs off its
-- cell (Akusen, 2026-09-22). What changes is where it is born; what it is
-- does not.
--
-- A field, and six rows under it: the applications (with an empty field
-- the most used, since an alphabetical list is an archive), a sum on the
-- first row when the query is one, and the files of the home under the
-- applications. The arrows move, Enter launches, Ctrl+Enter shows a file
-- where it lives, Escape closes.
--
-- Not yet: Ctrl with a press (Genoma's presses carry no modifiers); a
-- folder's path elided in its middle rather than at its end.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local search = require("cells/launcher_search")
local registry = require("cells/registry")
local field_mod = require("components/field")
local scroller_mod = require("components/scroller")
local files = require("services/files")
local calculator = require("services/calculator")
local focus = require("structure/focus")

local CLEAR = "#00000000"
local SHOWN_ROWS = 6

local letters_of = search.letters_of

local function simple(cell: any): any
    local function m(): any return cell.metrics() end
    local function f(): number return m().factor end
    local function inset(): number return 10 * f() end
    local function field_height(): number return 44 * f() end
    local function result_height(): number return 52 * f() end
    local function list_gap(): number return 6 * f() end
    local function glyph(): number return 20 * f() end
    local function section_height(): number return 26 * f() end
    local function panel_width(): number return 480 * f() end
    local function inner(): number return panel_width() - inset() * 2 end
    local function list_height(): number return SHOWN_ROWS * result_height() end
    -- The height is **fixed**: a panel that grew and shrank with the
    -- results re-centred on every letter typed, and the field jumped
    -- under the fingers. Six rows is what it always holds.
    local function body_extent(): number return inset() * 2 + field_height() + list_gap() + list_height() end
    local as_panel = cell.floating

    -- ---- What it knows -----------------------------------------------------

    local query = g.signal("")
    local chosen = g.signal(1)

    local function applications(wanted: { string }): { any }
        return search.applications(wanted, if #wanted == 0 then SHOWN_ROWS * 3 else 40)
    end

    local results = g.computed(function(): { any }
        local q = string.lower(string.match(query.value, "^%s*(.-)%s*$") or "")
        local wanted = letters_of(q)
        local out = {}
        -- A sum or a conversion, on the first row: the figure is what
        -- was asked for, so it is the name, and Enter copies it.
        local sum = calculator.result()
        if sum ~= "" then
            table.insert(out, { kind = "sum", group = "", name = sum, at = {}, icon = "accessories-calculator", detail = "CALCULATOR" })
        end
        -- With files to show, the applications are the few that answer
        -- best: the tail would push every file out of sight. The files
        -- land a moment after, below, so what Enter takes stays put.
        local found = files.results()
        local list = applications(wanted)
        local shown = if #found > 0 then math.min(SHOWN_ROWS, #list) else #list
        for i = 1, shown do table.insert(out, list[i]) end
        for _, file in found do
            table.insert(out, { kind = "file", group = "FILES", file = file, name = file.name, at = file.at, icon = file.icon, detail = file.folder })
        end
        return out
    end)
    local function searching(): boolean return files.searching() or calculator.pending() end

    -- Where each row sits, the files' word for what they are above the
    -- first of them.
    local layout = g.computed(function(): { [string]: any }
        local rows, y, group = {}, 0, ""
        for i, r in results.value do
            if r.group ~= group then
                group = r.group
                if group ~= "" then y += section_height() end
            end
            table.insert(rows, { index = i, y = y, result = r, section = if r.group ~= "" and (i == 1 or results.value[i - 1].group ~= r.group) then r.group else "" })
            y += result_height()
        end
        return { rows = rows, height = y }
    end)

    local scroll = scroller_mod.new {
        viewport = list_height,
        content = function() return layout.value.height end,
        step = result_height,
        factor = f,
    }

    g.watch(function() return query.value end, function(q: string)
        chosen.value = 1
        scroll.to(0)
        files.ask(q)
        calculator.ask(q)
    end)
    g.watch(function() return #results.value end, function(n: number)
        if g.untracked(function() return chosen.value end) > n then chosen.value = 1 end
    end)

    -- The chosen row is kept in view by whoever draws the rows.
    local function move(delta: number)
        local n = #g.untracked(function() return results.value end)
        if n == 0 then return end
        local next = (g.untracked(function() return chosen.value end) - 1 + delta) % n + 1
        chosen.value = next
        local row = g.untracked(function() return layout.value.rows[next] end)
        if row then
            local top = if row.section ~= "" then row.y - section_height() else row.y
            scroll.reveal(top, row.y + g.untracked(result_height) - top)
        end
    end

    -- ---- Doing it -------------------------------------------------------------

    local handle: any = nil
    local function dismiss()
        if handle then handle.set("") end
        query.value = ""
        focus.dismiss()
    end

    -- A file is opened by whatever opens it; with Ctrl it is shown where
    -- it lives instead. Ctrl means nothing to an application.
    local function launch(index: number, reveal: boolean)
        local r = g.untracked(function() return results.value[index] end)
        if not r then return end
        search.launch(r, reveal)
        dismiss()
    end

    -- Closed, it forgets what was typed.
    g.watch(function() return if as_panel then cell.placed.value else cell.open.value end, function(on: boolean)
        if not on and g.untracked(function() return query.value end) ~= "" then
            if handle then handle.set("") end
            query.value = ""
        end
    end)

    local function on_key(name: string, typed: string?, mods: { [string]: boolean }): boolean
        if name == "Escape" then return false end
        if not as_panel and not g.untracked(function() return cell.open.value end) then return false end
        if name == "Down" then move(1) return true end
        if name == "Up" then move(-1) return true end
        if name == "Return" or name == "KP_Enter" then
            launch(g.untracked(function() return chosen.value end), mods.ctrl == true)
            return true
        end
        return if handle then handle.key(name, typed, mods) else false
    end

    -- ---- The body ---------------------------------------------------------------

    local function meta_text(text: string | () -> string, color: any, max: (() -> number)?): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
            max_width = max,
        }
    end

    local function result_row(item: () -> any): any
        local function r(): any return item().result end
        local function picked(): boolean return chosen.value == item().index end
        local hovered = g.signal(false)
        local function portrait(): number return 36 * f() end
        local function source(): string
            local icon = r().icon
            if icon == "" then return "" end
            return g.icon_path(icon) or ""
        end
        local function text_width(): number return inner() - 8 * f() - portrait() - 8 * f() - 14 * f() * 2 end
        return g.box {
            overlay = true,
            attach = "corner",
            offset_y = function() return item().y end,
            width = function() return inner() - 8 * f() end,
            height = result_height,
            g.text {
                overlay = true,
                attach = "corner",
                present = function() return item().section ~= "" end,
                offset_x = function() return 8 * f() end,
                offset_y = function() return -section_height() + 6 * f() end,
                text = function() return item().section end,
                color = theme.text_faint,
                font = typography.technical,
                size = function() return m().font_meta end,
                weight = typography.weight_label,
                tracking = typography.label_tracking,
            },
            -- Selection is a fill and never an outline: the lit outline
            -- means "surface" in this shell. The pointer only lights the
            -- row it is over; the choice belongs to the keyboard.
            g.capsule {
                role = "button",
                name = "Result",
                width = function() return inner() - 10 * f() end,
                height = result_height,
                direction = "row",
                align = "center",
                justify = "start",
                padding_left = function() return 8 * f() end,
                gap = function() return 14 * f() end,
                radius = function() return metrics_mod.shaped(14 * f()) end,
                fill = function()
                    if picked() then return theme.selection() end
                    return if hovered.value then colour.alpha(theme.text(), 0.06) else CLEAR
                end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function(button: number)
                    if button == 272 then launch(g.untracked(function() return item().index end), false) end
                end,
                g.box {
                    width = portrait,
                    height = portrait,
                    align = "center",
                    justify = "center",
                    g.capsule {
                        overlay = true,
                        present = picked,
                        width = portrait,
                        height = portrait,
                        stroke = function() return 1.5 * f() end,
                        rim_top = theme.primary,
                        rim_bottom = theme.primary,
                    },
                    g.icon {
                        present = function() return source() ~= "" end,
                        width = function() return portrait() * 0.7 end,
                        height = function() return portrait() * 0.7 end,
                        icon = source,
                    },
                    g.icon {
                        present = function() return source() == "" end,
                        width = function() return portrait() * 0.6 end,
                        height = function() return portrait() * 0.6 end,
                        icon = "app-fallback",
                        color = theme.text_muted,
                    },
                },
                -- The name, with the letters the search matched lit. A
                -- name is human language; the line under it is the
                -- system's own word and takes the other voice.
                g.box {
                    direction = "column",
                    align = "start",
                    gap = function() return 2 * f() end,
                    g.text {
                        text = function() return r().name end,
                        marks = function() return g.array(table.clone(r().at)) end,
                        mark_color = theme.primary,
                        color = theme.text,
                        font = typography.expressive,
                        size = function() return 15 * f() end,
                        max_width = text_width,
                    },
                    g.box {
                        present = function() return r().detail ~= "" end,
                        meta_text(function() return r().detail end, theme.text_faint, text_width),
                    },
                },
            },
        }
    end

    local function body(): any
        local node, h = field_mod.new {
            text = query,
            width = function() return inner() - 6 * f() - 17 * f() - 12 * f() - 6 * f() end,
            font = typography.expressive,
            size = function() return 16 * f() end,
            placeholder = "Search",
            taking = function() return true end,
        }
        handle = h
        return g.box {
            width = inner,
            height = function() return body_extent() - inset() * 2 end,
            direction = "column",
            align = "start",
            gap = list_gap,
            g.box {
                width = inner,
                height = field_height,
                direction = "row",
                align = "center",
                padding_left = function() return 6 * f() end,
                gap = function() return 12 * f() end,
                g.icon {
                    width = function() return 17 * f() end,
                    height = function() return 17 * f() end,
                    icon = "search",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                },
                node,
            },
            g.box {
                width = inner,
                height = list_height,
                -- Nothing found is one line, and the field does not move.
                -- Not while the home is still being walked: "nothing"
                -- said before the files are back would be taken back.
                g.box {
                    overlay = true,
                    attach = "corner",
                    present = function() return query.value ~= "" and #results.value == 0 and not searching() end,
                    width = inner,
                    height = result_height,
                    align = "center",
                    justify = "center",
                    g.text {
                        text = "Nothing answers to that",
                        color = theme.text_muted,
                        font = typography.expressive,
                        size = function() return m().font_title end,
                    },
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    width = inner,
                    height = list_height,
                    clip = true,
                    scroll_y = scroll.offset,
                    fade_bottom = scroll.fade,
                    transition = { scroll_y = "reflow" },
                    on_wheel = scroll.wheel,
                    g.each {
                        overlay = true,
                        attach = "corner",
                        items = function() return layout.value.rows end,
                        key = function(row: any): string
                            local res = row.result
                            return res.kind .. ":" .. (if res.kind == "file" then res.file.path elseif res.kind == "app" then res.entry.id else "") .. ":" .. row.section
                        end,
                        row = result_row,
                    },
                    scroll.bar(function() return inner() - 3 * f() end),
                },
            },
        }
    end

    local function mark(size: () -> number): any
        return g.icon {
            width = size,
            height = size,
            icon = "launcher",
            gradient_top = function() return theme.gradient_top(theme.primary()) end,
            gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
        }
    end

    if as_panel then
        -- Asked for, it *is* the panel; and it is there only when asked
        -- for: always there, it would hold the keyboard for good.
        return {
            interactive = false,
            wants_keyboard = true,
            fixed_visibility = registry.fixed_when_floating("launcher"),
            padding_leading = inset,
            padding_trailing = inset,
            content_width = inner,
            body_height = body_extent,
            radius = function() return metrics_mod.radius_for(body_extent(), m()) end,
            contracted = body,
            on_key = on_key,
        }
    end
    return {
        panel = {
            width = panel_width,
            height = body_extent,
            content = function()
                return g.box { padding = inset, body() }
            end,
        },
        wants_keyboard = true,
        padding_leading = function() return (m().cell_height - glyph()) / 2 end,
        padding_trailing = function() return (m().cell_height - glyph()) / 2 end,
        content_width = glyph,
        header_title = "LAUNCHER",
        header_mark_size = glyph,
        header_mark = mark,
        contracted = function() return mark(glyph) end,
        on_key = on_key,
    }
end

return {
    new = function(cell: any)
        local plain = simple(cell)
        -- On a membrane, hung from a glyph, it is always the list.
        if not cell.floating then return plain end
        -- Floating, it may be the organic one (Settings → Cells): its
        -- results gather in clusters round the field. Both are built and
        -- the choice is read as it is drawn, so a launcher that already
        -- exists (one declared in a floating tissue) changes form when the
        -- setting does, not only one summoned after it.
        local organic = require("cells/launcher_organic").new(cell)
        local function chosen(): boolean return config.get("launcher.style", "simple") == "organic" end
        local function pick(): any return if chosen() then organic else plain end
        local function value(key: string): (...any) -> any
            return function(...)
                local v = pick()[key]
                if type(v) == "function" then return v(...) end
                return v
            end
        end
        return {
            interactive = false,
            wants_keyboard = true,
            fixed_visibility = plain.fixed_visibility,
            padding_leading = value("padding_leading"),
            padding_trailing = value("padding_trailing"),
            content_width = value("content_width"),
            body_height = value("body_height"),
            radius = value("radius"),
            contracted = function()
                return g.box {
                    g.box { present = function() return not chosen() end, plain.contracted() },
                    g.box { present = chosen, organic.contracted() },
                }
            end,
            around = organic.around,
            withdrawal = function() return if chosen() then organic.withdrawal() else 0 end,
            on_key = function(name: string, typed: string?, mods: { [string]: boolean }): boolean
                return pick().on_key(name, typed, mods)
            end,
        }
    end,
}
