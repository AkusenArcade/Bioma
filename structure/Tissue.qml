import QtQuick
import Quickshell
import qs.core
import qs.cells

// A positioned container. Owns anchor, margins, orientation, padding, opacity
// and the ordered list of its cells. It has no opinion about what a cell shows.
//
// The percentage a tissue declares is a **ceiling, not a reservation**: the
// tissue is as long as its visible cells need, up to that ceiling. That is why
// collision between tissues on one membrane is impossible by construction.
//
// See PRD §4.2 and §4.4, and docs/design/STYLE_GUIDE.md §5, §7.
Item {
    id: root

    // ---- Configuration -----------------------------------------------------

    property var metrics: Metrics.step("normal")
    property var cellsConfig: []

    // The membrane's monitor, passed through to the cells that answer per
    // screen rather than per session.
    property string output: ""

    // And its edge, so an expansion knows which way is away from the screen,
    // plus the line the compositor's windows begin on: a panel hangs from
    // there, so the thread is however long it has to be to reach it.
    property string edge: "top"
    property real windowLine: 0
    property bool opensAway: true

    readonly property real originGap: {
        const outer = opensAway ? y + padding + metrics.cellHeight : y + padding;
        return Math.max(0, opensAway ? windowLine - outer : outer - windowLine);
    }

    property bool floating: false
    property string orientation: "horizontal"
    readonly property bool horizontal: orientation === "horizontal"

    // Where the tissue sits inside the length its membrane granted it, and
    // therefore which way it grows: a corner tissue stacks inward so existing
    // cells never shift when a new one appears, a centre tissue redistributes
    // symmetrically. One rule, two anchors.
    property string anchorSide: "start"    // "start" | "centre" | "end"
    property real slotLength: 0            // the ceiling, in logical units

    // 2–12. The tissue background is a surface, not a border: at a wide padding
    // the band reads as a tray.
    property real padding: Math.max(2, Math.min(12, Config.get("tissue.padding", 2)))
    property real fillOpacity: Config.get("tissue.opacity", 0.5)

    // The gap between two cells is the band showing through, and it is the same
    // margin on each side — so twice the padding, which is what the design page
    // draws (4 px at the default 2).
    readonly property real gap: padding * 2

    // ---- Geometry ----------------------------------------------------------

    readonly property real thickness: metrics.cellHeight + padding * 2

    // Concentric by construction: the cell radius is the tissue's minus the
    // padding, at every value of the user's radius percentage.
    readonly property real radiusPercent: Config.get("appearance.radius", 100)
    readonly property real radius: (radiusPercent / 100) * Metrics.radiusFor(thickness, metrics)
    readonly property real cellRadius: Metrics.innerRadius(radius, padding)

    // Recomputed whenever a cell appears, disappears or changes width. Reading
    // it inside the length expressions is what makes them re-evaluate.
    property int revision: 0

    function bump() {
        root.revision++;
    }

    // ---- What actually fits ------------------------------------------------
    //
    // The percentage is a ceiling, and a ceiling that is only respected by the
    // band is not a ceiling at all: the cells were laid out in a row from the
    // anchor whatever their total came to, so on a narrow monitor the last of
    // them stood outside the band and, far enough over, outside the screen.
    //
    // So the tissue hands out room by precedence first and anchor order second
    // — the cells against the screen edge are the settled ones, and a tissue
    // grows inward from there — and a cell it cannot fit is not placed at all.
    // It waits: the moment its neighbours need less, it takes its place back.
    //
    // Precedence before position, because position is where a cell is and
    // precedence is whether it has anything to say. A recording asking to be
    // saved keeps its place and the theme chips wait; the reverse was tried
    // first and it drops the one cell that has to be answerable.
    readonly property var placement: {
        revision;
        const ceiling = root.slotLength > 0 ? root.slotLength - root.padding * 2
                                            : Number.MAX_VALUE;

        const order = root.anchorSide === "end" ? root.cells.slice().reverse()
                                                : root.cells.slice();
        const placed = [];
        let used = 0;

        // Taken in bands rather than by sorting: within one band the anchor
        // order decides, and that order has to be exactly the declared one.
        for (const level of [2, 1, 0]) {
            for (const cell of order) {
                if (!cell.shown || cell.precedence !== level)
                    continue;
                const grant = root.grantFor(cell);
                const before = placed.length > 0 ? root.gap : 0;
                if (used + before + grant > ceiling + 0.5)
                    continue;
                used += before + grant;
                placed.push(cell);
            }
        }

        return { "cells": placed, "length": used };
    }

    readonly property real contentLength: root.placement.length

    readonly property real length: Math.min(slotLength > 0 ? slotLength : Number.MAX_VALUE,
                                            contentLength + padding * 2)

    width: horizontal ? length : thickness
    height: horizontal ? thickness : length

    // A tissue changes length whenever a cell appears, disappears or takes a
    // longer string. That change is the reflow, and the PRD calls it a design
    // moment rather than an incidental animation — so the tissue grows at the
    // same rate as the cells inside it, and a centred tissue is re-placed from
    // this animated width, which is what makes it grow from its middle instead
    // of jumping to a new centre.
    Behavior on width {
        NumberAnimation {
            duration: Timing.reflow
            easing.type: Easing.Bezier
            easing.bezierCurve: Timing.easeOpenFlat
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: Timing.reflow
            easing.type: Easing.Bezier
            easing.bezierCurve: Timing.easeOpenFlat
        }
    }

    // A tissue with nothing to show is not an empty tray.
    visible: contentLength > 0

    // ---- Cells -------------------------------------------------------------
    //
    // Built here rather than by a Repeater and a Loader: a Loader with an
    // explicit size overwrites the size bindings a cell holds over itself, and
    // a cell owns its own width — contracted or expanded — by design.

    property list<Item> cells: []

    Item {
        id: cellHost
        anchors.fill: parent
    }

    function build() {
        for (const existing of root.cells)
            existing.destroy();
        root.cells = [];

        const built = [];
        for (const entry of root.cellsConfig) {
            if (entry.enabled === false)
                continue;

            const component = Registry.component(entry.type);
            if (!component)
                continue;

            const cell = component.createObject(cellHost, {
                "metrics": Qt.binding(() => root.metrics),
                "radius": Qt.binding(() => root.cellRadius),
                "origin": Qt.binding(() => root.anchorSide),
                "originGap": Qt.binding(() => root.originGap),
                "output": Qt.binding(() => root.output),
                "edge": Qt.binding(() => root.edge),
                "config": entry
            });

            if (!cell) {
                console.warn(`Bioma: cell "${entry.type}" failed to instantiate`);
                continue;
            }

            // `contractedWidth` is the one that must be watched: it is what a
            // cell asks for. Listening to `width` alone deadlocks — the width
            // only changes once the layout runs, and the layout only runs once
            // the width changes — and the cell never grows to fit its content.
            // What the tissue could not fit follows the placement rather than
            // being assigned while laying out: the membrane rebuilds its mask
            // and its blur region from the same signal, and an assignment made
            // half-way through a layout pass reaches it in whatever order the
            // handlers happen to run in.
            cell.crowded = Qt.binding(() => cell.shown && root.placement.cells.indexOf(cell) < 0);

            cell.contractedWidthChanged.connect(root.bump);
            cell.shownChanged.connect(root.bump);
            // A panel coming or going changes what the membrane has to mask
            // and blur, and the membrane is listening to this. So does the
            // moment it finishes growing: a region bound while the shape was
            // still a point describes a point, and the shell would go on
            // treating the panel as though it were not there.
            cell.panelVisibleChanged.connect(root.bump);
            cell.panelReadyChanged.connect(root.bump);
            built.push(cell);
        }

        root.cells = built;
        root.bump();
    }

    onCellsConfigChanged: build()
    Component.onCompleted: build()

    // ---- Layout ------------------------------------------------------------
    //
    // Fixed order, variable position. A cell appearing reflows the whole
    // tissue, always-visible cells included, so the tissue always behaves the
    // same way.

    // What one cell may occupy. An elastic cell takes the space the others
    // leave, capped by its own limit — it does not fill space it has no content
    // for, or a title cell would sit in a pill the width of a monitor.
    function grantFor(cell) {
        if (!cell.elastic)
            return cell.contractedWidth;
        const share = root.elasticShare;
        return Math.max(cell.minWidth, Math.min(cell.contractedWidth, share));
    }

    // Equal share among the elastic cells, each capped by its own limit, the
    // remainder redistributed. With one elastic cell — the usual case — this is
    // simply what the others left.
    readonly property real elasticShare: {
        revision;
        if (slotLength <= 0)
            return Number.MAX_VALUE;

        let fixed = 0;
        let elastic = 0;
        let visible = 0;
        for (const cell of root.cells) {
            if (!cell.shown)
                continue;
            visible++;
            if (cell.elastic)
                elastic++;
            else
                fixed += cell.contractedWidth;
        }
        if (elastic === 0)
            return 0;

        const gaps = visible > 0 ? gap * (visible - 1) : 0;
        const free = slotLength - padding * 2 - gaps - fixed;
        return Math.max(0, free / elastic);
    }

    function relayout() {
        let offset = padding;
        for (const cell of root.cells) {
            if (!cell.placed)
                continue;

            const grant = root.grantFor(cell);
            cell.grantedWidth = grant;

            if (horizontal) {
                cell.x = offset;
                cell.y = padding;
            } else {
                cell.x = padding;
                cell.y = offset;
            }
            offset += grant + gap;
        }

        settled.restart();
    }

    // A cell missing from a membrane is a configuration that does not fit this
    // monitor, and the only place that can be noticed is here — but only once
    // the reflow has finished. Cells cross each other's widths while they grow,
    // and a message sent from inside that crossing names whichever cell was
    // momentarily too wide, which is how the log starts crying wolf.
    property string lastCrowding: ""

    Timer {
        id: settled
        interval: Timing.reflow + 80
        onTriggered: {
            const crowded = [];
            for (const cell of root.cells)
                if (cell.crowded)
                    crowded.push(cell.domain);

            const said = crowded.join(", ");
            if (said === root.lastCrowding)
                return;
            root.lastCrowding = said;
            if (said.length > 0)
                console.info(`Bioma: the ${root.edge} membrane on ${root.output || "this monitor"} `
                             + `grants less room than its cells ask for — ${said} `
                             + `${crowded.length > 1 ? "are" : "is"} waiting for space`);
        }
    }

    onRevisionChanged: relayout()
    onPaddingChanged: relayout()
    onSlotLengthChanged: relayout()

    // ---- Background --------------------------------------------------------
    //
    // One continuous fill, behind the cells, following the tissue's own radius.
    //
    // docs/design/IMPLEMENTATION.md asks for the fill to be drawn only in the
    // band, with the cell areas punched out of it, so that cell blur is not
    // seen through two layers. That was tried first and it is wrong at this
    // scale: with a 2 px margin the punched band *is* a one-pixel outline
    // around every cell plus a rule standing in the gap between two of them,
    // which is exactly what the design forbids. The design page draws the
    // tissue as a plain background behind its cells, and so does this.
    //
    // The cost is real and worth stating: a cell composites over the band
    // rather than straight over the blurred desktop, so its declared opacity
    // reads a little heavier than the number says.

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.elevated, root.fillOpacity)
        radius: root.radius
        antialiasing: true
        z: -1
    }

    // What the membrane needs in order to declare its blur region and its input
    // mask: the shape of every visible cell, never the band.
    function shapes() {
        const out = [];
        for (const cell of root.cells)
            if (cell.placed)
                out.push(cell.shape());
        return out;
    }
}
