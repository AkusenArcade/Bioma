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
// is loaded, weather when its reading is too old to trust.
//
// See docs/design/ORGANISMS.md.
Item {
    id: root

    // The block from the configuration: type, monitor, x, y, size and the
    // organism's own options.
    property var entry: ({})

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
    readonly property bool present: root.body !== null && (root.body.present === undefined || root.body.present === true)

    // ---- Size and place ---------------------------------------------------------

    readonly property real padding: 20 * root.metrics.factor
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

    readonly property real centreX: root.placed(root.entry.x ?? 0.5, root.free.x, root.free.width, root.targetWidth)
    readonly property real centreY: root.placed(root.entry.y ?? 0.5, root.free.y, root.free.height, root.targetHeight)

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

            source: root.source.length > 0 ? Qt.resolvedUrl("../organisms/" + root.source) : ""

            onLoaded: {
                item.metrics = Qt.binding(() => root.metrics);
                item.entry = Qt.binding(() => root.entry);
                root.decide();
            }
        }
    }

    // The shape the blur follows: the panel itself, which grows and shrinks
    // with the organism, so the glass is always exactly what is drawn.
    function shapes() {
        return panel.visible ? [{ "item": panel, "radius": panel.radius }] : [];
    }

    readonly property bool visibleShape: panel.visible

    Component.onCompleted: if (root.source.length === 0 && root.type.length > 0)
        console.warn("Organism: no organism of type", root.type);
}
