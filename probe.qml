import QtQuick
import Quickshell
import qs.services

// Headless service probe.
//
//   qs -p ~/Documents/Development/Bioma/probe.qml
//
// Creates no surfaces and touches nothing. It binds each service the way a cell
// would, waits, prints what arrived, and exits. Every service is verified
// through this before a cell is built on it — a service that silently returns
// stale data is far harder to diagnose once there is a face on top of it.
//
// Note the bindings below. Quickshell's singletons and the compositor-backed
// models initialise on their first property binding, not on first access: read
// them from inside a function and they answer empty. Bind, then read.
ShellRoot {
    id: root

    readonly property int settleMs: 2500

    // Bindings — these are what start the services.
    readonly property bool niriConnected: Niri.connected
    readonly property var niriWindows: Niri.windows
    readonly property var niriWorkspaces: Niri.workspaceList
    readonly property var niriFocused: Niri.focusedWindow
    readonly property var niriLayouts: Niri.windowLayouts
    readonly property bool wallpaperLoaded: Wallpaper.loaded
    readonly property string wallpaperPath: Wallpaper.path
    readonly property string wallpaperMode: Wallpaper.mode

    function line(label, value) {
        console.log(("  " + label + "                      ").slice(0, 24) + value);
    }

    function probeNiri() {
        console.log("── Niri ──────────────────────────────────────────");
        line("socket", Niri.socketPath.length > 0 ? Niri.socketPath : "NOT SET");
        line("connected", root.niriConnected);

        const wins = Object.values(root.niriWindows);
        line("windows", wins.length);
        for (const w of wins) {
            const layout = Niri.layoutFor(w.id);
            const size = layout?.size ? layout.size.join("×") : "—";
            console.log(`    [${w.id}] ${w.appId}  ${size}  ws:${w.workspaceId}  pid:${w.pid}`
                        + (w.isFocused ? "  FOCUSED" : "") + (w.isUrgent ? "  URGENT" : ""));
            console.log(`         "${w.title}"`);
        }

        line("focused", root.niriFocused
             ? `${root.niriFocused.appId} — "${root.niriFocused.title}"`
             : "none");

        line("workspaces", root.niriWorkspaces.length);
        for (const ws of root.niriWorkspaces) {
            const label = ws.name.length > 0 ? `"${ws.name}"` : `#${ws.idx}`;
            console.log(`    ${ws.output}  ${label}`
                        + (ws.isActive ? "  active" : "")
                        + (ws.isFocused ? "  focused" : "")
                        + (ws.isUrgent ? "  urgent" : "")
                        + `  windows:${Niri.windowsOnWorkspace(ws.id).length}`);
        }

        // One active workspace per output is the shape to design the workspaces
        // cell around — there is no single global current workspace.
        for (const screen of Quickshell.screens) {
            const active = Niri.activeWorkspaceForOutput(screen.name);
            line("active on " + screen.name, active
                 ? (active.name.length > 0 ? active.name : "#" + active.idx)
                 : "none");
        }

        line("overview", Niri.overviewOpen);
        line("keyboard", Niri.keyboardLayout.length > 0 ? Niri.keyboardLayout : "—");
    }

    function probeWallpaper() {
        console.log("── Wallpaper ─────────────────────────────────────");
        line("state file", Wallpaper.statePath);
        line("loaded", root.wallpaperLoaded);
        line("folder", Wallpaper.folder);
        line("mode", root.wallpaperMode);
        line("image", root.wallpaperPath.length > 0 ? root.wallpaperPath : "none set");

        // The span arithmetic is the part worth checking against real outputs:
        // every screen must map onto its own portion of one bounding box.
        for (const screen of Quickshell.screens) {
            const g = Wallpaper.spanGeometry(screen.name);
            if (!g) { line(screen.name, "no span geometry"); continue; }
            console.log(`    ${screen.name}  box ${g.totalWidth}×${g.totalHeight}`
                        + `  portion ${g.screenWidth}×${g.screenHeight}`
                        + `  at ${g.offsetX},${g.offsetY}`
                        + `  → image drawn ${Math.round(g.totalWidth / g.screenWidth * 100) / 100}×`
                        + ` the screen width`);
            line("  resolves to", Wallpaper.pathForScreen(screen.name) || "none");
        }
    }

    function probeScreens() {
        console.log("── Screens ───────────────────────────────────────");
        for (const s of Quickshell.screens)
            console.log(`    ${s.name}  ${s.width}×${s.height}  scale ${s.devicePixelRatio}`
                        + `  at ${s.x},${s.y}`);
    }

    Timer {
        interval: root.settleMs
        running: true
        onTriggered: {
            probeScreens();
            probeNiri();
            probeWallpaper();
            console.log("──────────────────────────────────────────────────");
            Qt.exit(0);
        }
    }
}
