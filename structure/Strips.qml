pragma Singleton

import QtQuick
import Quickshell
import qs.core
import qs.services

// Where the windows begin, seen from one edge of one screen.
//
// Two things on a screen are placed by the line the windows start on rather
// than by the screen's edge: a floating tissue anchored to an edge, and the
// organisms, which live in what the membranes leave free. Both need the same
// answer, so it is given here once.
//
// Not `Edges`: Quickshell exports an `Edges` type of its own, and it shadows a
// singleton of that name the way QtQuick's `Scale` shadows one (CLAUDE.md).
Singleton {
    id: root

    // Which monitor a block belongs to — a membrane's, a floating tissue's or
    // an organism's. `primary` is the first screen the compositor reports
    // (niri has no notion of a primary output) and `all` is every one.
    function belongs(entry, screen) {
        const monitor = entry.monitor || "primary";
        if (monitor === "all" || monitor === "*")
            return true;
        if (monitor === "primary")
            return Quickshell.screens.length > 0 && Quickshell.screens[0] === screen;
        return screen && screen.name === monitor;
    }

    // The density the membranes run at — this screen's, else any — for an
    // edge that has no membrane of its own. The register holds the floating
    // surfaces too; only what has a strip is a membrane.
    function stripMetrics(screenItem, fallback) {
        let any = null;
        for (const membrane of Focus.membranes) {
            if (!membrane || membrane.strip === undefined)
                continue;
            if (membrane.screenItem === screenItem)
                return membrane.metrics;
            any = any || membrane.metrics;
        }
        return any || fallback;
    }

    // The distance from `side` of the screen to the line the windows begin on.
    //
    // A membrane on that edge answers with its strip and the gap niri leaves
    // past it. With none, a top or bottom edge still holds the strip one would
    // take at the membranes' density: one that hides comes back to the same
    // place, and a tissue anchored bottom-left never sits where a cell on the
    // left of a bottom membrane would (Akusen, 2026-09-28 and 2026-10-02). A
    // side edge has no such strip unless a membrane is on it.
    function windowLine(screenItem, side, fallback) {
        for (const membrane of Focus.membranes)
            if (membrane && membrane.screenItem === screenItem && membrane.edge === side)
                return membrane.strip + membrane.windowInset;
        if (side === "top" || side === "bottom") {
            const step = root.stripMetrics(screenItem, fallback);
            return step.marginEdge + step.cellHeight + step.tissuePadding * 2
                + Niri.windowGap + Niri.strutFor(side);
        }
        return fallback.marginEdge;
    }
}
