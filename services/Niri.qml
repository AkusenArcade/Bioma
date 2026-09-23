pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The compositor, as one push-based source.
//
// Quickshell 0.3.1 ships no `Quickshell.Niri` module — the one Prisma was built
// against does not exist here. Everything below reads niri's own IPC socket
// instead: a single connection that requests `"EventStream"` once and then
// receives newline-delimited JSON for the life of the session. Nothing polls.
//
// The compositor-agnostic protocols (`ToplevelManager`, `WindowManager`) cover
// titles, app ids and workspaces on any compositor, and niri implements both.
// They are not used here because they do not carry window geometry, pids,
// workspace indices or output names, and Bioma targets niri explicitly. If that
// ever changes, they are the fallback.
Singleton {
    id: root

    // A screenshot niri took itself — its own screenshot UI, or a bind to
    // `screenshot-screen` — with the path it was saved to, if it was saved.
    signal screenshotCaptured(string path)

    // ── Connection ───────────────────────────────────────────────────────

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""
    readonly property bool connected: socket.connected

    // ── Raw state, keyed by id ───────────────────────────────────────────

    // id -> { id, title, appId, pid, workspaceId, isFocused, isFloating, isUrgent }
    property var windows: ({})
    // id -> { id, idx, name, output, isActive, isFocused, isUrgent, activeWindowId }
    property var workspaces: ({})

    // Geometry lives apart from the rest of the window record on purpose:
    // WindowLayoutsChanged fires continuously while a window is being resized,
    // and a consumer bound to a title must not re-evaluate on every frame.
    property var windowLayouts: ({})

    property int focusedWindowId: -1
    property bool overviewOpen: false
    property string keyboardLayout: ""

    // ── Derived ──────────────────────────────────────────────────────────

    readonly property var focusedWindow: windows[focusedWindowId] ?? null
    readonly property string focusedTitle: focusedWindow?.title ?? ""
    readonly property string focusedAppId: focusedWindow?.appId ?? ""

    // Sorted by output, then by index — a stable order for the workspaces cell.
    readonly property var workspaceList: {
        const list = Object.values(root.workspaces);
        list.sort((a, b) => a.output === b.output ? a.idx - b.idx
                                                  : a.output.localeCompare(b.output));
        return list;
    }

    // Which output the user is on. There is one focused workspace in the
    // session however many outputs there are, and it is on the monitor the
    // keyboard is pointed at — which is where an invoked cell belongs.
    readonly property string focusedOutput: {
        const focused = root.workspaceList.find(ws => ws.isFocused);
        return focused ? focused.output : "";
    }

    // niri keeps one active workspace per output, so there is no single global
    // "current" workspace on a multi-monitor session — ask per output.
    function workspacesForOutput(outputName) {
        return root.workspaceList.filter(ws => ws.output === outputName);
    }

    function activeWorkspaceForOutput(outputName) {
        return root.workspaceList.find(ws => ws.output === outputName && ws.isActive) ?? null;
    }

    // The one the keyboard is on.
    readonly property var focusedWorkspace: workspaceList.find(ws => ws.isFocused) ?? null

    function windowsOnWorkspace(workspaceId) {
        return Object.values(root.windows).filter(w => w.workspaceId === workspaceId);
    }

    function layoutFor(windowId) {
        return root.windowLayouts[windowId] ?? null;
    }

    function normaliseLayout(layout) {
        if (!layout)
            return null;
        return {
            size: layout.window_size ?? null,
            tileSize: layout.tile_size ?? null,
            positionInView: layout.tile_pos_in_workspace_view ?? null,
            offsetInTile: layout.window_offset_in_tile ?? null
        };
    }

    // ── Event stream ─────────────────────────────────────────────────────

    Socket {
        id: socket
        path: root.socketPath
        connected: root.socketPath.length > 0

        onConnectedChanged: {
            if (connected) {
                // A single request; every later message is an unsolicited event.
                socket.write('"EventStream"\n');
                socket.flush();
            } else {
                reconnect.start();
            }
        }

        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => root.handle(line)
        }
    }

    Timer {
        id: reconnect
        interval: 2000
        onTriggered: socket.connected = root.socketPath.length > 0
    }

    function normaliseWindow(w) {
        return {
            id: w.id,
            title: w.title ?? "",
            appId: w.app_id ?? "",
            pid: w.pid ?? -1,
            workspaceId: w.workspace_id ?? -1,
            isFocused: w.is_focused === true,
            isFloating: w.is_floating === true,
            isUrgent: w.is_urgent === true
        };
    }

    function normaliseWorkspace(ws) {
        return {
            id: ws.id,
            idx: ws.idx ?? 0,
            // A workspace has a name only if the user gave it one; otherwise the
            // index stands in. The two are different registers in the UI — a
            // name is human language, an index is a measurement — so keep them
            // distinguishable rather than collapsing them here.
            name: ws.name ?? "",
            output: ws.output ?? "",
            isActive: ws.is_active === true,
            isFocused: ws.is_focused === true,
            isUrgent: ws.is_urgent === true,
            activeWindowId: ws.active_window_id ?? -1
        };
    }

    function handle(line) {
        if (!line || line.length === 0)
            return;

        let event;
        try {
            event = JSON.parse(line);
        } catch (error) {
            console.warn("Niri: unparseable event —", error.message);
            return;
        }

        // The reply to the request itself, before the stream proper.
        if (event.Ok !== undefined)
            return;

        const kind = Object.keys(event)[0];
        const data = event[kind];

        switch (kind) {
        case "WindowsChanged": {
            // Window records carry their layout inline. WindowLayoutsChanged
            // only ever reports subsequent changes, so without reading it here
            // geometry stays empty until something is moved.
            const map = {};
            const layouts = {};
            for (const w of data.windows) {
                map[w.id] = root.normaliseWindow(w);
                const layout = root.normaliseLayout(w.layout);
                if (layout) layouts[w.id] = layout;
                if (w.is_focused) root.focusedWindowId = w.id;
            }
            root.windows = map;
            root.windowLayouts = layouts;
            break;
        }
        case "WindowOpenedOrChanged": {
            const w = root.normaliseWindow(data.window);
            const map = Object.assign({}, root.windows);
            map[w.id] = w;
            root.windows = map;
            const layout = root.normaliseLayout(data.window.layout);
            if (layout) {
                const layouts = Object.assign({}, root.windowLayouts);
                layouts[w.id] = layout;
                root.windowLayouts = layouts;
            }
            if (w.isFocused) root.focusedWindowId = w.id;
            break;
        }
        case "WindowClosed": {
            const map = Object.assign({}, root.windows);
            delete map[data.id];
            root.windows = map;
            const layouts = Object.assign({}, root.windowLayouts);
            delete layouts[data.id];
            root.windowLayouts = layouts;
            if (root.focusedWindowId === data.id) root.focusedWindowId = -1;
            break;
        }
        case "WindowFocusChanged":
            // null id means the compositor has no focused window — the window
            // title cell's condition lapsing.
            root.focusedWindowId = data.id ?? -1;
            break;
        case "WindowUrgencyChanged": {
            const existing = root.windows[data.id];
            if (!existing) break;
            const map = Object.assign({}, root.windows);
            map[data.id] = Object.assign({}, existing, { isUrgent: data.urgent === true });
            root.windows = map;
            break;
        }
        case "WindowLayoutsChanged": {
            const layouts = Object.assign({}, root.windowLayouts);
            for (const entry of data.changes) {
                const layout = root.normaliseLayout(entry[1]);
                if (layout) layouts[entry[0]] = layout;
            }
            root.windowLayouts = layouts;
            break;
        }
        case "WorkspacesChanged": {
            const map = {};
            for (const ws of data.workspaces)
                map[ws.id] = root.normaliseWorkspace(ws);
            root.workspaces = map;
            break;
        }
        case "WorkspaceActivated": {
            const target = root.workspaces[data.id];
            if (!target) break;
            const map = Object.assign({}, root.workspaces);
            // Activation is per output: only this workspace's own output loses
            // its previous active one.
            for (const id in map) {
                if (map[id].output !== target.output) continue;
                map[id] = Object.assign({}, map[id], { isActive: map[id].id === data.id });
            }
            if (data.focused === true) {
                for (const id in map)
                    map[id] = Object.assign({}, map[id], { isFocused: map[id].id === data.id });
            }
            root.workspaces = map;
            break;
        }
        case "WorkspaceActiveWindowChanged": {
            const existing = root.workspaces[data.workspace_id];
            if (!existing) break;
            const map = Object.assign({}, root.workspaces);
            map[data.workspace_id] = Object.assign({}, existing,
                                                   { activeWindowId: data.active_window_id ?? -1 });
            root.workspaces = map;
            break;
        }
        case "WorkspaceUrgencyChanged": {
            const existing = root.workspaces[data.id];
            if (!existing) break;
            const map = Object.assign({}, root.workspaces);
            map[data.id] = Object.assign({}, existing, { isUrgent: data.urgent === true });
            root.workspaces = map;
            break;
        }
        case "OverviewOpenedOrClosed":
            root.overviewOpen = data.is_open === true;
            break;
        case "KeyboardLayoutsChanged":
            root.layoutNames = data.keyboard_layouts?.names ?? [];
            root.keyboardLayout = root.layoutNames[data.keyboard_layouts?.current_idx ?? 0] ?? "";
            break;
        case "KeyboardLayoutSwitched":
            root.keyboardLayout = root.layoutNames[data.idx] ?? root.keyboardLayout;
            break;
        case "ConfigLoaded":
            if (data.failed === true)
                console.warn("Niri: config reload failed");
            break;
        case "ScreenshotCaptured":
            root.screenshotCaptured(data.path ?? "");
            break;
        }
    }

    property var layoutNames: []

    // ── Actions ──────────────────────────────────────────────────────────
    //
    // Sent through `niri msg`, not the socket, so a malformed action cannot
    // take the event stream down with it. The socket path is passed in the
    // environment rather than inherited, because an inherited NIRI_SOCKET
    // points at the wrong session when the shell is started from a different
    // TTY — a bug Prisma already hit.

    function dispatch(args) {
        actionProc.command = ["niri", "msg"].concat(args);
        actionProc.running = false;
        actionProc.running = true;
    }

    Process {
        id: actionProc
        running: false
        environment: ({ "NIRI_SOCKET": root.socketPath })
        onExited: code => {
            if (code !== 0)
                console.warn("Niri: action failed —", actionProc.command.join(" "), "exit", code);
        }
    }

    // ── The compositor's own layout figures ──────────────────────────────
    //
    // Windows do not begin at the edge of a reserved strip: niri insets them by
    // its `gaps`, and by any `struts`, and a cell's expansion has to hang from
    // the line where they actually start rather than from where the shell
    // stopped. There is no IPC for the configuration — `niri msg` lists
    // outputs, workspaces, windows and layers and nothing else — so this reads
    // niri's own file and watches it.

    readonly property string configPath: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/niri/config.kdl`

    property real windowGap: 0
    property var struts: ({ "top": 0, "bottom": 0, "left": 0, "right": 0 })

    function strutFor(edge) {
        return root.struts[edge] !== undefined ? root.struts[edge] : 0;
    }

    // The block a key belongs to, with its own braces balanced, so a `gaps`
    // inside some other section is not mistaken for the layout's.
    function blockOf(text, name) {
        const opening = text.search(new RegExp(`(^|\\n)\\s*${name}\\s*\\{`));
        if (opening < 0)
            return "";
        let depth = 0;
        for (let i = text.indexOf("{", opening); i < text.length; i++) {
            if (text[i] === "{")
                depth++;
            else if (text[i] === "}" && --depth === 0)
                return text.slice(opening, i);
        }
        return "";
    }

    function readLayout(text) {
        if (!text)
            return;
        // Comments first: a commented-out `gaps 0` is not a value.
        const stripped = text.replace(/\/\/[^\n]*/g, "");
        const layout = root.blockOf(stripped, "layout");
        if (!layout)
            return;

        const gaps = layout.match(/(^|\s)gaps\s+(-?\d+(?:\.\d+)?)/);
        root.windowGap = gaps ? parseFloat(gaps[2]) : 0;

        const struts = root.blockOf(layout, "struts");
        const read = side => {
            const match = struts.match(new RegExp(`(^|\\s)${side}\\s+(-?\\d+(?:\\.\\d+)?)`));
            return match ? parseFloat(match[2]) : 0;
        };
        root.struts = {
            "top": read("top"),
            "bottom": read("bottom"),
            "left": read("left"),
            "right": read("right")
        };
    }

    FileView {
        id: niriConfig
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: root.readLayout(text())
        onFileChanged: reload()
    }

    function focusWindow(id) { root.dispatch(["action", "focus-window", "--id", String(id)]); }
    function closeWindow() { root.dispatch(["action", "close-window"]); }
    function focusWorkspace(reference) { root.dispatch(["action", "focus-workspace", String(reference)]); }
    function moveWindowToWorkspace(reference) { root.dispatch(["action", "move-column-to-workspace", String(reference)]); }
    function focusMonitor(name) { root.dispatch(["action", "focus-monitor", name]); }

    // The neighbours of the focused workspace. niri numbers workspaces per
    // output and keeps an empty one at the end, so "down" is the next index on
    // this monitor rather than the next id.
    function focusWorkspaceDown() { root.dispatch(["action", "focus-workspace-down"]); }
    function focusWorkspaceUp() { root.dispatch(["action", "focus-workspace-up"]); }
    function toggleOverview() { root.dispatch(["action", "toggle-overview"]); }
    // niri calls it `load-config-file`; `reload-config` is not an action it
    // knows, and the call failed silently because nothing here reads what
    // `niri msg` says back. Found while wiring the keybinds, 2026-09-22.
    function reloadConfig() { root.dispatch(["action", "load-config-file"]); }

    // Verified against niri 26.04: `center-window` centres the focused window.
    // The window title cell shows the focused window, so no prior focus call is
    // needed — but anything else that centres a window must focus it first.
    function centerFocusedWindow() { root.dispatch(["action", "center-window"]); }
}
