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

    function start() {
        if (root.active)
            return;
        root.working = JSON.parse(JSON.stringify(Config.get("organisms", [])));
        root.active = true;
    }

    function finish() {
        if (!root.active)
            return;
        if (JSON.stringify(root.working) !== JSON.stringify(Config.get("organisms", [])))
            Config.set("organisms", root.working);
        root.active = false;
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
