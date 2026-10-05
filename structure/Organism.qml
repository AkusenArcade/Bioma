import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.organisms

// One organism: a read-only surface placed on the desktop.
//
// It is not a cell. A cell speaks when something happens and hangs from a
// membrane; an organism is there because it was put there to be looked at,
// and hangs from nothing. So it has no contracted state, no thread and no
// input — it is a glass panel with the rim, without the shadow that would lift
// it off the wallpaper, born in place by growing from its own centre.
//
// What it shows is the organism's own file, found by type in
// `organisms/Organisms.qml`. That file is an Item with an implicit size and, if
// its presence is conditional, a `present` property: media leaves when nothing
// is loaded, a note when its file cannot be read. Absent, it is still placed:
// while arranging it comes up in its blank form — the body draws itself empty,
// saying why, whenever its `present` is false — so the hand has something to
// take (Akusen, 2026-10-05: a media organism added with nothing playing was
// nowhere to be dragged).
//
// See docs/design/ORGANISMS.md.
Item {
    id: root

    // The block from the configuration: type, monitor, x, y, size and the
    // organism's own options.
    property var entry: ({})

    // Its place in the whole list, which is what a drop writes back to, and
    // the surface that carries it — the one that knows what to snap to.
    property int place: -1
    property var surface: null

    // Being placed: lifted above the windows with the rest, outlined, and
    // free to be dragged.
    property bool arranging: false

    // Whether it belongs on this surface's screen. Every surface keeps one of
    // these for every organism and shows only its own: carried to another
    // screen, an organism leaves this one and arrives on that one, and
    // nothing is destroyed under the hand that let it go.
    property bool here: true

    // What the membranes leave free on this screen, in the surface's
    // coordinates — the box the organism is placed in and never leaves.
    property rect free: Qt.rect(0, 0, 0, 0)

    // The density it is drawn at: its own `size` if it says one, else the
    // membranes'.
    property var baseMetrics: Metrics.step("normal")
    readonly property var metrics: root.entry.size ? Metrics.step(root.entry.size) : root.baseMetrics

    readonly property string type: root.entry.type || ""
    readonly property string source: Organisms.fileFor(root.type)

    readonly property Item body: loader.item
    readonly property bool retiring: Arranging.retiring.indexOf(root.place) >= 0
    readonly property bool present: root.here && !root.retiring && root.body !== null
                                    && (root.arranging || root.body.present === undefined || root.body.present === true)

    // ---- Size and place ---------------------------------------------------------

    // An organism whose content is its surface — the media organism's cover,
    // edge to edge — says `bleeds` and is given no padding; the rim is then
    // drawn over its content rather than under it.
    readonly property bool bleeds: root.body !== null && root.body.bleeds === true
    readonly property real padding: root.bleeds ? 0 : 20 * root.metrics.factor

    // The screen it is on, for content that asks whether the desktop there is
    // showing at all.
    readonly property string output: root.surface && root.surface.screenItem ? root.surface.screenItem.name : ""
    readonly property real targetWidth: root.body ? root.body.implicitWidth + root.padding * 2 : 0
    readonly property real targetHeight: root.body ? root.body.implicitHeight + root.padding * 2 : 0

    // The block keeps the centre as fractions of the free area, so a change of
    // resolution, scale or membranes leaves it in the same part of the screen.
    // The panel is held wholly inside: a centre that would push it past an
    // edge is pulled back, and one too large for the area sits in its middle.
    function placed(fraction, start, length, extent) {
        const wanted = start + Math.max(0, Math.min(1, fraction)) * length;
        if (extent >= length)
            return start + length / 2;
        return Math.max(start + extent / 2, Math.min(start + length - extent / 2, wanted));
    }

    readonly property real restX: root.placed(root.entry.x ?? 0.5, root.free.x, root.free.width, root.targetWidth)
    readonly property real restY: root.placed(root.entry.y ?? 0.5, root.free.y, root.free.height, root.targetHeight)

    // While it is held it is where the hand puts it, snapped; the moment it
    // is let go the list is told and it is where the list says again.
    property bool held: false
    property real heldX: 0
    property real heldY: 0

    readonly property real centreX: root.held ? root.heldX : root.restX
    readonly property real centreY: root.held ? root.heldY : root.restY

    // ---- Arriving and leaving -----------------------------------------------------

    // It grows when it has something to show and the shape has somewhere to
    // be; it leaves content first, then shape — the shell's one way of going.
    property bool wanted: false
    property real growth: 0

    onPresentChanged: root.decide()
    onTargetWidthChanged: root.decide()

    function decide() {
        if (root.present && root.targetWidth > 0) {
            parting.stop();
            root.wanted = true;
        } else if (root.wanted) {
            // Content out first; the shape follows once it has gone.
            parting.restart();
        }
    }

    Timer {
        id: parting
        interval: Timing.contentFade
        onTriggered: root.wanted = false
    }

    readonly property bool leaving: parting.running

    states: State {
        name: "here"
        when: root.wanted
        PropertyChanges { root.growth: 1 }
    }

    transitions: [
        Transition {
            to: "here"
            NumberAnimation {
                property: "growth"
                duration: Timing.open
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Timing.easeOpenFlat
            }
        },
        Transition {
            from: "here"
            NumberAnimation {
                property: "growth"
                duration: Timing.close
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Timing.easeClose
            }
        }
    ]

    // ---- The surface --------------------------------------------------------------

    Panel {
        id: panel

        metrics: root.metrics
        shadowed: false
        padding: root.padding
        fixedWidth: root.targetWidth
        fixedHeight: root.targetHeight

        anchorX: root.centreX - root.targetWidth / 2
        anchorY: root.centreY - root.targetHeight / 2
        nodeX: root.centreX
        nodeY: root.centreY
        growth: root.growth
        contentReady: root.wanted && !root.leaving && root.growth > 0.999

        Loader {
            id: loader

            // Not loaded on a screen it does not belong to — once it has
            // finished leaving it.
            active: root.here || root.growth > 0
            source: root.source.length > 0 ? Qt.resolvedUrl("../organisms/" + root.source) : ""

            onLoaded: {
                item.metrics = Qt.binding(() => root.metrics);
                item.entry = Qt.binding(() => root.entry);
                if (item.organism !== undefined)
                    item.organism = root;
                root.decide();
            }
        }
    }

    // The rim over content that bleeds: the cover reaches the edge, and the
    // light on the top edge is still the surface's.
    Rim {
        visible: root.bleeds && panel.visible
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        radius: panel.radius
    }

    // ---- Being placed -------------------------------------------------------------------

    // Outlined while the mode lasts, a little outside the panel so the rim
    // stays the rim: dashed, because it marks a thing that can move rather
    // than a surface. Brighter under the pointer and in the hand.
    readonly property real ring: 8 * root.metrics.factor
    readonly property bool lit: grab.containsMouse || root.held

    DashedSlot {
        visible: root.arranging && panel.visible
        x: root.centreX - root.targetWidth / 2 - root.ring
        y: root.centreY - root.targetHeight / 2 - root.ring
        width: root.targetWidth + root.ring * 2
        height: root.targetHeight + root.ring * 2
        radius: panel.radius + root.ring
        colour: root.lit ? Theme.primary : Qt.alpha(Theme.primary, 0.55)
        dash: 8 * root.metrics.factor
        space: 6 * root.metrics.factor
    }

    // Its name and where it is, above its top-left corner: the figures are
    // what will be written.
    Row {
        visible: root.arranging && panel.visible
        x: root.centreX - root.targetWidth / 2 - root.ring
        y: root.centreY - root.targetHeight / 2 - root.ring - height - 6 * root.metrics.factor
        spacing: 10 * root.metrics.factor

        readonly property font face: Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontMeta,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
        }))

        Text {
            text: (Organisms.names[root.type] || root.type).toUpperCase()
            color: Theme.primary
            font: parent.face
        }

        Text {
            readonly property real fx: root.free.width > 0 ? (root.centreX - root.free.x) / root.free.width : 0
            readonly property real fy: root.free.height > 0 ? (root.centreY - root.free.y) / root.free.height : 0
            text: `X ${fx.toFixed(2)} · Y ${fy.toFixed(2)}`
            color: Theme.textMuted
            font: parent.face
        }
    }

    // The hand. Where the press lands inside the panel is kept, so the panel
    // does not jump to centre itself under the pointer.
    MouseArea {
        id: grab

        enabled: root.arranging && panel.visible
        x: root.centreX - root.targetWidth / 2
        y: root.centreY - root.targetHeight / 2
        width: root.targetWidth
        height: root.targetHeight
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real offsetX: 0
        property real offsetY: 0

        onPressed: mouse => {
            grab.offsetX = mouse.x - root.targetWidth / 2;
            grab.offsetY = mouse.y - root.targetHeight / 2;
            root.heldX = root.restX;
            root.heldY = root.restY;
            root.held = true;
        }

        onPositionChanged: mouse => {
            if (!root.held || !root.surface)
                return;
            const at = grab.mapToItem(root, mouse.x, mouse.y);
            const snapped = root.surface.snap(root, at.x - grab.offsetX, at.y - grab.offsetY);
            root.heldX = snapped.x;
            root.heldY = snapped.y;
            root.surface.guideX = snapped.guideX;
            root.surface.guideY = snapped.guideY;
        }

        onReleased: mouse => {
            if (!root.held)
                return;
            const at = grab.mapToItem(root, mouse.x, mouse.y);
            root.drop(at.x, at.y);
        }

        onCanceled: root.drop(NaN, NaN)
    }

    // Let go. The screen under the pointer is where it now lives — its own,
    // or another one it was carried to — and its centre is written as
    // fractions of that screen's free area, held wholly inside it.
    function drop(pointerX, pointerY) {
        const surface = root.surface;
        let target = surface;
        let cx = root.heldX;
        let cy = root.heldY;

        if (surface && !isNaN(pointerX)) {
            const screen = surface.screenItem;
            const there = Arranging.surfaceAt(screen.x + pointerX, screen.y + pointerY);
            if (there && there !== surface) {
                target = there;
                cx += screen.x - there.screenItem.x;
                cy += screen.y - there.screenItem.y;
            }
        }

        if (surface) {
            surface.guideX = NaN;
            surface.guideY = NaN;
        }
        if (!target) {
            root.held = false;
            return;
        }

        const free = target.free;
        const x = root.placed((cx - free.x) / free.width, free.x, free.width, root.targetWidth);
        const y = root.placed((cy - free.y) / free.height, free.y, free.height, root.targetHeight);
        const place = root.place;
        const monitor = target.screenItem.name;
        const fx = free.width > 0 ? (x - free.x) / free.width : 0.5;
        const fy = free.height > 0 ? (y - free.y) / free.height : 0.5;

        // Written once the release has been handled, not inside it. Carried to
        // another screen, the last organism of this one takes its delegate
        // with it, and a MouseArea destroyed inside its own release left the
        // shell deaf to the next drag on any screen (2026-10-04). Held until
        // then, so it does not flick back to where it was for a frame.
        //
        // Carried to another screen, it stays held here: it leaves this one
        // from where it was let go, rather than from where its new place
        // would be on a screen it no longer belongs to.
        const away = target !== surface;
        Qt.callLater(() => {
            Arranging.place(place, monitor, fx, fy);
            if (!away)
                root.held = false;
        });
    }

    onHereChanged: if (root.here) root.held = false

    // The shape the blur follows: the panel itself, which grows and shrinks
    // with the organism, so the glass is always exactly what is drawn.
    function shapes() {
        return panel.visible ? [{ "item": panel, "radius": panel.radius }] : [];
    }

    readonly property bool visibleShape: panel.visible

    Component.onCompleted: if (root.here && root.source.length === 0 && root.type.length > 0)
        console.warn("Organism: no organism of type", root.type);
}
