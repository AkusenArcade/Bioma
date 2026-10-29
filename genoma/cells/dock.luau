--!strict
-- The applications kept at hand and the ones open (cells/dock/Dock.qml at
-- 11bb81e). See docs/design/CELLS.md §09.
--
-- Kept ones first, in the order chosen, then a hairline, then what is open
-- and not kept. A ring of the primary round an icon says it is running. A
-- press focuses it (again: the next of its windows) or starts it; the
-- middle button always starts another; the right one keeps or lets go. A
-- kept icon is dragged along the row to reorder, the others making room.
--
-- Conditional, it is there while the desktop shows: on an empty workspace.
--
-- Not yet: a long press on a touch screen keeping an icon (Genoma's touch
-- input has not come).
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local apps = require("core/apps")
local niri = require("services/niri")
local proxy = require("services/proxy")
local focus = require("structure/focus")

local CLEAR = "#00000000"
local LEFT, RIGHT, MIDDLE = 272, 273, 274

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function icon_size(): number return 28 * f() end
        local function pitch(): number return 10 * f() end
        local function divider_room(): number return 1 + 12 * f() end
        local function step(): number return icon_size() + pitch() end
        local function inner(): number return icon_size() - 2 * math.floor(icon_size() * 0.19 + 0.5) end

        local function pinned(): { string } return config.get("dock.pinned", {}) end

        -- Two names for one application are one application: the window's
        -- id and the desktop entry's.
        local function same_app(a: string?, b: string?): boolean
            if not a or not b or a == "" or b == "" then return false end
            if string.lower(a) == string.lower(b) then return true end
            local left, right = apps.entry_for(a), apps.entry_for(b)
            return left ~= nil and right ~= nil and left == right
        end
        local function is_pinned(app_id: string): boolean
            for _, id in pinned() do
                if same_app(id, app_id) then return true end
            end
            return false
        end

        -- The open applications, each with its windows, in the order first seen.
        local running = g.computed(function(): { any }
            local out, seen = {}, {}
            local list = {}
            for _, w in niri.windows() do table.insert(list, w) end
            table.sort(list, function(a, b) return a.id < b.id end)
            for _, w in list do
                if w.app_id ~= "" then
                    if seen[w.app_id] then
                        table.insert(out[seen[w.app_id]].windows, w)
                    else
                        table.insert(out, { app_id = w.app_id, windows = { w } })
                        seen[w.app_id] = #out
                    end
                end
            end
            return out
        end)
        local function windows_of(app_id: string): { any }
            for _, group in running.value do
                if same_app(group.app_id, app_id) then return group.windows end
            end
            return {}
        end
        local loose = g.computed(function(): { any }
            local out = {}
            for _, group in running.value do
                if not is_pinned(group.app_id) then table.insert(out, group) end
            end
            return out
        end)

        local function with_launcher(): boolean return config.get("dock.launcher", false) == true end
        local function app_count(): number return #pinned() + #loose.value end
        local function count(): number return app_count() + (if with_launcher() then 1 else 0) end
        local function divided(): boolean return #pinned() > 0 and #loose.value > 0 end
        local function launcher_divided(): boolean return with_launcher() and app_count() > 0 end

        local function desktop_showing(): boolean
            local ws = niri.active_workspace_for_output(cell.output)
            return ws ~= nil and #niri.windows_on_workspace(ws.id) == 0
        end

        -- ---- What a press does ------------------------------------------------------------

        local function launch(app_id: string)
            local entry = apps.entry_for(app_id)
            if not entry then
                print('Bioma: the dock has no desktop entry for "' .. app_id .. '"')
                return
            end
            apps.run(entry, g.untracked(proxy.environment))
        end
        -- Each press moves to the next of its windows.
        local rounds: { [string]: number } = {}
        local function activate(app_id: string)
            local windows = g.untracked(function() return windows_of(app_id) end)
            if #windows == 0 then
                launch(app_id)
                return
            end
            local nxt = ((rounds[app_id] or 0) % #windows) + 1
            rounds[app_id] = nxt
            niri.focus_window(windows[nxt].id)
        end
        local function keep(app_id: string)
            local entry = apps.entry_for(app_id)
            local id = if entry and entry.id then entry.id else app_id
            if g.untracked(function() return is_pinned(id) end) then return end
            local next = g.array()
            for _, p in g.untracked(pinned) do table.insert(next, p) end
            table.insert(next, id)
            config.set("dock.pinned", next)
        end
        local function unkeep(app_id: string)
            local next = g.array()
            for _, p in g.untracked(pinned) do
                if not same_app(p, app_id) then table.insert(next, p) end
            end
            config.set("dock.pinned", next)
        end

        -- ---- Reordering -----------------------------------------------------------------
        --
        -- The icon held follows the pointer; the slot it would drop into is
        -- the nearest, and the icons between move over to make it.
        local held = g.signal(-1)
        local gap_at = g.signal(-1)
        local grip = g.signal(0)
        local grab_offset = 0
        local function dragging(): boolean return held.value >= 0 end
        local function slot_x(i: number): number return (i - 1) * step() end
        local function held_x(): number return grip.value - grab_offset end
        local function resting_x(i: number): number
            local h, gp = held.value, gap_at.value
            if h < 0 or i == h then return slot_x(i) end
            if h < gp and i > h and i <= gp then return slot_x(i - 1) end
            if h > gp and i >= gp and i < h then return slot_x(i + 1) end
            return slot_x(i)
        end
        local function take(i: number, x: number)
            g.batch(function()
                held.value = i
                gap_at.value = i
                grip.value = x
            end)
            grab_offset = x - slot_x(i)
        end
        local function drag(x: number)
            if not g.untracked(dragging) then return end
            grip.value = x
            local n = #g.untracked(pinned)
            gap_at.value = math.clamp(math.floor(g.untracked(held_x) / g.untracked(step) + 0.5) + 1, 1, n)
        end
        local function release()
            local from, to = g.untracked(function() return held.value end), g.untracked(function() return gap_at.value end)
            g.batch(function()
                held.value = -1
                gap_at.value = -1
            end)
            if from < 0 or to < 0 or from == to then return end
            local next = g.array()
            for _, p in g.untracked(pinned) do table.insert(next, p) end
            local moved = table.remove(next, from)
            table.insert(next, to, moved)
            config.set("dock.pinned", next)
        end

        -- ---- The name, while the pointer is on an icon ----------------------------------------
        local named = g.signal("")
        local named_centre = g.signal(0)
        local function label_of(app_id: string): string
            local entry = apps.entry_for(app_id)
            return if entry and entry.name and entry.name ~= "" then entry.name else app_id
        end

        -- ---- Pieces ------------------------------------------------------------------------

        -- An icon in its well; a ring of the primary while it runs.
        local function dock_icon(t: { [string]: any }): any
            local function size(): number
                return if t.held and t.held() then icon_size() * 1.12 else icon_size()
            end
            local function source(): string return apps.icon_for(t.app_id()) end
            local pressed_at: number? = nil
            local moved = false
            return g.capsule {
                role = "button",
                name = "Application",
                overlay = t.x ~= nil,
                attach = if t.x ~= nil then "corner" else nil,
                offset_x = if t.x then function() return t.x() - (size() - icon_size()) / 2 end else nil,
                offset_y = function() return (icon_size() - size()) / 2 end,
                width = size,
                height = size,
                align = "center",
                justify = "center",
                fill = function() return theme.lift(theme.background(), -0.015) end,
                rim_top = function() return colour.alpha(theme.text(), 0.35) end,
                rim_bottom = function() return colour.alpha(theme.text(), 0.35) end,
                transition = {
                    width = "transition",
                    height = "transition",
                    offset_x = function() return if t.held and t.held() then "instant" else "reflow" end,
                },
                on_hover = function(on: boolean)
                    local label = label_of(g.untracked(t.app_id))
                    if on then
                        named.value = label
                        named_centre.value = t.centre()
                    elseif g.untracked(function() return named.value end) == label then
                        named.value = ""
                    end
                end,
                on_press = function(button: number, x: number)
                    moved = false
                    pressed_at = if button == LEFT then x else nil
                end,
                on_drag = function(x: number)
                    if not t.holdable or pressed_at == nil then return end
                    local row_x = g.untracked(t.x) + x
                    if not moved and math.abs(x - pressed_at) > 6 then
                        moved = true
                        take(t.index(), g.untracked(t.x) + pressed_at)
                    end
                    if moved then drag(row_x) end
                end,
                on_release = function()
                    if moved then release() end
                end,
                on_click = function(button: number)
                    if moved then moved = false return end
                    local id = g.untracked(t.app_id)
                    if button == LEFT then activate(id)
                    elseif button == MIDDLE then launch(id)
                    elseif button == RIGHT then t.on_toggle(id) end
                end,
                -- Running: the ring.
                g.capsule {
                    overlay = true,
                    present = t.running,
                    width = size,
                    height = size,
                    stroke = function() return 1.5 * f() end,
                    rim_top = theme.primary,
                    rim_bottom = theme.primary,
                },
                -- An application's icon is the application's, never tinted.
                g.icon {
                    present = function() return source() ~= "" end,
                    width = inner,
                    height = inner,
                    icon = function() local s = source() return if s ~= "" then s else "app-fallback" end,
                },
                g.icon {
                    present = function() return source() == "" end,
                    width = inner,
                    height = inner,
                    icon = "app-fallback",
                    gradient_top = theme.text_muted,
                    gradient_bottom = theme.text_muted,
                },
            }
        end

        local function divider(present: () -> boolean): any
            return g.box {
                present = present,
                width = function() return divider_room() - pitch() end,
                height = icon_size,
                align = "center",
                justify = "center",
                g.capsule {
                    width = 1,
                    height = function() return 22 * f() end,
                    crisp = true,
                    radius = 0,
                    fill = theme.line,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                },
            }
        end

        -- Where an icon's centre is in the cell's content, for its name.
        local function launcher_room(): number
            return if with_launcher() then icon_size() + pitch() + (if launcher_divided() then divider_room() else 0) else 0
        end
        local function kept_width(): number return math.max(0, #pinned() * step() - pitch()) end

        local function contracted(): any
            return g.box {
                direction = "row",
                align = "center",
                gap = pitch,
                -- The hint, with nothing in it.
                g.box {
                    present = function() return count() == 0 end,
                    g.text {
                        text = "Launch an app and right click on the icon to pin it",
                        color = theme.text_muted,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                    },
                },
                -- The launcher, when asked for.
                g.capsule {
                    role = "button",
                    name = "Launcher",
                    present = with_launcher,
                    width = icon_size,
                    height = icon_size,
                    align = "center",
                    justify = "center",
                    fill = function() return theme.lift(theme.background(), -0.015) end,
                    rim_top = function() return colour.alpha(theme.text(), 0.35) end,
                    rim_bottom = function() return colour.alpha(theme.text(), 0.35) end,
                    on_hover = function(on: boolean)
                        if on then
                            named.value = "Launcher"
                            named_centre.value = icon_size() / 2
                        elseif g.untracked(function() return named.value end) == "Launcher" then
                            named.value = ""
                        end
                    end,
                    on_click = function() focus.invoke("launcher", cell.output) end,
                    g.icon {
                        width = inner,
                        height = inner,
                        icon = "launcher",
                        gradient_top = function() return theme.gradient_top(theme.primary()) end,
                        gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    },
                },
                divider(launcher_divided),
                -- The kept ones, placed by hand so one can be carried.
                g.box {
                    present = function() return #pinned() > 0 end,
                    width = kept_width,
                    height = icon_size,
                    g.each {
                        overlay = true,
                        attach = "corner",
                        width = kept_width,
                        height = icon_size,
                        items = pinned,
                        key = function(id: string) return id end,
                        row = function(id: () -> string, index: () -> number)
                            local function x(): number
                                return if held.value == index() then held_x() else resting_x(index())
                            end
                            return dock_icon {
                                app_id = id,
                                index = index,
                                x = x,
                                holdable = true,
                                held = function() return held.value == index() end,
                                running = function() return #windows_of(id()) > 0 end,
                                centre = function() return launcher_room() + x() + icon_size() / 2 end,
                                on_toggle = unkeep,
                            }
                        end,
                    },
                },
                divider(divided),
                g.each {
                    direction = "row",
                    align = "center",
                    gap = pitch,
                    items = function() return loose.value end,
                    key = function(group: any) return group.app_id end,
                    row = function(group: () -> any, index: () -> number)
                        return dock_icon {
                            app_id = function() return group().app_id end,
                            running = function() return true end,
                            centre = function()
                                return launcher_room() + (if #pinned() > 0 then kept_width() + pitch() else 0)
                                    + (if divided() then divider_room() else 0) + (index() - 1) * step() + icon_size() / 2
                            end,
                            on_toggle = keep,
                        }
                    end,
                },
                -- The name, beside the strip, over the icon the pointer is on.
                g.capsule {
                    overlay = true,
                    attach = "corner",
                    present = function() return named.value ~= "" end,
                    offset_x = function()
                        local w = g.text_width { text = named.value, font = typography.expressive(), size = m().font_secondary } + 20 * f()
                        return math.max(0, math.min(cell.room() - w, named_centre.value - w / 2))
                    end,
                    offset_y = function()
                        local pad = (m().cell_height - icon_size()) / 2
                        local h = 26 * f()
                        return if cell.edge == "bottom" then -pad - m().gap - h else icon_size() + pad + m().gap
                    end,
                    height = function() return 26 * f() end,
                    padding_x = function() return 10 * f() end,
                    align = "center",
                    radius = function() return metrics_mod.radius_for(26 * f(), m()) end,
                    fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.92) end,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                    g.text {
                        text = function() return named.value end,
                        color = theme.text,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                    },
                },
            }
        end

        return {
            padding_leading = function()
                return if count() > 0 then (m().cell_height - icon_size()) / 2 else 16 * f()
            end,
            padding_trailing = function()
                return if count() > 0 then (m().cell_height - icon_size()) / 2 else 16 * f()
            end,
            condition = function() return if count() > 0 and desktop_showing() then 1 else 0 end,
            content_width = function()
                local n = count()
                if n == 0 then
                    return g.text_width { text = "Launch an app and right click on the icon to pin it",
                        font = typography.expressive(), size = m().font_secondary }
                end
                return n * icon_size() + (n - 1) * pitch()
                    + (if divided() then divider_room() else 0) + (if launcher_divided() then divider_room() else 0)
            end,
            contracted = contracted,
        }
    end,
}
