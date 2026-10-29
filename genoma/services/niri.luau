--!strict
-- niri (services/Niri.qml), through its own IPC socket: one connection, one
-- `"EventStream"` request, newline-delimited JSON for the life of the
-- session. Nothing polls.
--
-- Every record is replaced, never changed in place: a signal holds a table
-- by reference, and only a new one is news.
local g = require("@genoma")

local M = {}

-- ---- Raw state, keyed by id -------------------------------------------------

-- id -> { id, title, app_id, pid, workspace_id, is_focused, is_floating, is_urgent }
local windows = g.signal({})
-- id -> { id, idx, name, output, is_active, is_focused, is_urgent, active_window_id }
local workspaces = g.signal({})
-- Geometry lives apart from the rest of the window record on purpose:
-- WindowLayoutsChanged fires continuously while a window is being resized,
-- and a binding on a title must not re-run on every frame.
local layouts = g.signal({})
local focused_id = g.signal(-1)
local overview = g.signal(false)
local keyboard_layout = g.signal("")
local layout_names: { string } = {}
-- The same names, for who follows them (the keyboard cell's list).
local layout_list = g.signal({})
-- The screen being captured: niri's screencasts by stream id, as it reports
-- them (`target`, `is_active`, the consumer's `pid` or `pw_node_id`).
local casts = g.signal({})
local connected = g.signal(false)

local screenshot_listeners: { (string) -> () } = {}

local function copy(t: { [any]: any }): { [any]: any }
    local out = {}
    for k, v in t do out[k] = v end
    return out
end

local function with(t: { [any]: any }, changes: { [any]: any }): { [any]: any }
    local out = copy(t)
    for k, v in changes do out[k] = v end
    return out
end

local function normalise_window(w: any): any
    return {
        id = w.id,
        title = w.title or "",
        app_id = w.app_id or "",
        pid = w.pid or -1,
        workspace_id = w.workspace_id or -1,
        is_focused = w.is_focused == true,
        is_floating = w.is_floating == true,
        is_urgent = w.is_urgent == true,
    }
end

-- A workspace has a name only if the user gave it one; otherwise the index
-- stands in. A name is language and an index a measurement, so the two are
-- kept apart rather than collapsed here.
local function normalise_workspace(ws: any): any
    return {
        id = ws.id,
        idx = ws.idx or 0,
        name = ws.name or "",
        output = ws.output or "",
        is_active = ws.is_active == true,
        is_focused = ws.is_focused == true,
        is_urgent = ws.is_urgent == true,
        active_window_id = ws.active_window_id or -1,
    }
end

local function normalise_layout(layout: any): any
    if type(layout) ~= "table" then return nil end
    return {
        size = layout.window_size,
        tile_size = layout.tile_size,
        position_in_view = layout.tile_pos_in_workspace_view,
        offset_in_tile = layout.window_offset_in_tile,
    }
end

local function current(signal: any): any
    return g.untracked(function() return signal.value end)
end

-- ---- Events -------------------------------------------------------------------

local handlers: { [string]: (any) -> () } = {
    -- Window records carry their layout inline; WindowLayoutsChanged only
    -- reports later changes, so without reading it here the geometry stays
    -- empty until something moves.
    WindowsChanged = function(data)
        local map, geometry = {}, {}
        for _, w in data.windows do
            map[w.id] = normalise_window(w)
            geometry[w.id] = normalise_layout(w.layout)
            if w.is_focused then focused_id.value = w.id end
        end
        windows.value = map
        layouts.value = geometry
    end,
    WindowOpenedOrChanged = function(data)
        local w = normalise_window(data.window)
        windows.value = with(current(windows), { [w.id] = w })
        local layout = normalise_layout(data.window.layout)
        if layout then layouts.value = with(current(layouts), { [w.id] = layout }) end
        if w.is_focused then focused_id.value = w.id end
    end,
    WindowClosed = function(data)
        local map = copy(current(windows))
        map[data.id] = nil
        windows.value = map
        local geometry = copy(current(layouts))
        geometry[data.id] = nil
        layouts.value = geometry
        if current(focused_id) == data.id then focused_id.value = -1 end
    end,
    -- A null id: no window has the focus, the window title's condition
    -- lapsing.
    WindowFocusChanged = function(data)
        focused_id.value = data.id or -1
    end,
    WindowUrgencyChanged = function(data)
        local existing = current(windows)[data.id]
        if not existing then return end
        windows.value = with(current(windows), { [data.id] = with(existing, { is_urgent = data.urgent == true }) })
    end,
    WindowLayoutsChanged = function(data)
        local geometry = copy(current(layouts))
        for _, entry in data.changes do
            local layout = normalise_layout(entry[2])
            if layout then geometry[entry[1]] = layout end
        end
        layouts.value = geometry
    end,
    WorkspacesChanged = function(data)
        local map = {}
        for _, ws in data.workspaces do map[ws.id] = normalise_workspace(ws) end
        workspaces.value = map
    end,
    -- Activation is per output: only this workspace's own output loses its
    -- previous active one.
    WorkspaceActivated = function(data)
        local all = current(workspaces)
        local target = all[data.id]
        if not target then return end
        local map = {}
        for id, ws in all do
            local changes: { [string]: any } = {}
            if ws.output == target.output then changes.is_active = ws.id == data.id end
            if data.focused == true then changes.is_focused = ws.id == data.id end
            map[id] = if next(changes) then with(ws, changes) else ws
        end
        workspaces.value = map
    end,
    WorkspaceActiveWindowChanged = function(data)
        local existing = current(workspaces)[data.workspace_id]
        if not existing then return end
        workspaces.value = with(current(workspaces), {
            [data.workspace_id] = with(existing, { active_window_id = data.active_window_id or -1 }),
        })
    end,
    WorkspaceUrgencyChanged = function(data)
        local existing = current(workspaces)[data.id]
        if not existing then return end
        workspaces.value = with(current(workspaces), { [data.id] = with(existing, { is_urgent = data.urgent == true }) })
    end,
    OverviewOpenedOrClosed = function(data)
        overview.value = data.is_open == true
    end,
    KeyboardLayoutsChanged = function(data)
        local layouts_info = data.keyboard_layouts or {}
        layout_names = layouts_info.names or {}
        layout_list.value = layout_names
        keyboard_layout.value = layout_names[(layouts_info.current_idx or 0) + 1] or ""
    end,
    KeyboardLayoutSwitched = function(data)
        keyboard_layout.value = layout_names[(data.idx or 0) + 1] or current(keyboard_layout)
    end,
    ConfigLoaded = function(data)
        if data.failed == true then print("niri: config reload failed") end
    end,
    ScreenshotCaptured = function(data)
        for _, f in screenshot_listeners do f(data.path or "") end
    end,
    CastsChanged = function(data)
        local map = {}
        for _, cast in data.casts or {} do map[cast.stream_id] = cast end
        casts.value = map
    end,
    CastStartedOrChanged = function(data)
        casts.value = with(current(casts), { [data.cast.stream_id] = data.cast })
    end,
    CastStopped = function(data)
        local map = copy(current(casts))
        map[data.stream_id] = nil
        casts.value = map
    end,
}

local function handle(line: string)
    if line == "" then return end
    local ok, event = pcall(g.parse_json, line)
    if not ok or type(event) ~= "table" then
        print("niri: unparseable event")
        return
    end
    -- The reply to the request itself, before the stream proper.
    if event.Ok ~= nil then return end
    local kind, data = next(event)
    local handler = handlers[kind]
    -- One event is one change, however many records it touches.
    if handler then g.batch(function() handler(data) end) end
end

-- ---- The connection -----------------------------------------------------------

local socket_path = g.env("NIRI_SOCKET") or ""
local stream: any = nil

local function connect()
    if socket_path == "" then return end
    local ok, s = pcall(g.socket, {
        path = socket_path,
        on_line = handle,
        on_close = function()
            connected.value = false
            stream = nil
            g.after(2, connect)
        end,
    })
    if not ok then
        print("niri: " .. tostring(s))
        g.after(2, connect)
        return
    end
    stream = s
    -- A single request; every later message is an unsolicited event.
    s:send('"EventStream"\n')
    connected.value = true
end
connect()

function M.connected(): boolean return connected.value end

-- ---- Derived ------------------------------------------------------------------

function M.windows(): { [number]: any } return windows.value end
function M.workspaces(): { [number]: any } return workspaces.value end

-- Sorted by output, then by index: a stable order for the workspaces cell.
local workspace_list = g.computed(function(): { any }
    local list = {}
    for _, ws in workspaces.value do table.insert(list, ws) end
    table.sort(list, function(a, b)
        if a.output == b.output then return a.idx < b.idx end
        return a.output < b.output
    end)
    return list
end)
function M.workspace_list(): { any } return workspace_list.value end

function M.focused_window(): any return windows.value[focused_id.value] end
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
function M.focused_output(): string
    local ws = M.focused_workspace()
    return if ws then ws.output else ""
end

-- niri keeps one active workspace per output: ask per output.
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

function M.windows_on_workspace(id: number): { any }
    local out = {}
    for _, w in windows.value do
        if w.workspace_id == id then table.insert(out, w) end
    end
    return out
end

function M.layout_for(id: number): any return layouts.value[id] end
function M.overview_open(): boolean return overview.value end
function M.keyboard_layout(): string return keyboard_layout.value end
function M.layout_names(): { string } return layout_list.value end
function M.casts(): { [any]: any } return casts.value end

-- A screenshot niri took itself, with the path it was saved to, if it was.
function M.on_screenshot(f: (string) -> ()) table.insert(screenshot_listeners, f) end

-- ---- The compositor's own layout figures --------------------------------------
--
-- Windows do not begin at the edge of a reserved strip: niri insets them by
-- its `gaps` and by any `struts`, and an expansion hangs from the line where
-- they actually start. There is no IPC for the configuration, so this reads
-- niri's own files and follows them: every `layout` section in the order
-- niri reads them, a value written later winning (Niri.qml read the main
-- file alone, and missed a `gaps` in an included `layout.kdl`).

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
-- Through `niri msg`, not the socket, so a malformed action cannot take the
-- event stream down with it.

local function dispatch(command: { string })
    g.process {
        command = command,
        on_exit = function(code: number)
            if code ~= 0 then print("niri: action failed — " .. table.concat(command, " ") .. ", exit " .. code) end
        end,
    }
end

local function action(...: string)
    dispatch({ "niri", "msg", "action", ... })
end

function M.focus_window(id: number) action("focus-window", "--id", tostring(id)) end
function M.switch_layout(target: string) action("switch-layout", target) end
function M.close_window() action("close-window") end
function M.focus_workspace(reference: any) action("focus-workspace", tostring(reference)) end
function M.move_window_to_workspace(reference: any) action("move-column-to-workspace", tostring(reference)) end
function M.focus_monitor(name: string) action("focus-monitor", name) end
-- niri numbers workspaces per output and keeps an empty one at the end, so
-- "down" is the next index on this monitor rather than the next id.
function M.focus_workspace_down() action("focus-workspace-down") end
function M.focus_workspace_up() action("focus-workspace-up") end

-- The same, on a given monitor. Both actions work where the keyboard is, and
-- a wheel over another monitor's workspaces does not move it there, so that
-- monitor is focused first, in the same process.
function M.focus_workspace_step(output: string?, down: boolean)
    local step = if down then "focus-workspace-down" else "focus-workspace-up"
    if not output or output == "" or output == g.untracked(M.focused_output) then
        action(step)
        return
    end
    dispatch({ "sh", "-c", 'niri msg action focus-monitor "$1" && niri msg action "$2"', "sh", output, step })
end
function M.toggle_overview() action("toggle-overview") end
-- niri calls it `load-config-file`; `reload-config` is not an action it knows.
function M.reload_config() action("load-config-file") end
-- Centres the focused window: the window title shows the focused one, so no
-- focus call comes first.
function M.center_focused_window() action("center-window") end

return M
