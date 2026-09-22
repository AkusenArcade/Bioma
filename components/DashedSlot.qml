import QtQuick
import QtQuick.Shapes
import qs.core

// A dashed rounded rectangle: a place rather than a content.
//
// The rectangular sibling of `DashedRing`, and it says the same thing — the
// slot exists and is free. The settings cell draws a membrane as three of
// these per edge, and an empty one is somewhere a tissue *could* go rather
// than somewhere something is.
Shape {
    id: root

    property color colour: Qt.alpha(Theme.line, 0.7)
    property real thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
    property real radius: 0
    property real dash: 3
    property real space: 3

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: root.colour
        strokeWidth: root.thickness
        fillColor: "transparent"
        strokeStyle: ShapePath.DashLine
        // In units of the stroke width, so a hairline needs a long pattern to
        // read as dashes rather than as a grey line.
        dashPattern: [root.dash / root.thickness, root.space / root.thickness]

        PathRectangle {
            x: root.thickness / 2
            y: root.thickness / 2
            width: Math.max(0, root.width - root.thickness)
            height: Math.max(0, root.height - root.thickness)
            radius: root.radius
        }
    }
}
