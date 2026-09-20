import QtQuick
import Quickshell
import qs.core
import qs.cells
import qs.components

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

    readonly property real contentLength: {
        revision;
        let total = 0;
        let visible = 0;
        for (const cell of root.cells) {
            if (!cell.shown)
                continue;
            total += root.grantFor(cell);
            visible++;
        }
        return visible === 0 ? 0 : total + gap * (visible - 1);
    }

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
            cell.contractedWidthChanged.connect(root.bump);
            cell.shownChanged.connect(root.bump);
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
            if (!cell.shown)
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
    }

    onRevisionChanged: relayout()
    onPaddingChanged: relayout()
    onSlotLengthChanged: relayout()

    // ---- Background --------------------------------------------------------
    //
    // The band is drawn **only in the band**. One rectangle behind the cells
    // would put the tissue fill between the blurred background and the cell
    // glass: the blur would be seen through two layers and the cell's opacity
    // would stop meaning what it declares.
    //
    // So it is a ring — it follows the outer radius, which a band tiled out of
    // plain rectangles cannot — plus one straight bridge in each gap between
    // two cells. Nothing is drawn where a cell is.

    readonly property color bandColour: Qt.alpha(Theme.elevated, fillOpacity)

    Ring {
        anchors.fill: parent
        radius: root.radius
        thickness: root.padding
        innerRadius: root.cellRadius
        colour: root.bandColour
        z: -1
    }

    // The bridges: the band showing through between two cells, a gap wide and
    // as tall as the cells themselves. Each binds to its neighbours' live
    // geometry, so the band follows a reflow frame by frame rather than being
    // recomputed after it.
    Repeater {
        model: root.cells.length

        delegate: Rectangle {
            required property int index

            readonly property Item cell: root.cells[index]
            readonly property Item previous: {
                root.revision;
                for (let i = index - 1; i >= 0; i--)
                    if (root.cells[i].shown)
                        return root.cells[i];
                return null;
            }

            visible: cell !== undefined && cell.shown && previous !== null
            color: root.bandColour
            z: -1

            x: root.horizontal ? (previous ? previous.x + previous.width : 0) : root.padding
            y: root.horizontal ? root.padding : (previous ? previous.y + previous.height : 0)
            width: root.horizontal ? (visible ? Math.max(0, cell.x - x) : 0) : root.width - root.padding * 2
            height: root.horizontal ? root.height - root.padding * 2 : (visible ? Math.max(0, cell.y - y) : 0)
        }
    }

    // What the membrane needs in order to declare its blur region and its input
    // mask: the shape of every visible cell, never the band.
    function shapes() {
        const out = [];
        for (const cell of root.cells)
            if (cell.shown)
                out.push(cell.shape());
        return out;
    }
}
