pragma Singleton

import QtQuick
import Quickshell

// Which cell has the user's attention, and who else is on screen.
//
// One cell is open at a time. Opening a second closes the first: two panels on
// screen at once would be two conversations, and the shell only ever answers
// one question at a time.
//
// It also keeps the register of membranes, which the full-screen input surface
// needs: to close a cell when the pointer lands anywhere else, that surface has
// to know everywhere the shell already claims — otherwise it would swallow the
// clicks meant for the cells themselves.
Singleton {
    id: root

    // The open cell, if any.
    property Item cell: null
    readonly property bool anyOpen: cell !== null

    // Bumped whenever the set of shapes on screen changes, so a surface holding
    // a region built from them knows to rebuild it.
    property int revision: 0

    function bump() {
        root.revision++;
    }

    function opened(item) {
        if (root.cell && root.cell !== item)
            root.cell.open = false;
        root.cell = item;
    }

    function released(item) {
        if (root.cell === item)
            root.cell = null;
    }

    // The pointer landed somewhere that belongs to nobody.
    function dismiss() {
        if (root.cell)
            root.cell.open = false;
    }

    // ---- The register ------------------------------------------------------

    property var membranes: []

    function register(membrane) {
        if (root.membranes.indexOf(membrane) < 0) {
            root.membranes = root.membranes.concat([membrane]);
            root.bump();
        }
    }

    function unregister(membrane) {
        const index = root.membranes.indexOf(membrane);
        if (index >= 0) {
            const next = root.membranes.slice();
            next.splice(index, 1);
            root.membranes = next;
            root.bump();
        }
    }

    // Every shape the shell claims on one monitor: the cells, and the panels of
    // whichever is open.
    function claimed(screenName) {
        const out = [];
        for (const membrane of root.membranes) {
            if (!membrane || !membrane.screenItem || membrane.screenItem.name !== screenName)
                continue;
            for (const shape of membrane.inputShapes())
                out.push(shape);
        }
        return out;
    }
}
