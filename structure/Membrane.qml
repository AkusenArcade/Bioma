import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

// One edge of one monitor. Tissues anchored to it share its length.
//
// `reserve_space`, `auto_hide` and `scale` govern every tissue and cell on this
// membrane, the dock included. Hiding a membrane hides everything on it.
//
// The surface is transparent and covers the whole edge, so its input mask is
// the union of the visible cell shapes and nothing else — otherwise the strip
// would swallow clicks meant for the windows underneath. The same union, minus
// the cells that ask not to be blurred, is what is handed to
// `ext-background-effect`: blur follows the declared shapes exactly, never the
// gaps between them, which is why no compositor layer rule is used.
//
// See PRD §4.1, §4.4, §6.6.
PanelWindow {
    id: root

    // Named for what it is rather than `modelData`: a membrane is instantiated
    // from a Variants over the membrane list, and that delegate's `modelData`
    // is the membrane's own configuration block.
    required property var screenItem
    required property string edge            // "top" | "bottom" | "left" | "right"
    property var tissuesConfig: []

    property bool reserveSpace: false
    property bool autoHide: false
    property string scaleStep: "normal"

    readonly property var metrics: Metrics.step(scaleStep)
    readonly property bool horizontal: edge === "top" || edge === "bottom"

    // Geometric rule, no exceptions: only horizontal edges may reserve.
    readonly property bool reserving: reserveSpace && horizontal && !autoHide

    screen: screenItem
    color: "transparent"

    // Named on the wayland side, so that `niri msg layers` and any compositor
    // rule can tell one Bioma surface from another.
    WlrLayershell.namespace: `bioma-membrane-${edge}`

    anchors {
        top: edge !== "bottom"
        bottom: edge !== "top"
        left: edge !== "right"
        right: edge !== "left"
    }

    // ---- Thickness ---------------------------------------------------------

    readonly property real tissueThickness: metrics.cellHeight + metrics.tissuePadding * 2

    // The strip the membrane actually occupies: the screen edge margin is a
    // frame, not a surface, but it is part of what the windows must not cover.
    readonly property real strip: metrics.marginEdge + tissueThickness

    // Where the compositor actually starts drawing windows, in this surface's
    // coordinates. It is not the edge of the reserved strip: niri insets its
    // windows by `gaps`, and by any `struts`, and an expansion hangs from the
    // line the windows really begin on — otherwise the panel floats a gap above
    // them and the alignment the eye checks is the one that is wrong.
    readonly property real windowInset: Niri.windowGap + Niri.strutFor(edge)
    readonly property real windowLine: {
        if (edge === "top" || edge === "left")
            return strip + windowInset;
        return (horizontal ? height : width) - strip - windowInset;
    }

    // When space is reserved it stays reserved even while a conditional cell
    // inside is invisible — the "slot" model, so windows never reflow. An
    // expansion never changes it either: expansions go over windows.
    exclusiveZone: reserving ? Math.round(strip) : 0

    // An expansion grows out of the strip and over the windows, so the surface
    // has to be large enough to hold it — and it holds that size for the whole
    // session rather than taking it when a cell opens and giving it back when
    // it closes.
    //
    // Resizing a layer surface is not free and it is not atomic: the window's
    // height changes on one frame and the compositor applies the new size on
    // another, and everything positioned from that height — the tissue on a
    // bottom membrane sits at `height - margin - thickness` — is drawn once at
    // the old size and once at the new. What the eye sees is the whole bar
    // appearing twice, one of them near the top of the screen, and every cell
    // losing its glass for that frame. Akusen saw both, 2026-09-22.
    //
    // A surface the size of the output costs a transparent buffer and nothing
    // else: it reserves only its strip, and outside its cells it catches no
    // pointer, because the input mask is built from the cells themselves.
    readonly property bool anyOpen: {
        for (const tissue of root.tissues)
            for (const cell of tissue.cells)
                if (cell.open)
                    return true;
        return false;
    }

    implicitHeight: horizontal ? (screen ? screen.height : strip) : 0
    implicitWidth: horizontal ? 0 : (screen ? screen.width : strip)

    // Keyboard focus is asked for by the cell that needs it, and by no other.
    //
    // A layer surface that declares on-demand keyboard interactivity is one a
    // compositor may focus, and under `focus-follows-mouse` niri focuses it the
    // moment the pointer crosses it — which takes the focus off the window. So
    // a membrane that asked for the keyboard because *something* was open made
    // the focused window flicker away and back as the pointer travelled over
    // its cells, and the window title cell, which exists on that focus, went
    // with it. Akusen saw the title; the rule is the focus.
    readonly property bool anyKeyboard: {
        for (const tissue of root.tissues)
            for (const cell of tissue.cells)
                if (cell.open && cell.wantsKeyboard)
                    return true;
        return false;
    }

    focusable: anyKeyboard

    // ---- Auto-hide ---------------------------------------------------------

    // An auto-hidden membrane stays present as a surface: destroying it would
    // leave nothing at the edge to catch the pointer. The reveal zone is inside
    // the surface bounds — a bug Prisma already hit and fixed, and it comes back
    // identical here.
    readonly property int revealZone: 2
    property bool revealed: !autoHide

    Item {
        id: revealStrip
        width: root.horizontal ? root.width : root.revealZone
        height: root.horizontal ? root.revealZone : root.height
        x: root.edge === "right" ? root.width - root.revealZone : 0
        y: root.edge === "bottom" ? root.height - root.revealZone : 0

        HoverHandler {
            onHoveredChanged: if (hovered) root.revealed = true
        }
    }

    HoverHandler {
        id: membraneHover
        onHoveredChanged: {
            if (hovered)
                hideTimer.stop();
            else if (root.autoHide)
                hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: Timing.autoHide
        onTriggered: if (!root.anyOpen) root.revealed = false
    }

    // The whole content slides out; nothing on the membrane has a hiding rule
    // of its own.
    Item {
        id: content
        anchors.fill: parent

        readonly property real hiddenOffset: root.strip - root.revealZone
        transform: Translate {
            x: root.horizontal ? 0 : (root.revealed ? 0 : (root.edge === "left" ? -content.hiddenOffset : content.hiddenOffset))
            y: !root.horizontal ? 0 : (root.revealed ? 0 : (root.edge === "top" ? -content.hiddenOffset : content.hiddenOffset))

            Behavior on x { NumberAnimation { duration: Timing.open; easing.type: Easing.InOutQuad } }
            Behavior on y { NumberAnimation { duration: Timing.open; easing.type: Easing.InOutQuad } }
        }

        Repeater {
            id: tissueRepeater
            model: root.tissuesConfig

            delegate: Tissue {
                id: tissue
                required property var modelData
                required property int index

                metrics: root.metrics
                cellsConfig: modelData.cells || []
                output: root.screenItem ? root.screenItem.name : ""
                edge: root.edge
                windowLine: root.windowLine
                opensAway: root.edge === "top" || root.edge === "left"
                orientation: modelData.orientation || (root.horizontal ? "horizontal" : "vertical")
                padding: modelData.padding !== undefined
                         ? Math.max(2, Math.min(12, modelData.padding)) * root.metrics.factor
                         : root.metrics.tissuePadding
                fillOpacity: modelData.opacity !== undefined ? modelData.opacity : Config.get("tissue.opacity", 0.5)

                anchorSide: root.anchorFor(index, modelData)
                slotLength: (modelData.percentage || 0) / 100 * root.usableLength

                x: root.horizontal ? root.offsetFor(tissue, index) : root.crossOffset
                y: root.horizontal ? root.crossOffset : root.offsetFor(tissue, index)

                onVisibleChanged: root.refreshRegions()
                onRevisionChanged: root.refreshRegions()
                // What the tissue could not fit takes no input and is not
                // blurred, so the regions follow the placement as well as the
                // revision — and they follow it from here rather than from a
                // bump inside the tissue, which would be the tissue asking
                // itself to recompute what it had just computed.
                onPlacementChanged: root.refreshRegions()
            }
        }
    }

    readonly property list<Item> tissues: {
        const out = [];
        for (let i = 0; i < tissueRepeater.count; i++) {
            const item = tissueRepeater.itemAt(i);
            if (item)
                out.push(item);
        }
        return out;
    }

    // ---- Placement ---------------------------------------------------------

    readonly property real membraneLength: horizontal ? width : height
    readonly property real usableLength: Math.max(0, membraneLength - metrics.marginEdge * 2)

    // The distance from the screen edge. The edge margin is a thin frame: the
    // tissue never touches the screen edge, and an expansion grows away from it
    // into the screen.
    readonly property real crossOffset: {
        if (edge === "top" || edge === "left")
            return metrics.marginEdge;
        return (horizontal ? height : width) - metrics.marginEdge - tissueThickness;
    }

    // Growth moves away from the anchor, so the anchor has to be known. The
    // configuration declares `growth`; where the tissue sits is derived from
    // its place in the list, which is what the three-tissue default means when
    // it reads left, centre, right. An explicit `anchor` overrides it.
    function anchorFor(index, config) {
        if (config.anchor)
            return config.anchor;
        if (config.growth === "symmetric")
            return "centre";
        if (index === 0)
            return "start";
        if (index === tissuesConfig.length - 1)
            return "end";
        return "centre";
    }

    // Tissues of the same anchor stack in declared order; the centred ones are
    // centred as a group. Collision is impossible as long as the percentages
    // hold, and when they do not the group is pushed inside the free span
    // rather than allowed to overlap.
    function offsetFor(tissue, index) {
        const margin = metrics.marginEdge;
        // The margin is measured to the **cell**, not to the band around it, so
        // the outermost cell on a membrane lines up with the edge of the
        // windows the compositor draws. The tissue's own padding therefore
        // hangs outside it.
        const outer = Math.max(0, margin - tissue.padding);
        let startRun = 0;
        let endRun = 0;
        let centreTotal = 0;
        let centreBefore = 0;

        // Every length here is the tissue's **animated** size, not the value it
        // is heading for. Placement then follows the growth frame by frame: a
        // centred tissue widens around its own middle rather than snapping to
        // the centre its final width would have.
        for (let i = 0; i < tissues.length; i++) {
            const other = tissues[i];
            if (!other || !other.visible)
                continue;
            const side = other.anchorSide;
            const length = root.horizontal ? other.width : other.height;

            if (side === "start" && i < index)
                startRun += length + margin;
            else if (side === "end" && i > index)
                endRun += length + margin;

            if (side === "centre") {
                centreTotal += length + (centreTotal > 0 ? margin : 0);
                if (i < index)
                    centreBefore += length + margin;
            }
        }

        const own = root.horizontal ? tissue.width : tissue.height;
        const side = tissue.anchorSide;
        if (side === "start")
            return outer + startRun;
        if (side === "end")
            return membraneLength - outer - endRun - own;

        // Centred: the group is centred on the membrane, then clamped between
        // whatever the corner tissues occupy.
        let groupStart = (membraneLength - centreTotal) / 2;
        const leftLimit = margin + root.runLength("start");
        const rightLimit = membraneLength - margin - root.runLength("end");
        if (groupStart < leftLimit)
            groupStart = leftLimit;
        if (groupStart + centreTotal > rightLimit)
            groupStart = Math.max(leftLimit, rightLimit - centreTotal);
        return groupStart + centreBefore;
    }

    function runLength(side) {
        let total = 0;
        for (const tissue of tissues) {
            if (tissue && tissue.visible && tissue.anchorSide === side)
                total += (root.horizontal ? tissue.width : tissue.height) + metrics.marginEdge;
        }
        return total;
    }

    // Percentages are ceilings, not reservations, and must not exceed 100.
    function validate() {
        let total = 0;
        for (const entry of tissuesConfig)
            total += entry.percentage || 0;
        if (total > 100)
            console.warn(`Bioma: membrane ${edge} on ${screenItem ? screenItem.name : "?"} declares ${total}% of tissue — above 100, tissues will be clamped`);
    }

    onTissuesConfigChanged: validate()

    // ---- Blur and input ----------------------------------------------------

    property var maskRegion: null
    property var blurRegion: null

    // Until the first rebuild the mask has to be **empty**, not absent: a null
    // mask means the whole surface takes the pointer, and this surface is the
    // size of the output. A region with no item and no size claims nothing.
    Region { id: nothing }

    mask: maskRegion ? maskRegion : nothing
    BackgroundEffect.blurRegion: blurRegion

    // Where this surface sits on its output. A layer surface has no position of
    // its own as far as Qt is concerned — the compositor places it — so it is
    // derived from the edge it is anchored to and the size it has. Covering the
    // output, as it now always does, that offset is nothing; the arithmetic
    // stays because a membrane on an edge it does not fill is still a case the
    // engine has to answer, and because it is what makes the catcher's
    // coordinates true.
    readonly property real originX: edge === "right" ? (screen ? screen.width : 0) - width : 0
    readonly property real originY: edge === "bottom" ? (screen ? screen.height : 0) - height : 0

    // Everything on this membrane that takes input: the cells, and the panel of
    // whichever is open — as rectangles on the output, not as items. The
    // full-screen catcher subtracts these from its own region so that a press
    // on a cell never reaches it, and it lives on another surface: handed items,
    // it punched its holes wherever those items sat inside *this* window, which
    // for a bottom membrane is a screen's height away from the truth.
    function inputRects() {
        const out = [];
        for (const tissue of root.tissues) {
            if (!tissue || !tissue.visible)
                continue;
            for (const cell of tissue.cells) {
                if (!cell.placed)
                    continue;
                for (const shape of cell.shapes()) {
                    const item = shape.item;
                    if (!item)
                        continue;
                    const here = item.mapToItem(null, 0, 0);
                    out.push({
                        "x": here.x + root.originX,
                        "y": here.y + root.originY,
                        "width": item.width,
                        "height": item.height,
                        "radius": shape.radius
                    });
                }
            }
        }
        return out;
    }

    // The offset above changes with the surface, so the catcher has to be told
    // when the surface changes size. It no longer does so for an expansion —
    // it is the size of the output from the start — but a monitor that changes
    // mode still moves every cell in the catcher's coordinates.
    onHeightChanged: root.refreshRegions()
    onWidthChanged: root.refreshRegions()

    function refreshRegions() {
        const input = [];
        const blur = [];

        for (const tissue of root.tissues) {
            if (!tissue || !tissue.visible)
                continue;
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

        // Hidden, the only thing that may catch the pointer is the reveal zone.
        if (root.autoHide && !root.revealed)
            input.splice(0, input.length, { "item": revealStrip, "radius": 0 });

        root.maskRegion = Regions.rebind(root, root.maskRegion, input);
        root.blurRegion = Regions.rebind(root, root.blurRegion, blur);

        // The catcher builds its own region out of these.
        Focus.bump();
    }

    onRevealedChanged: refreshRegions()

    Component.onCompleted: {
        Focus.register(root);
        refreshRegions();
    }

    Component.onDestruction: Focus.unregister(root)
}
