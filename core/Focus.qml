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

    // Whether the shell is holding the keyboard. A cell that has a field to
    // type in makes its membrane focusable, and a focusable layer surface is
    // one the compositor moves the focus to — which means no window has it.
    // The window title cell reads this: the focus did not go nowhere, it came
    // here, and a cell that says which window has the focus can say that too.
    readonly property bool holdsKeyboard: cell !== null && cell.wantsKeyboard === true

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

    // ---- Cells that answer to a name ---------------------------------------
    //
    // A shortcut does not reach a cell directly: it reaches the shell, which
    // asks this register for the cell of that domain. The register is what
    // makes "launcher, session menu and settings are not a separate category"
    // true in code (PRD §5) — there is no second model for invoked surfaces,
    // only cells that happen to be invocable.
    //
    // The same cell exists once per monitor, so a domain answers with several
    // and the one on the output the keyboard is pointed at is the one meant.

    property var invocable: []

    function offer(cell) {
        if (root.invocable.indexOf(cell) < 0)
            root.invocable = root.invocable.concat([cell]);
    }

    function withdraw(cell) {
        const index = root.invocable.indexOf(cell);
        if (index >= 0) {
            const next = root.invocable.slice();
            next.splice(index, 1);
            root.invocable = next;
        }
    }

    function cellFor(domain, output) {
        let fallback = null;
        for (const cell of root.invocable) {
            if (!cell || cell.domain !== domain)
                continue;
            if (output && cell.output === output)
                return cell;
            if (!fallback)
                fallback = cell;
        }
        return fallback;
    }

    readonly property var domains: {
        const out = [];
        for (const cell of root.invocable)
            if (cell && out.indexOf(cell.domain) < 0)
                out.push(cell.domain);
        return out.sort();
    }

    // What a shortcut does. A cell that is only ever there when asked for
    // arrives and opens in one gesture; one that is always on the membrane is
    // already there, so the gesture is the opening.
    function invoke(domain, output) {
        const cell = root.cellFor(domain, output);
        if (!cell)
            return false;

        if (cell.visibility.type === "invoked") {
            cell.visibility.toggle();
            cell.open = cell.visibility.invoked && cell.hasPanel;
            return true;
        }

        cell.open = !cell.open;
        return true;
    }

    function retire(domain, output) {
        const cell = root.cellFor(domain, output);
        if (!cell)
            return false;
        cell.open = false;
        if (cell.visibility.type === "invoked")
            cell.visibility.invoked = false;
        return true;
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

    // Every shape the shell claims on one monitor, as rectangles on that
    // output: the cells, and the panels of whichever is open. Rectangles rather
    // than items, because whoever asks is on a different surface — see
    // `Membrane.inputRects`.
    function claimed(screenName) {
        const out = [];
        for (const membrane of root.membranes) {
            if (!membrane || !membrane.screenItem || membrane.screenItem.name !== screenName)
                continue;
            for (const rect of membrane.inputRects())
                out.push(rect);
        }
        return out;
    }
}
