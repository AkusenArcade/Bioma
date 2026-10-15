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

    // ---- The keyboard inside the open cell ----------------------------------
    //
    // Arrows move, Enter and Space act, Tab walks in reading order (Akusen,
    // 2026-10-10). Only inside the cell that is open: cells are reached by
    // their own shortcuts, so there is no second way of travelling between
    // them to learn.
    //
    // **Nothing is marked until a key asks for it.** At rest the interface
    // does not speak, and a hand on the pointer has no use for a mark it did
    // not ask for. The first key marks what is nearest to where the cell was
    // born — the expansion grows from there, so that is where the eye already
    // is — and acts as nothing else.
    //
    // What can be reached says so itself, with `navigable: true`, and answers
    // `activate()` — and `adjust(step)` if Left and Right change its value
    // rather than leave it, and `discard()` if it can be removed: Delete is
    // the keyboard's way to the cross a row shows only under the pointer. A slider is the case: travelling off it sideways
    // would leave no way of moving it. Every stop draws its own `KeyMark`.
    // Nothing is registered: the stops are found by walking the open cell, so
    // a row that arrives in a list is reachable the moment it is drawn and one
    // that leaves takes nothing with it.
    //
    // Something that opens over the rest — a dropdown's list — says
    // `keyScope: true` while it is out. The arrows then stay inside it, as the
    // pointer does, and Escape calls its `close()` before it closes the cell.

    property Item marked: null

    // Where the mark was, so a stop that leaves under it — a stream that ends
    // — hands the mark to whatever is nearest, not back to the beginning.
    property point lastMark: Qt.point(-1, -1)

    onCellChanged: {
        root.marked = null;
        root.lastMark = Qt.point(-1, -1);
    }

    // The keys a shell surface did not use for itself. True when the event
    // was answered here.
    function key(event) {
        if (!root.cell)
            return false;
        // A chord is somebody else's.
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;

        switch (event.key) {
        case Qt.Key_Escape: {
            const scope = root.scope();
            if (!scope || typeof scope.close !== "function")
                return false;
            scope.close();
            return true;
        }
        case Qt.Key_Up:
            return root.travel(0, -1);
        case Qt.Key_Down:
            return root.travel(0, 1);
        case Qt.Key_Left:
            return root.sideways(-1);
        case Qt.Key_Right:
            return root.sideways(1);
        case Qt.Key_Tab:
            return root.walk(event.modifiers & Qt.ShiftModifier ? -1 : 1);
        case Qt.Key_Backtab:
            return root.walk(-1);
        case Qt.Key_Delete:
            if (!root.marked || typeof root.marked.discard !== "function")
                return false;
            root.marked.discard();
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (!root.marked || typeof root.marked.activate !== "function")
                return false;
            root.marked.activate();
            return true;
        }
        return false;
    }

    function sideways(step) {
        if (root.marked && typeof root.marked.adjust === "function") {
            root.marked.adjust(step);
            return true;
        }
        return root.travel(step, 0);
    }

    // Every stop the open cell has on screen now, with its rectangle in the
    // cell's coordinates. Shown means shown: hidden, or faded to nothing, is
    // not somewhere the hand can be sent.
    function stops() {
        const out = [];
        const visit = item => {
            if (!item || !item.visible || item.opacity <= 0)
                return;
            if (item.navigable === true && item.width > 0 && item.height > 0) {
                const at = item.mapToItem(root.cell, 0, 0);
                out.push({ "item": item, "x": at.x, "y": at.y, "w": item.width, "h": item.height });
            }
            for (const child of item.children)
                visit(child);
        };
        visit(root.scope() || root.cell);
        return out;
    }

    // What is open over the rest of the cell, if anything.
    function scope() {
        if (!root.cell)
            return null;
        let found = null;
        const visit = item => {
            if (found || !item || !item.visible)
                return;
            if (item.keyScope === true) {
                found = item;
                return;
            }
            for (const child of item.children)
                visit(child);
        };
        visit(root.cell);
        return found;
    }

    function rectOf(item) {
        const at = item.mapToItem(root.cell, 0, 0);
        return { "item": item, "x": at.x, "y": at.y, "w": item.width, "h": item.height };
    }

    // The nearest stop to a point, by its centre.
    function nearest(list, x, y) {
        let best = null;
        let distance = Infinity;
        for (const s of list) {
            const d = Math.hypot(s.x + s.w / 2 - x, s.y + s.h / 2 - y);
            if (d < distance) {
                best = s;
                distance = d;
            }
        }
        return best;
    }

    // The first key: nothing is marked yet, or what was has gone.
    function begin(list) {
        const from = root.lastMark.x >= 0 ? root.lastMark
                                           : Qt.point(root.cell.width / 2, root.cell.height / 2);
        return root.nearest(list, from.x, from.y);
    }

    function travel(dx, dy) {
        const list = root.stops();
        if (list.length === 0)
            return false;
        if (!root.marked) {
            root.mark(root.begin(list));
            return true;
        }

        const from = root.rectOf(root.marked);
        const best = (dy !== 0 ? root.nextLine(list, from, dy) : null)
                     || root.ahead(list, from, dx, dy);
        // At the edge the mark stays where it is: the key was still meant
        // for this cell, and it must not go on to anything underneath.
        if (best)
            root.mark(best);
        return true;
    }

    // Up and Down inside one surface go to the next line, and on it to
    // whatever is nearest across: a panel is read in lines, and a button at
    // the far side of the next one is still the next thing down. Measured
    // from the marked stop alone, the column of switches down the right of
    // the connectivity panel skipped every button on the left.
    function nextLine(list, from, dy) {
        const home = root.surfaceOf(root.marked);
        const fromY = from.y + from.h / 2;
        const fromX = from.x + from.w / 2;
        const ahead = list.filter(s => s.item !== root.marked
                                       && (s.y + s.h / 2 - fromY) * dy > 0.5
                                       && root.surfaceOf(s.item) === home);
        if (ahead.length === 0)
            return null;
        let nearest = Infinity;
        for (const s of ahead)
            nearest = Math.min(nearest, (s.y + s.h / 2 - fromY) * dy);
        let best = null;
        let cross = Infinity;
        for (const s of ahead) {
            const along = (s.y + s.h / 2 - fromY) * dy;
            if (along > nearest + Math.min(from.h, s.h) / 2)
                continue;
            const off = Math.abs(s.x + s.w / 2 - fromX);
            if (off < cross) {
                best = s;
                cross = off;
            }
        }
        return best;
    }

    // Anywhere else — sideways, or out of one surface into the next — ahead
    // in the direction asked, then as little out of line as possible. Out of
    // line is measured between the two spans, not the centres: rows of one
    // list all overlap, and the nearest of them is the next one whatever its
    // width.
    function ahead(list, from, dx, dy) {
        const fromAlong = dx !== 0 ? from.x + from.w / 2 : from.y + from.h / 2;
        const fromCross = dx !== 0 ? from.y + from.h / 2 : from.x + from.w / 2;
        let best = null;
        let score = Infinity;
        for (const s of list) {
            if (s.item === root.marked)
                continue;
            const along = ((dx !== 0 ? s.x + s.w / 2 : s.y + s.h / 2) - fromAlong) * (dx + dy);
            if (along <= 0.5)
                continue;
            const lo = dx !== 0 ? Math.max(from.y, s.y) : Math.max(from.x, s.x);
            const hi = dx !== 0 ? Math.min(from.y + from.h, s.y + s.h)
                                : Math.min(from.x + from.w, s.x + s.w);
            const gap = Math.max(0, lo - hi);
            // Further out of line than ahead is not in that direction: Right
            // on a row with nothing beside it found the capsule's slider four
            // rows up, the only thing further right.
            if (gap > along)
                continue;
            const cross = Math.abs((dx !== 0 ? s.y + s.h / 2 : s.x + s.w / 2) - fromCross);
            const value = along + gap * 3 + cross * 0.1;
            if (value < score) {
                best = s;
                score = value;
            }
        }
        return best;
    }

    // The surface a stop is drawn on: the nearest `Panel` above it, known by
    // the growth it is born with — or the cell itself.
    function surfaceOf(item) {
        for (let up = item.parent; up && up !== root.cell; up = up.parent)
            if (up.growth !== undefined && up.targetWidth !== undefined)
                return up;
        return root.cell;
    }

    // Tab: reading order, top to bottom and then along the line, round
    // again at the end — one surface at a time, in the order the surfaces
    // are read: taken by height alone, the settings categories and the page
    // beside them were interleaved, a capsule and a slider in turn.
    function walk(step) {
        const list = root.stops();
        if (list.length === 0)
            return false;
        if (!root.marked) {
            root.mark(root.begin(list));
            return true;
        }
        const inReading = (a, b) => {
            const line = Math.min(a.h, b.h) / 2;
            const dy = (a.y + a.h / 2) - (b.y + b.h / 2);
            return Math.abs(dy) > line ? dy : (a.x - b.x);
        };
        const first = new Map();
        for (const s of list) {
            s.surface = root.surfaceOf(s.item);
            const known = first.get(s.surface);
            if (!known || inReading(s, known) < 0)
                first.set(s.surface, s);
        }
        list.sort((a, b) => a.surface === b.surface ? inReading(a, b)
                                                    : inReading(first.get(a.surface), first.get(b.surface)));
        let index = list.findIndex(s => s.item === root.marked);
        index = index < 0 ? 0 : (index + step + list.length) % list.length;
        root.mark(list[index]);
        return true;
    }

    // A field the keyboard opened, while it is being typed into. The mark
    // lets go so the caret is the one thing that says where typing goes —
    // and when the mark moves on, the field lets go of the keys too, or Enter
    // and every letter would still be going into it. The focus goes to the
    // stop rather than nowhere: a key it does not use has to rise through the
    // tissue to reach this register again.
    property Item field: null

    function type(field) {
        root.marked = null;
        root.field = field;
        const at = field.mapToItem(root.cell, field.width / 2, field.height / 2);
        root.lastMark = Qt.point(at.x, at.y);
        field.forceActiveFocus();
    }

    // And a field can let go by itself: Enter or Escape put its focus down,
    // or it is hidden with the form it was in. The keys would then go to no
    // item at all — the surface still has them, but nothing on it is a
    // descendant of the tissue, so neither the arrows nor Escape would arrive
    // anywhere. The nearest stop takes them instead, marked.
    readonly property bool fieldFocused: root.field ? root.field.activeFocus : false

    onFieldFocusedChanged: {
        if (root.fieldFocused || !root.field)
            return;
        root.field = null;
        Qt.callLater(() => {
            if (!root.cell)
                return;
            const near = root.nearest(root.stops(), root.lastMark.x, root.lastMark.y);
            if (!near)
                return;
            root.marked = near.item;
            near.item.forceActiveFocus();
        });
    }

    function mark(stop) {
        if (!stop)
            return;
        const typing = root.field;
        root.field = null;
        if (typing && typing.activeFocus)
            stop.item.forceActiveFocus();
        root.marked = stop.item;
        root.lastMark = Qt.point(stop.x + stop.w / 2, stop.y + stop.h / 2);
        root.reveal(stop.item);
    }

    // A stop in a list longer than its room is brought into view: the mark
    // has to be somewhere the eye can follow it to.
    function reveal(item) {
        for (let up = item.parent; up && up !== root.cell; up = up.parent) {
            if (up.contentItem === undefined || up.contentY === undefined
                || typeof up.returnToBounds !== "function")
                continue;
            const top = item.mapToItem(up.contentItem, 0, 0).y;
            const bottom = top + item.height;
            const lowest = Math.max(0, up.contentHeight - up.height) + up.originY;
            if (top < up.contentY)
                up.contentY = Math.max(up.originY, top);
            else if (bottom > up.contentY + up.height)
                up.contentY = Math.min(lowest, bottom - up.height);
            return;
        }
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
        // Held here, because closing it releases it: `root.cell` is already
        // null by the line after `open = false`.
        const cell = root.cell;
        if (!cell)
            return;
        cell.open = false;
        if (cell.visibility.invocable)
            cell.visibility.invoked = false;
    }

    // ---- Cells that answer to a name ---------------------------------------
    //
    // A shortcut does not reach a cell directly: it reaches the shell, which
    // asks this register for the cell of that domain. The register is what
    // makes "launcher, session menu and settings are not a separate category"
    // true in code (PRD §5) — there is no second model for invoked surfaces.
    //
    // **Every cell is in it, and every cell answers** (Akusen's rule,
    // 2026-09-23): on a membrane it opens where it is, in a floating slot it
    // appears there, and placed nowhere on the monitor it is summoned into the
    // middle. A cell has one place per monitor — the Structure page will not
    // give it a second — so the answer is never a guess.
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

            // Every cell answers its name — on a membrane it opens where it
            // is, in a floating slot it appears there. One cell per domain per
            // monitor is the Structure page's rule; a block whose visibility
            // is `invoked` (the summoned copy, or an old configuration) still
            // wins over one that is simply placed.
            const asked = cell.visibility.type === "invoked" ? 2 : 1;
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
            if (!Registry.isInternal(domain))
                out.push(domain);
        for (const cell of root.known)
            if (cell && out.indexOf(cell.domain) < 0 && !Registry.isInternal(cell.domain))
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
        domain = Registry.canonical(domain);
        const cell = root.cellFor(domain, output);
        if (cell) {
            // Asking twice puts it away: open, it closes; there because it was
            // asked for, it goes.
            if (cell.open || cell.visibility.invoked) {
                cell.open = false;
                cell.visibility.invoked = false;
                root.released(cell);
                return true;
            }

            // Asked for, it is shown whatever its visibility says — a
            // conditional cell with nothing to report comes anyway, and goes
            // again when it is closed. Arriving is opening, for a cell that has
            // a panel and does not arrive as its own first shape; one that does
            // claims the attention instead, so a press outside sends it off.
            cell.visibility.invoked = true;
            if (cell.hasPanel && cell.opensOnArrival)
                cell.open = true;
            else
                root.opened(cell);
            return true;
        }

        const host = root.hostFor(output);
        if (!host)
            return false;

        // Asking twice puts it away, the way a shortcut does everywhere else
        // — and it leaves the way it arrived, so the host is asked to retire
        // it rather than to drop it.
        if (host.summoned === domain) {
            host.retire();
            return true;
        }
        return host.summon(domain);
    }

    function retire(domain, output) {
        domain = Registry.canonical(domain);
        const cell = root.cellFor(domain, output);
        if (cell) {
            cell.open = false;
            if (cell.visibility.type === "invoked")
                cell.visibility.invoked = false;
            return true;
        }

        const host = root.hostFor(output);
        if (host && host.summoned === domain) {
            host.retire();
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
