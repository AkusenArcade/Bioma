pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
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
    //   span         one image covering the bounding box of every monitor,
    //                cropped rather than stretched, each showing its own portion
    //   per_monitor  a different image per output, each filled
    readonly property var modes: ["fill", "fit", "span", "per_monitor"]

    property string path: ""
    property string mode: "fill"
    property var perMonitorPaths: ({})     // { "DP-1": "/path/img.jpg", … }

    // Shown until an image is chosen, so a first session opens on a picture
    // and not on a black screen. Bioma's own, drawn for it — see
    // docs/design/wallpaper/. `path` stays what the user chose, empty here,
    // so the fallback is never written into their state.
    readonly property string shippedFolder:
        Qt.resolvedUrl("../assets/wallpapers").toString().replace("file://", "")
    readonly property string fallback: `${root.shippedFolder}/bioma-forest.jpg`
    // Nothing until the saved state has been read: shown before it, the
    // fallback came up at every start and the chosen picture faded in over it
    // a moment later — two wallpapers, one after the other (Akusen,
    // 2026-09-28).
    readonly property string current: root.path.length > 0 ? root.path
                                    : root.loaded ? root.fallback : ""

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
        return root.current;
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

    onCurrentChanged: root.imageChanged(root.current)
    onPathChanged: root.scheduleSave()
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
        // `current` changes as this lands — to the saved image, or to the
        // fallback — and that change is what announces it.
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

    // ── The library ──────────────────────────────────────────────────────
    //
    // What the theme cell offers a choice among: Bioma's own images first, then
    // the ones in the folder, and a small copy of each to look at. The shipped
    // ones are always offered, so an empty folder still leaves a choice, and the
    // fallback is one of them, so the carousel opens on what is on screen. The cache lives here rather than in the
    // cell because it is the wallpaper's own domain — the settings page will
    // want it too — and because a carousel that decodes fifty photographs every
    // time it opens is not the same component as one that decodes fifty
    // thumbnails.

    readonly property bool thumbnails: Config.get("wallpaper.thumbnails", true)

    readonly property string cacheDirectory:
        `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/bioma/thumbnails`

    // Absolute paths: the shipped images, then the folder's, each in name order.
    property var entries: []

    // Of what is on screen, not of what was chosen: with nothing chosen the
    // fallback is showing, and it is in the list.
    readonly property int index: root.entries.indexOf(root.current)

    // The carousel's whole interaction, and it wraps: a folder of wallpapers
    // has no first and no last.
    function step(delta) {
        const count = root.entries.length;
        if (count === 0)
            return;
        const from = root.index >= 0 ? root.index : 0;
        root.path = root.entries[((from + delta) % count + count) % count];
    }

    // The image `offset` places along from the current one, for the neighbours
    // the carousel shows dimmed at its sides.
    function neighbour(offset) {
        const count = root.entries.length;
        if (count === 0)
            return "";
        if (count === 1)
            return offset === 0 ? root.entries[0] : "";
        const from = root.index >= 0 ? root.index : 0;
        return root.entries[((from + offset) % count + count) % count];
    }

    FolderListModel {
        id: shipped
        folder: `file://${root.shippedFolder}`
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        caseSensitive: false
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: root.readLibrary()
        onStatusChanged: if (status === FolderListModel.Ready) root.readLibrary()
    }

    FolderListModel {
        id: library
        folder: `file://${root.folder}`
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", "*.avif"]
        caseSensitive: false
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
        onCountChanged: root.readLibrary()
        onStatusChanged: if (status === FolderListModel.Ready) root.readLibrary()
    }

    function readLibrary() {
        const out = [];
        for (let i = 0; i < shipped.count; i++)
            out.push(String(shipped.get(i, "filePath")));
        // A folder pointed at assets/wallpapers would offer each image twice.
        for (let i = 0; i < library.count; i++) {
            const path = String(library.get(i, "filePath"));
            if (out.indexOf(path) < 0)
                out.push(path);
        }
        root.entries = out;
    }

    // ── Thumbnails ───────────────────────────────────────────────────────
    //
    // A name that is stable for the path and legal as a file name. FNV-1a is
    // not a cryptographic choice and does not need to be: it only has to be
    // stable and cheap, and the worst a collision costs is one wrong picture in
    // a carousel. The fingerprint is of the path alone, so replacing a file
    // with another of the same name keeps the old thumbnail — deleting the
    // cache directory is the cure, and it costs nothing.
    function fingerprint(text) {
        let hash = 0x811c9dc5;
        for (let i = 0; i < text.length; i++) {
            hash ^= text.charCodeAt(i);
            hash = Math.imul(hash, 0x01000193) >>> 0;
        }
        return hash.toString(36);
    }

    function thumbnailName(imagePath) {
        return `${root.fingerprint(imagePath)}.jpg`;
    }

    property var cached: ({})

    FolderListModel {
        id: cache
        folder: `file://${root.cacheDirectory}`
        nameFilters: ["*.jpg"]
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: root.readCache()
        onStatusChanged: if (status === FolderListModel.Ready) root.readCache()
    }

    // A converter creates its output file before it has finished writing it,
    // and the directory model announces it at that moment: read the half-written
    // file and Qt reports an unsupported format and gives up on it for good. The
    // one being written is therefore left out of the set until the process that
    // is writing it has exited.
    function readCache() {
        const writing = convert.running && convert.image.length > 0
                        ? root.thumbnailName(convert.image) : "";
        const out = {};
        for (let i = 0; i < cache.count; i++) {
            const name = String(cache.get(i, "fileName"));
            if (name !== writing)
                out[name] = true;
        }
        root.cached = out;
    }

    // The thumbnail where there is one, the image itself where there is not:
    // the carousel never shows a hole, it shows a picture that costs more the
    // first time it is seen and nothing every time after.
    // A lookup and nothing else: a binding that started work would change the
    // state it was reading, and Qt calls that a binding loop and stops
    // evaluating it. Asking for the thumbnail and asking for it to be made are
    // two calls — `prepare` is the second.
    function thumbnail(imagePath) {
        if (!imagePath || imagePath.length === 0 || !root.thumbnails || root.broken)
            return imagePath;
        const name = root.thumbnailName(imagePath);
        return root.cached[name] ? `${root.cacheDirectory}/${name}` : imagePath;
    }

    function prepare(imagePath) {
        if (!imagePath || imagePath.length === 0 || !root.thumbnails || root.broken)
            return;
        if (!root.cached[root.thumbnailName(imagePath)])
            root.request(imagePath);
    }

    // One at a time. Fifty converters at once would take the machine away from
    // whatever the user was actually doing, which is the opposite of the point.
    property var queue: []
    property bool directoryReady: false
    property int failures: 0
    readonly property bool broken: root.failures > 2

    function request(imagePath) {
        if (root.broken || convert.image === imagePath || root.queue.indexOf(imagePath) >= 0)
            return;
        root.queue = root.queue.concat([imagePath]);
        root.pump();
    }

    function pump() {
        if (convert.running || root.queue.length === 0 || root.broken)
            return;
        if (!root.directoryReady) {
            if (!thumbnailDirectory.running)
                thumbnailDirectory.running = true;
            return;
        }
        const next = root.queue[0];
        root.queue = root.queue.slice(1);
        convert.image = next;
        convert.command = [
            "magick", next,
            "-auto-orient", "-strip",
            "-thumbnail", "640x640>",
            "-quality", "82",
            `${root.cacheDirectory}/${root.thumbnailName(next)}`
        ];
        convert.running = false;
        convert.running = true;
    }

    Process {
        id: thumbnailDirectory
        command: ["mkdir", "-p", root.cacheDirectory]
        running: false
        onExited: code => {
            root.directoryReady = code === 0;
            if (code !== 0)
                root.failures = 3;
            root.pump();
        }
    }

    // Without ImageMagick there are no thumbnails and the carousel reads the
    // images themselves — slower, and still a working cell. A missing tool is
    // not a reason for a surface to be empty.
    Process {
        id: convert
        property string image: ""
        running: false
        onExited: code => {
            if (code === 0) {
                root.failures = 0;
                // The file is whole now, so it may join the set.
                root.readCache();
            } else {
                root.failures++;
                if (root.broken)
                    console.warn("Wallpaper: no thumbnails — `magick` failed on", convert.image);
            }
            convert.image = "";
            root.pump();
        }
    }
}
