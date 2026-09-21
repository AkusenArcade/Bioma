import QtQuick
import QtQuick.Effects
import qs.core

// A rectangular surface for an expanded cell: glass, the lit rim, radius 20,
// and the shadow that only invoked and expanded cells carry.
//
// It is **born from its point** — the node of the thread that ties it to the
// cell it came out of. Growth animates width and height from that node, never a
// scale: scaling deforms the rim, distorts the radius and stretches the text.
//
// Content enters only once the shape is at size, and it enters the way it
// leaves: growing from its own centre. STYLE_GUIDE §6 asks for opacity plus a
// 4 px rise instead; on the machine that reads as the content dropping in from
// above, and a shell where things arrive one way and leave another has two
// gestures where it needs one. Akusen's call, 2026-09-21.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    // Where the shape ends up, in the coordinates of whatever holds it.
    property real anchorX: 0
    property real anchorY: 0

    // The node it grows out of, in the same coordinates.
    property real nodeX: 0
    property real nodeY: 0

    // 0 contracted, 1 at size.
    property real growth: 0

    // Content enters after the shape, and leaves before it.
    property bool contentReady: false

    property real padding: 10 * metrics.factor
    property real radius: metrics.radiusPanel

    // A panel is as wide as its job: the content declares the size, the panel
    // adds its padding. Symmetry is not a reason to narrow one.
    default property alias content: contentSlot.data
    property real targetWidth: contentSlot.childrenRect.width + padding * 2
    property real targetHeight: contentSlot.childrenRect.height + padding * 2

    x: nodeX + (anchorX - nodeX) * growth
    y: nodeY + (anchorY - nodeY) * growth
    width: targetWidth * growth
    height: targetHeight * growth
    visible: growth > 0

    // Only invoked and expanded cells carry a shadow; a contracted cell never
    // does.
    RectangularShadow {
        anchors.fill: parent
        radius: root.radius
        blur: 28
        spread: 0
        offset.y: 14
        color: Theme.shadow
        opacity: root.growth
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Theme.cell, Config.get("cell.opacity", 0.72))
        antialiasing: true
    }

    Rim {
        anchors.fill: parent
        radius: root.radius
    }

    // The content sits inside the padding and is centred in what is left: a
    // pill with its content against the top edge reads as a mistake, and every
    // pod in the shell is a pill.
    //
    // Its size is the shape's **target** size, not the size the shape is at.
    // Bound to the animated one, the slot narrows on every frame of a growth
    // and whatever is centred in it re-centres with it: at rest nothing shows,
    // and on the way out the content shoots sideways while the capsule retracts
    // under it. At full size the two are the same figure, so this changes
    // nothing that is ever still.
    //
    // Content is the one thing in the shell that scales. Shapes never do — a
    // scaled shape deforms its rim and its radii — but content has neither, and
    // growing and shrinking about its own centre is what reads as arriving in
    // the shape and being put back into it.
    //
    // It still arrives only once the shape is at size, and it still leaves
    // before the shape does: `contentFade` against the shape's `close`.
    Item {
        id: contentSlot

        readonly property real inner: Math.max(0, root.targetWidth - root.padding * 2)
        readonly property real innerHeight: Math.max(0, root.targetHeight - root.padding * 2)

        width: contentSlot.inner
        height: contentSlot.innerHeight

        x: (root.width - width) / 2
        y: (root.height - height) / 2

        opacity: root.contentReady ? 1 : 0
        scale: root.contentReady ? 1 : 0.88
        transformOrigin: Item.Center

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        Behavior on scale { NumberAnimation { duration: Timing.contentFade; easing.type: Easing.OutQuad } }
    }
}
