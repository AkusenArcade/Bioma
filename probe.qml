import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.core
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
    readonly property bool matugenRunning: Matugen.running
    readonly property string matugenError: Matugen.lastError
    readonly property color themeBackground: Theme.background
    readonly property color themeText: Theme.text
    readonly property color themePrimary: Theme.primary
    readonly property color themeSecondary: Theme.secondary
    readonly property var mediaPlayers: Media.players
    readonly property var mediaPlayer: Media.player
    readonly property string mediaTitle: Media.title
    readonly property real mediaPosition: Media.position
    readonly property var audioOutputs: Audio.outputs
    readonly property var audioInputs: Audio.inputs
    readonly property var audioStreams: Audio.streams
    readonly property real audioVolume: Audio.volume
    readonly property real audioPeak: Audio.peak
    readonly property string brightnessBackend: Brightness.backend
    readonly property real brightnessValue: Brightness.brightness
    readonly property var ddcDisplays: Brightness.ddcDisplays

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

    function probeTheme() {
        console.log("── Theme ─────────────────────────────────────────");
        line("source", Theme.source);
        line("matugen variant", Matugen.variant + " / " + Matugen.scheme);
        line("matugen config", Matugen.configDirectory);
        line("palette file", Theme.matugenPath);
        line("generating", root.matugenRunning);
        if (root.matugenError.length > 0)
            line("last error", root.matugenError);

        // The four interface roles, then two of the derived ones, so a bad
        // derivation shows up here rather than in a cell.
        line("background", root.themeBackground);
        line("text", root.themeText);
        line("primary", root.themePrimary);
        line("secondary", root.themeSecondary);
        line("is dark", Theme.isDark + "  (luminance " + Math.round(Theme.backgroundLuminance * 1000) / 1000 + ")");
        line("derived surface", Theme.surface);
        line("derived elevated", Theme.elevated);

        // Fixed, and never from matugen — a blue wallpaper must not turn the
        // semantic code into three blues.
        line("calm/active/alert", `${Theme.calm}  ${Theme.active}  ${Theme.alert}`);
    }

    function probeMedia() {
        console.log("── Media ─────────────────────────────────────────");
        line("players", root.mediaPlayers.length);
        for (const p of root.mediaPlayers)
            console.log(`    ${p.identity}  [${p.dbusName}]`
                        + `  ${p.playbackState === MprisPlaybackState.Playing ? "playing" : "paused"}`);

        if (!Media.available) {
            line("active", "none — nothing is playing");
            return;
        }

        line("active", Media.identity + (Media.chosenExplicitly ? "  (chosen)" : "  (automatic)"));
        line("title", Media.title || "—");
        line("artist", Media.artist || "—");
        line("album", Media.album || "—");
        line("art", Media.hasArt ? Media.artUrl : "none");
        line("playing", Media.playing);
        line("position", `${Media.formatTime(root.mediaPosition)} / ${Media.formatTime(Media.length)}`
                         + `  (${Math.round(Media.progress * 100)}%)`);
        line("can", [Media.canToggle ? "toggle" : "", Media.canGoNext ? "next" : "",
                     Media.canGoPrevious ? "previous" : "", Media.canSeek ? "seek" : ""]
                    .filter(x => x.length > 0).join(" "));
    }

    function probeAudio() {
        console.log("── Audio ─────────────────────────────────────────");
        line("default output", Audio.describe(Audio.sink) || "none");
        line("volume", `${Audio.volumePercent}%` + (Audio.muted ? "  MUTED" : ""));
        line("default input", Audio.describe(Audio.source) || "none");
        line("input volume", `${Math.round(Audio.inputVolume * 100)}%`
                             + (Audio.inputMuted ? "  MUTED" : ""));
        line("signal", Audio.monitoring
             ? `${Math.round(root.audioPeak * 1000) / 1000}` + (Audio.signalPresent ? "  present" : "  silent")
             : "not monitored");

        console.log(`  outputs (${root.audioOutputs.length})`);
        for (const node of root.audioOutputs)
            console.log(`    ${Audio.isDefaultOutput(node) ? "*" : " "} ${Audio.describe(node)}`
                        + `  vol ${Math.round((node.audio?.volume ?? 0) * 100)}%`);

        console.log(`  inputs (${root.audioInputs.length})`);
        for (const node of root.audioInputs)
            console.log(`    ${Audio.isDefaultInput(node) ? "*" : " "} ${Audio.describe(node)}`);

        console.log(`  streams (${root.audioStreams.length} playing, `
                    + `${Audio.recordingStreams.length} recording)`);
        for (const node of root.audioStreams)
            console.log(`      ${Audio.describeStream(node)}`
                        + `  vol ${Math.round((node.audio?.volume ?? 0) * 100)}%`
                        + ((node.audio?.muted ?? false) ? "  muted" : "")
                        + `  icon:${Audio.streamIcon(node) || "—"}`);
    }

    function probeBrightness() {
        console.log("── Brightness ────────────────────────────────────");
        line("configured", Brightness.configuredBackend);
        line("backend in use", root.brightnessBackend);
        line("available", Brightness.available);
        line("backlight", Brightness.hasBacklight
             ? `${Brightness.backlightDevice}  ${Brightness.backlightValue}/${Brightness.backlightMax}`
             : "none — no /sys/class/backlight device");
        console.log(`  ddc displays (${root.ddcDisplays.length})`);
        for (const display of root.ddcDisplays)
            console.log(`    [${display.index}] ${display.name}`
                        + (display.brightness >= 0
                           ? `  ${display.brightness}/${display.max}`
                           : "  not read"));
        line("brightness", root.brightnessBackend === "none"
             ? "nothing to control"
             : `${Math.round(root.brightnessValue * 100)}%`);
        if (Brightness.lastError.length > 0)
            line("last error", Brightness.lastError);
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
            probeTheme();
            probeMedia();
            probeAudio();
            probeBrightness();
            console.log("──────────────────────────────────────────────────");
            Qt.exit(0);
        }
    }
}
