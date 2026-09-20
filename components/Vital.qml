import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.core

// One vital sign: a ring, and inside it a shape that moves.
//
// Colour says state, form says domain. The ring is the same for all of them —
// that is what makes them a family — and what happens inside it says which
// machine part is speaking: a beating dot is the processor, a liquid that
// sloshes is the memory, a satellite in orbit is the graphics card. Colour only
// ever says how hard that part is working.
//
// Every movement carries a live value in its rate. An indicator with nothing to
// report is still — never a fixed rhythm chosen to look alive.
Item {
    id: root

    // "cpu" | "ram" | "gpu" | "battery"
    property string kind: "cpu"

    // 0..1, the load: it decides the colour and nothing else.
    property real load: 0
    // 0..1, the frequency or its equivalent: it decides the rhythm.
    property real rate: 0
    // 0..1, how full: the memory's level, the battery's charge.
    property real level: 0

    // A scale the user moves would be a control and would stay primary; these
    // are measurements, so they speak in the state colours.
    readonly property color base: Theme.stateFor(load)
    readonly property bool critical: load >= Theme.thresholdAlert

    implicitWidth: 26
    implicitHeight: 26

    // The geometry is written in the 64 grid the design draws it in.
    readonly property real unit: Math.min(width, height) / 64
    readonly property real centre: 32 * unit
    readonly property real ringRadius: 24 * unit
    readonly property real ringStroke: Math.max(Metrics.crisp(1.5 * unit, Screen.devicePixelRatio), 1.5 * unit)

    // ---- The ring ----------------------------------------------------------

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // The memory reaching the top is the one case where the ring itself
        // goes: a full disc, not a dot inside a ring, which is what a critical
        // processor looks like and the two have to stay apart.
        visible: !root.ramFull

        ShapePath {
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1
            fillGradient: LightGradient {
                base: root.base
                boxWidth: root.width
                boxHeight: root.height
            }

            PathAngleArc {
                centerX: root.centre; centerY: root.centre
                radiusX: root.ringRadius + root.ringStroke / 2
                radiusY: root.ringRadius + root.ringStroke / 2
                startAngle: 0; sweepAngle: 360; moveToStart: true
            }
            PathAngleArc {
                centerX: root.centre; centerY: root.centre
                radiusX: root.ringRadius - root.ringStroke / 2
                radiusY: root.ringRadius - root.ringStroke / 2
                startAngle: 0; sweepAngle: 360; moveToStart: true
            }
        }
    }

    // Past the threshold the ring emits a wave: it expands and fades, and it is
    // the only thing in the shell that repeats at a fixed rate — an alarm has
    // no value to encode beyond the fact that it is one.
    Shape {
        id: halo
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.critical
        opacity: 0

        property real spread: 0

        ShapePath {
            strokeColor: Theme.alert
            strokeWidth: root.ringStroke
            fillColor: "transparent"

            PathAngleArc {
                centerX: root.centre; centerY: root.centre
                radiusX: root.ringRadius + halo.spread
                radiusY: root.ringRadius + halo.spread
                startAngle: 0; sweepAngle: 360; moveToStart: true
            }
        }

        SequentialAnimation {
            running: root.critical
            loops: Animation.Infinite

            ParallelAnimation {
                NumberAnimation { target: halo; property: "spread"; from: 0; to: 8 * root.unit; duration: 900; easing.type: Easing.OutQuad }
                SequentialAnimation {
                    NumberAnimation { target: halo; property: "opacity"; from: 0.5; to: 0; duration: 405; easing.type: Easing.OutQuad }
                    PauseAnimation { duration: 495 }
                }
            }
        }
    }

    // ---- The processor: a beating dot --------------------------------------
    //
    // The beat is the clock, on the moving average the service already keeps:
    // 45 beats a minute at idle, 140 at full speed. It pulses and then waits,
    // the way a heart does — a dot pulsing continuously would be a metronome.

    readonly property int beatInterval: Math.round(60000 / (45 + root.rate * 95))

    Item {
        id: heart
        anchors.centerIn: parent
        width: 16 * root.unit
        height: width
        visible: root.kind === "cpu"

        property real pulse: 1

        Disc {
            anchors.centerIn: parent
            base: root.base
            // Grown by size rather than scaled: a scaled disc is cheap and
            // correct here, but the shell has one way of growing things.
            width: heart.width * heart.pulse
            height: width
        }

        SequentialAnimation {
            running: heart.visible
            loops: Animation.Infinite

            NumberAnimation { target: heart; property: "pulse"; to: 1.45; duration: Math.round(root.beatInterval * 0.09); easing.type: Easing.OutQuad }
            NumberAnimation { target: heart; property: "pulse"; to: 1.0; duration: Math.round(root.beatInterval * 0.15); easing.type: Easing.InQuad }
            PauseAnimation { duration: Math.round(root.beatInterval * 0.76) }
        }
    }

    // ---- The memory: a liquid ----------------------------------------------
    //
    // The level is the memory in use — data, not animation: it moves when the
    // machine allocates, not when time passes. The wave on top is the only part
    // that runs on a clock, and it runs at one period per cycle so that the
    // translation closes on itself.

    readonly property bool ramFull: kind === "ram" && level >= 0.995

    // The liquid is held inside the ring by a mask, not by a clip: clipping in
    // Qt Quick is rectangular and cannot follow a circle. Source and mask are
    // both hidden and only the masked result is drawn.
    OpacityMask {
        anchors.fill: parent
        visible: root.kind === "ram" && !root.ramFull
        source: liquid
        maskSource: liquidShape
    }

    Item {
        id: liquid
        anchors.fill: parent
        // Hidden from the scene but rendered to a texture of its own: in Qt 6 an
        // item that is merely invisible is not drawn at all, and a mask has
        // nothing to sample.
        visible: false
        layer.enabled: true

        // The surface sits where the memory is, measured against the vessel —
        // the inside of the ring, not the square it is drawn in. Half full puts
        // it on the centre line either way, which is what the design draws; the
        // difference is at the ends, where a fifth of the memory has to read as
        // a fifth rather than as a sliver below the glass.
        readonly property real vessel: (root.ringRadius - root.ringStroke) * 2
        readonly property real surface: root.centre - vessel / 2 + (1 - root.level) * vessel
        readonly property real period: 46 * root.unit

        Shape {
            id: wave
            width: root.width * 4
            height: root.height
            x: -liquid.period
            preferredRendererType: Shape.CurveRenderer

            NumberAnimation on x {
                running: liquid.visible
                loops: Animation.Infinite
                from: -liquid.period
                to: 0
                duration: 2400
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: LightGradient {
                    base: root.base
                    boxWidth: root.width
                    boxHeight: root.height
                }

                startX: 0
                startY: liquid.surface

                // The path runs past the circle by more than one translation on
                // both sides: stop it at the edge and the end of a cycle leaves
                // an empty margin and the movement appears to halt.
                PathQuad { x: 23 * root.unit; y: liquid.surface; controlX: 11.5 * root.unit; controlY: liquid.surface - 6 * root.unit }
                PathQuad { x: 46 * root.unit; y: liquid.surface; controlX: 34.5 * root.unit; controlY: liquid.surface + 6 * root.unit }
                PathQuad { x: 69 * root.unit; y: liquid.surface; controlX: 57.5 * root.unit; controlY: liquid.surface - 6 * root.unit }
                PathQuad { x: 92 * root.unit; y: liquid.surface; controlX: 80.5 * root.unit; controlY: liquid.surface + 6 * root.unit }
                PathQuad { x: 115 * root.unit; y: liquid.surface; controlX: 103.5 * root.unit; controlY: liquid.surface - 6 * root.unit }
                PathLine { x: 115 * root.unit; y: 64 * root.unit }
                PathLine { x: 0; y: 64 * root.unit }
            }
        }
    }

    // The shape the liquid is held in: the inside of the ring.
    Item {
        id: liquidShape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Disc {
            anchors.centerIn: parent
            width: (root.ringRadius - root.ringStroke) * 2
            height: width
            base: "#ffffff"
        }
    }

    // Memory at the top: the ring becomes a full disc and pulses in the alert
    // colour.
    Disc {
        id: fullMemory
        anchors.centerIn: parent
        visible: root.ramFull
        base: Theme.alert
        width: (root.ringRadius + root.ringStroke / 2) * 2 * pulse
        height: width

        property real pulse: 1

        SequentialAnimation {
            running: fullMemory.visible
            loops: Animation.Infinite
            NumberAnimation { target: fullMemory; property: "pulse"; to: 0.88; duration: 450; easing.type: Easing.InOutQuad }
            NumberAnimation { target: fullMemory; property: "pulse"; to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
        }
    }

    // ---- The graphics card: a satellite ------------------------------------
    //
    // Two different quantities on one shape, and §9.2 of the PRD is explicit
    // about why they must stay apart: a card at thirty per cent utilisation can
    // sit at full clock. The orbit is the clock; the colour is the load.

    Item {
        id: orbit
        anchors.fill: parent
        visible: root.kind === "gpu"

        property real angle: 0
        readonly property int period: Math.round(4000 - root.rate * 2800)

        RotationAnimation {
            target: orbit
            property: "angle"
            running: orbit.visible && root.rate > 0.01
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: orbit.period
        }

        Disc {
            base: root.base
            width: 12 * root.unit
            height: width
            x: root.centre + Math.cos((orbit.angle - 45) * Math.PI / 180) * root.ringRadius - width / 2
            y: root.centre + Math.sin((orbit.angle - 45) * Math.PI / 180) * root.ringRadius - height / 2
        }
    }

    // ---- The battery: a level that fills sideways --------------------------
    //
    // Horizontal, left to right, precisely so that it cannot be confused with
    // the memory's liquid, which rises from the bottom. It exists only where
    // there is a battery.

    OpacityMask {
        anchors.fill: parent
        visible: root.kind === "battery"
        source: charge
        maskSource: liquidShape
    }

    Item {
        id: charge
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            x: 0
            y: 0
            width: root.width * root.level
            height: root.height
            color: root.base
        }
    }
}
