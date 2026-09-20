import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// A ring filled by a sector: the minute on the clock, and any other quantity
// that is a fraction of a whole rather than a load.
//
// A dial that measures no load stays primary and never takes a state colour
// (STYLE_GUIDE §3). Whatever drives `fraction` must be a live value: the
// movement is the measurement, never a rate chosen to look alive.
Item {
    id: root

    // 0 to 1. Above 1 it wraps, which is what a minute does.
    property real fraction: 0
    property color base: Theme.primary

    implicitWidth: 17
    implicitHeight: 17

    readonly property real centreX: width / 2
    readonly property real centreY: height / 2
    readonly property real outer: Math.min(width, height) / 2
    readonly property real ringWidth: Metrics.crisp(Metrics.thread, Screen.devicePixelRatio)

    // The fill is data. When the source steps — the clock ticks once a second —
    // the step is smoothed just enough not to read as a tick.
    property real sweep: (root.fraction % 1) * 360

    Behavior on sweep {
        NumberAnimation {
            duration: Timing.transition
            easing.type: Easing.OutQuad
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // The ring: an annulus rather than a stroke, because a stroke cannot
        // carry the gradient and the gradient is what makes it an indicator.
        ShapePath {
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1
            fillGradient: LightGradient {
                base: root.base
                boxWidth: root.width
                boxHeight: root.height
            }

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: root.outer
                radiusY: root.outer
                startAngle: 0
                sweepAngle: 360
                moveToStart: true
            }

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: root.outer - root.ringWidth
                radiusY: root.outer - root.ringWidth
                startAngle: 0
                sweepAngle: 360
                moveToStart: true
            }
        }

        // The filled sector, from twelve o'clock.
        ShapePath {
            strokeWidth: -1
            startX: root.centreX
            startY: root.centreY
            fillGradient: LightGradient {
                base: root.base
                boxWidth: root.width
                boxHeight: root.height
            }

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: root.outer
                radiusY: root.outer
                startAngle: -90
                sweepAngle: root.sweep
                moveToStart: false
            }
        }
    }
}
