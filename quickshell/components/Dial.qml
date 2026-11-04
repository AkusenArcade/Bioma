import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.core
import qs.components

// The clock's face: two fractions of a whole on one small drawing.
//
//   the sector   fills from twelve o'clock with `fraction` — the hour on the
//                clock, or what is left of a timer while one runs
//   the orbit    a small disc travelling the rim with `orbit` — the minute —
//                drawing behind it, from twelve o'clock, the lit arc the
//                volume dial draws behind its node (Akusen, 2026-09-27)
//
// The rim itself is a track in the line colour: the road the disc runs on, not
// a value. A dial that measures no load stays primary and never takes a state
// colour (STYLE_GUIDE §3). Whatever drives the two values must be live: the
// disc moves because a second passed, never at a rate chosen to look alive.
//
// The geometry is drawn in a 64-unit box and scaled to whatever the dial is
// given, so the face of the contracted cell and the large one beside the lock
// screen's time are the same drawing. It is the graphics card's satellite
// drawing — track at r 24, stroke 1.5, disc 12 across — so at the same box the
// two are the same size on the membrane (Akusen, 2026-09-27).
Item {
    id: root

    // 0 to 1. Above 1 each wraps, which is what an hour and a minute do.
    property real fraction: 0
    // Below 0 there is no orbit, and the dial is the sector alone.
    property real orbit: -1
    property color base: Theme.primary

    // Whether a change is eased. A value that steps — the clock's seconds —
    // is smoothed just enough not to read as a tick. A value that is already
    // continuous — a notification's time draining frame by frame — is drawn
    // as it is: eased, every frame restarted the easing from its first
    // instant and the face never moved at all.
    property bool eased: true
    // The orbit on its own: the clock's second hand is continuous, while its
    // hour sector still steps and is eased.
    property bool orbitEased: root.eased

    implicitWidth: 26
    implicitHeight: 26

    readonly property real size: Math.min(width, height)
    readonly property real unit: size / 64
    readonly property real centreX: width / 2
    readonly property real centreY: height / 2

    readonly property bool orbiting: root.orbit >= 0
    readonly property real trackRadius: 24 * unit
    readonly property real stroke: Math.max(Metrics.crisp(1.5 * unit, Screen.devicePixelRatio), 1.5 * unit)
    readonly property real discRadius: 6 * unit
    // Inside the rim with a clear gap past the disc, so the two never read as
    // one shape.
    readonly property real sectorRadius: root.orbiting ? 13 * unit : 32 * unit

    // ---- Following the values ----------------------------------------------------
    //
    // Each value steps — the clock ticks once a second — and each step is
    // smoothed just enough not to read as a tick.
    //
    // A cycle that closes does **not** rewind. At the end of the minute the
    // disc is at 354° and the next reading is 0°: animated, that is the disc
    // running backwards round the face, which says the opposite of what
    // happened. The new cycle starts at its first frame instead, and only a
    // rising value is animated.

    component Follower: QtObject {
        id: follower

        property real target: 0
        property real value: 0
        property bool eased: true

        readonly property NumberAnimation step: NumberAnimation {
            target: follower
            property: "value"
            duration: Timing.transition
            easing.type: Easing.OutQuad
        }

        onTargetChanged: {
            if (!follower.eased || follower.target < follower.value) {
                follower.step.stop();
                follower.value = follower.target;
            } else {
                follower.step.to = follower.target;
                follower.step.restart();
            }
        }

        Component.onCompleted: follower.value = follower.target
    }

    Follower {
        id: sector
        eased: root.eased
        target: (root.fraction % 1) * 360
    }

    Follower {
        id: travel
        eased: root.orbitEased
        target: root.orbiting ? (root.orbit % 1) * 360 : 0
    }

    // ---- The track -----------------------------------------------------------------

    Shape {
        anchors.fill: parent
        visible: root.orbiting
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Qt.alpha(Theme.line, 0.4)
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

    // ---- The values -------------------------------------------------------------------
    //
    // One light over the whole face, revealed by the sector, the trail and the
    // disc — the volume dial's technique, and for the same reason: a stroke
    // cannot carry a gradient, and separately filled shapes would be separate
    // light sources.

    Rectangle {
        id: light
        anchors.fill: parent
        opacity: 0
        layer.enabled: true

        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradientTop(root.base) }
            GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
        }
    }

    Item {
        id: marks
        anchors.fill: parent
        opacity: 0
        layer.enabled: true

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Without an orbit the sector keeps the thin rim it always had,
            // so the dial still reads as a face and not as a pie.
            ShapePath {
                fillRule: ShapePath.OddEvenFill
                strokeWidth: -1
                fillColor: root.orbiting ? "transparent" : "white"

                PathAngleArc {
                    centerX: root.centreX
                    centerY: root.centreY
                    radiusX: root.size / 2
                    radiusY: root.size / 2
                    startAngle: 0
                    sweepAngle: 360
                    moveToStart: true
                }

                PathAngleArc {
                    centerX: root.centreX
                    centerY: root.centreY
                    radiusX: root.size / 2 - Metrics.crisp(Metrics.thread, Screen.devicePixelRatio)
                    radiusY: root.size / 2 - Metrics.crisp(Metrics.thread, Screen.devicePixelRatio)
                    startAngle: 0
                    sweepAngle: 360
                    moveToStart: true
                }
            }

            // The sector, from twelve o'clock.
            ShapePath {
                strokeWidth: -1
                fillColor: "white"
                startX: root.centreX
                startY: root.centreY

                PathAngleArc {
                    centerX: root.centreX
                    centerY: root.centreY
                    radiusX: root.sectorRadius
                    radiusY: root.sectorRadius
                    startAngle: -90
                    sweepAngle: sector.value
                    moveToStart: false
                }
            }

            // The trail the disc draws behind it.
            ShapePath {
                strokeColor: root.orbiting ? "white" : "transparent"
                strokeWidth: root.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: root.centreX
                    centerY: root.centreY
                    radiusX: root.trackRadius
                    radiusY: root.trackRadius
                    startAngle: -90
                    sweepAngle: travel.value
                    moveToStart: true
                }
            }
        }

        // The disc, at the head of the trail.
        Rectangle {
            visible: root.orbiting
            readonly property real angle: travel.value * Math.PI / 180
            width: root.discRadius * 2
            height: width
            radius: width / 2
            antialiasing: true
            color: "white"
            x: root.centreX + Math.sin(angle) * root.trackRadius - width / 2
            y: root.centreY - Math.cos(angle) * root.trackRadius - height / 2
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: light
        maskSource: marks
    }
}
