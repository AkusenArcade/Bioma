pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The wallpaper: which image, and how.
//
// Rendered natively by `structure/WallpaperSurface.qml` on a Background-layer
// surface — no swww, no wpaperd, no swaybg. This service owns the choice and
// the geometry; it draws nothing and knows nothing about the surface above it.
//
// Ported from Prisma with three changes. Screen geometry comes from
// `Quickshell.screens` rather than the Niri module, which does not exist in
// Quickshell 0.3.1 and would have made the wallpaper compositor-specific for no
// reason. The home directory is read from the environment instead of being
// awaited from a shell process. And persistence uses `FileView.setText` with
// atomic writes rather than shelling out to `printf >`.
Singleton {
    id: root

    // ── Modes ────────────────────────────────────────────────────────────
    //
    // The wallpaper is "which image and how", so the how is not a detail:
    //
    //   fill         cover each monitor, cropping the overflow
    //   fit          contain within each monitor, letterboxing
    //   span         one image stretched across the bounding box of every
    //                monitor, each showing its own portion
    //   per_monitor  a different image per output, each filled
    readonly property var modes: ["fill", "fit", "span", "per_monitor"]

    property string path: ""
    property string mode: "fill"
    property var perMonitorPaths: ({})     // { "DP-1": "/path/img.jpg", … }

    // Where to look when the theme cell offers a choice of images. Written by
    // a human in the config file, so it may well carry a `~` or a `$HOME`.
    readonly property string folder: root.expand(Config.get("wallpaper.folder",
                                                           "$HOME/Pictures/Wallpapers"))

    function expand(candidate) {
        const home = Quickshell.env("HOME") ?? "";
        if (candidate.startsWith("~/"))
            return home + candidate.slice(1);
        if (candidate.startsWith("$HOME"))
            return home + candidate.slice(5);
        return candidate;
    }

    // Emitted whenever the effective image changes. The matugen service listens
    // to this rather than being called directly, so neither knows about the
    // other and either can be absent.
    signal imageChanged(string imagePath)

    // ── Per-screen resolution ────────────────────────────────────────────

    function pathForScreen(screenName) {
        if (root.mode === "per_monitor" && root.perMonitorPaths[screenName])
            return root.perMonitorPaths[screenName];
        return root.path;
    }

    function fillModeForScreen() {
        return root.mode === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop;
    }

    // For `span`: where this screen sits inside the bounding box of all of
    // them, so the surface can scale the image to the whole box and translate
    // negatively to show only its own portion.
    //
    // These are logical units, like everything else in Bioma — the bounding box
    // of a 3440×1440 monitor above a 1920×1080 one is 3440×2520 regardless of
    // either output's scale factor.
    function spanGeometry(screenName) {
        const screens = Quickshell.screens;
        if (screens.length === 0)
            return null;

        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const s of screens) {
            minX = Math.min(minX, s.x);
            minY = Math.min(minY, s.y);
            maxX = Math.max(maxX, s.x + s.width);
            maxY = Math.max(maxY, s.y + s.height);
        }

        const target = screens.find(s => s.name === screenName);
        if (!target)
            return null;

        return {
            totalWidth: maxX - minX,
            totalHeight: maxY - minY,
            offsetX: target.x - minX,
            offsetY: target.y - minY,
            screenWidth: target.width,
            screenHeight: target.height
        };
    }

    // ── Persistence ──────────────────────────────────────────────────────
    //
    // Kept out of the configuration layers deliberately. The theme cell rewrites
    // this every time the user tries an image, and that churn does not belong in
    // a file a human hand-edits or in the settings override that has to merge
    // cleanly against it.

    readonly property string stateDirectory:
        `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/bioma`
    readonly property string statePath: `${stateDirectory}/wallpaper.json`

    property bool loaded: false

    onPathChanged: { root.imageChanged(root.path); root.scheduleSave(); }
    onModeChanged: root.scheduleSave()
    onPerMonitorPathsChanged: root.scheduleSave()

    function scheduleSave() {
        // Nothing is written while the saved state is still being read, or the
        // first default would overwrite what is on disk.
        if (root.loaded)
            saveDebounce.restart();
    }

    Timer {
        id: saveDebounce
        interval: 300
        onTriggered: root.save()
    }

    function save() {
        stateFile.setText(JSON.stringify({
            path: root.path,
            mode: root.mode,
            perMonitorPaths: root.perMonitorPaths
        }, null, 2));
    }

    function load(text) {
        if (text && text.trim().length > 0) {
            try {
                const saved = JSON.parse(text);
                if (typeof saved.path === "string") root.path = root.expand(saved.path);
                if (root.modes.includes(saved.mode)) root.mode = saved.mode;
                if (saved.perMonitorPaths && typeof saved.perMonitorPaths === "object")
                    root.perMonitorPaths = saved.perMonitorPaths;
            } catch (error) {
                console.warn("Wallpaper: state file is not valid JSON —", error.message);
            }
        }
        root.loaded = true;
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: root.load(text())
        onLoadFailed: root.load("")        // no state yet — start from defaults
        onFileChanged: reload()

        // The config directory may not exist on a first run. Create it once,
        // on the first failure, rather than spawning anything at startup.
        onSaveFailed: {
            if (mkdir.running || mkdir.attempted)
                return;
            mkdir.attempted = true;
            mkdir.running = true;
        }
    }

    Process {
        id: mkdir
        property bool attempted: false
        command: ["mkdir", "-p", root.stateDirectory]
        running: false
        onExited: code => { if (code === 0) root.save(); }
    }
}
