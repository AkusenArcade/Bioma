pragma Singleton

import QtQuick
import Quickshell

// Scale is a discrete step set, not a free value, and it is a membrane
// property — a smaller second monitor can run `compact`.
//
// Scale and density are separate concerns. Wayland reports each surface's
// output scale factor and Qt applies it, so everything here is written as
// though that factor were 1: these are logical units, the equivalent of
// Android `dp`. Scale is the aesthetic preference layered on top; it
// multiplies the density, it does not replace it.
//
// The base figures are the ones in docs/design/tokens.css, at `normal`.
Singleton {
    id: root

    // ---- Base geometry, logical units, normal scale ------------------------

    readonly property real cellHeight: 40      // every contracted cell
    readonly property real rowHeight: 30       // list rows: icon 20, name, value
    readonly property real fieldHeight: 40     // search and text fields

    // The three margins the settings cell offers, and the only geometry in the
    // token set a person is meant to move: the frame around the screen, the
    // line a tissue keeps around its cells, and the distance between the
    // shapes of one open cell. The figures below are the handoff's, and they
    // are what the shell uses until somebody says otherwise.
    readonly property real marginEdge: Config.get("appearance.edge", 12)
    readonly property real gapShape: Config.get("appearance.gap", 24)

    // The tissue margin is `tissue.padding`, where it has always been, and the
    // clamp that keeps it a margin rather than a tray lives here — it used to
    // be written out at each of the four places that read the key, and a
    // second key for the same distance under `appearance` was worse: one of
    // the two was bound to nothing.
    readonly property real marginTissue: Math.max(2, Math.min(12, Config.get("tissue.padding", 2)))

    readonly property real radiusPanel: 20     // fixed, for rectangular content
    readonly property real radiusWell: 10      // concentric inside a panel
    readonly property real pillCeiling: 110    // above this, radius 20 rather than 100%

    readonly property real blurRadius: 20      // glass; niri owns the real one

    // ---- Critical dimensions ----------------------------------------------
    //
    // Hairlines do not take the scale step: a thread is 1.3 px because that is
    // the weight at which it reads as a connection rather than as an edge, and
    // multiplying it by an aesthetic preference only smears it. They are
    // rounded to whole physical pixels instead — see `crisp`.

    readonly property real thread: 1.3
    readonly property real nodeSize: 2.5
    readonly property real rimWidth: 1

    // ---- Steps -------------------------------------------------------------

    readonly property var factors: ({
        "compact": 0.85,
        "normal": 1.0,
        "comfortable": 1.15
    })

    function factor(name) {
        return root.factors[name] !== undefined ? root.factors[name] : 1.0;
    }

    // Everything a membrane, a tissue or a cell needs at one step. Density
    // values scale; hairlines do not.
    function step(name) {
        const f = root.factor(name);
        return {
            "name": root.factors[name] !== undefined ? name : "normal",
            "factor": f,

            "cellHeight": root.cellHeight * f,
            "rowHeight": root.rowHeight * f,
            "fieldHeight": root.fieldHeight * f,

            "marginEdge": root.marginEdge * f,
            "tissuePadding": root.marginTissue * f,
            "gap": root.gapShape * f,

            "radiusPanel": root.radiusPanel * f,
            "radiusWell": root.radiusWell * f,
            "pillCeiling": root.pillCeiling * f,

            "thread": root.thread,
            "nodeSize": root.nodeSize,
            "rimWidth": root.rimWidth,
            "blurRadius": root.blurRadius * f,

            // Type scale. Sizes live here because they follow the density step;
            // families, weights and numeral features live in Typography.
            //
            // Rounded, because Qt's `font.pixelSize` is an integer and silently
            // truncates a fractional one — the 14.5 of the design lands on 14
            // rather than 15, and every string in the shell is a little small.
            "fontValue": Math.round(20 * f),
            "fontLabel": Math.round(15 * f),
            "fontSecondary": Math.round(13 * f),
            "fontMeta": Math.round(11 * f),
            "fontTitle": Math.round(14.5 * f)
        };
    }

    // A pill up to the ceiling, the panel radius above it. Past 110 px the cap
    // reaches sixty or eighty pixels, stops being a border and starts dictating
    // the content — eating the corners of images and lists.
    function radiusFor(height, metrics) {
        const m = metrics || root.step("normal");
        return height <= m.pillCeiling ? height / 2 : m.radiusPanel;
    }

    // Concentric by construction: a well inset by `inset` inside a shape of
    // radius `outer` takes outer − inset, never below zero.
    function innerRadius(outer, inset) {
        return Math.max(0, outer - inset);
    }

    // Lands a dimension on a whole physical pixel without forcing it to at
    // least one: the position and size of a small shape, where `crisp` would
    // turn a zero into a pixel.
    function snap(logical, devicePixelRatio) {
        const ratio = devicePixelRatio > 0 ? devicePixelRatio : 1;
        return Math.round(logical * ratio) / ratio;
    }

    // Hairlines, thread strokes and icon strokes must land on whole physical
    // pixels under fractional scaling, or they blur or vanish. Layouts stay
    // fluid — only critical dimensions are rounded.
    function crisp(logical, devicePixelRatio) {
        const ratio = devicePixelRatio > 0 ? devicePixelRatio : 1;
        return Math.max(1, Math.round(logical * ratio)) / ratio;
    }
}
