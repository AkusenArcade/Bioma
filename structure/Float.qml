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
        root.heldReach = 0;
    }

    // A summoned cell leaves the way it arrived — shrinking about its own
    // centre — and only then is it let go. Nothing else on this surface has
    // anywhere to retract to, so the leaving is the cell's own.
    function retire() {
        const cell = tissue.cells.length > 0 ? tissue.cells[0] : null;
        if (!cell) {
            root.dismiss();
            return;
        }
        cell.depart();
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

                // Summoned into the middle of the screen, it grows into
                // place rather than sliding in from wherever the tissue
                // happened to be a moment ago.
                cell.growsOnArrival = true;

                // A cell with a panel opens it; one whose content is itself
                // has nothing to open and claims the attention directly, so
                // that a press outside still reaches it and closes it.
                if (cell.hasPanel)
                    cell.open = true;
                else
                    Focus.opened(cell);
            }
        }
    }

    // And it is let go once it has finished leaving: a cell cleared at the
    // moment it closes takes its own closing animation with it. So it is asked
    // to leave, and cleared when it says it has — `retire` below.
    Connections {
        target: tissue.cells.length > 0 ? tissue.cells[0] : null
        enabled: root.host && root.summoned.length > 0
        function onGone() { root.dismiss(); }
        function onExpandedChanged() {
            const cell = tissue.cells[0];
            if (cell && !cell.open && !cell.expanded && !cell.visibility.invoked)
                root.retire();
        }
        function onShownChanged() {
            const cell = tissue.cells[0];
            if (cell && !cell.shown && !cell.expanded)
                root.retire();
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

    // The keyboard is asked for by the cell that needs it and by no other —
    // and here it is asked for **exclusively**, which a membrane never does.
    //
    // On-demand means "the compositor may focus this surface", and niri does
    // that when the pointer crosses it or a press lands on it. A cell that
    // was summoned by a shortcut has had neither: the hand is on the keyboard
    // and the pointer is wherever it was left, so the launcher came up and
    // swallowed nothing. Exclusive is the layer-shell way of saying the keys
    // are mine while I am here, which is exactly what an invoked cell means —
    // and it is what `structure/SelectionSurface.qml` already does so that
    // Escape cancels a capture.
    // Placed, not open: a cell whose whole content is itself never opens —
    // the launcher has no panel to grow, it *is* the panel — and asking only
    // open cells left it on screen with the keys going elsewhere.
    readonly property bool anyKeyboard: {
        for (const cell of tissue.cells)
            if (cell.placed && cell.wantsKeyboard)
                return true;
        return false;
    }

    WlrLayershell.keyboardFocus: anyKeyboard ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

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
    // A cell counts while it is still on screen, not only while it is placed:
    // dismissing one stops it being placed at once, and a tissue re-centred
    // on the instant carried the whole composition — still retracting —
    // two hundred pixels down the screen. Measured, 2026-09-22: reach 396 to 0
    // in one frame, the tissue from y 500 to y 698.
    readonly property real liveReach: {
        let out = 0;
        for (const cell of tissue.cells)
            if ((cell.placed || cell.expanded) && cell.reach > out)
                out = cell.reach;
        return out;
    }

    // And once the last of it is leaving there is nothing left to measure, so
    // the figure is held: the pill shrinks where it stands rather than being
    // moved while it does.
    readonly property bool departing: {
        for (const cell of tissue.cells)
            if (cell.leaving)
                return true;
        return false;
    }

    property real heldReach: 0

    // Whatever it last measured while there was something to measure. The
    // expansion unloads a frame *before* the cell starts leaving, so a figure
    // kept only while nothing was leaving was already zero by the time it was
    // needed.
    onLiveReachChanged: if (root.liveReach > 0) root.heldReach = root.liveReach

    readonly property real reach: root.departing ? root.heldReach : root.liveReach

    readonly property real spread: {
        let out = tissue.width;
        for (const cell of tissue.cells)
            if ((cell.placed || cell.expanded || cell.leaving) && cell.reachWidth > out)
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

        // What it holds arrives and leaves whole: the band does not reflow,
        // the cell grows.
        animates: false
        orientation: root.config.orientation || "vertical"
        anchorSide: root.config.anchor_side
                    || (root.atLeft ? "start" : root.atRight ? "end" : "centre")

        // No ceiling: nothing shares this surface, so the tissue is as long as
        // its cells need. A membrane's percentage is about neighbours, and a
        // floating tissue has none.
        slotLength: 0

        padding: root.config.padding !== undefined
                 ? Math.max(2, Math.min(12, root.config.padding)) * root.metrics.factor
                 : root.metrics.tissuePadding
        fillOpacity: root.config.opacity !== undefined
                     ? root.config.opacity : Config.get("tissue.opacity", 0.5)

        // Which way its cells open. There is no line here for them to open
        // onto — nothing reserves space against a floating surface — so the
        // tissue uses the shape gap and no window line is given.
        edge: root.atBottom ? "bottom" : "top"
        opensAway: root.opensDown

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
            for (const shape of cell.claims()) {
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
                for (const shape of cell.claims())
                    input.push(shape);
                if (!cell.blur)
                    continue;
                for (const shape of cell.shapes())
                    blur.push(shape);
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
