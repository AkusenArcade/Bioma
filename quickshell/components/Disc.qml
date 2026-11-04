import QtQuick
import QtQuick.Shapes
import qs.core

// A filled circle carrying the light gradient: a selected control, an active
// button, the head of an indicator.
//
// A `Rectangle` with a vertical gradient would be close but not the same
// light: the shell has one source, at 165°, and small shapes are where a
// different angle is noticed first, because they sit next to the ones that got
// it right.
Shape {
    id: root

    property color base: Theme.primary

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillGradient: LightGradient {
            base: root.base
            boxWidth: root.width
            boxHeight: root.height
        }

        PathAngleArc {
            centerX: root.width / 2
            centerY: root.height / 2
            radiusX: root.width / 2
            radiusY: root.height / 2
            startAngle: 0
            sweepAngle: 360
            moveToStart: true
        }
    }
}
