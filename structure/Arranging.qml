pragma Singleton

import QtQuick
import Quickshell
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

    // From the configuration's list, or from one just written that the
    // configuration has not caught up with yet — an organism just added.
    function start(from) {
        if (root.active)
            return;
        // Named only when written: renaming the list now would make every
        // surface rebuild its organisms the moment the mode begins.
        root.working = JSON.parse(JSON.stringify(from || Config.get("organisms", [])));
        root.active = true;
    }

    function finish() {
        if (!root.active)
            return;
        if (JSON.stringify(root.working) !== JSON.stringify(Config.get("organisms", [])))
            Config.set("organisms", root.named(root.working));
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

    // An organism dropped: its new centre, as fractions of the free area of
    // the screen it now belongs to. One that was on every screen stays on
    // every screen — it moves on all of them.
    function place(index, monitor, x, y) {
        if (index < 0 || index >= root.working.length)
            return;
        const next = JSON.parse(JSON.stringify(root.working));
        const entry = next[index];
        entry.x = Math.round(x * 10000) / 10000;
        entry.y = Math.round(y * 10000) / 10000;
        if (monitor && entry.monitor !== "all" && entry.monitor !== "*")
            entry.monitor = monitor;
        root.working = next;
    }

    // ---- Adding and taking away -----------------------------------------------------

    // A new organism appears in the middle of its screen's free area, and the
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
