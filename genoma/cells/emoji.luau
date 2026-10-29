--!strict
-- Emoji: found by name and put where the keyboard points (cells/emoji/
-- EmojiCell.qml and EmojiPanel.qml at 11bb81e).
--
-- At rest its glyph. Opened: a search field with the skin tones beside it,
-- the grid (recent ones first, then each group under its name, or what the
-- search found), and under it the one chosen, large, with its name. The
-- arrows move the choice, Tab the tone, Return sends; a press sends the one
-- under the pointer. Sending closes the cell first, so the text reaches the
-- window that had the keyboard.
--
-- Only the rows in view, and a few either side, are built: two thousand
-- glyphs at once would be drawn for nothing.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local emoji = require("services/emoji")
local field = require("components/field")
local scroller_mod = require("components/scroller")

local COLUMNS = 10
local SHOWN_ROWS = 7
local TONES = { "✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿" }
-- Named, not left to the fallback: for many of them fontconfig finds a
-- text face with outline glyphs first (DejaVu Sans), and the grid came out
-- half in black and white.
local FACE = "Noto Color Emoji"

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 20 * f() end
        local function row_height(): number return 42 * f() end
        local function label_height(): number return 26 * f() end
        local function panel_width(): number return 440 * f() end
        local function inner(): number return panel_width() - 20 * f() end
        local function list_height(): number return SHOWN_ROWS * row_height() + 12 * f() end
        local function foot_height(): number return 36 * f() end
        local function grid_width(): number return inner() - 18 * f() end
        local function slot_width(): number return grid_width() / COLUMNS end

        g.watch(function() return cell.open.value end, function(open: boolean)
            if open then emoji.want() end
            emoji.ready(open)
        end)

        local query = g.signal("")
        local chosen = g.signal(1)

        -- The grid as rows: a label row, or up to ten emoji, each with its
        -- top, so a row in view is found without walking the rest.
        local layout = g.computed(function(): { [string]: any }
            local flat, rows, y = {}, {}, 0
            local function section(label: string, entries: { any })
                if #entries == 0 then return end
                if label ~= "" then
                    table.insert(rows, { label = label, from = 0, count = 0, y = y })
                    y += label_height()
                end
                local at = 1
                while at <= #entries do
                    local count = math.min(COLUMNS, #entries - at + 1)
                    table.insert(rows, { label = "", from = #flat + 1, count = count, y = y })
                    for i = 0, count - 1 do table.insert(flat, entries[at + i]) end
                    y += row_height()
                    at += count
                end
            end
            if emoji.loaded() then
                local q = string.match(query.value, "^%s*(.-)%s*$") or ""
                if q ~= "" then
                    section("", emoji.search(q))
                else
                    section("RECENT", emoji.recent_entries())
                    local by_group = {}
                    for i = 1, #emoji.groups() do by_group[i] = {} end
                    for _, e in emoji.all() do table.insert(by_group[e.group + 1], e) end
                    for i, name in emoji.groups() do section(name, by_group[i]) end
                end
            end
            return { flat = flat, rows = rows, height = y }
        end)
        local function flat(): { any } return layout.value.flat end
        local function chosen_entry(): any return flat()[chosen.value] end

        local scroll = scroller_mod.new {
            viewport = function() return list_height() - 12 * f() end,
            content = function() return layout.value.height end,
            step = row_height,
            factor = f,
        }
        g.watch(function() return query.value end, function()
            chosen.value = 1
            scroll.to(0)
        end)

        local function row_of(index: number): number
            for r, row in layout.value.rows do
                if row.count > 0 and index >= row.from and index < row.from + row.count then return r end
            end
            return 0
        end
        local function choose(index: number)
            local n = #g.untracked(flat)
            if n == 0 then return end
            chosen.value = math.clamp(index, 1, n)
            local rows = g.untracked(function() return layout.value.rows end)
            local r = row_of(chosen.value)
            if r > 0 then
                local top = rows[r].y
                if r > 1 and rows[r - 1].count == 0 then top = rows[r - 1].y end
                scroll.reveal(top, rows[r].y + g.untracked(row_height) - top)
            end
        end
        local function vertical(step: number, count: number)
            local rows = g.untracked(function() return layout.value.rows end)
            local r = row_of(g.untracked(function() return chosen.value end))
            if r == 0 then return end
            local column = g.untracked(function() return chosen.value end) - rows[r].from
            local left, nxt, at = count, r, r + step
            while at >= 1 and at <= #rows and left > 0 do
                if rows[at].count > 0 then
                    nxt = at
                    left -= 1
                end
                at += step
            end
            choose(rows[nxt].from + math.min(column, rows[nxt].count - 1))
        end
        local function send(index: number)
            local e = g.untracked(flat)[index]
            if not e then return end
            emoji.send(e)
            cell.open.value = false
        end

        local field_node, field_handle = field.new {
            text = query,
            width = function() return inner() - 26 * f() - 6 * 28 * f() - 12 * f() end,
            font = typography.expressive,
            size = function() return m().font_title end,
            placeholder = "Search emoji",
            taking = function() return cell.open.value end,
            on_submit = function() send(g.untracked(function() return chosen.value end)) end,
        }
        g.watch(function() return cell.open.value end, function(open: boolean) if not open then field_handle.set("") end end)

        -- The rows in view, and two either side.
        local function visible(): { any }
            local top, view = scroll.offset(), list_height()
            local out = {}
            for i, row in layout.value.rows do
                if row.y + row_height() >= top - 2 * row_height() and row.y <= top + view + 2 * row_height() then
                    table.insert(out, { index = i, row = row })
                end
            end
            return out
        end

        local function slot(r: () -> any, column: number): any
            local function at(): number return r().row.from + column - 1 end
            local function entry(): any return if column <= r().row.count then flat()[at()] else nil end
            return g.box {
                role = "button",
                name = "Emoji",
                overlay = true,
                attach = "corner",
                present = function() return entry() ~= nil end,
                offset_x = function() return (column - 1) * slot_width() end,
                width = slot_width,
                height = row_height,
                align = "center",
                justify = "center",
                on_hover = function(on: boolean) if on then chosen.value = g.untracked(at) end end,
                on_click = function() send(g.untracked(at)) end,
                g.capsule {
                    overlay = true,
                    present = function() return chosen.value == at() end,
                    width = function() return math.min(slot_width(), row_height()) - 2 * f() end,
                    height = function() return math.min(slot_width(), row_height()) - 2 * f() end,
                    radius = function() return metrics_mod.shaped(10 * f()) end,
                    fill = function() return colour.alpha(theme.primary(), 0.14) end,
                    rim_top = "#00000000",
                    rim_bottom = "#00000000",
                },
                g.text {
                    text = function() local e = entry() return if e then emoji.shown(e) else "" end,
                    font = FACE,
                    size = function() return 24 * f() end,
                    color = theme.text,
                },
            }
        end

        local function grid_row(item: () -> any): any
            local node: { [any]: any } = {
                overlay = true,
                attach = "corner",
                offset_y = function() return item().row.y end,
                width = grid_width,
                height = function() return if item().row.count > 0 then row_height() else label_height() end,
                -- A group's name, in the machine's voice, over its rows.
                g.box {
                    overlay = true,
                    attach = "corner",
                    present = function() return item().row.count == 0 end,
                    offset_x = function() return 6 * f() end,
                    width = grid_width,
                    height = label_height,
                    align = "end",
                    padding_y = function() return 2 * f() end,
                    g.text {
                        text = function() return item().row.label end,
                        color = theme.text_faint,
                        font = typography.technical,
                        size = function() return m().font_meta end,
                        weight = typography.weight_label,
                        tracking = typography.label_tracking,
                    },
                },
            }
            for column = 1, COLUMNS do table.insert(node, slot(item, column)) end
            return g.box(node)
        end

        local function tone_button(i: number): any
            local hovered = g.signal(false)
            local function on(): boolean return emoji.tone() == i - 1 end
            return g.capsule {
                role = "button",
                name = "Tone",
                width = function() return 26 * f() end,
                height = function() return 26 * f() end,
                align = "center",
                justify = "center",
                fill = function()
                    if on() then return colour.alpha(theme.primary(), 0.16) end
                    return if hovered.value then colour.alpha(theme.text(), 0.06) else "#00000000"
                end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                on_hover = function(h: boolean) hovered.value = h end,
                on_click = function() emoji.set_tone(i - 1) end,
                g.text {
                    text = TONES[i],
                    font = FACE,
                    size = function() return 15 * f() end,
                    color = theme.text,
                    opacity = function() return if on() or hovered.value then 1 else 0.55 end,
                },
            }
        end

        local function content(): any
            local tones: { [any]: any } = { direction = "row", gap = function() return 2 * f() end }
            for i = 1, #TONES do table.insert(tones, tone_button(i)) end
            return g.box {
                direction = "column",
                gap = function() return 10 * f() end,
                g.box {
                    width = inner,
                    height = function() return m().field_height end,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    g.box {
                        direction = "row",
                        align = "center",
                        gap = function() return 10 * f() end,
                        padding_left = function() return 6 * f() end,
                        g.icon {
                            width = function() return 16 * f() end,
                            height = function() return 16 * f() end,
                            icon = "search",
                            gradient_top = function() return theme.gradient_top(theme.primary()) end,
                            gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                        },
                        field_node,
                    },
                    g.box(tones),
                },
                g.capsule {
                    width = inner,
                    height = list_height,
                    radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                    fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                    rim_top = "#00000000",
                    rim_bottom = "#00000000",
                    g.box {
                        overlay = true,
                        present = function() return emoji.loaded() and #flat() == 0 end,
                        g.text {
                            text = "Nothing answers to that",
                            color = theme.text_muted,
                            font = typography.expressive,
                            size = function() return m().font_secondary end,
                        },
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        offset_x = function() return 6 * f() end,
                        offset_y = function() return 6 * f() end,
                        width = function() return inner() - 12 * f() end,
                        height = function() return list_height() - 12 * f() end,
                        clip = true,
                        scroll_y = scroll.offset,
                        transition = { scroll_y = "reflow" },
                        on_wheel = scroll.wheel,
                        g.each {
                            overlay = true,
                            attach = "corner",
                            width = grid_width,
                            items = visible,
                            key = function(v: any) return v.index end,
                            row = grid_row,
                        },
                        scroll.bar(function() return inner() - 19 * f() end),
                    },
                },
                -- The one chosen, large, with its name.
                g.box {
                    width = inner,
                    height = foot_height,
                    direction = "row",
                    align = "center",
                    gap = function() return 10 * f() end,
                    padding_left = function() return 8 * f() end,
                    g.text {
                        text = function() local e = chosen_entry() return if e then emoji.shown(e) else "" end,
                        font = FACE,
                        size = function() return 20 * f() end,
                        color = theme.text,
                    },
                    g.text {
                        text = function() local e = chosen_entry() return if e then e.name else "" end,
                        color = theme.text_muted,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return inner() - 60 * f() end,
                    },
                },
            }
        end

        local function mark(size: () -> number): any
            return g.icon {
                width = size,
                height = size,
                icon = "emoji",
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            }
        end

        return {
            panel = {
                width = panel_width,
                height = function() return m().field_height + 10 * f() + list_height() + 10 * f() + foot_height() + 20 * f() end,
                content = content,
            },
            on_key = function(name: string, typed: string?, mods: { [string]: boolean }): boolean
                if name == "Escape" and g.untracked(function() return query.value end) ~= "" then
                    field_handle.set("")
                    return true
                end
                if name == "Escape" then return false end
                local c = g.untracked(function() return chosen.value end)
                if name == "Left" and not mods.ctrl then choose(c - 1) return true end
                if name == "Right" and not mods.ctrl then choose(c + 1) return true end
                if name == "Up" then vertical(-1, 1) return true end
                if name == "Down" then vertical(1, 1) return true end
                if name == "Next" or name == "Page_Down" then vertical(1, SHOWN_ROWS - 1) return true end
                if name == "Prior" or name == "Page_Up" then vertical(-1, SHOWN_ROWS - 1) return true end
                if name == "Tab" then emoji.set_tone((g.untracked(emoji.tone) + 1) % 6) return true end
                if name == "ISO_Left_Tab" then emoji.set_tone((g.untracked(emoji.tone) + 5) % 6) return true end
                return field_handle.key(name, typed, mods)
            end,
            padding_leading = function() return (m().cell_height - glyph()) / 2 end,
            padding_trailing = function() return (m().cell_height - glyph()) / 2 end,
            content_width = glyph,
            header_title = "EMOJI",
            header_mark_size = glyph,
            header_mark = mark,
            contracted = function() return mark(glyph) end,
        }
    end,
}
