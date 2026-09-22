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

    readonly property int settleMs: 6000

    // Bindings — these are what start the services.
    readonly property bool niriConnected: Niri.connected
    readonly property var niriWindows: Niri.windows
    readonly property var niriWorkspaces: Niri.workspaceList
    readonly property var niriFocused: Niri.focusedWindow
    readonly property var niriLayouts: Niri.windowLayouts
    readonly property bool wallpaperLoaded: Wallpaper.loaded
    readonly property string wallpaperPath: Wallpaper.path
    readonly property string wallpaperMode: Wallpaper.mode
    readonly property var wallpaperEntries: Wallpaper.entries
    readonly property var wallpaperCached: Wallpaper.cached
    readonly property var themePalettes: Theme.palettes
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
    readonly property var ddcDisplays: Brightness.displays
    readonly property var networkDevices: Network.devices
    readonly property bool wiredConnected: Network.wiredConnected
    readonly property bool wifiConnected: Network.wifiConnected
    readonly property var wifiNetworks: Network.visibleNetworks
    readonly property int reachability: Network.reachability
    readonly property var networkActive: Network.active
    readonly property var btAdapter: Bluetooth.adapter
    readonly property var btDevices: Bluetooth.devices
    readonly property var btConnected: Bluetooth.connectedDevices
    readonly property bool btEnabled: Bluetooth.enabled
    readonly property real cpuPercent: SystemMonitor.cpuPercent
    readonly property real cpuClock: SystemMonitor.cpuClock
    readonly property real ramPercent: SystemMonitor.ramPercent
    readonly property real gpuPercent: SystemMonitor.gpuPercent
    readonly property real gpuClock: SystemMonitor.gpuClock
    readonly property var vitalProcesses: SystemMonitor.processes
    readonly property bool hasBattery: SystemMonitor.hasBattery
    readonly property var trayItems: Tray.items
    readonly property bool trayAttention: Tray.attention
    readonly property string captureFolder: Capture.folder
    readonly property bool capturing: Capture.busy
    readonly property bool capturingVideo: Capture.recording

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

        // The library behind the theme cell's carousel: what is in the folder,
        // and how much of it has a thumbnail yet.
        line("library", `${root.wallpaperEntries.length} images`);
        line("current index", Wallpaper.index);
        if (root.wallpaperEntries.length > 0) {
            line("  previous", Wallpaper.neighbour(-1));
            line("  next", Wallpaper.neighbour(1));
        }
        line("thumbnails", Wallpaper.thumbnails ? (Wallpaper.broken ? "unavailable" : "on") : "off");
        line("cache", `${Object.keys(root.wallpaperCached).length} files in ${Wallpaper.cacheDirectory}`);
        if (root.wallpaperPath.length > 0)
            line("  current is", Wallpaper.thumbnail(root.wallpaperPath) === root.wallpaperPath
                                 ? "not cached yet" : "cached");
    }

    function probeTheme() {
        console.log("── Theme ─────────────────────────────────────────");
        line("source", Theme.source);
        line("matugen variant", Matugen.variant + " / " + Matugen.scheme);
        line("matugen config", Matugen.configDirectory);
        line("palette file", Theme.matugenPath);
        line("palettes", root.themePalettes.map(p => `${p.name} (${p.file})`).join(", ") || "none found");
        line("chosen", `${Theme.manualPalette} → ${Theme.paletteName}`);
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
        console.log(`  ddc displays (${root.ddcDisplays.length})`
                    + (Brightness.probing ? "  — still detecting" : ""));
        for (const entry of root.ddcDisplays)
            console.log(`    [${entry.index}] bus ${entry.bus}  ${Brightness.describe(entry)}`
                        + (entry.value >= 0 ? `  ${entry.value}/${entry.max}` : "  not read yet"));
        line("brightness", root.brightnessBackend === "none"
             ? "nothing to control"
             : `${Math.round(root.brightnessValue * 100)}%`);
        if (Brightness.lastError.length > 0)
            line("last error", Brightness.lastError);
    }

    function probeNetwork() {
        console.log("── Network ───────────────────────────────────────");
        line("backend", Network.backendName + (Network.available ? "" : "  — no backend"));
        line("devices", root.networkDevices.length);

        line("wired", Network.wiredPresent
             ? `${Network.wiredInterface}  ${Network.describeState(Network.wiredState)}`
             : "no wired device");
        if (Network.wiredPresent) {
            line("  link", Network.wiredHasLink
                 ? (Network.wiredSpeed > 0 ? `up  ${Network.wiredSpeed} Mb/s` : "up")
                 : "down — nothing plugged in");
            line("  connection", Network.wiredName || "—");
            line("  address", Network.wiredAddress || "—");
        }

        line("wifi", Network.wifiPresent
             ? `${Network.wifiDevice.name}  ${Network.describeState(Network.wifiState)}`
             : "no wifi device");
        if (Network.wifiPresent) {
            // Two switches, and the hard one wins: the soft switch cannot be
            // turned on while rfkill holds the radio down.
            line("  radio", (Network.wifiEnabled ? "enabled" : "disabled")
                 + (Network.wifiHardwareEnabled ? "" : "  — blocked by rfkill"));
            line("  connected", root.wifiConnected
                 ? `${Network.ssid}  ${Network.signalPercent}%  ${Network.signalBars}/4 bars`
                 : "no");
            console.log(`    networks (${root.wifiNetworks.length}, scanner `
                        + `${Network.scanning ? "on" : "off"})`);
            for (const n of root.wifiNetworks)
                console.log(`      ${n.connected ? "*" : " "} ${n.name}`
                            + `  ${Network.percentFor(n.signalStrength)}%  ${Network.barsFor(n.signalStrength)}/4`
                            + `  ${Network.security(n)}`
                            + (n.known ? "  known" : "")
                            + (Network.needsPassword(n) ? "  needs password" : ""));
        }

        line("reachability", Network.canCheckReachability
             ? Network.reachabilityName + (Network.captivePortal ? "  — captive portal" : "")
             : "not checked — NetworkManager connectivity check is off");
        line("online", Network.reachabilityKnown ? Network.online : "unknown");
        if (Network.lastError.length > 0)
            line("last error", Network.lastError);

        // What the connectivity cell composes itself from: one entry per live
        // connection, and an empty list means the cell is absent entirely.
        console.log(`  active connections (${root.networkActive.length})`);
        for (const entry of root.networkActive)
            console.log(`      ${entry.kind}  ${entry.label}`
                        + (entry.detail.length > 0 ? `  ${entry.detail}` : ""));
    }

    function probeTray() {
        console.log("── Tray ──────────────────────────────────────────");
        line("items", root.trayItems.length);
        line("attention", root.trayAttention);

        for (const item of root.trayItems) {
            line("· " + Tray.nameOf(item),
                 `${item.id}  ${item.status}  ${item.category}`
                 + `${item.hasMenu ? "  menu" : ""}${item.onlyMenu ? " only" : ""}`);
            if (item.icon)
                line("   icon", item.icon);
            line("   resolved", Tray.iconFor(item) || "NONE — falls back to a glyph");
            const tip = Tray.tooltipOf(item);
            if (tip.length > 0)
                line("   tooltip", tip);
        }
    }

    function probeBluetooth() {
        console.log("── Bluetooth ─────────────────────────────────────");
        if (!Bluetooth.available) {
            line("adapter", "none — no bluetooth hardware or bluez is not running");
            return;
        }

        line("adapter", `${Bluetooth.adapterName}  [${Bluetooth.adapterId}]`);
        line("state", Bluetooth.stateName
             + (Bluetooth.blocked ? "  — blocked by rfkill" : "")
             + (Bluetooth.settling ? "  — still settling" : ""));
        line("powered", root.btEnabled);
        line("discovering", Bluetooth.scanning
             + (Bluetooth.discovering === Bluetooth.scanning ? "" : "  (asked for "
                + Bluetooth.discovering + ")"));

        console.log(`  devices (${root.btDevices.length}: `
                    + `${root.btConnected.length} connected, `
                    + `${Bluetooth.pairedDevices.length} paired)`);
        for (const d of root.btDevices)
            console.log(`      ${d.connected ? "*" : " "} ${Bluetooth.describe(d)}`
                        + `  ${d.address}`
                        + `  ${Bluetooth.describeState(d)}`
                        + (d.paired ? "  paired" : "")
                        + (d.trusted ? "  trusted" : "")
                        + (Bluetooth.isBusy(d) ? "  busy" : "")
                        + `  icon:${Bluetooth.icon(d) || "—"}`
                        + (Bluetooth.hasBattery(d)
                           ? `  battery ${Bluetooth.batteryPercent(d)}% (raw ${Bluetooth.battery(d)})`
                           : ""));

        console.log(`  active connections (${Bluetooth.active.length})`);
        for (const entry of Bluetooth.active)
            console.log(`      ${entry.kind}  ${entry.label}`
                        + (entry.detail.length > 0 ? `  ${entry.detail}` : ""));
    }

    function probeVitals() {
        console.log("── Vitals ────────────────────────────────────────");
        line("sampling every", SystemMonitor.interval + " ms");
        line("cpu", `${Math.round(root.cpuPercent)}%  across ${SystemMonitor.cores} cores`);
        line("cpu clock", `${Math.round(root.cpuClock)} MHz averaged`
             + `  (raw ${Math.round(SystemMonitor.cpuClockRaw)},`
             + ` window ${SystemMonitor.clockSamples.length}/${SystemMonitor.averageWindow})`);
        line("  range", SystemMonitor.cpuClockRangeKnown
             ? `${Math.round(SystemMonitor.cpuClockMin)}–${Math.round(SystemMonitor.cpuClockMax)} MHz`
               + `  → fraction ${Math.round(SystemMonitor.cpuClockFraction * 100) / 100}`
             : "unknown — no cpufreq, the beat has no ceiling to map onto");
        line("ram", `${SystemMonitor.ramUsedGb}/${SystemMonitor.ramTotalGb} GiB`
             + `  ${Math.round(root.ramPercent)}%`);
        line("swap", SystemMonitor.swapTotal > 0
             ? `${Math.round(SystemMonitor.swapUsed)}/${Math.round(SystemMonitor.swapTotal)} MiB`
             : "none");

        if (!SystemMonitor.gpuPresent) {
            line("gpu", "none found");
        } else {
            line("gpu", `${SystemMonitor.gpuName}  ${SystemMonitor.gpuPath}`);
            // Utilisation and clock are separate quantities and diverge; the
            // cell encodes one as colour and the other as rotation.
            line("  utilisation", `${Math.round(root.gpuPercent)}%`);
            line("  clock", `${Math.round(root.gpuClock)} MHz`
                 + `  of ${Math.round(SystemMonitor.gpuClockMin)}–${Math.round(SystemMonitor.gpuClockMax)}`
                 + `  → fraction ${Math.round(SystemMonitor.gpuClockFraction * 100) / 100}`
                 + (SystemMonitor.gpuAsleep ? "  — asleep, a power state not an index" : ""));
            line("  vram", `${Math.round(SystemMonitor.vramUsed)}/${Math.round(SystemMonitor.vramTotal)} MiB`
                 + `  ${Math.round(SystemMonitor.vramPercent)}%`);
        }

        // Presence, not state: vitals draws three indicators here and four on a
        // laptop, from the same cell.
        line("battery", root.hasBattery
             ? `${SystemMonitor.batteryLevelRaw} raw  ${SystemMonitor.batteryStateName}`
               + `  ${Math.round(SystemMonitor.batterySecondsLeft / 60)} min left`
             : "none — desktop, so vitals shows three indicators");

        console.log(`  processes (${root.vitalProcesses.length}, `
                    + `sampling ${SystemMonitor.listProcesses ? "on" : "off"})`);
        for (const p of root.vitalProcesses.slice(0, 5))
            console.log(`      ${p.pid}  ${p.name}`
                        + `  cpu ${p.cpu}%  ram ${p.memMb} MiB (${p.memPercent}%)`);
    }

    function probeCapture() {
        console.log("── Capture ───────────────────────────────────────");
        // Nothing here takes a screenshot: this probe reports state, and a
        // capture writes files and takes the clipboard. The capture paths are
        // exercised separately — see INVENTORY §17.
        line("stills", root.captureFolder);
        line("video", Capture.videoFolder);
        line("temporary", Capture.temporaryDirectory);
        line("clipboard", Capture.copyToClipboard ? "yes" : "no");
        line("ocr language", Capture.language);
        line("video", `${Capture.codec}  ${Capture.fps} fps  ${Capture.bitrate}`);
        line("busy", root.capturing + (root.capturingVideo
             ? `  recording, ${Capture.elapsed}s` : ""));

        // The one piece of arithmetic no hardware here can confirm: this
        // machine has no fractional-scale output.
        line("encode 101x51 @1x", Capture.encodeResolution("0,0 101x51", 1));
        line("encode 101x51 @1.5x", Capture.encodeResolution("0,0 101x51", 1.5));
        if (Capture.lastPath.length > 0)
            line("last", Capture.lastPath);
        if (Capture.lastError.length > 0)
            line("last error", Capture.lastError);
    }

    function probeScreens() {
        console.log("── Screens ───────────────────────────────────────");
        for (const s of Quickshell.screens)
            console.log(`    ${s.name}  ${s.width}×${s.height}  scale ${s.devicePixelRatio}`
                        + `  at ${s.x},${s.y}`);
    }

    Component.onCompleted: SystemMonitor.listProcesses = true

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
            probeNetwork();
            probeBluetooth();
            probeVitals();
            probeTray();
            probeCapture();
            console.log("──────────────────────────────────────────────────");
            Qt.exit(0);
        }
    }
}
