--!strict
-- Bioma's own settings, and nothing else's (cells/settings/SettingsCell.qml
-- and SettingsExpansion.qml at 11bb81e). See docs/design/CELLS.md §12,
-- PRD §9.12.
--
-- Not a control panel: anything that has a cell of its own does not come
-- back here as a category. At rest it is the mark, and this is the only
-- place the mark appears.
--
-- Opened, the categories on one side and the chosen one on the other, with
-- a thread between them. The selection is the thread: the chosen capsule is
-- the one the thread leaves from, and the others stay identical. The page
-- is one height and one width for every category (the widest), so the
-- column never moves under a pointer running down it.
--
-- On Genoma the page is the panel that buds from the cell and the
-- categories hang to its left, a stagger apart, as the vitals' pods hang
-- from theirs; the cell's thread always lands on the page.
--
-- Ported so far: the frame and the Sounds page. The others say "Not built
-- yet", as Quickshell's did for a category whose page was still to come.
-- Not yet: the setup's steps (docs/design/SETUP.md), keyboard travel down
-- the column.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local thread_mod = require("components/thread")
local scroller_mod = require("components/scroller")

-- Each says how wide its page needs to be, logical units at the normal step.
local CATEGORIES = {
    { key = "structure", label = "STRUCTURE", glyph = "structure", hint = "membranes, tissues, order", width = 644 },
    { key = "cells", label = "CELLS", glyph = "cells", hint = "options and visibility", width = 560 },
    { key = "organisms", label = "ORGANISMS", glyph = "organisms", hint = "on the desktop, by hand", width = 560 },
    { key = "appearance", label = "APPEARANCE", glyph = "appearance", hint = "opacity, blur, radius, scale", width = 440 },
    { key = "monitors", label = "MONITORS", glyph = "monitors", hint = "position, scale, snapping", width = 720 },
    { key = "keybinds", label = "KEYBINDS", glyph = "keyboard", hint = "shortcuts · niri.kdl", width = 560 },
    { key = "niri", label = "NIRI", glyph = "window", hint = "gaps, workspaces, rules", width = 600 },
    { key = "session", label = "SESSION", glyph = "lock", hint = "locking, power profile", width = 540 },
    { key = "sounds", label = "SOUNDS", glyph = "sounds", hint = "events, volume", width = 540 },
    { key = "performance", label = "PERFORMANCE", glyph = "performance", hint = "lean mode, its triggers", width = 560 },
    { key = "actions", label = "ACTIONS", glyph = "actions", hint = "the ring at the pointer", width = 600 },
}

-- The pages written on Genoma so far, by category.
local PAGES = {
    sounds = "cells/settings_sounds",
}

-- Which category is being looked at, kept across a close and on every
-- screen (cells/SettingsPlace.qml).
local place = { category = nil :: string? }

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function mark_size(): number return 20 * f() end
        local function capsule_width(): number return 240 * f() end
        local function capsule_height(): number return 64 * f() end
        local function pitch(): number return 76 * f() end
        local function glyph_size(): number return 26 * f() end
        local function padding(): number return 14 * f() end

        local chosen = g.signal(place.category or CATEGORIES[1].key)
        local function choose(key: string)
            place.category = key
            chosen.value = key
        end
        local function chosen_index(): number
            for i, c in CATEGORIES do
                if c.key == chosen.value then return i end
            end
            return 1
        end

        local function page_width(): number
            local widest = 0
            for _, c in CATEGORIES do widest = math.max(widest, c.width) end
            return widest * f()
        end
        local function column_height(): number return #CATEGORIES * pitch() - (pitch() - capsule_height()) end
        -- One height for every category, and never shorter than the column.
        local function page_height(): number return math.max(620 * f(), column_height()) end
        local function gap(): number return m().gap end
        local function inner_width(): number return page_width() - padding() * 2 end
        local function inner_height(): number return page_height() - padding() * 2 end

        -- ---- The page ------------------------------------------------------------

        local pages: { [string]: any } = {}
        local function page_of(key: string): any
            if pages[key] == nil then
                local path = PAGES[key]
                pages[key] = if path then require(path) else false
            end
            return pages[key] or nil
        end

        -- The page scrolls inside the fixed height if a scale or a font ever
        -- makes it taller.
        local content_height = g.signal(0)
        local scroll = scroller_mod.new {
            viewport = inner_height,
            content = function() return content_height.value end,
            step = function() return 40 * f() end,
            factor = f,
        }

        local function body(): any
            return g.box {
                width = inner_width,
                height = inner_height,
                g.text {
                    overlay = true,
                    present = function() return page_of(chosen.value) == nil end,
                    text = "Not built yet",
                    color = theme.text_faint,
                    font = typography.expressive,
                    size = function() return m().font_title end,
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    width = inner_width,
                    height = inner_height,
                    clip = true,
                    scroll_y = scroll.offset,
                    transition = { scroll_y = "reflow" },
                    on_wheel = scroll.wheel,
                    g.each {
                        overlay = true,
                        attach = "corner",
                        width = function() return inner_width() - 8 * f() end,
                        items = function()
                            return if page_of(chosen.value) then { chosen.value } else {}
                        end,
                        key = function(k: string) return k end,
                        row = function(k: () -> string)
                            local page = page_of(g.untracked(k))
                            return page.new {
                                metrics = m,
                                width = function() return inner_width() - 8 * f() end,
                                height = inner_height,
                            }
                        end,
                    },
                    scroll.bar(function() return inner_width() - 7 * f() end),
                },
            }
        end

        -- ---- The categories ------------------------------------------------------

        local function satellite(index: number): any
            local c = CATEGORIES[index]
            local function is_chosen(): boolean return chosen.value == c.key end
            local function curve(): string
                return if cell.open.value then "cascade_" .. math.min(index, 12) else "cascade_close"
            end
            local hovered = g.signal(false)
            return g.capsule {
                name = c.label,
                role = "button",
                overlay = true,
                attach = "left",
                width = capsule_width,
                height = capsule_height,
                radius = function() return metrics_mod.radius_for(capsule_height(), m()) end,
                offset_x = function() return if cell.open.value then -gap() else 0 end,
                offset_y = function()
                    local centre = (index - 1) * pitch() + capsule_height() / 2
                    return centre - column_height() / 2
                end,
                growth = function() return if cell.open.value then 1 else 0 end,
                direction = "row",
                align = "center",
                justify = "start",
                padding_left = function() return 21 * f() end,
                padding_right = function() return 20 * f() end,
                gap = function() return 16 * f() end,
                fill = function()
                    local base = if hovered.value and not is_chosen() then theme.lift(theme.cell(), 0.05) else theme.cell()
                    return colour.alpha(base, require("core/config").get("cell.opacity", 0.72))
                end,
                rim_top = theme.rim,
                rim_bottom = theme.line,
                blur = require("core/performance").blurred,
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function() choose(c.key) end,
                transition = { growth = curve, offset_x = curve, fill = "colour" },
                -- The chosen one carries more light: the glyph the primary
                -- gradient, the name the primary.
                g.icon {
                    width = glyph_size,
                    height = glyph_size,
                    icon = c.glyph,
                    gradient_top = function() return if is_chosen() then theme.gradient_top(theme.primary()) else theme.text_muted() end,
                    gradient_bottom = function() return if is_chosen() then theme.gradient_bottom(theme.primary()) else theme.text_muted() end,
                },
                g.box {
                    direction = "column",
                    align = "start",
                    gap = function() return 3 * f() end,
                    opacity = function() return if cell.open.value then 1 else 0 end,
                    transition = { opacity = function() return if cell.open.value then "content_enter" else "content_leave" end },
                    g.text {
                        text = c.label,
                        color = function() return if is_chosen() then theme.primary() else theme.text() end,
                        font = typography.technical,
                        size = function() return m().font_label end,
                        weight = function() return if is_chosen() then typography.weight_title else typography.weight_label end,
                        tracking = typography.label_tracking,
                    },
                    -- What is inside is said in words: the human voice.
                    g.text {
                        text = c.hint,
                        color = theme.text_muted,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return capsule_width() - 21 * f() - 20 * f() - glyph_size() - 16 * f() end,
                    },
                },
            }
        end

        -- The thread leaves the chosen capsule and feeds the page: it moves
        -- when the choice does, which is the whole of the selection.
        local function link(): any
            return thread_mod.new {
                vertical = false,
                overlay = true,
                attach = "left",
                length = gap,
                offset_y = function()
                    local centre = (chosen_index() - 1) * pitch() + capsule_height() / 2
                    return centre - column_height() / 2
                end,
                shown = function() return cell.open.value end,
                timing = function() return "cascade_" .. math.min(#CATEGORIES + 1, 12) end,
                closing = function() return "thread_close" end,
            }
        end

        local function mark(size: () -> number): any
            return g.icon {
                width = size,
                height = size,
                icon = "mark",
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            }
        end

        return {
            panel = {
                width = page_width,
                height = page_height,
                lead = function() return capsule_width() + gap() end,
                content = body,
                satellites = function()
                    local out = {}
                    for i = 1, #CATEGORIES do table.insert(out, satellite(i)) end
                    table.insert(out, link())
                    return out
                end,
            },
            padding_leading = function() return (m().cell_height - mark_size()) / 2 end,
            padding_trailing = function() return (m().cell_height - mark_size()) / 2 end,
            content_width = mark_size,
            header_title = "SETTINGS",
            header_mark_size = mark_size,
            header_mark = mark,
            contracted = function() return mark(mark_size) end,
        }
    end,
}
