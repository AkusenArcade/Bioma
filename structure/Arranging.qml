pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Placing the organisms.
//
// At rest an organism takes no input — the pointer passes through it to the
// desktop — so it is moved in a mode of its own. While the mode lasts every
// organism surface comes up above the windows, takes the pointer, and lets its
// organisms be dragged; leaving it puts them back under the windows and writes
// where they now are.
//
// What is being edited is a working copy of the configuration's list, so a
// drag does not write the file sixty times a second: the list is written once,
// on leaving (docs/design/ORGANISMS.md, Arranging).
Singleton {
    id: root

    property bool active: false

    // The organisms as they are being placed: the configuration's list,
    // copied when the mode begins.
    property var working: []

    // ---- The grid ---------------------------------------------------------------------

    // Organisms are placed on a grid of squares. Its module is one unit of a
    // template and the gap beside it, and the wheel divides the module into
    // 1, 2, 4 or 8 squares — always a whole number, so every organism's
    // edges land on the lines and it covers whole squares, never halves
    // (Akusen, 2026-10-07). The wheel changes how finely they are placed,
    // never how large they are: that is each organism's SIZE.
    readonly property var divisions: [1, 2, 4, 8]
    property int grid: 2

    function finer(steps) {
        const at = root.divisions.indexOf(root.grid);
        const next = Math.max(0, Math.min(root.divisions.length - 1, (at < 0 ? 1 : at) + steps));
        root.grid = root.divisions[next];
    }

    function storedGrid() {
        const wanted = Config.get("arrange.grid", 2);
        return root.divisions.indexOf(wanted) >= 0 ? wanted : 2;
    }

    Component.onCompleted: root.grid = root.storedGrid()

    // From the configuration's list, or from one just written that the
    // configuration has not caught up with yet — an organism just added.
    function start(from) {
        if (root.active)
            return;
        // Named only when written: renaming the list now would make every
        // surface rebuild its organisms the moment the mode begins.
        root.working = JSON.parse(JSON.stringify(from || Config.get("organisms", [])));
        root.grid = root.storedGrid();
        root.active = true;
    }

    function finish() {
        if (!root.active)
            return;
        const pairs = [];
        if (JSON.stringify(root.working) !== JSON.stringify(Config.get("organisms", [])))
            pairs.push(["organisms", root.named(root.working)]);
        if (root.grid !== root.storedGrid())
            pairs.push(["arrange.grid", root.grid]);
        if (pairs.length > 0)
            Config.setMany(pairs);
        root.active = false;
    }

    // Every block written from here carries an `id`, so a surface can tell
    // one organism from another when the list changes around it: taken away
    // from the middle of the list, an organism must not take the ones after
    // it with it. A block written by hand without one gets one the first
    // time the list is written from here.
    function named(list) {
        return list.map(entry => entry.id ? entry
                                          : Object.assign({ "id": root.newId() }, entry));
    }

    function newId() {
        return Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
    }

    function toggle() {
        if (root.active)
            root.finish();
        else
            root.start();
    }

    // An organism dropped: the grid point its top-left corner landed on, in
    // modules from the grid's corner, on the screen it now belongs to. The
    // fractions it may have been written with before are dropped with it.
    // One that was on every screen stays on every screen — it moves on all
    // of them.
    function place(index, monitor, col, row) {
        if (index < 0 || index >= root.working.length)
            return;
        const next = JSON.parse(JSON.stringify(root.working));
        const entry = next[index];
        entry.col = Math.round(col * 1000) / 1000;
        entry.row = Math.round(row * 1000) / 1000;
        delete entry.x;
        delete entry.y;
        if (monitor && entry.monitor !== "all" && entry.monitor !== "*")
            entry.monitor = monitor;
        root.working = next;
    }

    // ---- Adding and taking away -----------------------------------------------------

    // A new organism appears in the middle of its screen's free area — it has
    // no grid point yet, so it is centred and snapped — and the
    // mode begins so it can be put where it belongs — unless `quietly`: a note
    // with no file yet has nothing to show, and is given its file first.
    function add(type, monitor, quietly) {
        const next = root.named(JSON.parse(JSON.stringify(root.active ? root.working
                                                                       : Config.get("organisms", []))));
        next.push({ "id": root.newId(), "type": type, "monitor": monitor, "x": 0.5, "y": 0.5 });
        if (root.active) {
            root.working = next;
            return;
        }
        Config.set("organisms", next);
        if (!quietly)
            root.start(next);
    }

    // Taken away, it leaves the way everything in the shell leaves — content,
    // then shape, into its own centre — and only then is the list written
    // without it. Until then it is held here, by its place in the list.
    property var retiring: []

    function remove(index) {
        if (root.active) {
            root.working = root.working.filter((_, i) => i !== index);
            return;
        }
        if (root.retiring.indexOf(index) < 0)
            root.retiring = root.retiring.concat([index]);
        gone.restart();
    }

    Timer {
        id: gone
        interval: Timing.contentFade + Timing.close
        onTriggered: {
            const kept = Config.get("organisms", []).filter((_, i) => root.retiring.indexOf(i) < 0);
            root.retiring = [];
            Config.set("organisms", root.named(kept));
        }
    }

    // ---- A note's file ------------------------------------------------------------------

    // Chosen with zenity, from here rather than from the settings page: the
    // picker is a window, a press on it lands outside the settings and closes
    // them, and a picker owned by the page died with it — the window closed
    // under the first click (Akusen, 2026-10-04). The wallpaper's folder
    // picker lives in its service for the same reason.
    //
    // A note that had no file yet has never been on the desktop, so once it
    // has one the mode begins and it can be put where it belongs.
    readonly property string home: Quickshell.env("HOME")
    property int choosingFor: -1
    property bool placeAfter: false
    property string pickerError: ""

    function chooseFile(index) {
        const list = Config.get("organisms", []);
        if (index < 0 || index >= list.length || filePicker.running)
            return;
        const current = list[index].file || "";
        root.choosingFor = index;
        root.placeAfter = current.length === 0;
        filePicker.start = current.length > 0
            ? (current.startsWith("~") ? root.home + current.slice(1) : current)
            : root.home + "/";
        filePicker.running = true;
    }

    // Written with the home as `~`, so the block reads the same on a machine
    // with another user name.
    function setFile(index, path) {
        let wanted = String(path).trim();
        if (wanted.length === 0)
            return null;
        if (root.home.length > 0 && wanted.startsWith(root.home + "/"))
            wanted = "~" + wanted.slice(root.home.length);
        const next = root.named(JSON.parse(JSON.stringify(Config.get("organisms", []))));
        if (!next[index])
            return null;
        next[index].file = wanted;
        Config.set("organisms", next);
        return next;
    }

    Process {
        id: filePicker

        property string start: ""

        // 127 is the shell's own answer for a command it cannot find, so a
        // missing zenity is told apart from a picker that was cancelled (1).
        command: ["sh", "-c", 'command -v zenity >/dev/null || exit 127; '
                  + 'exec zenity --file-selection --title="Note" '
                  + '--file-filter="Markdown | *.md *.markdown" --file-filter="All files | *" '
                  + '--filename="$1"', "sh", filePicker.start]
        running: false
        stdout: StdioCollector { id: pickedFile }
        onExited: code => {
            root.pickerError = code === 127 ? "zenity is not installed, so there is no file picker." : "";
            if (code === 0 && root.choosingFor >= 0) {
                const next = root.setFile(root.choosingFor, pickedFile.text);
                if (next && root.placeAfter)
                    root.start(next);
            }
            root.choosingFor = -1;
        }
    }

    // ---- The surfaces ---------------------------------------------------------------

    // Every organism surface, so a drop can land on another screen: the
    // organism is carried by its own surface, and the one under the pointer
    // when it is let go is where it now lives.
    property var surfaces: []

    function register(surface) {
        if (root.surfaces.indexOf(surface) < 0)
            root.surfaces = root.surfaces.concat([surface]);
    }

    function unregister(surface) {
        root.surfaces = root.surfaces.filter(s => s !== surface);
    }

    function surfaceAt(globalX, globalY) {
        for (const surface of root.surfaces) {
            const screen = surface.screenItem;
            if (screen && globalX >= screen.x && globalX < screen.x + screen.width
                && globalY >= screen.y && globalY < screen.y + screen.height)
                return surface;
        }
        return null;
    }
}
