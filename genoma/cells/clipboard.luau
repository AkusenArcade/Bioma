--!strict
-- What was copied, kept, and put back with a press (cells/clipboard/
-- ClipboardCell.qml and ClipboardPanel.qml at 11bb81e).
--
-- At rest its glyph and nothing else: the history is somebody's text, and
-- a cell showing the last thing copied would read it out on the membrane.
-- Conditional, it is there a moment after a copy. Opened: a filter, then
-- what was copied, newest first, text as its first words in the expressive
-- face and an image as itself, small; a press puts it back and closes the
-- cell, the cross under the pointer drops one, CLEAR drops them all after
-- asking by asking again.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local clipboard = require("services/clipboard")
local field = require("components/field")
local scroller_mod = require("components/scroller")

local SHOWN_ROWS = 7

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 20 * f() end
        local function row_height(): number return 48 * f() end
        local function image_row(): number return 72 * f() end
        local function panel_width(): number return 380 * f() end
        local function inner(): number return panel_width() - 20 * f() end
        local function list_height(): number return SHOWN_ROWS * row_height() + 12 * f() end

        clipboard.on_copied(function() cell.pulse() end)

        -- The age of each entry moves on with the minute, not every frame.
        local minute = g.signal(os.time())
        g.effect(function()
            if cell.open.value then g.timer { every = 60, on_tick = function() minute.value = os.time() end } end
        end)

        local query = g.signal("")
        local chosen = g.signal(1)
        local function shown(): { any }
            local w = string.lower(string.match(query.value, "^%s*(.-)%s*$") or "")
            if w == "" then return clipboard.entries() end
            local out = {}
            for _, e in clipboard.entries() do
                if not clipboard.is_image(e) and string.find(string.lower(tostring(e.preview)), w, 1, true) then table.insert(out, e) end
            end
            return out
        end
        g.watch(function() return query.value end, function() chosen.value = 1 end)
        local function height_of(e: any): number return if clipboard.is_image(e) then image_row() else row_height() end
        local function choose(e: any)
            if not e then return end
            clipboard.restore(e)
            cell.open.value = false
        end

        local field_node, field_handle = field.new {
            text = query,
            width = function() return inner() - 26 * f() - 110 * f() end,
            font = typography.expressive,
            size = function() return m().font_title end,
            placeholder = "Search what was copied",
            taking = function() return cell.open.value end,
            on_submit = function()
                local list = g.untracked(shown)
                choose(list[math.max(1, g.untracked(function() return chosen.value end))])
            end,
        }
        g.watch(function() return cell.open.value end, function(open: boolean) if not open then field_handle.set("") end end)

        local scroll = scroller_mod.new {
            viewport = function() return list_height() - 12 * f() end,
            content = function()
                local h = 0
                for _, e in shown() do h += height_of(e) end
                return h
            end,
            step = row_height,
            factor = f,
        }

        local armed = g.signal(false)
        local clear_hovered = g.signal(false)

        local function row(item: () -> any, index: () -> number): any
            local function e(): any return item() end
            local function image(): boolean return clipboard.is_image(e()) end
            local hovered = g.signal(false)
            local function y(): number
                local at = 0
                for i, other in shown() do
                    if i >= index() then break end
                    at += height_of(other)
                end
                return at
            end
            local function picture_width(): number return (image_row() - 12 * f()) * 1.6 end
            return g.capsule {
                role = "button",
                name = "Copied",
                overlay = true,
                attach = "corner",
                offset_y = y,
                width = function() return inner() - 18 * f() end,
                height = function() return height_of(e()) end,
                radius = function() return metrics_mod.shaped(8 * f()) end,
                fill = function()
                    return if hovered.value or index() == chosen.value then colour.alpha(theme.text(), 0.05) else "#00000000"
                end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                direction = "row",
                align = "center",
                gap = function() return 10 * f() end,
                padding_x = function() return 8 * f() end,
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function() choose(g.untracked(e)) end,
                g.image {
                    present = image,
                    src = function() return if image() then e().file else "" end,
                    width = picture_width,
                    height = function() return image_row() - 12 * f() end,
                    fit = "contain",
                },
                g.box {
                    grow = 1,
                    present = function() return not image() end,
                    g.text {
                        text = function() return tostring(e().preview or "") end,
                        color = theme.text,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return inner() - 18 * f() - 16 * f() - 90 * f() end,
                        wrap = true,
                    },
                },
                g.box { grow = 1, present = image },
                g.text {
                    text = function()
                        local _ = minute.value
                        return clipboard.age(e(), os.time())
                    end,
                    color = theme.text_faint,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tracking = typography.label_tracking,
                    tabular = true,
                },
                g.box {
                    role = "button",
                    name = "Drop",
                    width = function() return 18 * f() end,
                    height = function() return 18 * f() end,
                    align = "center",
                    justify = "center",
                    opacity = function() return if hovered.value then 1 else 0 end,
                    on_click = function() clipboard.remove(g.untracked(e)) end,
                    g.icon {
                        width = function() return 9 * f() end,
                        height = function() return 9 * f() end,
                        icon = "close",
                        gradient_top = theme.text,
                        gradient_bottom = theme.text,
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
                    -- Dropping everything asks, by asking again.
                    g.capsule {
                        role = "button",
                        name = "Clear",
                        present = function() return #clipboard.entries() > 0 end,
                        height = function() return 24 * f() end,
                        padding_x = function() return 11 * f() end,
                        align = "center",
                        justify = "center",
                        radius = function() return metrics_mod.radius_for(24 * f(), m()) end,
                        fill = function() return if armed.value then colour.alpha(theme.alert(), 0.16) else "#00000000" end,
                        rim_top = function()
                            return if armed.value then theme.alert() elseif clear_hovered.value then theme.text() else theme.line()
                        end,
                        rim_bottom = function()
                            return if armed.value then theme.alert() elseif clear_hovered.value then theme.text() else theme.line()
                        end,
                        on_hover = function(on: boolean)
                            clear_hovered.value = on
                            if not on then armed.value = false end
                        end,
                        on_click = function()
                            if not g.untracked(function() return armed.value end) then
                                armed.value = true
                                return
                            end
                            armed.value = false
                            clipboard.clear()
                        end,
                        g.text {
                            text = function() return if armed.value then "CLEAR ALL?" else "CLEAR" end,
                            color = function() return if armed.value then theme.alert() else theme.text() end,
                            font = typography.technical,
                            size = function() return m().font_meta end,
                            tracking = typography.label_tracking,
                        },
                    },
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
                        present = function() return #shown() == 0 end,
                        g.text {
                            text = function() return if #clipboard.entries() == 0 then "Nothing copied yet" else "Nothing like that" end,
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
                            items = shown,
                            key = function(e: any) return tostring(e.hash) end,
                            row = row,
                        },
                        scroll.bar(function() return inner() - 19 * f() end),
                    },
                },
            }
        end

        local function glyph_node(size: () -> number): any
            return g.icon {
                width = size,
                height = size,
                icon = "clipboard",
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            }
        end

        return {
            panel = {
                width = panel_width,
                height = function() return m().field_height + 10 * f() + list_height() + 20 * f() end,
                content = content,
            },
            -- Escape empties the filter first; Up and Down choose; Return
            -- puts the chosen one back.
            on_key = function(name: string, typed: string?, mods: { [string]: boolean }): boolean
                if name == "Escape" and g.untracked(function() return query.value end) ~= "" then
                    field_handle.set("")
                    return true
                end
                if name == "Escape" then return false end
                if name == "Down" or name == "Up" then
                    local n = #g.untracked(shown)
                    local now = g.untracked(function() return chosen.value end)
                    chosen.value = math.clamp(now + (if name == "Down" then 1 else -1), 1, math.max(1, n))
                    local at = 0
                    local list = g.untracked(shown)
                    for i = 1, chosen.value - 1 do at += height_of(list[i]) end
                    scroll.reveal(at, height_of(list[chosen.value] or {}))
                    return true
                end
                return field_handle.key(name, typed, mods)
            end,
            padding_leading = function() return (m().cell_height - glyph()) / 2 end,
            padding_trailing = function() return (m().cell_height - glyph()) / 2 end,
            condition = function() return if cell.pulsing() then 1 else 0 end,
            content_width = glyph,
            header_title = "CLIPBOARD",
            header_mark_size = glyph,
            header_mark = glyph_node,
            contracted = function() return glyph_node(glyph) end,
        }
    end,
}
