import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// A lava lamp heated by the processor.
//
// The one place Bioma draws metaballs. They were rejected for the shapes of
// the interface (PRD §6.5) because a soft union has no outline anyone can
// predict, and a surface that is pressed needs one. An organism is never
// pressed, and here the union is the point: wax melts together where it meets.
// The silhouette stays inside the panel — the glass is still a rectangle, and
// the blur still follows it.
//
// Every motion is the temperature. Wax sits on the heater and warms towards
// it; once it is as warm as the heater will make it, it lets go and rises,
// cools as it climbs and sinks back. How high it gets is how hot the
// processor is — a fifth of the lamp a little above idle, the whole lamp near
// the ceiling — and below the start of the scale nothing warms enough to
// leave the bottom, so a cool machine is a still pool. The heater's light and
// the wax's colour say the same thing as the state colours everywhere else.
//
// The simulation runs only while something moves. A pool at rest draws no
// frames until the next reading warms it.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    // The wax fills the glass edge to edge, with the rim drawn over it.
    readonly property bool bleeds: true

    readonly property bool present: SystemMonitor.cpuTemperatureKnown

    implicitWidth: 200 * root.factor
    implicitHeight: 320 * root.factor

    // ---- The scale --------------------------------------------------------------

    // Degrees at which the wax is cold and at which it is as hot as it gets.
    // The default cold sits just above this processor's idle, so an idle
    // machine is a still lamp; a machine that idles warmer says so here.
    readonly property real cold: root.entry.cold ?? 48
    readonly property real hot: root.entry.hot ?? 90

    readonly property real temperature: SystemMonitor.cpuTemperature
    readonly property real heat: root.present
        ? Math.max(0, Math.min(1, (root.temperature - root.cold) / Math.max(1, root.hot - root.cold)))
        : 0

    // The state colours by default, as every reading of load is drawn; or,
    // with `colour: "theme"`, the theme's own light — the colour the icons
    // are lit with — for a lamp that is an object on the desktop before it is
    // a gauge. The heat is then said by the motion and the heater alone.
    readonly property bool themed: root.entry.colour === "theme"
    readonly property color wax: root.themed ? Theme.primary : Theme.stateFor(root.heat)

    // ---- The wax ----------------------------------------------------------------

    // Constants of the simulation, not durations: rates per second and
    // fractions of the lamp. Tuned offline (2026-10-05) so that the height the
    // wax reaches grows with the heat, from 0.2 of the lamp at the start of
    // the scale to its top at the end of it.
    readonly property var physics: ({
        "release": 0.16,    // heat below which nothing leaves the bottom
        "buoyant": 0.12,    // wax warmer than this rises, cooler sinks
        "warming": 1.2,     // towards the heater's heat, per second, on it
        "cooling": 0.2,     // towards nothing, per second, off it
        "lift": 1.2,
        "drag": 2.2,
        "zone": 0.08,       // how far above the bottom the heater reaches
        "sway": 0.10        // sideways wander, a fraction of the width
    })

    // Seven blobs of different sizes, side by side on the heater: at rest
    // they overlap into one pool. Radii are fractions of the width.
    property var blobs: []

    function seed() {
        const out = [];
        const count = 7;
        for (let i = 0; i < count; i++) {
            // Sizes, warming rates and starting warmth shuffled differently,
            // so the blobs do not all let go of the heater at once.
            const spread = ((i * 37) % count) / (count - 1);
            out.push({
                "r": 0.07 + 0.05 * spread,
                "home": 0.2 + 0.6 * i / (count - 1),
                "warming": 0.4 + 1.2 * ((i * 53) % count) / (count - 1),
                "y": 0,
                "vy": 0,
                "t": -0.15 * ((i * 29) % count) / (count - 1),
                "phase": i * 1.7,
                "pinned": true
            });
        }
        root.blobs = out;
        root.settle();
        root.moving = true;
    }

    // Where a blob of radius r rests: its centre a little above the bottom,
    // the rest of it under the edge, so the pool is cut by the glass.
    function floorOf(blob) {
        return blob.r * 0.6 * root.width / Math.max(1, root.height);
    }

    // Where it stops rising: under the cap, which is where the figure is
    // written, so the wax never runs over what it is saying.
    readonly property real cap: caption.visible ? caption.y + caption.height + root.inset / 2 : 0

    function ceilingOf(blob) {
        return 1 - (root.cap + blob.r * 1.1 * root.width) / Math.max(1, root.height);
    }

    function settle() {
        for (const blob of root.blobs)
            if (blob.pinned)
                blob.y = root.floorOf(blob);
        root.draw();
    }

    property bool moving: false

    onHeatChanged: root.moving = true
    onWidthChanged: root.settle()
    onHeightChanged: root.settle()

    function step(dt) {
        const p = root.physics;
        const heat = root.heat;
        const free = heat > p.release;
        // Hotter wax is also quicker wax.
        dt *= 0.3 + 1.7 * heat;

        let moving = false;
        for (const blob of root.blobs) {
            const floor = root.floorOf(blob);
            const ceiling = root.ceilingOf(blob);

            if (blob.y < floor + p.zone)
                blob.t += (heat - blob.t) * p.warming * blob.warming * dt;
            else
                blob.t -= blob.t * p.cooling * (1 + 2 * Math.max(0, blob.y - 0.7)) * dt;

            if (blob.pinned) {
                if (free && blob.t > 0.9 * heat) {
                    blob.pinned = false;
                } else {
                    if (free)
                        moving = true;
                    continue;
                }
            }
            moving = true;

            const buoyancy = (blob.t - p.buoyant) * p.lift * 0.1 / blob.r;
            blob.vy += (buoyancy - p.drag * blob.vy) * dt;
            blob.y += blob.vy * dt;
            blob.phase += Math.abs(blob.vy) * 6 * dt;

            if (blob.y > ceiling) {
                blob.y = ceiling;
                blob.vy = Math.min(0, blob.vy);
            }
            if (blob.y < floor) {
                blob.y = floor;
                blob.vy = 0;
                blob.pinned = true;
            }
        }
        root.moving = moving;
        root.draw();
    }

    // Into the shader's ten slots, in pixels; the slots left over are empty.
    function draw() {
        const w = root.width;
        const h = root.height;
        const slots = [];
        for (const blob of root.blobs) {
            const r = blob.r * w;
            const x = Math.max(blob.r, Math.min(1 - blob.r, blob.home + root.physics.sway * Math.sin(blob.phase))) * w;
            slots.push(Qt.vector4d(x, h - blob.y * h, root.present ? r : 0, 0));
        }
        while (slots.length < 10)
            slots.push(Qt.vector4d(0, 0, 0, 0));
        lamp.b0 = slots[0]; lamp.b1 = slots[1]; lamp.b2 = slots[2]; lamp.b3 = slots[3]; lamp.b4 = slots[4];
        lamp.b5 = slots[5]; lamp.b6 = slots[6]; lamp.b7 = slots[7]; lamp.b8 = slots[8]; lamp.b9 = slots[9];
    }

    // At the monitor's rate. Thirty frames a second showed as stutter at
    // once, and a timer at sixty is not tied to the refresh, so on a 120 or
    // 165 Hz screen it would land unevenly (Akusen, 2026-10-05). Measured: the
    // moving wax costs about 5.6% of a core at 165 Hz, nothing at rest.
    FrameAnimation {
        running: root.moving && root.visible && root.present
        // A long frame — the lamp just came back on screen — is taken as a
        // short one, so the wax resumes rather than leaps.
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    Component.onCompleted: root.seed()

    ShaderEffect {
        id: lamp

        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("lava.frag.qsb")

        readonly property size extent: Qt.size(width, height)
        readonly property real radius: root.metrics.radiusPanel
        property real heat: root.heat
        property color wax: root.wax
        readonly property color core: Theme.text

        property vector4d b0; property vector4d b1; property vector4d b2; property vector4d b3; property vector4d b4
        property vector4d b5; property vector4d b6; property vector4d b7; property vector4d b8; property vector4d b9

        Behavior on heat { NumberAnimation { duration: Timing.theme } }
        Behavior on wax { ColorAnimation { duration: Timing.theme } }
    }

    // ---- The figure ---------------------------------------------------------------

    readonly property bool figures: root.entry.figures !== false
    readonly property real inset: 18 * root.factor

    Column {
        id: caption

        visible: root.figures && root.present
        x: root.inset
        y: root.inset
        spacing: 2 * root.factor

        Text {
            text: "CPU"
            color: Theme.text
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontLabel,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
            })
        }

        LitText {
            base: root.wax
            text: `${Math.round(root.temperature)}°`
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontValue,
                "weight": Typography.weightValue
            }))
        }
    }

    // Blank: placed while arranging on a machine that reports no temperature.
    Text {
        visible: !root.present
        anchors.centerIn: parent
        width: parent.width - root.inset * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "No temperature sensor"
        color: Theme.textFaint
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontSecondary,
            "weight": Typography.weightSecondary
        })
    }
}
