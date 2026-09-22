pragma Singleton

import QtQuick
import Quickshell
import qs.cells

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
    //
    // Closing is not only `open = false`: a cell whose whole content is
    // itself never opened in the first place — the launcher is the panel —
    // and the way such a cell leaves is by no longer being asked for.
    function dismiss() {
        if (!root.cell)
            return;
        root.cell.open = false;
        if (root.cell.visibility.invocable)
            root.cell.visibility.invoked = false;
    }

    // ---- Cells that answer to a name ---------------------------------------
    //
    // A shortcut does not reach a cell directly: it reaches the shell, which
    // asks this register for the cell of that domain. The register is what
    // makes "launcher, session menu and settings are not a separate category"
    // true in code (PRD §5) — there is no second model for invoked surfaces,
    // only cells that happen to be invocable.
    //
    // **Every cell is in it**, not only the ones whose block says invocable.
    // A cell already on the membrane is the answer to somebody asking for it
    // by name — it held only the declared ones before, so asking for the
    // workspaces cell, which is always visible and says nothing about being
    // invocable, summoned a second copy of it into the middle of the screen
    // while the first sat on the membrane. What `invocable` decides is the
    // *ranking* below, not who may answer.
    //
    // The same cell exists once per monitor, so a domain answers with several
    // and the one on the output the keyboard is pointed at is the one meant.

    property var known: []

    function offer(cell) {
        if (root.known.indexOf(cell) < 0)
            root.known = root.known.concat([cell]);
    }

    function withdraw(cell) {
        const index = root.known.indexOf(cell);
        if (index >= 0) {
            const next = root.known.slice();
            next.splice(index, 1);
            root.known = next;
        }
    }

    // The same domain may answer twice on one monitor: the audio cell is on
    // the membrane *and* centred on the screen as its invoked form (CELLS
    // §05). A shortcut means the one that exists only when it is asked for —
    // the other is already on screen and needs no asking — so a cell whose
    // visibility is `invoked` wins over one that is merely invocable, and the
    // output the keyboard is on wins over any other.
    // Only this monitor answers. A cell of the same domain on the other screen
    // is not the one meant: pressing a key and having something open where you
    // are not looking is worse than it not opening at all — and there is
    // somewhere for it to appear here, which is the whole point of the host.
    // With no focused output to go by, any of them will do.
    function cellFor(domain, output) {
        let best = null;
        let rank = -1;

        for (const cell of root.known) {
            if (!cell || cell.domain !== domain)
                continue;
            if (output && cell.output !== output)
                continue;

            // Three ranks, in the order of how much the asking is *for* them:
            // a cell that exists only when it is asked for, then one that says
            // it answers, then one that is simply on screen already. A cell
            // that is neither declared nor currently shown is not an answer at
            // all — a conditional cell with nothing to report has nothing to
            // open — and the summoned copy is what that asking gets.
            const asked = cell.visibility.type === "invoked" ? 3
                        : cell.visibility.invocable ? 2
                        : cell.shown ? 1 : 0;
            if (asked === 0)
                continue;
            if (asked > rank) {
                best = cell;
                rank = asked;
            }
        }
        return best;
    }

    // What a keybind file can be written against: every cell the shell knows
    // how to build, not only the ones placed somewhere. A domain with no place
    // of its own is precisely the one a shortcut is for — it has nowhere else
    // to be reached from — so leaving it out of the list would hide the cells
    // that need the list most.
    readonly property var domains: {
        const out = [];
        for (const domain in Registry.files)
            out.push(domain);
        for (const cell of root.known)
            if (cell && out.indexOf(cell.domain) < 0)
                out.push(cell.domain);
        return out.sort();
    }

    // Where a cell with no place of its own appears. One host per monitor,
    // empty until something is asked for.
    property var hosts: []

    function offerHost(surface) {
        if (root.hosts.indexOf(surface) < 0)
            root.hosts = root.hosts.concat([surface]);
    }

    function withdrawHost(surface) {
        const index = root.hosts.indexOf(surface);
        if (index >= 0) {
            const next = root.hosts.slice();
            next.splice(index, 1);
            root.hosts = next;
        }
    }

    function hostFor(output) {
        let fallback = null;
        for (const surface of root.hosts) {
            if (!surface)
                continue;
            const name = surface.screenItem ? surface.screenItem.name : "";
            if (output && name === output)
                return surface;
            if (!fallback)
                fallback = surface;
        }
        return fallback;
    }

    // What a shortcut does, and it depends on where the cell lives.
    //
    // A cell that is somewhere on the screen already — on a membrane, or in a
    // floating tissue the configuration declares — is opened where it is: the
    // invocation is the ordinary anchored opening, and nothing moves. A cell
    // that is nowhere has no place to be opened *in*, so it is summoned into
    // the middle of the screen the keyboard is pointed at. Akusen's rule,
    // 2026-09-22, and it is the one that makes the floating form free: nothing
    // has to be declared twice.
    function invoke(domain, output) {
        const cell = root.cellFor(domain, output);
        if (cell) {
            if (cell.visibility.type === "invoked") {
                cell.visibility.toggle();
                cell.open = cell.visibility.invoked && cell.hasPanel;
            } else {
                cell.open = !cell.open;
            }
            return true;
        }

        const host = root.hostFor(output);
        if (!host)
            return false;

        // Asking twice puts it away, the way a shortcut does everywhere else.
        if (host.summoned === domain) {
            host.dismiss();
            return true;
        }
        return host.summon(domain);
    }

    function retire(domain, output) {
        const cell = root.cellFor(domain, output);
        if (cell) {
            cell.open = false;
            if (cell.visibility.type === "invoked")
                cell.visibility.invoked = false;
            return true;
        }

        const host = root.hostFor(output);
        if (host && host.summoned === domain) {
            host.dismiss();
            return true;
        }
        return false;
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
