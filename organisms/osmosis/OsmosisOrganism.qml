import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Osmosis: the machine's network traffic, as water crossing a membrane.
//
// The membrane across the top is the link; the pool at the bottom is the
// machine. What arrives buds off the underside of the membrane and falls into
// the pool; what leaves buds off the pool's surface and rises into the
// membrane. Every drop is a rate: drops in each direction come as often as
// bytes cross that way, on a logarithmic scale, at random intervals around
// that rate, as packets do. Below the quiet threshold nothing buds, and with
// no drop left in flight the water is still and draws no frames.
//
// The lava lamp's metaballs (§07), for the same reason they are allowed
// there: an organism is never pressed, and the union is the point — a drop
// joins the water it falls into.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    // The water fills the glass edge to edge, with the rim drawn over it.
    readonly property bool bleeds: true

    readonly property bool present: SystemMonitor.netKnown

    // One unit by two: the membrane above, the pool below.

    // ---- The scale --------------------------------------------------------------

    // Kilobytes per second: below `quiet` a link is idle — a machine at rest
    // still trades a few hundred bytes a second of name lookups and keepalives
    // — and at `ceiling` the drops come as fast as they ever do, about what a
    // gigabit link carries.
    readonly property real quiet: (root.entry.quiet ?? 4) * 1024
    readonly property real ceiling: (root.entry.ceiling ?? 100000) * 1024

    // Drops per second, each way.
    readonly property real slowest: 0.4
    readonly property real fastest: 6

    function dropsPerSecond(bytes) {
        if (!root.present || bytes < root.quiet)
            return 0;
        const span = Math.log(root.ceiling / root.quiet);
        const along = Math.max(0, Math.min(1, Math.log(bytes / root.quiet) / span));
        return root.slowest + (root.fastest - root.slowest) * along;
    }

    readonly property real inRate: root.dropsPerSecond(SystemMonitor.netIn)
    readonly property real outRate: root.dropsPerSecond(SystemMonitor.netOut)

    readonly property color water: Theme.primary

    // ---- Where the water is -------------------------------------------------------

    readonly property real inset: 18 * root.factor
    readonly property real thickness: 6 * root.factor

    // The membrane runs under the figures, so no drop ever crosses what they
    // say; without them it sits just under the top of the glass.
    readonly property real membrane: (caption.visible ? caption.y + caption.height + root.inset * 0.6
                                                      : root.inset) + root.thickness / 2
    readonly property real poolSurface: root.height * 0.8

    // Constants of the fall, not durations: fractions of the distance between
    // the membrane and the pool per second squared, and seconds a drop takes
    // to gather before it lets go. A drop crosses in about a second, whatever
    // the traffic; how many cross is what the traffic says.
    readonly property var physics: ({
        "gravity": 2.2,
        "gather": 0.35,
        "absorb": 0.18
    })

    // { "x", "y", "r" (pixels, at full size), "size" (0..1 of r), "vy",
    //   "up", "stage": "gather" | "travel" | "absorb" }
    property var drops: []
    readonly property int slots: 20

    // Seconds until the next drop each way: drawn from an exponential, so the
    // drops come at the rate on average and never on a beat.
    property real nextIn: Infinity
    property real nextOut: Infinity

    function wait(rate) {
        return rate > 0 ? -Math.log(1 - Math.random()) / rate : Infinity;
    }

    onInRateChanged: {
        if (root.inRate <= 0)
            root.nextIn = Infinity;
        else if (!isFinite(root.nextIn))
            root.nextIn = root.wait(root.inRate);
    }
    onOutRateChanged: {
        if (root.outRate <= 0)
            root.nextOut = Infinity;
        else if (!isFinite(root.nextOut))
            root.nextOut = root.wait(root.outRate);
    }

    // A rate already there when the organism is made changes nothing, so it
    // is read once here.
    Component.onCompleted: {
        root.nextIn = root.wait(root.inRate);
        root.nextOut = root.wait(root.outRate);
    }

    function bud(up) {
        if (root.drops.length >= root.slots)
            return;
        const w = root.width;
        const r = (0.045 + 0.025 * Math.random()) * w;
        const x = r * 1.5 + Math.random() * (w - r * 3);
        root.drops.push({
            "x": x,
            "r": r,
            "size": 0,
            "vy": 0,
            "up": up,
            "stage": "gather",
            // Half in the water it comes from, so it grows out of it.
            "y": up ? root.poolSurface + r * 0.1
                    : root.membrane + root.thickness / 2 - r * 0.1
        });
    }

    readonly property bool moving: root.drops.length > 0 || root.inRate > 0 || root.outRate > 0

    function step(dt) {
        root.nextIn -= dt;
        root.nextOut -= dt;
        if (root.nextIn <= 0) {
            root.bud(false);
            root.nextIn = root.wait(root.inRate);
        }
        if (root.nextOut <= 0) {
            root.bud(true);
            root.nextOut = root.wait(root.outRate);
        }

        const p = root.physics;
        const span = Math.max(1, root.poolSurface - root.membrane);
        const kept = [];
        for (const drop of root.drops) {
            if (drop.stage === "gather") {
                drop.size = Math.min(1, drop.size + dt / p.gather);
                // Swelling, it hangs further out of the water it grows from.
                const hang = drop.r * (drop.size - 0.1);
                drop.y = drop.up ? root.poolSurface - hang
                                 : root.membrane + root.thickness / 2 + hang;
                if (drop.size >= 1)
                    drop.stage = "travel";
            } else if (drop.stage === "travel") {
                drop.vy += p.gravity * span * dt;
                drop.y += (drop.up ? -drop.vy : drop.vy) * dt;
                const arrived = drop.up
                    ? drop.y <= root.membrane + root.thickness / 2 + drop.r * 0.4
                    : drop.y >= root.poolSurface + drop.r * 0.4;
                if (arrived)
                    drop.stage = "absorb";
            } else {
                // Taken in where it touched: it shrinks into the water it
                // reached. Carried on into the pool, a drop's own field shows
                // through the water as a darker bubble.
                drop.size -= dt / p.absorb;
            }
            if (drop.size > 0)
                kept.push(drop);
        }
        root.drops = kept;
        root.draw();
    }

    // Into the shader's twenty slots; the slots left over are empty.
    function draw() {
        const slots = [];
        for (const drop of root.drops)
            slots.push(Qt.vector4d(drop.x, drop.y, drop.r * drop.size, 0));
        while (slots.length < root.slots)
            slots.push(Qt.vector4d(0, 0, 0, 0));
        liquid.d0 = slots[0]; liquid.d1 = slots[1]; liquid.d2 = slots[2]; liquid.d3 = slots[3];
        liquid.d4 = slots[4]; liquid.d5 = slots[5]; liquid.d6 = slots[6]; liquid.d7 = slots[7];
        liquid.d8 = slots[8]; liquid.d9 = slots[9]; liquid.d10 = slots[10]; liquid.d11 = slots[11];
        liquid.d12 = slots[12]; liquid.d13 = slots[13]; liquid.d14 = slots[14]; liquid.d15 = slots[15];
        liquid.d16 = slots[16]; liquid.d17 = slots[17]; liquid.d18 = slots[18]; liquid.d19 = slots[19];
    }

    // At the monitor's rate, as the lava lamp, while anything is in flight or
    // about to bud.
    FrameAnimation {
        running: root.moving && root.visible && root.present
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    ShaderEffect {
        id: liquid

        anchors.fill: parent
        visible: root.present
        fragmentShader: Qt.resolvedUrl("osmosis.frag.qsb")

        readonly property size extent: Qt.size(width, height)
        readonly property real radius: root.metrics.radiusPanel
        readonly property real membrane: root.membrane
        readonly property real thickness: root.thickness
        readonly property real pool: root.poolSurface
        property color water: root.water
        readonly property color core: Theme.text

        property vector4d d0; property vector4d d1; property vector4d d2; property vector4d d3
        property vector4d d4; property vector4d d5; property vector4d d6; property vector4d d7
        property vector4d d8; property vector4d d9; property vector4d d10; property vector4d d11
        property vector4d d12; property vector4d d13; property vector4d d14; property vector4d d15
        property vector4d d16; property vector4d d17; property vector4d d18; property vector4d d19

        Behavior on water { ColorAnimation { duration: Timing.theme } }
    }

    // ---- The figures --------------------------------------------------------------

    readonly property bool figures: root.entry.figures !== false

    function rate(bytes) {
        if (bytes < 1024)
            return `${Math.round(bytes)} B/s`;
        if (bytes < 1024 * 1024)
            return `${Math.round(bytes / 1024)} KB/s`;
        const mb = bytes / (1024 * 1024);
        return mb < 10 ? `${mb.toFixed(1)} MB/s` : `${Math.round(mb)} MB/s`;
    }

    Grid {
        id: caption

        visible: root.figures && root.present
        x: root.inset
        y: root.inset
        columns: 2
        columnSpacing: 10 * root.factor
        rowSpacing: 2 * root.factor
        verticalItemAlignment: Grid.AlignVCenter

        Text {
            text: "IN"
            color: Theme.text
            font: root.labelFont
        }

        LitText {
            base: root.water
            text: root.rate(SystemMonitor.netIn)
            font: root.valueFont
        }

        Text {
            text: "OUT"
            color: Theme.text
            font: root.labelFont
        }

        LitText {
            base: root.water
            text: root.rate(SystemMonitor.netOut)
            font: root.valueFont
        }
    }

    readonly property font labelFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontLabel,
        "weight": Typography.weightLabel,
        "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
    })

    readonly property font valueFont: Typography.tabular(Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontValue,
        "weight": Typography.weightValue
    }))

    // Blank: placed while arranging on a machine with no network link.
    Text {
        visible: !root.present
        anchors.centerIn: parent
        width: parent.width - root.inset * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "No network link"
        color: Theme.textFaint
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontSecondary,
            "weight": Typography.weightSecondary
        })
    }
}
