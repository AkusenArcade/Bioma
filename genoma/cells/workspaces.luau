--!strict
-- The workspace this monitor is on (cells/workspaces/Workspaces.qml and
-- WorkspaceList.qml at 7ea52ac). One cell per monitor, each listing its
-- own screen. See docs/design/CELLS.md §03.
--
-- At rest the mark and a name: the workspace's own name in the expressive
-- face, its number in the technical one when it has none. Conditional, it
-- is there for a moment after the workspace changes, and the mark steps in
-- the direction of the jump: the answer to a shortcut, for an eye that was
-- not on the membrane. Pressed, the list of this monitor's workspaces buds
-- out of it; the wheel goes to the previous or next without opening.
--
-- Not yet: the shell-wide keyboard travel inside an open cell; the list
-- answers the arrows and Enter itself.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local typography = require("core/typography")
local metrics_mod = require("core/metrics")
local niri = require("services/niri")
local bars = require("components/workspace_bars")

local VISIBLE = 5

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function spacing(): number return 11 * f() end
        local function mark_size(): number return 16 * f() end

        local function workspace(): any return niri.active_workspace_for_output(cell.output) end
        local function named(): boolean
            local ws = workspace()
            return ws ~= nil and ws.name ~= ""
        end
        local function label(): string
            local ws = workspace()
            if not ws then return "" end
            return if ws.name ~= "" then ws.name else tostring(ws.idx)
        end

        local mark, shift = bars.new(mark_size)

        -- Told by its id, because the service hands out a fresh record on
        -- every event and a new record is not a new workspace; and stepped
        -- by its index.
        local last_id, last_index = -1, -1
        g.watch(workspace, function(ws: any)
            if not ws then return end
            if ws.id ~= last_id then
                if last_id ~= -1 then cell.pulse() end
                last_id = ws.id
            end
            if last_index >= 0 and ws.idx ~= last_index then shift(if ws.idx > last_index then 1 else -1) end
            last_index = ws.idx
        end)

        -- A name is human language and takes the expressive face; a number
        -- is the machine's own count and takes the technical one.
        local function name_font(): { [string]: any }
            return { font = typography.expressive(), size = cell.metrics().font_title, weight = 400, tracking = 0, tabular = false }
        end
        local function number_font(): { [string]: any }
            local size = cell.metrics().font_label
            return { font = typography.technical(), size = size, weight = typography.weight_label,
                tracking = typography.label_tracking, tabular = true }
        end
        local function font(): { [string]: any } return if named() then name_font() else number_font() end

        -- ---- The list ----------------------------------------------------------

        local function rows(): { any } return niri.workspaces_for_output(cell.output) end
        local function row_height(): number return 44 * f() end
        local function button(): number return 36 * f() end
        local function row_padding(): number return 8 * f() end
        local function list_width(): number return 216 * f() end

        local scroll = g.signal(0)
        local marked = g.signal(0) -- the row a key moved to; 0 before any key
        local function active_index(): number
            for i, ws in rows() do
                if ws.is_active then return i end
            end
            return 1
        end
        local function scroll_to(y: number)
            local most = math.max(0, #g.untracked(rows) - VISIBLE) * g.untracked(row_height)
            scroll.value = math.clamp(y, 0, most)
        end
        -- Past five rows it scrolls, and the row in question stays inside.
        local function reveal(i: number)
            local h = g.untracked(row_height)
            local top = g.untracked(function() return scroll.value end)
            local y = (i - 1) * h
            if y < top then
                scroll_to(y)
            elseif y + h > top + VISIBLE * h then
                scroll_to(y + h - VISIBLE * h)
            end
        end
        g.watch(function() return cell.open.value end, function(open: boolean)
            if not open then return end
            marked.value = 0
            scroll.value = 0
            reveal(g.untracked(active_index))
        end)

        -- Jump and close: the action is done, and staying open would be noise.
        local function jump(ws: any)
            niri.focus_workspace(ws.idx)
            cell.open.value = false
        end

        -- A name is the user's own word for the workspace. Without one, the
        -- window it is showing says more than "Workspace 4" beside a button
        -- with a 4 in it. niri keeps one empty workspace at the end: a place,
        -- not a content.
        local function describe(ws: any): string
            if ws.name ~= "" then return ws.name end
            local w = niri.windows()[ws.active_window_id]
            return if w and w.title ~= "" then w.title else ""
        end
        local function vacant(ws: any): boolean return ws.name == "" and ws.active_window_id < 0 end

        local function row(item: () -> any, index: () -> number): any
            local function ws(): any return item() end
            return g.capsule {
                role = "button",
                width = list_width,
                height = row_height,
                radius = function() return metrics_mod.shaped(math.min(row_height() / 2, 14 * f())) end,
                -- The keyboard's mark (KeyMark.qml): shown once a key moved it.
                fill = function()
                    return if marked.value == index() then colour.alpha(theme.primary(), 0.12) else "#00000000"
                end,
                justify = "start",
                align = "center",
                padding_left = row_padding,
                gap = function() return 12 * f() end,
                on_click = function() jump(g.untracked(ws)) end,
                -- Three states, as shapes rather than colours: filled where
                -- you are, a drawn ring for a workspace with something on
                -- it, a dashed one for the free place.
                g.capsule {
                    width = button,
                    height = button,
                    fill = function() return if ws().is_active then theme.gradient_top(theme.primary()) else "#00000000" end,
                    fill_bottom = function()
                        return if ws().is_active then theme.gradient_bottom(theme.primary()) else "#00000000"
                    end,
                    rim_top = function()
                        local w = ws()
                        return if w.is_active then "#00000000" elseif vacant(w) then colour.alpha(theme.line(), 0.7) else theme.line()
                    end,
                    rim_bottom = function()
                        local w = ws()
                        return if w.is_active then "#00000000" elseif vacant(w) then colour.alpha(theme.line(), 0.7) else theme.line()
                    end,
                    dash = function()
                        local w = ws()
                        return if vacant(w) and not w.is_active then 3 else 0
                    end,
                    dash_gap = 3,
                    justify = "center",
                    align = "center",
                    g.text {
                        font = typography.technical,
                        size = function() return math.round(14 * f()) end,
                        tabular = true,
                        weight = function() return if ws().is_active then 600 else typography.weight_value end,
                        color = function()
                            local w = ws()
                            if w.is_active then return theme.background() end
                            return colour.alpha(theme.text(), if vacant(w) then 0.3 else 0.72)
                        end,
                        text = function() return tostring(ws().idx) end,
                    },
                },
                g.text {
                    font = typography.expressive,
                    size = function() return math.round(14 * f()) end,
                    max_width = function() return math.max(0, list_width() - row_padding() * 2 - button() - 12 * f()) end,
                    italic = function() return describe(ws()) == "" end,
                    color = function()
                        local w = ws()
                        if describe(w) == "" then return colour.alpha(theme.text(), 0.28) end
                        return if w.is_active then theme.text() else colour.alpha(theme.text(), 0.5)
                    end,
                    text = function()
                        local d = describe(ws())
                        return if d ~= "" then d else "empty"
                    end,
                },
            }
        end

        local function list_height(): number return math.min(math.max(#rows(), 1), VISIBLE) * row_height() end

        -- The well (Well.qml): it clips the scroll, never the panel.
        local function well(): any
            return g.capsule {
                width = list_width,
                height = list_height,
                radius = function() return metrics_mod.inner_radius(cell.metrics().radius_panel, 10 * f()) end,
                fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                clip = true,
                align = "start",
                justify = "start",
                scroll_y = function() return scroll.value end,
                transition = { scroll_y = "reflow" },
                -- A wheel moves a row a step; a touchpad follows the fingers.
                on_wheel = function(_, dy: number)
                    local discrete = dy == math.floor(dy) and math.abs(dy) <= 3
                    local now = g.untracked(function() return scroll.value end)
                    scroll_to(now + (if discrete then dy * g.untracked(row_height) else dy))
                end,
                g.each {
                    direction = "column",
                    justify = "start",
                    items = rows,
                    key = function(ws: any) return ws.id end,
                    row = row,
                },
            }
        end

        return {
            padding_leading = 16,
            padding_trailing = 16,
            -- Conditional on the moment after the workspace changes.
            condition = function() return if cell.pulsing() then 1 else 0 end,
            content_width = function()
                local ft = font()
                return mark_size() + spacing()
                    + g.text_width { text = label(), font = ft.font, size = ft.size, weight = ft.weight, tracking = ft.tracking }
            end,
            -- The configured minimum is for names: they come in every length,
            -- and a floor keeps a short one from making the pill twitch. A
            -- number needs none (Akusen, 2026-10-02).
            min_width = function()
                if not named() then return 0 end
                local m = cell.block().min_width
                return ((m and m.value) or 24) * f()
            end,
            -- Open, the capsule names itself: it is the title of the list
            -- hanging under it.
            header_title = "WORKSPACES",
            header_mark_size = mark_size,
            header_mark = function(size: () -> number)
                local node = bars.new(size)
                return node
            end,
            -- Previous and next workspace without opening anything.
            on_wheel = function(_, dy: number)
                if dy ~= 0 then niri.focus_workspace_step(cell.output, dy > 0) end
            end,
            on_key = function(key: string)
                local list = g.untracked(rows)
                local n = #list
                if n == 0 then return end
                local at = g.untracked(function() return marked.value end)
                -- The first key marks where the eye already is, and acts as
                -- nothing else.
                if key == "Down" or key == "Up" then
                    if at == 0 then
                        at = g.untracked(active_index)
                    else
                        at = math.clamp(at + (if key == "Down" then 1 else -1), 1, n)
                    end
                    marked.value = at
                    reveal(at)
                elseif (key == "Return" or key == "KP_Enter" or key == "space") and at > 0 then
                    jump(list[at])
                end
            end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    mark,
                    g.text {
                        color = theme.text,
                        font = function() return font().font end,
                        size = function() return font().size end,
                        weight = function() return font().weight end,
                        tracking = function() return font().tracking end,
                        tabular = function() return font().tabular end,
                        text = label,
                        max_width = function() return math.max(0, cell.room() - mark_size() - spacing()) end,
                    },
                }
            end,
            panel = {
                -- The panel pads its content by 10 on each side.
                width = function() return list_width() + 20 * f() end,
                height = function() return list_height() + 20 * f() end,
                content = well,
            },
        }
    end,
}
