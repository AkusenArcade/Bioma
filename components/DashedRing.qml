import QtQuick
import QtQuick.Shapes
import qs.core

// A dashed ring: a place rather than a content.
//
// The one use so far is the trailing empty workspace niri always keeps. A drawn
// ring would say there is something there; a dashed one says the slot exists
// and is free, which is the truth and needs no label.
Shape {
    id: root

    property color colour: Qt.alpha(Theme.line, 0.7)
    property real thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
    property real dash: 3
    property real space: 3

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: root.colour
        strokeWidth: root.thickness
        fillColor: "transparent"
        strokeStyle: ShapePath.DashLine
        // The pattern is in units of the stroke width, so a hairline needs a
        // long one to read as dashes rather than as a grey line.
        dashPattern: [root.dash / root.thickness, root.space / root.thickness]

        PathAngleArc {
            centerX: root.width / 2
            centerY: root.height / 2
            radiusX: (root.width - root.thickness) / 2
            radiusY: (root.height - root.thickness) / 2
            startAngle: -90
            sweepAngle: 360
            moveToStart: true
        }
    }
}
