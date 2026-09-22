import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.core

// A travel with a start and an end: a track, an arc that follows the value, and
// a node at the head of it.
//
// Not a Dial and not a Vital. A dial fills a sector because a minute is a
// fraction of a whole; this is a scale the **user** moves, so it keeps the
// primary for its whole run — red at full volume would say "past threshold",
// and turning the sound up is not an alarm (STYLE_GUIDE §3).
//
// Three limit cases, and they are three different drawings:
//
//   muted   the arc goes and a cut stays across the track. No red: muting is
//           not a fault, and it is not zero either — zero is a position in the
//           travel, muted is a state that suspends it.
//   zero    the arc is closed and the node is back at the top. It differs from
//           muted because there is no cut.
//   over    past the end of the travel the excess restarts as a second, thinner
//           arc further out, in the same gradient.
//
// The geometry is the handoff's, which draws it in a 64-unit box: track at
// r 24, node r 3.4, the outer arc at r 30. Everything here is that box scaled
// to whatever size the dial is given, which is why one component serves both
// the 26 px dial of the contracted cell and the 56 px one in the capsule.
//
// See docs/design/CELLS.md §05.
Item {
    id: root

    // The travel, 0 to 1.
    property real fraction: 0
    // What is left over above it, as a fraction of a whole turn: 1.18 of volume
    // is a fraction of 1 and an overflow of 0.18.
    property real overflow: 0
    property bool muted: false

    property color base: Theme.primary

    // Stroke weights in the drawing's own units, so a caller changes them the
    // way the handoff states them: 3 contracted, 1.5 in the capsule.
    property real trackUnits: 3
    property real nodeUnits: 3.4

    implicitWidth: 26
    implicitHeight: 26

    readonly property real size: Math.min(width, height)
    readonly property real unit: size / 64
    readonly property real centreX: width / 2
    readonly property real centreY: height / 2

    readonly property real trackRadius: 24 * unit
    readonly property real overRadius: 30 * unit
    readonly property real stroke: Metrics.crisp(root.trackUnits * unit, Screen.devicePixelRatio)
    readonly property real overStroke: Metrics.crisp(root.trackUnits * 0.7 * unit, Screen.devicePixelRatio)
    readonly property real nodeRadius: root.nodeUnits * unit

    // The arc answers the wheel, so it follows the value rather than stepping
    // to it — the same smoothing the band uses, and for the same reason: a jump
    // between two frames reads as a flicker, not as a movement. The value is
    // the data; this is only how it arrives.
    property real sweep: 0
    onFractionChanged: sweep = fraction
    Component.onCompleted: sweep = fraction

    Behavior on sweep {
        NumberAnimation {
            duration: Timing.contentFade
            easing.type: Easing.OutQuad
        }
    }

    // The head of the travel. Past the end it stays at the top, where the
    // outer arc takes over.
    readonly property real headAngle: Math.min(1, root.sweep) * 2 * Math.PI
    readonly property real nodeX: root.centreX + Math.sin(root.headAngle) * root.trackRadius
    readonly property real nodeY: root.centreY - Math.cos(root.headAngle) * root.trackRadius

    // ---- The track ---------------------------------------------------------
    //
    // Never in the gradient: it is the road, not the value. It firms up a
    // little when muted, because then it is the only ring left.

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Qt.alpha(Theme.line, root.muted ? 0.9 : 0.75)
            strokeWidth: root.stroke
            fillColor: "transparent"

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: root.trackRadius
                radiusY: root.trackRadius
                startAngle: -90
                sweepAngle: 360
                moveToStart: true
            }
        }
    }

    // The cut: the extra sign muting has and zero does not.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.muted ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Timing.transition } }

        ShapePath {
            strokeColor: Qt.alpha(Theme.text, 0.5)
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            startX: root.centreX - 10 * root.unit
            startY: root.centreY - 10 * root.unit

            PathLine {
                x: root.centreX + 10 * root.unit
                y: root.centreY + 10 * root.unit
            }
        }
    }

    // ---- The value ---------------------------------------------------------
    //
    // One light over the whole dial, revealed by the arc and the node — the
    // band's technique, and for the same reason: a stroke cannot carry a
    // gradient, and two separately filled shapes would be two light sources.

    Rectangle {
        id: light
        anchors.fill: parent
        visible: false
        layer.enabled: true

        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradientTop(root.base) }
            GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
        }
    }

    Item {
        id: marks
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "white"
                strokeWidth: root.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: root.centreX
                    centerY: root.centreY
                    radiusX: root.trackRadius
                    radiusY: root.trackRadius
                    startAngle: -90
                    sweepAngle: Math.min(1, root.sweep) * 360
                    moveToStart: true
                }
            }

            ShapePath {
                strokeColor: "white"
                strokeWidth: root.overStroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: root.centreX
                    centerY: root.centreY
                    radiusX: root.overRadius
                    radiusY: root.overRadius
                    startAngle: -90
                    sweepAngle: Math.max(0, Math.min(1, root.overflow)) * 360
                    moveToStart: true
                }
            }
        }

        // The node is the thread's own sign, where something attaches — here,
        // the head of the travel.
        Rectangle {
            width: root.nodeRadius * 2
            height: width
            radius: width / 2
            color: "white"
            antialiasing: true
            x: root.nodeX - width / 2
            y: root.nodeY - height / 2
        }
    }

    // Muted, the whole value goes — the arc and the node with it. It is faded
    // here rather than on the gradient underneath: an opacity set on a layer
    // that is only ever read as a texture never reaches what is drawn from it,
    // and the node stayed lit over the cut.
    OpacityMask {
        anchors.fill: parent
        source: light
        maskSource: marks
        opacity: root.muted ? 0 : 1
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Timing.transition } }
    }
}
