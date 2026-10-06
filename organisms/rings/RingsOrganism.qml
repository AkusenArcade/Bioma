import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Growth rings: the days spent at this machine, laid down like a tree's.
//
// One ring per day, the oldest at the heart and today outermost. A ring is as
// thick as the hours that day was active — neither idle nor locked, as
// Activity counts it — so a long day is a wide band, a Sunday away a thin one,
// and a day not here leaves no ring at all, as a tree that does not grow lays
// down nothing. The disc is always full: the rings share its radius in
// proportion, so a fortnight is a few broad bands and a year is grain.
//
// Today's ring is the living one, the cambium: lit, and growing a little each
// minute somebody is here. It is the only thing that moves, and only while it
// grows; away from the machine the disc is still. It is drawn once per change
// — a canvas, not an animation — so it costs nothing between minutes.
//
// The rings are not perfect circles. Every ring follows one distortion of the
// trunk, slightly its own, so the disc reads as wood and not as a target. The
// distortion is fixed: it does not move.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    Component.onCompleted: Activity.hold(root, true)
    Component.onDestruction: Activity.hold(root, false)

    readonly property bool present: Activity.loaded

    // How many days back the disc reaches: 30, 90 or 365.
    readonly property int span: [30, 90, 365].indexOf(root.entry.days) >= 0 ? root.entry.days : 90

    readonly property bool figures: root.entry.figures !== false

    // Two units by two: the disc as large as the square leaves once the
    // figures have their line, centred across it.
    readonly property real gap: 14 * root.factor
    readonly property real disc: Math.max(0, Math.min(root.width,
        root.height - (root.figures ? root.gap + caption.implicitHeight : 0)))
    readonly property real discX: (root.width - root.disc) / 2

    // ---- The record -----------------------------------------------------------------

    // The days in the span with any growth, oldest first: { key, minutes }.
    readonly property var grown: {
        const days = Activity.days;
        const today = Activity.today;
        const out = [];
        const [y, m, d] = today.split("-").map(Number);
        for (let back = root.span - 1; back >= 0; back--) {
            const date = new Date(y, m - 1, d - back);
            const key = Activity.dateKey(date);
            const minutes = days[key] ?? 0;
            if (minutes > 0 || key === today)
                out.push({ "key": key, "minutes": minutes });
        }
        return out;
    }

    readonly property int totalMinutes: root.grown.reduce((sum, day) => sum + day.minutes, 0)

    function duration(minutes) {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return h > 0 ? `${h} H ${String(m).padStart(2, "0")} M` : `${m} M`;
    }

    onGrownChanged: wood.requestPaint()

    // ---- The wood -------------------------------------------------------------------

    // A small hash of a date, for each ring's own wobble.
    function seed(key) {
        let h = 0;
        for (let i = 0; i < key.length; i++)
            h = (h * 31 + key.charCodeAt(i)) % 9973;
        return h / 9973 * Math.PI * 2;
    }

    // The trunk's distortion at an angle, shared by every ring.
    function trunk(angle) {
        return 0.035 * Math.sin(2 * angle + 0.7)
             + 0.020 * Math.sin(3 * angle + 2.1)
             + 0.012 * Math.sin(5 * angle + 4.0);
    }

    Canvas {
        id: wood

        x: root.discX
        width: root.disc
        height: root.disc
        antialiasing: true

        // Repainted when the colours change too: the theme retints the wood.
        readonly property color grain: Theme.primary
        onGrainChanged: wood.requestPaint()

        function ring(ctx, radius, key, steps) {
            const own = root.seed(key);
            for (let i = 0; i <= steps; i++) {
                const angle = i / steps * Math.PI * 2;
                const wobble = 1 + root.trunk(angle) + 0.008 * Math.sin(7 * angle + own);
                const x = wood.width / 2 + Math.cos(angle) * radius * wobble;
                const y = wood.height / 2 + Math.sin(angle) * radius * wobble;
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.closePath();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const f = root.factor;
            const days = root.grown;
            const total = root.totalMinutes;
            const pith = 3 * f;
            // Inside the wobble, so the outermost ring stays within the disc.
            const outer = wood.width / 2 / 1.07 - 2 * f;
            const scale = total > 0 ? (outer - pith) / total : 0;
            const steps = 96;

            // Each day's band: from where the day before ended to where it
            // ends, filled as an annulus so the bands never stack their alpha.
            let inner = pith;
            const bands = [];
            for (const day of days) {
                const out = inner + day.minutes * scale;
                bands.push({ "key": day.key, "from": inner, "to": out, "today": day.key === Activity.today });
                inner = out;
            }

            ctx.fillRule = Qt.OddEvenFill;
            for (let i = 0; i < bands.length; i++) {
                const band = bands[i];
                if (band.to - band.from < 0.05)
                    continue;
                ctx.beginPath();
                wood.ring(ctx, band.to, band.key, steps);
                if (band.from > 0.5)
                    wood.ring(ctx, band.from, i > 0 ? bands[i - 1].key : band.key, steps);
                // Alternate days a shade apart, so thin rings stay apart.
                ctx.fillStyle = Qt.alpha(wood.grain, band.today ? 0.34 : (i % 2 === 0 ? 0.16 : 0.22));
                ctx.fill();
            }

            // The late wood: a line where each day ended.
            for (const band of bands) {
                if (band.to - band.from < 0.05 || band.today)
                    continue;
                ctx.beginPath();
                wood.ring(ctx, band.to, band.key, steps);
                ctx.lineWidth = 1 * f;
                ctx.strokeStyle = Qt.alpha(wood.grain, 0.55);
                ctx.stroke();
            }

            // The cambium: today's edge, lit.
            const living = bands.length > 0 ? bands[bands.length - 1] : null;
            if (living && living.today && living.to > pith) {
                ctx.beginPath();
                wood.ring(ctx, living.to, living.key, steps);
                ctx.lineWidth = 1.8 * f;
                ctx.strokeStyle = wood.grain;
                ctx.stroke();
            }

            // The pith.
            ctx.beginPath();
            ctx.arc(wood.width / 2, wood.height / 2, pith, 0, Math.PI * 2);
            ctx.fillStyle = Qt.alpha(wood.grain, 0.7);
            ctx.fill();
        }

        onWidthChanged: wood.requestPaint()
    }

    // ---- The figures ------------------------------------------------------------------

    Item {
        id: caption

        visible: root.figures
        x: root.discX
        y: root.disc + root.gap
        width: root.disc
        implicitHeight: today.implicitHeight

        Row {
            id: today
            spacing: 8 * root.factor

            Text {
                anchors.baseline: value.baseline
                text: "TODAY"
                color: Theme.text
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                })
            }

            LitText {
                id: value
                text: root.duration(Activity.todayMinutes)
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightValue
                }))
            }
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: today.verticalCenter
            text: `${root.span} DAYS · ${Math.round(root.totalMinutes / 60)} H`
            color: Theme.textMuted
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "weight": Typography.weightSecondary
            }))
        }
    }
}
