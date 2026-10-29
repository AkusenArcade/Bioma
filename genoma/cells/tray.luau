--!strict
-- The tray: what the running applications put there (cells/tray/
-- TrayCell.qml and TrayMenu.qml at 11bb81e).
--
-- Each item is its own application's icon, never tinted. A ring in the
-- alert says an item asks for attention; in the primary, whose menu is
-- open. A press activates it, or opens its menu when it is only a menu;
-- the right button opens the menu, the middle one is its second action,
-- the wheel scrolls it.
--
-- Conditional, it is there for a while after an item changes its status,
-- until the pointer has been on it.
--
-- Not yet: a long press on a touch screen; the keyboard's travel through
-- the menu.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local tray = require("services/tray")
local scroller_mod = require("components/scroller")

local CLEAR = "#00000000"
local LEFT, RIGHT, MIDDLE = 272, 273, 274
local SHOWN_ROWS = 10

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 18 * f() end
        local function spacing(): number return 12 * f() end

        -- An item whose status changed calls the cell up, until looked at.
        local calling = g.signal(false)
        local statuses: { [string]: string } = {}
        g.watch(function()
            local parts = {}
            for _, it in tray.items() do table.insert(parts, it.key .. "=" .. tostring(it.status)) end
            return table.concat(parts, "\n")
        end, function()
            local changed = false
            for _, it in g.untracked(tray.items) do
                if statuses[it.key] ~= nil and statuses[it.key] ~= it.status then changed = true end
                statuses[it.key] = it.status
            end
            if changed then calling.value = true end
        end)
        g.watch(function() return cell.hovered.value end, function(on: boolean) if on then calling.value = false end end)

        -- ---- The menu ---------------------------------------------------------------------

        local chosen = g.signal("") -- the item's key
        local trail = g.signal({}) -- the submenus entered, by id
        local function chosen_item(): any
            for _, it in tray.items() do
                if it.key == chosen.value then return it end
            end
            return nil
        end
        local function show(item: any)
            if not item or not item.has_menu then return end
            trail.value = {}
            chosen.value = item.key
            tray.open_menu(item)
            cell.open.value = true
        end
        g.watch(function() return cell.open.value end, function(open: boolean)
            if open then return end
            local it = g.untracked(chosen_item)
            if it then tray.close_menu(it) end
            chosen.value = ""
        end)
        local function press(item: any)
            if tray.opens(item) then show(item) else tray.activate(item) end
        end

        -- The level of the menu shown: the root, or the submenu last entered.
        local function level(): any
            local node = tray.menu(chosen_item())
            if not node then return nil end
            for _, id in trail.value do
                local found = nil
                for _, child in node.children or {} do
                    if child.id == id then found = child end
                end
                if not found then return node end
                node = found
            end
            return node
        end
        local function entries(): { any }
            local node = level()
            local out = {}
            for _, e in (if node then node.children else nil) or {} do
                if e.visible ~= false then table.insert(out, e) end
            end
            return out
        end
        local function heading(): string
            local t = trail.value
            if #t == 0 then return tray.name_of(chosen_item()) end
            local node = level()
            return if node then string.gsub(node.label or "", "_", "") else ""
        end
        local function back()
            local t = table.clone(g.untracked(function() return trail.value end))
            table.remove(t)
            trail.value = t
        end
        local function choose(e: any)
            if not e or e.separator or e.enabled == false then return end
            if e.children and #e.children > 0 then
                local t = table.clone(g.untracked(function() return trail.value end))
                table.insert(t, e.id)
                trail.value = t
                return
            end
            tray.click(g.untracked(chosen_item), e.id)
            cell.open.value = false
        end

        local function panel_width(): number return 240 * f() end
        local function pad(): number return 8 * f() end
        local function row_height(): number return 32 * f() end
        local function header_height(): number return 30 * f() end
        local function separator_height(): number return 9 * f() end
        local function height_of(e: any): number return if e.separator then separator_height() else row_height() end
        local function list_height(): number
            local h, n = 0, 0
            for _, e in entries() do
                n += 1
                if n > SHOWN_ROWS then break end
                h += height_of(e)
            end
            return math.max(h, row_height())
        end
        local function content_height(): number
            local h = 0
            for _, e in entries() do h += height_of(e) end
            return h
        end
        -- Inside the panel's own padding.
        local function panel_height(): number return 20 * f() + header_height() + list_height() + 8 * f() end
        local function inner(): number return panel_width() - 20 * f() end

        local scroll = scroller_mod.new {
            viewport = list_height,
            content = content_height,
            step = row_height,
            factor = f,
        }
        g.watch(function() return #trail.value .. chosen.value end, function() scroll.to(0) end)

        -- A menu's labels mark their mnemonic with an underscore.
        local function label(e: any): string return (string.gsub(e.label or "", "_(.)", "%1")) end

        local function entry_row(item: () -> any, index: () -> number): any
            local function e(): any return item() end
            local function y(): number
                local at = 0
                for i, other in entries() do
                    if i >= index() then break end
                    at += height_of(other)
                end
                return at
            end
            local function usable(): boolean return not e().separator and e().enabled ~= false end
            local function has_children(): boolean return e().children ~= nil and #e().children > 0 end
            local function checked(): boolean return e().toggle_type ~= "" and e().toggle_state == 1 end
            local hovered = g.signal(false)
            return g.capsule {
                role = "button",
                name = "Menu entry",
                overlay = true,
                attach = "corner",
                offset_x = function() return 4 * f() end,
                offset_y = y,
                width = function() return inner() - 8 * f() - 2 * f() end,
                height = function() return height_of(e()) end,
                radius = function() return metrics_mod.radius_for(row_height(), m()) end,
                direction = "row",
                align = "center",
                justify = "between",
                padding_x = function() return 8 * f() end,
                fill = function()
                    return if hovered.value and usable() then colour.alpha(theme.primary(), 0.12) else CLEAR
                end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function() choose(g.untracked(e)) end,
                -- A separator is a hairline across the row.
                g.capsule {
                    overlay = true,
                    present = function() return e().separator == true end,
                    width = function() return inner() - 20 * f() end,
                    height = 1,
                    crisp = true,
                    radius = 0,
                    fill = theme.line,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                },
                g.box {
                    present = function() return not e().separator end,
                    direction = "row",
                    align = "center",
                    gap = function() return 6 * f() end,
                    g.capsule {
                        present = checked,
                        width = function() return 7 * f() end,
                        height = function() return 7 * f() end,
                        fill = theme.primary,
                        rim_top = CLEAR,
                        rim_bottom = CLEAR,
                    },
                    g.text {
                        text = function() return label(e()) end,
                        color = function() return if usable() then theme.text() else theme.text_faint() end,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return inner() - 50 * f() end,
                    },
                },
                g.icon {
                    present = function() return not e().separator and has_children() end,
                    width = function() return 12 * f() end,
                    height = function() return 12 * f() end,
                    icon = "chevron-right",
                    gradient_top = theme.text_muted,
                    gradient_bottom = theme.text_muted,
                },
            }
        end

        local function menu(): any
            local back_hovered = g.signal(false)
            return g.box {
                direction = "column",
                width = inner,
                -- The heading: the item, or the submenu, with the way back.
                g.box {
                    role = "button",
                    name = "Back",
                    width = inner,
                    height = header_height,
                    direction = "row",
                    align = "center",
                    gap = function() return 8 * f() end,
                    padding_left = function() return 2 * f() end,
                    on_hover = function(on: boolean) back_hovered.value = on end,
                    on_click = function() if #g.untracked(function() return trail.value end) > 0 then back() end end,
                    -- The way back.
                    g.icon {
                        present = function() return #trail.value > 0 end,
                        width = function() return 14 * f() end,
                        height = function() return 14 * f() end,
                        icon = "chevron-left",
                        gradient_top = function() return if back_hovered.value then theme.primary() else theme.text() end,
                        gradient_bottom = function() return if back_hovered.value then theme.primary() else theme.text() end,
                    },
                    g.text {
                        text = heading,
                        color = theme.text,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return inner() - 30 * f() end,
                    },
                },
                g.capsule {
                    width = inner,
                    height = function() return list_height() + 8 * f() end,
                    radius = function() return metrics_mod.inner_radius(m().radius_panel, pad()) end,
                    fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                    g.box {
                        overlay = true,
                        attach = "corner",
                        offset_y = function() return 4 * f() end,
                        width = inner,
                        height = list_height,
                        clip = true,
                        scroll_y = scroll.offset,
                        transition = { scroll_y = "reflow" },
                        on_wheel = scroll.wheel,
                        g.each {
                            overlay = true,
                            attach = "corner",
                            width = inner,
                            items = entries,
                            key = function(e: any) return e.id end,
                            row = entry_row,
                        },
                        scroll.bar(function() return inner() - 7 * f() end),
                    },
                },
            }
        end

        -- ---- At rest ---------------------------------------------------------------------

        local function item_node(item: () -> any): any
            local function it(): any return item() end
            local function source(): string return tray.icon_for(it()) end
            local function ringed(): boolean return tray.attending(it()) or chosen.value == it().key end
            return g.box {
                role = "button",
                name = "Tray item",
                width = glyph,
                height = glyph,
                align = "center",
                justify = "center",
                on_click = function(button: number)
                    local now = g.untracked(it)
                    if button == LEFT then press(now)
                    elseif button == RIGHT then show(now)
                    elseif button == MIDDLE then tray.secondary(now) end
                end,
                on_wheel = function(_: number, dy: number)
                    tray.scroll(g.untracked(it), if dy < 0 then 1 else -1)
                end,
                g.capsule {
                    overlay = true,
                    present = ringed,
                    width = function() return glyph() + 8 * f() end,
                    height = function() return glyph() + 8 * f() end,
                    stroke = function() return 1.5 * f() end,
                    rim_top = function() return if tray.attending(it()) then theme.alert() else theme.primary() end,
                    rim_bottom = function() return if tray.attending(it()) then theme.alert() else theme.primary() end,
                },
                g.icon {
                    present = function() return source() ~= "" end,
                    width = glyph,
                    height = glyph,
                    icon = function() local s = source() return if s ~= "" then s else "app-fallback" end,
                },
                g.icon {
                    present = function() return source() == "" end,
                    width = glyph,
                    height = glyph,
                    icon = "app-fallback",
                    gradient_top = theme.text_muted,
                    gradient_bottom = theme.text_muted,
                },
            }
        end

        return {
            panel = {
                width = panel_width,
                height = panel_height,
                content = menu,
            },
            -- Its presses are the items'; the pill itself opens nothing.
            on_click = function() end,
            padding_leading = function() return (m().cell_height - glyph()) / 2 + 2 * f() end,
            padding_trailing = function() return (m().cell_height - glyph()) / 2 + 2 * f() end,
            condition = function() return if calling.value then 1 else 0 end,
            content_width = function()
                local n = tray.count()
                return math.max(glyph(), n * glyph() + math.max(0, n - 1) * spacing())
            end,
            replaces_content = false,
            contracted = function()
                return g.each {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    items = tray.items,
                    key = function(it: any) return it.key end,
                    row = item_node,
                }
            end,
        }
    end,
}
