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
// Content enters only once the shape is at size, with opacity plus a 4 px
// upward translation, and is never scaled.
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

    Item {
        id: contentSlot
        x: root.padding
        y: root.padding + (root.contentReady ? 0 : 4)
        width: Math.max(0, root.width - root.padding * 2)
        height: Math.max(0, root.height - root.padding * 2)
        opacity: root.contentReady ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        Behavior on y { NumberAnimation { duration: Timing.contentFade; easing.type: Easing.OutQuad } }
    }
}
