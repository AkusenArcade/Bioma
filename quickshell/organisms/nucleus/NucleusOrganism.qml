import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Nucleus: the battery, as the mass at the heart of the cell.
//
// The nucleus is as large as the charge: its area is the charge's share of
// the envelope round it, which is the battery full. Charging, drops come in
// from outside and melt into it, as often as watts go in. Discharging, it
// beats, as fast as watts go out. Full and on the mains, nothing goes in or
// out, and it is still.
//
// Colour is the charge's state: calm while there is plenty, active as it
// runs down, alert when little is left.
//
// The drops melt into the nucleus with the cytoplasm's shader (§08): what
// joins is what belongs together. Only a laptop has one; on a desktop it is
// absent.
//
// See docs/design/ORGANISMS.md §14.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    // What it draws, from the machine — properties rather than bindings
    // read in place, so a harness without a battery can hand it one.
    property bool battery: SystemMonitor.hasBattery
    property real level: SystemMonitor.batteryLevel
    property real watts: SystemMonitor.batteryWatts
    property bool charging: SystemMonitor.charging
    property bool discharging: SystemMonitor.discharging
    property real secondsLeft: SystemMonitor.batterySecondsLeft

    readonly property bool present: root.battery

    // Two units by one: the nucleus in the square on the left, the figures
    // beside it.
    readonly property real well: Math.min(root.height, root.width / 2)
    readonly property real envelope: root.well / 2 - 10 * root.factor
    readonly property real mass: Math.max(3 * root.factor, root.envelope * 0.92 * Math.sqrt(root.level))

    readonly property color tint: Theme.stateFor(1 - root.level)

    // ---- What moves -----------------------------------------------------------------

    // Constants, not durations: drops a second per watt in, beats a second
    // per watt out, and how far a beat swells the nucleus.
    readonly property var physics: ({
        "dropsPerWatt": 1 / 20,
        "fewest": 0.3,
        "most": 2.5,
        "beatsPerWatt": 1 / 12,
        "slowest": 0.2,
        "fastest": 2.0,
        "swell": 0.04,      // of the radius, and 2.5 px besides: a small nucleus beats visibly too
        "drop": 0.13,       // a drop's radius, as a share of the envelope's
        "fall": 260,        // px/s² at factor 1, towards the nucleus
        "absorb": 0.25      // seconds a drop takes to be taken in
    })

    readonly property real dropRate: root.charging && root.watts > 0.5
        ? Math.max(root.physics.fewest, Math.min(root.physics.most, root.watts * root.physics.dropsPerWatt)) : 0
    readonly property real beatRate: root.discharging && root.watts > 0.5
        ? Math.max(root.physics.slowest, Math.min(root.physics.fastest, root.watts * root.physics.beatsPerWatt)) : 0

    // Three drops in flight at most: the shader fuses three lobes with the
    // nucleus, and at the fastest rate a drop is in before the fourth comes.
    property var drops: []
    property real phase: 0
    property real untilNext: 0

    readonly property bool moving: root.present && (root.dropRate > 0 || root.beatRate > 0
                                                    || root.drops.length > 0 || root.phase !== 0)

    function wait() {
        return root.dropRate > 0 ? -Math.log(1 - Math.random()) / root.dropRate : 0;
    }

    onDropRateChanged: if (root.dropRate > 0 && root.untilNext <= 0) root.untilNext = root.wait()

    function step(dt) {
        const p = root.physics;
        const f = root.factor;

        if (root.beatRate > 0) {
            root.phase = (root.phase + dt * root.beatRate * Math.PI * 2) % (Math.PI * 2);
        } else if (root.phase !== 0) {
            // A beat that stops finishes going back to rest, not mid-swell:
            // the swell is the first half of the turn, the second is rest.
            root.phase += dt * p.slowest * Math.PI * 2;
            if (root.phase >= Math.PI)
                root.phase = 0;
        }

        const next = [];
        for (const drop of root.drops) {
            // Taken in where it touched, shrinking there: carried on inside
            // the nucleus, its own field showed through as a dark ring — as
            // osmosis found with its pool.
            if (drop.absorbing >= 0) {
                drop.absorbing += dt;
                if (drop.absorbing < p.absorb)
                    next.push(drop);
                continue;
            }
            drop.speed += p.fall * f * dt;
            drop.distance -= drop.speed * dt;
            const touching = root.mass + root.envelope * p.drop * 0.2;
            if (drop.distance <= touching) {
                drop.distance = touching;
                drop.absorbing = 0;
            }
            next.push(drop);
        }

        if (root.dropRate > 0) {
            root.untilNext -= dt;
            if (root.untilNext <= 0 && next.length < 3) {
                next.push({
                    "angle": Math.random() * Math.PI * 2,
                    // Just outside the envelope, and wholly inside the square.
                    "distance": Math.min(root.envelope * 1.08, root.well / 2 - root.envelope * p.drop - 1),
                    "speed": 0,
                    "absorbing": -1
                });
                root.untilNext = root.wait();
            }
        }
        root.drops = next;
        root.draw();
    }

    function draw() {
        const p = root.physics;
        const c = root.well / 2;
        const beat = Math.max(0, Math.sin(root.phase));
        const radius = root.mass * (1 + p.swell * beat) + 2.5 * root.factor * beat;
        tissue.l0 = Qt.vector4d(c, c, root.present ? radius : 0, 0);
        const out = [];
        for (let i = 0; i < 3; i++) {
            const drop = root.drops[i];
            if (!drop) {
                out.push(Qt.vector4d(c, c, 0, 0));
                continue;
            }
            const r = root.envelope * p.drop * (drop.absorbing >= 0 ? 1 - drop.absorbing / p.absorb : 1);
            out.push(Qt.vector4d(c + Math.cos(drop.angle) * drop.distance,
                                 c + Math.sin(drop.angle) * drop.distance, Math.max(0, r), 0));
        }
        tissue.l1 = out[0];
        tissue.l2 = out[1];
        tissue.l3 = out[2];
    }

    onMassChanged: root.draw()
    onPresentChanged: root.draw()
    Component.onCompleted: root.draw()

    FrameAnimation {
        running: root.moving && root.visible
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    // ---- The nucleus ----------------------------------------------------------------

    // The envelope: the battery full, a hairline round the room the nucleus
    // could fill.
    Rectangle {
        x: root.well / 2 - root.envelope
        y: root.well / 2 - root.envelope
        width: root.envelope * 2
        height: width
        radius: width / 2
        antialiasing: true
        color: Qt.alpha(Theme.text, 0.03)
        border.width: 1.5 * root.factor
        border.color: Qt.alpha(Theme.text, 0.22)
    }

    ShaderEffect {
        id: tissue

        width: root.well
        height: root.well
        fragmentShader: Qt.resolvedUrl("../cytoplasm/cytoplasm.frag.qsb")

        readonly property size extent: Qt.size(width, height)
        readonly property real radius: 0
        readonly property color core: Theme.text

        property color c0: root.tint
        readonly property color c1: root.tint
        readonly property color c2: root.tint
        readonly property color c3: root.tint
        readonly property color c4: root.tint
        readonly property color c5: root.tint

        Behavior on c0 { ColorAnimation { duration: Timing.theme } }

        property vector4d l0; property vector4d l1; property vector4d l2; property vector4d l3
        readonly property vector4d l4: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l5: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l6: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l7: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l8: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l9: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l10: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l11: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l12: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l13: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l14: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l15: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l16: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l17: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l18: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l19: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l20: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l21: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l22: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d l23: Qt.vector4d(0, 0, 0, 0)
    }

    // Blank, while arranging on a machine with no battery.
    Text {
        visible: !root.present
        x: 0
        width: root.well
        y: (root.well - height) / 2
        horizontalAlignment: Text.AlignHCenter
        text: "No battery"
        color: Theme.textFaint
        font.family: Typography.expressive
        font.pixelSize: Math.round(14 * root.factor)
        font.italic: true
    }

    // ---- The figures ------------------------------------------------------------------

    function duration(seconds) {
        const minutes = Math.round(seconds / 60);
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return h > 0 ? `${h} H ${String(m).padStart(2, "0")} M` : `${m} M`;
    }

    readonly property string flow: {
        const w = root.watts > 0.05 ? ` · ${root.watts.toFixed(1)} W` : "";
        if (root.charging)
            return "CHARGING" + w;
        if (root.discharging)
            return "DISCHARGING" + w;
        return root.level >= 0.995 ? "FULL" : "ON MAINS";
    }

    readonly property string remaining: root.secondsLeft <= 0 ? ""
        : root.charging ? `FULL IN ${root.duration(root.secondsLeft)}`
        : root.discharging ? `${root.duration(root.secondsLeft)} LEFT` : ""

    Column {
        visible: root.present
        x: root.well + 14 * root.factor
        width: root.width - x
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6 * root.factor

        LitText {
            text: `${Math.round(root.level * 100)}%`
            base: root.tint
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": Math.round(40 * root.factor),
                "weight": Typography.weightValue
            }))
        }

        Text {
            text: root.flow
            color: Theme.text
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
            }))
        }

        Text {
            visible: text.length > 0
            text: root.remaining
            color: Theme.textMuted
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "weight": Typography.weightSecondary
            }))
        }
    }
}
