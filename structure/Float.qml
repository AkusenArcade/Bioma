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

    readonly property real placedX: atLeft ? root.margin("left")
                                   : atRight ? root.width - tissue.width - root.margin("right")
                                   : (root.width - tissue.width) / 2

    readonly property real placedY: atTop ? root.margin("top")
                                   : atBottom ? root.height - tissue.height - root.margin("bottom")
                                   : (root.height - tissue.height) / 2

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
        cellsConfig: root.config.cells || []
        output: root.screenItem ? root.screenItem.name : ""

        floating: true
        orientation: root.config.orientation || "vertical"
        anchorSide: root.config.anchor_side || "start"

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
        refreshRegions();
    }

    Component.onDestruction: Focus.unregister(root)
}
