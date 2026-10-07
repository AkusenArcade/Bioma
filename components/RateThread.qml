import QtQuick
import QtQuick.Shapes
import qs.core

// A thread with a rate running along it: a hairline in the line colour, and
// dashes of light that run as fast as something comes.
//
// The download cell's measure. The light moves because bytes arrive, and at
// a speed that says how many — logarithmically, since a download goes from a
// few kilobytes a second to a hundred megabytes — and it is still when they
// stop. Nothing about it moves at a rate of its own.
Item {
    id: root

    // Bytes a second.
    property real rate: 0
    property bool running: true
    property real factor: 1

    // Pixels a second for bytes a second: still below a kilobyte a second,
    // 14 px/s at 64 KB/s, about 100 at 10 MB/s, 140 at 100 MB/s.
    readonly property real speed: root.rate < 1024 ? 0
        : (6 + 40 * Math.log10(1 + root.rate / 65536)) * root.factor

    property real offset: 0

    implicitHeight: 6 * root.factor
    height: implicitHeight

    FrameAnimation {
        running: root.running && root.visible && root.speed > 0
        onTriggered: root.offset = (root.offset + root.speed * Math.min(frameTime, 0.05)) % (12 * root.factor)
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Metrics.crisp(Metrics.thread, Screen.devicePixelRatio)
        color: Theme.line
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Theme.primary
            strokeWidth: 2 * root.factor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            // In units of the stroke width: 4 px of light every 12.
            dashPattern: [2, 4]
            dashOffset: -root.offset / (2 * root.factor)

            startX: 0
            startY: root.height / 2

            PathLine {
                x: root.width
                y: root.height / 2
            }
        }
    }
}
