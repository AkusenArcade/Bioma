import QtQuick
import QtQuick.Shapes
import qs.core

// A dashed horizontal line: where what is there ends and what could be begins.
//
// `DashedSlot`'s stroke, drawn as a rule. The settings pages put it between
// the chips already placed and the kinds offered by the dashed chip — the
// same dashes, because what lies past it is a place, not a content yet.
Shape {
    id: root

    property color colour: Qt.alpha(Theme.line, 0.7)
    property real thickness: Metrics.rim(Screen.devicePixelRatio)
    property real dash: 3
    property real space: 3

    implicitHeight: root.thickness
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: root.colour
        strokeWidth: root.thickness
        fillColor: "transparent"
        strokeStyle: ShapePath.DashLine
        // In units of the stroke width, as in DashedSlot.
        dashPattern: [root.dash / root.thickness, root.space / root.thickness]

        startX: 0
        startY: root.height / 2

        PathLine {
            x: root.width
            y: root.height / 2
        }
    }
}
