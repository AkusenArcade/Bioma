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
    // Watts going into the battery, and nothing else's: zero unless it is
    // charging. Drops come in as often as they do.
    property real inflow: 0
    // The battery full with the charger in: nothing comes in any more, so the
    // drops cannot say it, and a bolt is cut out of the charge instead.
    property bool mainsFull: false

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
    // The liquid's source item is hidden — it exists to be sampled by the mask
    // — so nothing inside it may take its `running` from being visible.
    readonly property bool ramMoving: kind === "ram" && !ramFull

    // The liquid is held inside the ring by a mask, not by a clip: clipping in
    // Qt Quick is rectangular and cannot follow a circle. Source and mask are
    // both hidden and only the masked result is drawn.
    OpacityMask {
        anchors.fill: parent
        visible: root.ramMoving
        source: liquid
        maskSource: liquidShape
    }

    Item {
        id: liquid
        anchors.fill: parent
        // Hidden from the scene but rendered to a texture of its own: in Qt 6 an
        // item that is merely hidden is not drawn at all, and a mask has
        // nothing to sample. Hidden by opacity, not `visible` (CLAUDE.md).
        opacity: 0
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
                running: root.ramMoving
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
        opacity: 0
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

        // A card at idle still has a clock, so the satellite never stops: it
        // turns at its slowest and speeds up in proportion. And it is advanced
        // frame by frame rather than by an animation with a duration — changing
        // a duration restarts the animation, which sends the satellite back to
        // where it began and reads as a stutter rather than as a change of
        // speed.
        readonly property real period: 6000 - root.rate * 4800

        FrameAnimation {
            running: orbit.visible
            onTriggered: orbit.angle = (orbit.angle + 360 * frameTime * 1000 / orbit.period) % 360
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
        maskSource: chargeShape
    }

    // The vessel the charge is held in, and, full on the mains, a bolt cut
    // out of it: a hole, so what shows through is whatever the indicator sits
    // on, never a colour copied in. Still — there is no value in it to move
    // with, only a state.
    Item {
        id: chargeShape
        anchors.fill: parent
        opacity: 0
        layer.enabled: true

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillRule: ShapePath.OddEvenFill
                strokeWidth: -1
                fillColor: "#ffffff"

                PathAngleArc {
                    centerX: root.centre; centerY: root.centre
                    radiusX: root.ringRadius - root.ringStroke
                    radiusY: root.ringRadius - root.ringStroke
                    startAngle: 0; sweepAngle: 360; moveToStart: true
                }
                // In the 64 grid, centred on the ring.
                PathPolyline {
                    path: root.kind === "battery" && root.mainsFull ? [
                        Qt.point(36 * root.unit, 16 * root.unit),
                        Qt.point(23 * root.unit, 35 * root.unit),
                        Qt.point(31 * root.unit, 35 * root.unit),
                        Qt.point(28 * root.unit, 48 * root.unit),
                        Qt.point(41 * root.unit, 29 * root.unit),
                        Qt.point(33 * root.unit, 29 * root.unit),
                        Qt.point(36 * root.unit, 16 * root.unit)
                    ] : []
                }
            }
        }
    }

    // The front sits where the charge is, measured against the vessel — the
    // inside of the ring, not the square it is drawn in — as the memory's
    // surface is: measured against the square, the first seventh of the
    // charge fell behind the glass, and a nearly flat battery read as empty.
    readonly property real chargeVessel: (ringRadius - ringStroke) * 2
    readonly property real chargeFront: centre - chargeVessel / 2 + level * chargeVessel

    Item {
        id: charge
        anchors.fill: parent
        opacity: 0
        layer.enabled: true

        Rectangle {
            x: 0
            y: 0
            width: root.chargeFront
            height: root.height
            color: root.base
        }
    }

    // Charging, drops come in and melt into the level, as often as watts go
    // in — the nucleus's vocabulary (ORGANISMS §14), so the two say a charger
    // the same way. They are born inside the ring, against its wall on the
    // empty side, and fall leftwards onto the level the way the level itself
    // grows; nothing is drawn outside the ring. Full on the mains, or with no
    // watts reported, nothing comes in and it is still.
    //
    // Constants, not durations: the nucleus's, its fall scaled from its
    // envelope to this ring.
    readonly property var physics: ({
        "dropsPerWatt": 1 / 20,
        "fewest": 0.3,
        "most": 2.5,
        "drop": 0.13,       // a drop's radius, as a share of the ring's
        "fall": 260 / 70,   // the nucleus's 260 px/s² over its 70 px envelope, in rings a second²
        "absorb": 0.25      // seconds a drop takes to be taken in
    })

    readonly property real dropRate: kind === "battery" && inflow > 0.5
        ? Math.max(physics.fewest, Math.min(physics.most, inflow * physics.dropsPerWatt)) : 0
    readonly property real dropRadius: ringRadius * physics.drop

    // Three in flight at most, as in the nucleus.
    property var drops: []
    property real untilNext: 0

    function dropWait() {
        return root.dropRate > 0 ? -Math.log(1 - Math.random()) / root.dropRate : 0;
    }

    onDropRateChanged: if (root.dropRate > 0 && root.untilNext <= 0) root.untilNext = root.dropWait()

    // The room a drop's centre has inside the ring: the circle it can move in
    // without leaving the glass.
    readonly property real dropRoom: ringRadius - ringStroke - dropRadius

    // Where the centre of a drop at height `y` stops: sunk into the level's
    // front, or against the far wall where the level does not reach that row.
    function landing(y) {
        const dy = Math.min(root.dropRoom, Math.abs(y - root.centre));
        const wall = root.centre - Math.sqrt(root.dropRoom * root.dropRoom - dy * dy);
        return Math.max(wall, root.chargeFront + root.dropRadius * 0.2);
    }

    function dropStep(dt) {
        const p = root.physics;
        const next = [];
        // Each drop is a new object every frame: one changed in place is the
        // same value to the binding that reads it, and the disc would move only
        // when another drop came or went.
        for (const old of root.drops) {
            const drop = Object.assign({}, old);
            if (drop.absorbing >= 0) {
                drop.absorbing += dt;
                if (drop.absorbing < p.absorb)
                    next.push(drop);
                continue;
            }
            drop.speed += p.fall * root.ringRadius * dt;
            drop.x -= drop.speed * dt;
            const touching = root.landing(drop.y);
            if (drop.x <= touching) {
                drop.x = touching;
                drop.absorbing = 0;
            }
            next.push(drop);
        }

        if (root.dropRate > 0) {
            root.untilNext -= dt;
            if (root.untilNext <= 0 && next.length < 3) {
                // Against the inside of the ring, on the empty side, no
                // further up or down than the level can take it in.
                const angle = (Math.random() - 0.5) * 100 * Math.PI / 180;
                next.push({
                    "x": root.centre + Math.cos(angle) * root.dropRoom,
                    "y": root.centre + Math.sin(angle) * root.dropRoom,
                    "speed": 0,
                    "absorbing": -1
                });
                root.untilNext = root.dropWait();
            }
        }
        root.drops = next;
    }

    FrameAnimation {
        running: root.visible && (root.dropRate > 0 || root.drops.length > 0)
        onTriggered: root.dropStep(Math.min(frameTime, 0.05))
    }

    Repeater {
        model: 3

        Disc {
            required property int index
            readonly property var drop: root.drops[index] ?? null
            readonly property real radius: drop === null ? 0
                : root.dropRadius * (drop.absorbing >= 0 ? 1 - drop.absorbing / root.physics.absorb : 1)

            visible: drop !== null && radius > 0
            base: root.base
            width: radius * 2
            height: width
            x: (drop?.x ?? 0) - radius
            y: (drop?.y ?? 0) - radius
        }
    }
}
