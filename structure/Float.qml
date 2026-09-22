import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.structure

// A tissue with no membrane: anchored to a corner or centred, over the
// windows, ceding nothing.
//
// The three levels are unchanged — a tissue still holds cells and a cell still
// takes what the tissue grants. What is missing is the edge: there is no strip
// to sit in, no space to reserve and no window line to hang an expansion from,
// so the tissue is placed by an anchor and a pair of margins instead.
//
// This is where the invoked forms live. PRD §5 says a launcher, a session menu
// and a settings page are cells whose visibility is `invoked` and need no
// second model; what they need is somewhere to be born that is not an edge,
// and this is it. CELLS §05 asks for the audio cell centred on the screen as
// the *same* cell it is on the membrane, and §10 hangs the notifications in a
// corner.
//
// The surface is the size of the output and never resizes — the membranes
// learnt that the hard way: a layer surface that changes size draws its
// content twice for a frame, once at each size.
PanelWindow {
    id: root

    required property var screenItem
    property var config: ({})

    // A host is a floating surface with nothing in it: it exists so that a
    // cell nobody has given a place to has somewhere to be. Ask for one by
    // name and it appears here, in the middle of the screen the keyboard is
    // pointed at — Akusen's rule, 2026-09-22: a cell that is on a membrane is
    // opened where it lives, and a cell that is nowhere floats.
    property bool host: false
    property string summoned: ""

    readonly property var declaredCells: root.host
        ? (root.summoned.length > 0
           ? [{ "type": root.summoned, "enabled": true,
                "visibility": { "type": "invoked" } }]
           : [])
        : (root.config.cells || [])

    function summon(domain) {
        if (!root.host)
            return false;
        root.summoned = domain;
        return true;
    }

    function dismiss() {
        root.summoned = "";
    }

    // The cell arrives a moment after it is asked for — it is built from the
    // configuration the way every other cell is — so it is opened when it
    // appears rather than when it is asked for.
    Connections {
        target: tissue
        function onCellsChanged() {
            if (!root.host || root.summoned.length === 0)
                return;
            for (const cell of tissue.cells) {
                if (cell.domain !== root.summoned)
                    continue;
                cell.visibility.invoked = true;
                cell.open = cell.hasPanel;
            }
        }
    }

    // And it is let go once it has finished leaving: a cell cleared at the
    // moment it closes takes its own closing animation with it.
    Connections {
        target: tissue.cells.length > 0 ? tissue.cells[0] : null
        enabled: root.host && root.summoned.length > 0
        function onExpandedChanged() {
            const cell = tissue.cells[0];
            if (cell && !cell.open && !cell.expanded && !cell.visibility.invoked)
                root.dismiss();
        }
        function onShownChanged() {
            const cell = tissue.cells[0];
            if (cell && !cell.shown && !cell.expanded)
                root.dismiss();
        }
    }

    screen: screenItem
    color: "transparent"

    // It floats: it reserves nothing and it is not part of anyone's strip.
    exclusiveZone: -1

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "bioma-float"

    // The same rule the membranes keep: the keyboard is asked for by the cell
    // that needs it and by no other, because a focusable surface is one the
    // compositor moves the focus to. Here it is not a nicety — a launcher
    // that cannot be typed into is not a launcher.
    readonly property bool anyKeyboard: {
        for (const cell of tissue.cells)
            if (cell.open && cell.wantsKeyboard)
                return true;
        return false;
    }

    focusable: anyKeyboard

    readonly property var metrics: Metrics.step(config.scale || "normal")

    // ---- Where it sits -------------------------------------------------------

    readonly property string anchorName: config.anchor || "centre"

    readonly property var margins: config.margins || ({})

    function margin(side) {
        const value = root.margins[side];
        return value !== undefined ? value * root.metrics.factor
                                   : root.metrics.marginEdge;
    }

    readonly property bool atTop: anchorName.indexOf("top") >= 0
    readonly property bool atBottom: anchorName.indexOf("bottom") >= 0
    readonly property bool atLeft: anchorName.indexOf("left") >= 0
    readonly property bool atRight: anchorName.indexOf("right") >= 0

    // What the tissue's cells draw beyond the tissue itself, which for an open
    // cell is the thread and everything hanging off it. Centring the tissue
    // alone would centre the shape a composition *grew from* and leave the
    // composition itself hanging off the bottom of the screen — Akusen's
    // correction, 2026-09-22: the whole cell is what goes in the middle.
    readonly property real reach: {
        let out = 0;
        for (const cell of tissue.cells)
            if (cell.placed && cell.reach > out)
                out = cell.reach;
        return out;
    }

    readonly property real spread: {
        let out = tissue.width;
        for (const cell of tissue.cells)
            if (cell.placed && cell.reachWidth > out)
                out = cell.reachWidth;
        return out;
    }

    readonly property real placedX: atLeft ? root.margin("left")
                                   : atRight ? root.width - tissue.width - root.margin("right")
                                   : (root.width - tissue.width) / 2

    // Anchored to an edge the tissue keeps its margin and the composition
    // hangs where it hangs; centred, the whole of it is centred, which moves
    // the tissue up by half of what hangs below it.
    readonly property real placedY: {
        if (atTop)
            return root.margin("top");
        if (atBottom)
            return root.height - tissue.height - root.margin("bottom");
        return (root.height - tissue.height - root.reach) / 2;
    }

    // An expansion grows away from whatever the tissue is nearest to, and a
    // centred one grows downward: there is more screen below the middle than
    // above it once a panel is as tall as a panel.
    readonly property bool opensDown: !atBottom

    // ---- The tissue ----------------------------------------------------------

    // Only invoked and expanded surfaces carry a shadow, and a floating one
    // carries the deeper of the two: it is the one thing on the screen that is
    // not attached to an edge, and the shadow is what says so.
    RectangularShadow {
        anchors.fill: tissue
        radius: tissue.radius
        blur: 44
        spread: 0
        offset.y: 22
        color: Theme.shadowFloat
        opacity: tissue.visible && tissue.length > 0 ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Timing.transition } }
    }

    Tissue {
        id: tissue

        metrics: root.metrics
        cellsConfig: root.declaredCells
        output: root.screenItem ? root.screenItem.name : ""

        floating: true
        orientation: root.config.orientation || "vertical"
        anchorSide: root.config.anchor_side
                    || (root.atLeft ? "start" : root.atRight ? "end" : "centre")

        // No ceiling: nothing shares this surface, so the tissue is as long as
        // its cells need. A membrane's percentage is about neighbours, and a
        // floating tissue has none.
        slotLength: 0

        padding: root.config.padding !== undefined
                 ? Math.max(2, Math.min(12, root.config.padding))
                 : Math.max(2, Math.min(12, Config.get("tissue.padding", 2)))
        fillOpacity: root.config.opacity !== undefined
                     ? root.config.opacity : Config.get("tissue.opacity", 0.5)

        // Which way its cells open, and the line they open onto. Away from the
        // edge it hangs from, at the same gap a membrane leaves.
        edge: root.atBottom ? "bottom" : "top"
        opensAway: root.opensDown
        windowLine: root.opensDown ? tissue.y + tissue.height + root.metrics.gap
                                   : tissue.y - root.metrics.gap

        x: root.placedX
        y: root.placedY

        onVisibleChanged: root.refreshRegions()
        onRevisionChanged: root.refreshRegions()
        onPlacementChanged: root.refreshRegions()
        onXChanged: root.refreshRegions()
        onYChanged: root.refreshRegions()
    }

    // ---- Blur and input ------------------------------------------------------
    //
    // The same contract a membrane keeps: the shell claims exactly the shapes
    // it draws and nothing else, so a press that is not on a cell goes to the
    // window underneath. Empty until the first rebuild, because a null mask on
    // a surface the size of the output would swallow the screen.

    property var maskRegion: null
    property var blurRegion: null

    Region { id: nothing }

    mask: maskRegion ? maskRegion : nothing
    BackgroundEffect.blurRegion: blurRegion

    // This surface covers the output, so an item's own coordinates are already
    // the output's — which is what the catcher on another surface needs.
    function inputRects() {
        const out = [];
        for (const cell of tissue.cells) {
            if (!cell.placed)
                continue;
            for (const shape of cell.shapes()) {
                const item = shape.item;
                if (!item)
                    continue;
                const here = item.mapToItem(null, 0, 0);
                out.push({
                    "x": here.x,
                    "y": here.y,
                    "width": item.width,
                    "height": item.height,
                    "radius": shape.radius
                });
            }
        }
        return out;
    }

    function refreshRegions() {
        const input = [];
        const blur = [];

        if (tissue.visible) {
            for (const cell of tissue.cells) {
                if (!cell.placed)
                    continue;
                for (const shape of cell.shapes()) {
                    input.push(shape);
                    if (cell.blur)
                        blur.push(shape);
                }
            }
        }

        root.maskRegion = Regions.rebind(root, root.maskRegion, input);
        root.blurRegion = Regions.rebind(root, root.blurRegion, blur);

        Focus.bump();
    }

    Component.onCompleted: {
        Focus.register(root);
        if (root.host)
            Focus.offerHost(root);
        refreshRegions();
    }

    Component.onDestruction: {
        Focus.unregister(root);
        Focus.withdrawHost(root);
    }
}
