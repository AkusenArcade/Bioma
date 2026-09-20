import QtQuick
import QtQuick.Shapes
import qs.core

// The connection between two shapes of one open cell: a 1.3 px line with a node
// at each end.
//
// Threads **touch the edge** of both shapes. A thread stopping two pixels short
// makes the shapes look placed against each other rather than connected, so the
// ends are computed from geometry and never placed by eye — this item is sized
// and positioned by whatever owns both shapes, and draws from end to end.
//
// It draws itself outward from its origin node, which is what makes an
// expansion read as growing out of the cell rather than appearing beside it.
Item {
    id: root

    property bool vertical: true

    // 0 while the cell is contracted, 1 when the thread has reached the far
    // shape. The far node arrives with the line.
    property real progress: 0

    property color lineColour: Theme.line
    property color nodeColour: Theme.node

    // 1.3 px is the case §4.5 of the PRD is about: round it to the physical
    // pixel or it smears and disappears under fractional scaling.
    readonly property real stroke: Metrics.crisp(Metrics.thread, Screen.devicePixelRatio)
    readonly property real nodeRadius: Metrics.nodeSize

    implicitWidth: vertical ? nodeRadius * 2 : 0
    implicitHeight: vertical ? 0 : nodeRadius * 2

    readonly property real span: vertical ? height : width

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // The line is drawn by moving its far end rather than by a dash
        // offset: the two are indistinguishable on a straight 24 px thread,
        // and this one keeps the node attached to the end while it travels.
        ShapePath {
            strokeColor: root.lineColour
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            startX: root.vertical ? root.width / 2 : 0
            startY: root.vertical ? 0 : root.height / 2

            PathLine {
                x: root.vertical ? root.width / 2 : root.span * root.progress
                y: root.vertical ? root.span * root.progress : root.height / 2
            }
        }
    }

    // The origin node, on the shape the expansion grew from.
    Rectangle {
        width: root.nodeRadius * 2
        height: width
        radius: width / 2
        color: root.nodeColour
        antialiasing: true
        x: root.vertical ? (root.width - width) / 2 : -width / 2
        y: root.vertical ? -height / 2 : (root.height - height) / 2
        opacity: root.progress > 0 ? 1 : 0
    }

    // The far node, which travels with the end of the line.
    Rectangle {
        width: root.nodeRadius * 2
        height: width
        radius: width / 2
        color: root.nodeColour
        antialiasing: true
        x: root.vertical ? (root.width - width) / 2 : root.span * root.progress - width / 2
        y: root.vertical ? root.span * root.progress - height / 2 : (root.height - height) / 2
        opacity: root.progress > 0 ? 1 : 0
    }
}
