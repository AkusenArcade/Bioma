import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Growth rings: the machine's age, laid down like a tree's.
//
// One ring per day since this system was installed (`Machine.born`), the
// oldest at the heart and today outermost. Every day is a ring and every ring
// is as wide as the next: the disc is the machine's life, and a day is a day
// whether anybody was here or not. The disc is always full, so once days are
// too thin to see, the lines mark months, and later years — how a tree is
// read from a distance.
//
// What is known of each day is its colour. A day Activity recorded — neither
// idle nor locked, as it counts — is wood, lit in proportion to the hours it
// held; a day before the record began, or a day away, is bare grain. Nothing
// is estimated: the record starts when the organism is first placed, and the
// rings before it say only that the days passed (Akusen, 2026-10-08).
//
// Today's ring is the living one, the cambium: lit at its edge, and its wood
// deepening each minute somebody is here. It is the only thing that changes,
// and only while it grows; away from the machine the disc is still. It is
// drawn once per change — a canvas, not an animation — so it costs nothing
// between minutes.
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

    Component.onCompleted: {
        Activity.hold(root, true);
        Machine.ask();
    }
    Component.onDestruction: Activity.hold(root, false)

    readonly property bool present: Activity.loaded && root.birth.length > 0

    readonly property bool figures: root.entry.figures !== false

    // Two units by two: the disc as large as the square leaves once the
    // figures have their line, centred across it.
    readonly property real gap: 14 * root.factor
    readonly property real disc: Math.max(0, Math.min(root.width,
        root.height - (root.figures ? root.gap + caption.implicitHeight : 0)))
    readonly property real discX: (root.width - root.disc) / 2

    // ---- The record -----------------------------------------------------------------

    // The day the machine was born. A record older than what the filesystem
    // remembers — a reinstall that kept the home — moves it back: a day that
    // was recorded happened.
    readonly property string birth: {
        if (Machine.born <= 0)
            return "";
        const born = Activity.dateKey(new Date(Machine.born));
        const recorded = Object.keys(Activity.days).sort()[0];
        return recorded && recorded < born ? recorded : born;
    }

    function dateOf(key) {
        const [y, m, d] = key.split("-").map(Number);
        return new Date(y, m - 1, d);
    }

    // Every day from the birth to today, oldest first: { key, minutes }.
    readonly property var lived: {
        if (root.birth.length === 0)
            return [];
        const days = Activity.days;
        const today = root.dateOf(Activity.today);
        const out = [];
        for (let date = root.dateOf(root.birth); date <= today;
                date = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1)) {
            const key = Activity.dateKey(date);
            out.push({ "key": key, "minutes": days[key] ?? 0, "known": key in days });
        }
        return out;
    }

    // The age in calendar years, months and days, the parts that are zero
    // left out: 21 D, 1 MO 5 D, 2 Y 3 D.
    readonly property string age: {
        if (root.birth.length === 0)
            return "";
        const born = root.dateOf(root.birth);
        const today = root.dateOf(Activity.today);
        let years = today.getFullYear() - born.getFullYear();
        let months = today.getMonth() - born.getMonth();
        let days = today.getDate() - born.getDate();
        if (days < 0) {
            months--;
            days += new Date(today.getFullYear(), today.getMonth(), 0).getDate();
        }
        if (months < 0) {
            years--;
            months += 12;
        }
        const parts = [];
        if (years > 0)
            parts.push(`${years} Y`);
        if (months > 0)
            parts.push(`${months} MO`);
        if (days > 0 || parts.length === 0)
            parts.push(`${days} D`);
        return parts.join(" ");
    }

    function duration(minutes) {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return h > 0 ? `${h} H ${String(m).padStart(2, "0")} M` : `${m} M`;
    }

    // The hours at which a day's wood is as lit as it gets.
    readonly property int fullDay: 10 * 60

    onLivedChanged: wood.requestPaint()

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
        readonly property color bare: Theme.text
        onGrainChanged: wood.requestPaint()
        onBareChanged: wood.requestPaint()

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
            const days = root.lived;
            if (days.length === 0)
                return;
            const pith = 3 * f;
            // Inside the wobble, so the outermost ring stays within the disc.
            const outer = wood.width / 2 / 1.07 - 2 * f;
            const width = (outer - pith) / days.length;
            const steps = 96;
            // Below this a boundary is no longer a line anybody can see.
            const visible = 3 * f;

            // The ring the eye can follow: the day while days are wide
            // enough, then the month, then the year — a tree read from a
            // distance shows its years, not its days. Keys are "YYYY-MM-DD",
            // so a unit is a prefix.
            const span = width >= visible ? 10
                       : width * 30.44 >= visible ? 7 : 4;

            // Each band filled as an annulus so the bands never stack their
            // alpha. Bare days of one unit are one band of grain once the
            // days are too thin to tell apart; recorded days keep their own.
            const bands = [];
            let unit = "";
            let units = -1;
            for (let i = 0; i < days.length; i++) {
                const day = days[i];
                const from = pith + i * width;
                const to = from + width;
                const today = day.key === Activity.today;
                const bare = !day.known && !today;
                const own = day.key.slice(0, span);
                if (own !== unit) {
                    unit = own;
                    units++;
                }
                const last = bands.length > 0 ? bands[bands.length - 1] : null;
                if (bare && span < 10 && last && last.bare && last.unit === unit) {
                    last.to = to;
                    last.key = day.key;
                    continue;
                }
                if (last)
                    last.ends = last.unit !== unit;
                bands.push({ "key": day.key, "from": from, "to": to, "bare": bare,
                             "today": today, "minutes": day.minutes, "unit": unit,
                             "index": units, "ends": true });
            }

            ctx.fillRule = Qt.OddEvenFill;
            let previous = "";
            for (const band of bands) {
                ctx.beginPath();
                wood.ring(ctx, band.to, band.key, steps);
                if (band.from > 0.5)
                    wood.ring(ctx, band.from, previous || band.key, steps);
                previous = band.key;
                if (band.bare) {
                    // Grain: the day passed, and that is all that is known.
                    ctx.fillStyle = Qt.alpha(wood.bare, band.index % 2 === 0 ? 0.05 : 0.08);
                } else {
                    // Wood: lit by the hours the day held.
                    const held = Math.min(1, band.minutes / root.fullDay);
                    ctx.fillStyle = Qt.alpha(wood.grain, 0.14 + 0.5 * held);
                }
                ctx.fill();
            }

            // The late wood: a line where each unit ended — a day, a month or
            // a year, whichever the rings are wide enough to carry.
            for (const band of bands) {
                if (band.today || !band.ends)
                    continue;
                ctx.beginPath();
                wood.ring(ctx, band.to, band.key, steps);
                ctx.lineWidth = 1 * f;
                ctx.strokeStyle = band.bare ? Qt.alpha(wood.bare, 0.16)
                                            : Qt.alpha(wood.grain, 0.55);
                ctx.stroke();
            }

            // The cambium: today's edge, lit.
            const living = bands[bands.length - 1];
            if (living.today) {
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

    // Who the tree is and how old, then how long somebody has been here.
    Item {
        id: caption

        visible: root.figures
        x: root.discX
        y: root.disc + root.gap
        width: root.disc
        implicitHeight: identity.implicitHeight + 6 * root.factor + session.implicitHeight

        Text {
            id: identity
            anchors.left: parent.left
            anchors.right: ageText.left
            anchors.rightMargin: 12 * root.factor
            text: Machine.host
            elide: Text.ElideRight
            color: Theme.text
            font: Qt.font({
                "family": Typography.expressive,
                "pixelSize": root.metrics.fontLabel,
                "weight": Typography.weightSecondary
            })
        }

        Text {
            id: ageText
            anchors.right: parent.right
            anchors.baseline: identity.baseline
            text: root.age
            color: Theme.textMuted
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "weight": Typography.weightSecondary
            }))
        }

        Row {
            id: session
            anchors.top: identity.bottom
            anchors.topMargin: 6 * root.factor
            spacing: 8 * root.factor

            Text {
                anchors.baseline: value.baseline
                text: Activity.present ? "SESSION" : "AWAY"
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
                visible: Activity.present
                text: root.duration(Activity.sessionMinutes)
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightValue
                }))
            }
        }
    }
}
