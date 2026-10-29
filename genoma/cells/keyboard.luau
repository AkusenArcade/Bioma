--!strict
-- The keyboard's layout: which one is on, switching it, and which ones there
-- are (cells/keyboard/KeyboardCell.qml and KeyboardPanel.qml at 11bb81e).
--
-- At rest its glyph and the layout's code, US, IT, in the machine's voice,
-- the way the workspace number is (Akusen, 2026-09-27). Opened, the list:
-- a press switches, a cross under the pointer removes (never the last
-- one), and typing turns the list into the catalogue, found by name or
-- code, where a press adds. One list in one place, because they are the
-- same question: which layouts.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local keyboard = require("services/keyboard")
local field = require("components/field")
local scroller_mod = require("components/scroller")

local SHOWN_ROWS = 6

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 20 * f() end
        local function glyph_gap(): number return 8 * f() end
        local function row_height(): number return 40 * f() end
        local function panel_width(): number return 360 * f() end
        local function inner(): number return panel_width() - 20 * f() end
        local function list_height(): number return SHOWN_ROWS * row_height() + 12 * f() end

        keyboard.on_switched(function() cell.pulse() end)

        local query = g.signal("")
        local chosen = g.signal(1)
        local function wanted(): string return string.lower(string.match(query.value, "^%s*(.-)%s*$") or "") end
        local function finding(): boolean return wanted() ~= "" end
        -- A code typed in full first, then names that start with it, then
        -- names that contain it.
        local function found(): { any }
            local w = wanted()
            if w == "" then return {} end
            local exact, starts, contains = {}, {}, {}
            for _, e in keyboard.catalogue() do
                local name = string.lower(e.name)
                if e.layout == w and e.variant == "" then table.insert(exact, e)
                elseif string.sub(name, 1, #w) == w then table.insert(starts, e)
                elseif string.find(name, w, 1, true) then table.insert(contains, e) end
            end
            local out = {}
            for _, list in { exact, starts, contains } do
                for _, e in list do
                    if #out < 60 then table.insert(out, e) end
                end
            end
            return out
        end
        local function rows(): { any }
            return if finding() then found() else keyboard.layouts()
        end
        g.watch(wanted, function() chosen.value = 1 end)

        local field_node, field_handle = field.new {
            text = query,
            width = function() return inner() - 30 * f() end,
            font = typography.expressive,
            size = function() return m().font_title end,
            placeholder = "Add a layout",
            taking = function() return cell.open.value end,
            on_submit = function()
                local list = g.untracked(found)
                local e = list[math.max(1, g.untracked(function() return chosen.value end))]
                if e then
                    keyboard.add(e)
                    field_handle.set("")
                end
            end,
        }
        g.watch(function() return cell.open.value end, function(open: boolean)
            if not open then field_handle.set("") end
        end)

        local scroll = scroller_mod.new {
            viewport = function() return list_height() - 12 * f() end,
            content = function() return #rows() * row_height() end,
            step = row_height,
            factor = f,
        }

        local function row(item: () -> any, index: () -> number): any
            local function e(): any return item() end
            local function active(): boolean return not finding() and index() == keyboard.current_index() end
            local function removable(): boolean return not finding() and #keyboard.layouts() > 1 and e().layout ~= "" end
            local hovered = g.signal(false)
            local function highlighted(): boolean return hovered.value or (finding() and index() == chosen.value) end
            return g.capsule {
                role = "button",
                name = "Layout",
                overlay = true,
                attach = "corner",
                offset_y = function() return (index() - 1) * row_height() end,
                width = function() return inner() - 18 * f() end,
                height = row_height,
                radius = function() return metrics_mod.shaped(8 * f()) end,
                fill = function() return if highlighted() then colour.alpha(theme.primary(), 0.1) else "#00000000" end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function()
                    if g.untracked(finding) then
                        keyboard.add(g.untracked(e))
                        field_handle.set("")
                    else
                        keyboard.switch_to(g.untracked(index))
                    end
                end,
                g.capsule {
                    overlay = true,
                    attach = "corner",
                    present = active,
                    offset_x = function() return 10 * f() end,
                    offset_y = function() return (row_height() - 6 * f()) / 2 end,
                    width = function() return 6 * f() end,
                    height = function() return 6 * f() end,
                    fill = theme.primary,
                    rim_top = "#00000000",
                    rim_bottom = "#00000000",
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return 26 * f() end,
                    width = function() return inner() - 18 * f() - 26 * f() end,
                    height = row_height,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    g.text {
                        text = function() return e().name end,
                        color = function() return if active() or finding() then theme.text() else theme.text_muted() end,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return inner() - 160 * f() end,
                    },
                    g.box {
                        direction = "row",
                        align = "center",
                        gap = function() return 8 * f() end,
                        g.text {
                            text = function()
                                local v = e().variant or ""
                                return keyboard.code_of(e()) .. (if v ~= "" then " · " .. v else "")
                            end,
                            color = theme.text_faint,
                            font = typography.technical,
                            size = function() return m().font_meta end,
                            tracking = typography.label_tracking,
                        },
                        g.box {
                            role = "button",
                            name = "Remove",
                            present = removable,
                            width = function() return 18 * f() end,
                            height = function() return 18 * f() end,
                            align = "center",
                            justify = "center",
                            opacity = function() return if hovered.value then 1 else 0 end,
                            on_click = function() keyboard.remove(g.untracked(index)) end,
                            g.icon {
                                width = function() return 9 * f() end,
                                height = function() return 9 * f() end,
                                icon = "close",
                                gradient_top = theme.text,
                                gradient_bottom = theme.text,
                            },
                        },
                    },
                },
            }
        end

        local function content(): any
            return g.box {
                direction = "column",
                gap = function() return 10 * f() end,
                g.box {
                    width = inner,
                    height = function() return m().field_height end,
                    direction = "row",
                    align = "center",
                    gap = function() return 10 * f() end,
                    padding_left = function() return 6 * f() end,
                    g.icon {
                        width = function() return 14 * f() end,
                        height = function() return 14 * f() end,
                        icon = "plus",
                        gradient_top = function() return theme.gradient_top(theme.primary()) end,
                        gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    },
                    field_node,
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
                        present = function() return finding() and #found() == 0 end,
                        g.text {
                            text = "No layout by that name",
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
                            width = function() return inner() - 12 * f() end,
                            items = rows,
                            key = function(e: any) return e.name .. "|" .. (e.layout or "") .. "|" .. (e.variant or "") end,
                            row = row,
                        },
                        scroll.bar(function() return inner() - 19 * f() end),
                    },
                },
                g.box {
                    present = function() return keyboard.error() ~= "" end,
                    g.text {
                        text = keyboard.error,
                        color = theme.alert,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = inner,
                        wrap = true,
                    },
                },
            }
        end

        return {
            panel = {
                width = panel_width,
                height = function()
                    return m().field_height + 10 * f() + list_height() + 20 * f()
                        + (if keyboard.error() ~= "" then 30 * f() else 0)
                end,
                content = content,
            },
            -- Escape empties the field first, and only then closes; Up and
            -- Down choose among what was found.
            on_key = function(name: string, typed: string?, mods: { [string]: boolean }): boolean
                if name == "Escape" and g.untracked(function() return query.value end) ~= "" then
                    field_handle.set("")
                    return true
                end
                if name == "Escape" then return false end
                if g.untracked(finding) and (name == "Down" or name == "Up") then
                    local n = #g.untracked(found)
                    local now = g.untracked(function() return chosen.value end)
                    chosen.value = math.clamp(now + (if name == "Down" then 1 else -1), 1, math.max(1, n))
                    scroll.reveal((chosen.value - 1) * g.untracked(row_height), g.untracked(row_height))
                    return true
                end
                return field_handle.key(name, typed, mods)
            end,
            padding_leading = function() return 12 * f() end,
            padding_trailing = function() return 14 * f() end,
            condition = function() return if cell.pulsing() then 1 else 0 end,
            content_width = function()
                return glyph() + glyph_gap() + g.text_width { text = keyboard.current_code(), font = typography.technical(),
                    size = m().font_label, weight = typography.weight_label, tracking = typography.label_tracking }
            end,
            header_title = "KEYBOARD",
            header_mark_size = glyph,
            header_mark = function(mark: () -> number)
                return g.icon {
                    width = mark,
                    height = mark,
                    icon = "keyboard",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                }
            end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = glyph_gap,
                    g.icon {
                        width = glyph,
                        height = glyph,
                        icon = "keyboard",
                        gradient_top = function() return theme.gradient_top(theme.primary()) end,
                        gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    },
                    g.text {
                        text = keyboard.current_code,
                        color = theme.text,
                        font = typography.technical,
                        size = function() return m().font_label end,
                        weight = typography.weight_label,
                        tracking = typography.label_tracking,
                    },
                }
            end,
        }
    end,
}
