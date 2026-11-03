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
-- Every category has its page. Not yet: the setup's steps
-- (docs/design/SETUP.md), keyboard travel down the column.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local thread_mod = require("components/thread")
local scroller_mod = require("components/scroller")
local choice_mod = require("components/choice")
local setup = require("services/setup")

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
    actions = "cells/settings_actions",
    appearance = "cells/settings_appearance",
    cells = "cells/settings_cells",
    keybinds = "cells/settings_keybinds",
    monitors = "cells/settings_monitors",
    niri = "cells/settings_niri",
    organisms = "cells/settings_organisms",
    performance = "cells/settings_performance",
    session = "cells/settings_session",
    sounds = "cells/settings_sounds",
    structure = "cells/settings_structure",
}

-- Which category is being looked at, kept across a close and on every
-- screen (cells/SettingsPlace.qml).
-- BIOMA_GENOMA_SETTINGS=<key> opens on that category, to look at a page
-- without pressing anything on a desktop someone is using.
-- Kept across reloads too, so a settings cell opened again after a monitor
-- came or went is on the page it was left on (structure/focus.luau).
local place = g.state("settings.category", g.env("BIOMA_GENOMA_SETTINGS") or "")
-- A category asked for from outside (`actions write`): every settings cell
-- turns to it, open or not.
local asked = g.signal("")

return {
    -- The next time settings is looked at, it is on this category.
    open_on = function(category: string)
        place.value = category
        asked.value = ""
        asked.value = category
    end,
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function mark_size(): number return 20 * f() end
        local function capsule_width(): number return 240 * f() end
        local function capsule_height(): number return 64 * f() end
        local function pitch(): number return 76 * f() end
        local function glyph_size(): number return 26 * f() end
        local function padding(): number return 14 * f() end

        local chosen = g.signal((function()
            local kept = g.untracked(function() return place.value end)
            return if kept ~= "" then kept else CATEGORIES[1].key
        end)())
        -- While the setup is under way on this screen the same composition
        -- holds its steps instead (SettingsExpansion.qml): the capsules are
        -- the steps, each line saying what was chosen once it is, and the
        -- page ends in BACK and NEXT. A wizard with a window of its own
        -- would be the one part of the shell not speaking its language.
        local function in_setup(): boolean return setup.active() and setup.output() == cell.output end
        local function entries(): { any } return if in_setup() then setup.steps() else CATEGORIES end
        local function current(): string return if in_setup() then setup.step() else chosen.value end
        -- Closed under the setup (Escape, a press outside): later. Only a
        -- close counts: a cell built closed (a reload, reopening it next)
        -- is not one.
        local was_open = false
        g.watch(function() return cell.open.value end, function(open: boolean)
            if not open and was_open and not cell.aside and g.untracked(in_setup) then setup.closed() end
            was_open = open
        end)
        -- A new choice draws the thread out again from its origin, at the
        -- new capsule, rather than moving it there whole (Akusen, 2026-11-02):
        -- taken away at once, then grown in the next turn.
        local redrawing = g.signal(false)
        -- Whether the thread last grew for a choice, not for the opening:
        -- the opening keeps its place in the cascade.
        local rechosen = g.signal(false)
        g.watch(function() return cell.open.value end, function(open: boolean)
            if not open then rechosen.value = false end
        end)
        local function choose(key: string)
            local setting_up = g.untracked(in_setup)
            if g.untracked(current) == key then return end
            if not setting_up then place.value = key end
            g.batch(function()
                redrawing.value = true
                rechosen.value = true
                if setting_up then setup.go(key) else chosen.value = key end
            end)
            g.after(0, function() redrawing.value = false end)
        end
        -- Asked from outside: the page is turned before the cell opens.
        g.watch(function() return asked.value end, function(key: string)
            if key ~= "" and not g.untracked(in_setup) then chosen.value = key end
        end)
        -- The setup's BACK and NEXT draw the thread out again as a press does.
        g.watch(setup.step, function()
            if not g.untracked(in_setup) then return end
            g.batch(function()
                redrawing.value = true
                rechosen.value = true
            end)
            g.after(0, function() redrawing.value = false end)
        end)
        local function chosen_index(): number
            for i, c in entries() do
                if c.key == current() then return i end
            end
            return 1
        end

        local function page_width(): number
            local widest = 0
            for _, c in entries() do widest = math.max(widest, c.width) end
            return widest * f()
        end
        local function column_height(): number return #entries() * pitch() - (pitch() - capsule_height()) end
        -- One height for every category, and never shorter than the column.
        local function page_height(): number return math.max(620 * f(), column_height()) end
        local function gap(): number return m().gap end
        local function inner_width(): number return page_width() - padding() * 2 end
        local function inner_height(): number return page_height() - padding() * 2 end

        -- ---- The page ------------------------------------------------------------

        local pages: { [string]: any } = {}
        -- A page that types (a field, a search) hands its keys handler here
        -- through `keyed`; the open page's has the keys.
        local page_keys: { [string]: any } = {}
        -- A setup step's page is `cells/setup_<key>`, keyed `setup:<key>`.
        local function page_of(key: string): any
            if pages[key] == nil then
                local step = string.match(key, "^setup:(.+)$")
                local path = if step then "cells/setup_" .. step else PAGES[key]
                pages[key] = if path then require(path) else false
            end
            return pages[key] or nil
        end
        local function page_key(): string return if in_setup() then "setup:" .. setup.step() else chosen.value end

        -- The page scrolls inside the fixed height when it is taller: its
        -- height is the layout's, told through on_size.
        local content_height = g.signal(0)
        local skip_hovered = g.signal(false)
        -- In the setup the page ends in its way through.
        local function footer_height(): number return 26 * f() end
        local function page_area(): number
            return inner_height() - (if in_setup() then footer_height() + padding() else 0)
        end
        local scroll = scroller_mod.new {
            viewport = page_area,
            content = function() return content_height.value end,
            step = function() return 40 * f() end,
            factor = f,
        }
        -- Each page is read from its top, as each had its own list.
        g.watch(page_key, function() scroll.home() end)

        local function body(): any
            return g.box {
                width = inner_width,
                height = inner_height,
                g.text {
                    overlay = true,
                    present = function() return page_of(page_key()) == nil end,
                    text = "Not built yet",
                    color = theme.text_faint,
                    font = typography.expressive,
                    size = function() return m().font_title end,
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    width = inner_width,
                    height = page_area,
                    clip = true,
                    scroll_y = scroll.offset,
                    transition = { scroll_y = "reflow" },
                    on_wheel = scroll.wheel,
                    g.each {
                        overlay = true,
                        attach = "corner",
                        width = function() return inner_width() - 8 * f() end,
                        items = function()
                            return if page_of(page_key()) then { page_key() } else {}
                        end,
                        key = function(k: string) return k end,
                        on_size = function(_: number, h: number) content_height.value = h end,
                        row = function(k: () -> string)
                            local key = g.untracked(k)
                            local page = page_of(key)
                            page_keys[key] = nil
                            -- Fixed by what the page is, not by the mode: a
                            -- page leaving as the setup starts would measure
                            -- itself again on its way out.
                            local stepping = string.sub(key, 1, 6) == "setup:"
                            local function list(): { any } return if stepping then setup.steps() else CATEGORIES end
                            local function width(): number
                                local widest = 0
                                for _, c in list() do widest = math.max(widest, c.width) end
                                return widest * f() - padding() * 2 - 8 * f()
                            end
                            local function height(): number
                                local column = #list() * pitch() - (pitch() - capsule_height())
                                return math.max(620 * f(), column) - padding() * 2
                                    - (if stepping then footer_height() + padding() else 0)
                            end
                            return page.new {
                                metrics = m,
                                width = width,
                                height = height,
                                keyed = function(handler: any) page_keys[key] = handler end,
                                output = cell.output,
                            }
                        end,
                    },
                    -- On the page's right edge, as Scroller.qml: the rows
                    -- end 8 short of it, so it stands clear of them.
                    scroll.bar(function() return inner_width() - 3 * f() end),
                },
                -- The setup's way through: SKIP SETUP at the start, BACK and
                -- NEXT at the end, DONE in NEXT's place on the last step. The
                -- capsules can be pressed in any order, so NEXT is a
                -- convenience, not a gate.
                g.box {
                    overlay = true,
                    attach = "corner",
                    present = in_setup,
                    offset_y = function() return inner_height() - footer_height() end,
                    width = inner_width,
                    height = footer_height,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    g.box {
                        role = "button",
                        name = "Skip setup",
                        height = footer_height,
                        align = "center",
                        on_hover = function(on: boolean) skip_hovered.value = on end,
                        on_click = setup.finish,
                        g.text {
                            text = "SKIP SETUP",
                            color = function() return if skip_hovered.value then theme.primary() else theme.text() end,
                            font = typography.technical,
                            size = function() return m().font_meta end,
                            tracking = typography.label_tracking,
                        },
                    },
                    g.box {
                        direction = "row",
                        align = "center",
                        gap = function() return 8 * f() end,
                        -- Nothing comes before the welcome, so there is no
                        -- way back from it; the way forward is the start.
                        g.box {
                            present = function() return setup.step_index() > 1 end,
                            choice_mod.new { metrics = m, label = "BACK", on_click = setup.back },
                        },
                        choice_mod.new {
                            metrics = m,
                            label = function()
                                if setup.last() then return "DONE" end
                                return if setup.step_index() == 1 then "START" else "NEXT"
                            end,
                            kind = "primary",
                            on_click = function()
                                if g.untracked(setup.last) then setup.finish() else setup.next() end
                            end,
                        },
                    },
                },
            }
        end

        -- ---- The categories ------------------------------------------------------

        local function satellite(index: number): any
            local function c(): any return entries()[index] or CATEGORIES[1] end
            local function is_chosen(): boolean return current() == c().key end
            -- In the setup, what was chosen replaces what the step is about,
            -- and the glyph says whether the step wants attention.
            local function outcome(): string return if in_setup() then setup.outcome(c().key) else "" end
            local function state(): string return if in_setup() then setup.state_of(c().key) else "muted" end
            local function idle_ink(): string
                local st = state()
                if st == "alert" then return theme.alert() end
                if st == "active" then return theme.active() end
                return theme.text_muted()
            end
            local function curve(): string
                return if cell.open.value then "cascade_" .. math.min(index, 12) else "cascade_close"
            end
            local hovered = g.signal(false)
            -- Glyph and words once the capsule is at size, and first to go.
            local function shown(): number return if cell.open.value then 1 else 0 end
            local function content_curve(): string
                return if cell.open.value then "cascade_content_" .. math.min(index, 12) else "content_leave"
            end
            return g.capsule {
                name = "Category",
                role = "button",
                present = function() return index <= #entries() end,
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
                on_click = function() choose(g.untracked(c).key) end,
                -- Its travel out lands on a spring at its turn in the cascade;
                -- its budding only grows (core/timing.luau, motion).
                transition = {
                    growth = curve,
                    offset_x = function()
                        if not cell.open.value then return curve() end
                        local i = math.min(index, 12)
                        return timing.motion("cascade_land_" .. i, "cascade_" .. i)
                    end,
                    fill = "colour",
                },
                -- The chosen one carries more light: the glyph the primary
                -- gradient, the name the primary.
                g.icon {
                    width = glyph_size,
                    height = glyph_size,
                    icon = function() return c().glyph end,
                    opacity = shown,
                    transition = { opacity = content_curve },
                    gradient_top = function() return if is_chosen() then theme.gradient_top(theme.primary()) else idle_ink() end,
                    gradient_bottom = function() return if is_chosen() then theme.gradient_bottom(theme.primary()) else idle_ink() end,
                },
                g.box {
                    direction = "column",
                    align = "start",
                    gap = function() return 3 * f() end,
                    opacity = shown,
                    transition = { opacity = content_curve },
                    g.text {
                        text = function() return c().label end,
                        color = function() return if is_chosen() then theme.primary() else theme.text() end,
                        font = typography.technical,
                        size = function() return m().font_label end,
                        weight = function() return if is_chosen() then typography.weight_title else typography.weight_label end,
                        tracking = typography.label_tracking,
                    },
                    -- What is inside is said in words: the human voice.
                    g.text {
                        text = function() local o = outcome() return if o ~= "" then o else c().hint end,
                        color = function() return if outcome() ~= "" then theme.text() else theme.text_muted() end,
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
                shown = function() return cell.open.value and not redrawing.value end,
                timing = function()
                    return if rechosen.value then "grow" else "cascade_" .. math.min(#entries() + 1, 12)
                end,
                closing = function() return if cell.open.value then "instant" else "thread_close" end,
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
                    -- As many as the longer list: the setup's steps are fewer.
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
            on_key = function(name: string, typed: string?, mods: { [string]: boolean }): boolean
                local handler = page_keys[g.untracked(page_key)]
                return if handler then handler(name, typed, mods) == true else false
            end,
        }
    end,
}
