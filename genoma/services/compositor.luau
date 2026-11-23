--!strict
-- The compositor, whichever it is — niri, Hyprland or Umbriel — through
-- Genoma's `@genoma/compositor`, which follows each one's own IPC (it was
-- services/niri.luau, niri's event stream read here). One model for all
-- three: windows, workspaces, the focus, each window's place, and the
-- actions the cells take. What a compositor does not say is absent, and
-- the cell that would show it is quiet there: the overview and the
-- screenshots are niri's, a screencast's program niri's alone.
--
-- Ids are strings, as Genoma hands them out. Every record is new when
-- anything changes: a binding that reads one follows it.
local g = require("@genoma")
local c = require("@genoma/compositor")

local M = {}

-- "niri", "hyprland", "umbriel", or "wayland" (only the standard
-- protocols: no layout, no gaps, no actions beyond focus and close).
function M.name(): string return c.name end

-- ---- Windows and workspaces ----------------------------------------------------

-- id -> { id, title, app_id, pid, workspace_id, output, is_focused,
-- is_floating, is_urgent }. Missing text is "", a missing pid -1.
local windows = g.computed(function(): { [string]: any }
    local focused = c.focused
    local focused_id = if focused then focused.id else nil
    local map = {}
    for _, w in c.windows do
        map[w.id] = {
            id = w.id,
            title = w.title or "",
            app_id = w.app_id or "",
            pid = w.pid or -1,
            workspace_id = w.workspace or "",
            output = w.output or "",
            is_focused = w.id == focused_id,
            is_floating = w.floating == true,
            is_urgent = w.urgent == true,
        }
    end
    return map
end)

-- A workspace has a name only if the user gave it one; otherwise the index
-- stands in. A name is language and an index a measurement, so the two are
-- kept apart. `active_window_id` is "" on an empty one.
local function record(ws: any): any
    return {
        id = ws.id,
        idx = ws.idx or 0,
        name = ws.name or "",
        output = ws.output or "",
        is_active = ws.active == true,
        is_focused = ws.focused == true,
        is_urgent = ws.urgent == true,
        vacant = ws.vacant == true,
        active_window_id = ws.active_window or "",
    }
end

-- Sorted by output, then by index: a stable order for the workspaces cell.
local workspace_list = g.computed(function(): { any }
    local list = {}
    for _, ws in c:workspaces() do table.insert(list, record(ws)) end
    return list
end)
local workspaces = g.computed(function(): { [string]: any }
    local map = {}
    for _, ws in workspace_list.value do map[ws.id] = ws end
    return map
end)

function M.windows(): { [string]: any } return windows.value end
function M.workspaces(): { [string]: any } return workspaces.value end
function M.workspace_list(): { any } return workspace_list.value end

function M.focused_window(): any
    local focused = c.focused
    return if focused then windows.value[focused.id] else nil
end
function M.focused_title(): string
    local w = M.focused_window()
    return if w then w.title else ""
end
function M.focused_app_id(): string
    local w = M.focused_window()
    return if w then w.app_id else ""
end

-- One focused workspace in the session, on the monitor the keyboard is
-- pointed at: where an invoked cell belongs.
function M.focused_workspace(): any
    for _, ws in workspace_list.value do
        if ws.is_focused then return ws end
    end
    return nil
end
function M.focused_output(): string return c.focused_output or "" end

-- Each output has its own active workspace: ask per output.
function M.workspaces_for_output(output: string): { any }
    local out = {}
    for _, ws in workspace_list.value do
        if ws.output == output then table.insert(out, ws) end
    end
    return out
end
function M.active_workspace_for_output(output: string): any
    for _, ws in workspace_list.value do
        if ws.output == output and ws.is_active then return ws end
    end
    return nil
end

function M.windows_on_workspace(id: string): { any }
    local out = {}
    for _, w in windows.value do
        if w.workspace_id == id then table.insert(out, w) end
    end
    return out
end

-- Where a window is laid out, on its output, apart from the window record
-- on purpose: it changes on every frame of a resize, and a binding on a
-- title must not re-run on each. `tile_size` { w, h }; `position_in_view`
-- { x, y } where the compositor says (niri: floating windows only);
-- `column` and `row` from 1 where the layout has columns (niri, Umbriel).
function M.layout_for(id: string): any
    local l = c:layout(id)
    if not l then return nil end
    return {
        tile_size = { l.w, l.h },
        position_in_view = if l.x and l.y then { l.x, l.y } else nil,
        column = l.column,
        row = l.row,
    }
end

function M.overview_open(): boolean return c.overview end
function M.keyboard_layout(): string return c.keyboard.name or "" end

-- The screen being captured: { id, active, pid, node, output, window }.
-- niri says which program and what; Hyprland only that one runs.
function M.casts(): { any } return c.casts end

-- A screenshot the compositor took itself (niri's own), with the path it
-- was saved to, if it was.
local screenshot_listeners: { (string) -> () } = {}
function M.on_screenshot(f: (string) -> ()) table.insert(screenshot_listeners, f) end
g.lasting(function()
    local seen = g.untracked(function() return c.screenshot.count end)
    g.watch(function() return c.screenshot end, function(shot: any)
        if shot.count == seen then return end
        seen = shot.count
        for _, f in screenshot_listeners do f(shot.path or "") end
    end)
end)

-- ---- The compositor's own layout figures --------------------------------------
--
-- Windows do not begin at the edge of a reserved strip: the compositor
-- insets them by its gaps and by any struts, and an expansion hangs from
-- the line where they actually start. None says it over IPC, so this reads
-- the configuration: niri's own files, every `layout` section in the order
-- niri reads them, a value written later winning (Niri.qml read the main
-- file alone, and missed a `gaps` in an included `layout.kdl`). Hyprland's
-- and Umbriel's come with their configuration (plan steps 5b, 5c); until
-- then their windows are taken to start at the strip.

local niri_config = require("services/niri_config")

-- The block a key belongs to, with its own braces balanced, so a `gaps`
-- inside some other section is not mistaken for the layout's.
local function block_of(text: string, name: string): string
    local _, open = string.find("\n" .. text, "\n%s*" .. name .. "%s*{")
    if not open then return "" end
    open -= 1 -- the "\n" added in front
    local depth = 0
    for i = open, #text do
        local ch = string.sub(text, i, i)
        if ch == "{" then
            depth += 1
        elseif ch == "}" then
            depth -= 1
            if depth == 0 then return string.sub(text, open, i) end
        end
    end
    return ""
end

local function number_after(text: string, key: string): number?
    local value = string.match(" " .. text, "%s" .. key .. "%s+(%-?%d+%.?%d*)")
    return tonumber(value)
end

local figures = g.computed(function(): { [string]: any }
    local out = { gap = 0, struts = { top = 0, bottom = 0, left = 0, right = 0 } }
    if c.name ~= "niri" then return out end
    for _, file in niri_config.texts() do
        -- Comments first: a commented-out `gaps 0` is not a value.
        local stripped = string.gsub(file.text, "//[^\n]*", "")
        local layout = block_of(stripped, "layout")
        if layout ~= "" then
            out.gap = number_after(layout, "gaps") or out.gap
            local struts = block_of(layout, "struts")
            for _, side in { "top", "bottom", "left", "right" } do
                out.struts[side] = number_after(struts, side) or out.struts[side]
            end
        end
    end
    return out
end)

function M.window_gap(): number return figures.value.gap end
function M.strut_for(edge: string): number return figures.value.struts[edge] or 0 end

-- ---- Actions ------------------------------------------------------------------
--
-- Each on a connection of its own, so a refused action cannot take the
-- event stream down with it; a refusal is said in the log, not raised in
-- the cell that asked.

local function act(what: string, f: () -> ())
    local ok, problem = pcall(f)
    if not ok then print("Bioma: " .. c.name .. " refused " .. what .. " — " .. tostring(problem)) end
end

function M.focus_window(id: string) act("focus-window", function() c:focus_window(id) end) end
function M.focus_workspace(id: string) act("focus-workspace", function() c:focus_workspace(id) end) end

-- The next workspace down (or up) on a given monitor, focused there: a
-- wheel over another monitor's workspaces moves that monitor, and the
-- keyboard with it.
function M.focus_workspace_step(output: string?, down: boolean)
    act("workspace step", function() c:step_workspace(if output == "" then nil else output, if down then 1 else -1) end)
end

-- Centres the focused window: the window title shows the focused one, so no
-- focus call comes first.
function M.center_focused_window() act("center-window", function() c:center_window() end) end

return M
