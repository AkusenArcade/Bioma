import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services
import "sky.js" as Sky

// Photoperiod: the sky over the weather's place — the sun's arc and the
// moon's, how much light the day has left, and how much of the moon is lit.
//
// The sky is drawn as one stands in it, facing the sun at noon: the compass
// across, east on the left in the northern hemisphere, the altitude up, the
// horizon a line and what is under it a shallow strip. The sun's arc is the
// whole of today's path; the part it has already travelled is dimmer than the
// part ahead, and the light under the part ahead is the light left — the
// figure above says it in hours. The moon has its own arc, and its disc is lit
// as the moon is.
//
// The place is the weather's, found once by its geocoder; everything else is
// computed here (sky.js), so it needs no network and asks nothing every half
// hour. It moves as the sky does: redrawn once a minute, never animated.
//
// Times are the machine's own clock: the place is where the machine is.
//
// See docs/design/ORGANISMS.md §11.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    // The weather is asked only to find the place; once it has coordinates
    // there is nothing more to ask it.
    readonly property bool wanted: (root.organism === null || root.organism.here) && !Weather.located
    onWantedChanged: Weather.hold(root, root.wanted)
    Component.onCompleted: Weather.hold(root, root.wanted)
    Component.onDestruction: Weather.hold(root, false)

    readonly property bool present: true
    readonly property bool blank: !Weather.located

    readonly property bool noCity: Weather.city.length === 0
    readonly property string reason: root.noCity ? "Type a city under Settings → Organisms → Weather → City."
        : Weather.problem.length > 0 ? Weather.problem : "Looking for the place…"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---- The sky ---------------------------------------------------------------------

    readonly property real latitude: Weather.located ? Weather.latitude : 0
    readonly property real longitude: Weather.located ? Weather.longitude : 0

    // Everything the picture and the figures need, once a minute: today's
    // arcs, sampled every five minutes, and the sun on through tomorrow to
    // find its next rising or setting.
    //
    // Today is the place's solar day, from the sun's lowest to its lowest —
    // the clock's midnight wherever the clock is right for the place, and
    // still the night wherever it is not, so the arc is never cut in the
    // middle of the day. The moon's day is fifty minutes longer, and its arc
    // is drawn over that, so it closes on itself.
    readonly property var sky: {
        if (root.blank)
            return null;
        const now = clock.date.getTime();
        const step = 5 * 60 * 1000;
        const day = 24 * 3600 * 1000;
        const solarMidnight = -root.longitude / 15 * 3600 * 1000;
        const start = now - ((now - solarMidnight) % day + day) % day;
        const sun = Sky.path(Sky.sun, start, start + 2 * day, step, root.latitude, root.longitude);
        const today = sun.slice(0, day / step + 1);
        return {
            "now": now,
            "sun": today,
            "sunNow": Sky.sun(now, root.latitude, root.longitude),
            "moon": Sky.path(Sky.moon, start, start + day + 50 * 60 * 1000, step, root.latitude, root.longitude),
            "moonNow": Sky.moon(now, root.latitude, root.longitude),
            "light": Sky.moonLight(now),
            "crossings": Sky.crossings(sun),
            "todayCrossings": Sky.crossings(today)
        };
    }

    readonly property bool daylight: root.sky !== null && Sky.daylight(root.sky.sunNow.altitude)

    // The next time the sun crosses the horizon, or null if it does not in
    // the next two days — the midnight sun, or the polar night.
    readonly property var next: {
        if (root.sky === null)
            return null;
        for (const crossing of root.sky.crossings)
            if (crossing.time > root.sky.now)
                return crossing;
        return null;
    }

    // Minutes of daylight today, the samples above the horizon counted and the
    // two at either end shared by where the line between them crosses.
    readonly property int dayMinutes: {
        if (root.sky === null)
            return 0;
        const samples = root.sky.sun;
        let minutes = 0;
        for (let i = 1; i < samples.length; i++) {
            const a = samples[i - 1].altitude + 0.833;
            const b = samples[i].altitude + 0.833;
            const span = (samples[i].time - samples[i - 1].time) / 60000;
            if (a > 0 && b > 0)
                minutes += span;
            else if (a > 0 || b > 0)
                minutes += span * Math.max(a, b) / Math.abs(a - b);
        }
        return Math.round(minutes);
    }

    function duration(minutes) {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return h > 0 ? `${h} H ${String(m).padStart(2, "0")} M` : `${m} M`;
    }

    function hhmm(time) {
        const date = new Date(time);
        return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
    }

    readonly property string headline: {
        if (root.sky === null)
            return "";
        if (root.next === null)
            return root.daylight ? "MIDNIGHT SUN" : "POLAR NIGHT";
        return root.daylight ? "LIGHT LEFT" : "SUNRISE IN";
    }

    readonly property string remaining: root.next === null ? ""
        : root.duration(Math.max(0, Math.round((root.next.time - root.sky.now) / 60000)))

    function technical(size, weight) {
        return Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": size,
            "weight": weight === undefined ? Typography.weightSecondary : weight
        }));
    }

    // ---- The words above ------------------------------------------------------------

    Text {
        id: place
        anchors.left: parent.left
        anchors.right: figure.left
        anchors.rightMargin: 12 * root.factor
        anchors.verticalCenter: figure.verticalCenter
        text: Weather.place.length > 0 ? Weather.place : "Photoperiod"
        elide: Text.ElideRight
        maximumLineCount: 1
        color: Theme.text
        font.family: Typography.expressive
        font.pixelSize: Math.round(15 * root.factor)
        font.weight: Font.Bold
    }

    Row {
        id: figure

        visible: !root.blank
        anchors.right: parent.right
        spacing: 8 * root.factor

        Text {
            anchors.baseline: value.baseline
            text: root.headline
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
            visible: root.remaining.length > 0
            text: root.remaining
            font: root.technical(root.metrics.fontLabel, Typography.weightValue)
        }
    }

    // ---- The sky ----------------------------------------------------------------------

    Canvas {
        id: picture

        y: figure.height + 10 * root.factor
        width: parent.width
        height: footer.y - y - 8 * root.factor
        antialiasing: true

        readonly property color sunlight: Theme.primary
        readonly property color moonlight: Theme.text
        readonly property color ground: Theme.line
        readonly property color faint: Theme.textMuted

        onSunlightChanged: picture.requestPaint()
        onMoonlightChanged: picture.requestPaint()
        onGroundChanged: picture.requestPaint()
        onWidthChanged: picture.requestPaint()
        onHeightChanged: picture.requestPaint()

        Connections {
            target: root
            function onSkyChanged() {
                picture.requestPaint();
            }
        }

        readonly property real margin: 9 * root.factor
        readonly property real horizon: Math.round(picture.height * 0.74)
        // Degrees to height: the same scale up as down would bury half the
        // strip under the horizon, so what is below is pressed into what is
        // left — a body under it is under it, how far matters less.
        readonly property real above: (picture.horizon - picture.margin) / 90
        readonly property real below: (picture.height - picture.horizon - 2 * root.factor) / 90

        // Facing the sun at noon: south in the northern hemisphere, north in
        // the southern.
        readonly property real facing: root.latitude >= 0 ? 180 : 0

        function px(bearing) {
            const along = ((bearing - picture.facing + 540) % 360) / 360;
            return picture.margin + along * (picture.width - 2 * picture.margin);
        }

        function py(altitude) {
            return altitude >= 0 ? picture.horizon - altitude * picture.above
                                 : picture.horizon - altitude * picture.below;
        }

        // One stretch of an arc, broken where it runs off one side of the
        // compass and back in at the other.
        function trace(ctx, samples, keep) {
            let open = false;
            let last = null;
            for (const s of samples) {
                const x = picture.px(s.bearing);
                const y = picture.py(s.altitude);
                const kept = keep(s);
                if (kept && open && last !== null && Math.abs(x - last) < picture.width / 2)
                    ctx.lineTo(x, y);
                else if (kept)
                    ctx.moveTo(x, y);
                open = kept;
                last = x;
            }
        }

        // The light left: the sky under the part of the arc still ahead,
        // down to the horizon.
        function fillAhead(ctx, samples, now) {
            let run = [];
            const runs = [];
            for (const s of samples) {
                const lit = s.time >= now && s.altitude > 0;
                if (lit && run.length > 0 && Math.abs(picture.px(s.bearing) - picture.px(run[run.length - 1].bearing)) >= picture.width / 2) {
                    runs.push(run);
                    run = [];
                }
                if (lit)
                    run.push(s);
                else if (run.length > 0) {
                    runs.push(run);
                    run = [];
                }
            }
            if (run.length > 0)
                runs.push(run);
            for (const r of runs) {
                if (r.length < 2)
                    continue;
                ctx.beginPath();
                ctx.moveTo(picture.px(r[0].bearing), picture.horizon);
                for (const s of r)
                    ctx.lineTo(picture.px(s.bearing), picture.py(s.altitude));
                ctx.lineTo(picture.px(r[r.length - 1].bearing), picture.horizon);
                ctx.closePath();
                ctx.fill();
            }
        }

        // The moon as it is lit: the bright limb on the sun's side, the
        // terminator an ellipse between. Waxing, the right side is lit north
        // of the equator and the left side south of it.
        function moonDisc(ctx, x, y, r, light, dim) {
            ctx.beginPath();
            ctx.arc(x, y, r, 0, Math.PI * 2);
            ctx.fillStyle = Qt.alpha(picture.moonlight, 0.10 * dim);
            ctx.fill();
            ctx.lineWidth = Math.max(1, root.factor);
            ctx.strokeStyle = Qt.alpha(picture.moonlight, 0.35 * dim);
            ctx.stroke();

            const waxing = light.phase < 0.5;
            const side = (waxing ? 1 : -1) * (root.latitude >= 0 ? 1 : -1);
            const squeeze = Math.cos(2 * Math.PI * light.phase);
            const steps = 24;
            ctx.beginPath();
            for (let i = 0; i <= steps; i++) {
                const t = -Math.PI / 2 + i / steps * Math.PI;
                const px = x + side * r * Math.cos(t);
                const py = y + r * Math.sin(t);
                if (i === 0)
                    ctx.moveTo(px, py);
                else
                    ctx.lineTo(px, py);
            }
            for (let i = steps; i >= 0; i--) {
                const t = -Math.PI / 2 + i / steps * Math.PI;
                ctx.lineTo(x + side * r * Math.cos(t) * squeeze, y + r * Math.sin(t));
            }
            ctx.closePath();
            ctx.fillStyle = Qt.alpha(picture.moonlight, 0.9 * dim);
            ctx.fill();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const f = root.factor;
            const hairline = Metrics.rim(Screen.devicePixelRatio);

            // The horizon.
            ctx.fillStyle = picture.ground;
            ctx.fillRect(0, picture.horizon - hairline / 2, picture.width, hairline);

            const sky = root.sky;
            if (sky === null)
                return;
            const now = sky.now;

            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            // The moon's arc, under the sun's.
            ctx.beginPath();
            picture.trace(ctx, sky.moon, s => s.altitude >= 0);
            ctx.lineWidth = 1 * f;
            ctx.strokeStyle = Qt.alpha(picture.moonlight, 0.22);
            ctx.stroke();

            // The sun's: the light left under it, then under the horizon,
            // the part already travelled, the part ahead.
            ctx.fillStyle = Qt.alpha(picture.sunlight, 0.10);
            picture.fillAhead(ctx, sky.sun, now);

            ctx.beginPath();
            picture.trace(ctx, sky.sun, s => s.altitude < 0);
            ctx.lineWidth = 1 * f;
            ctx.strokeStyle = Qt.alpha(picture.sunlight, 0.18);
            ctx.stroke();

            ctx.beginPath();
            picture.trace(ctx, sky.sun, s => s.altitude >= 0 && s.time <= now + 5 * 60 * 1000);
            ctx.lineWidth = 1.5 * f;
            ctx.strokeStyle = Qt.alpha(picture.sunlight, 0.38);
            ctx.stroke();

            ctx.beginPath();
            picture.trace(ctx, sky.sun, s => s.altitude >= 0 && s.time >= now - 5 * 60 * 1000);
            ctx.lineWidth = 1.5 * f;
            ctx.strokeStyle = picture.sunlight;
            ctx.stroke();

            // The moon where it is.
            const moonUp = sky.moonNow.altitude >= 0;
            picture.moonDisc(ctx, picture.px(sky.moonNow.bearing), picture.py(sky.moonNow.altitude),
                             7 * f, sky.light, moonUp ? 1 : 0.45);

            // The sun where it is: whole above the horizon, a ring under it.
            const sx = picture.px(sky.sunNow.bearing);
            const sy = picture.py(sky.sunNow.altitude);
            ctx.beginPath();
            ctx.arc(sx, sy, 6 * f, 0, Math.PI * 2);
            if (sky.sunNow.altitude >= 0) {
                ctx.fillStyle = picture.sunlight;
                ctx.fill();
            } else {
                ctx.lineWidth = 1.2 * f;
                ctx.strokeStyle = Qt.alpha(picture.sunlight, 0.5);
                ctx.stroke();
            }
        }

        // When the sun rises and sets today, under the horizon where it does.
        Repeater {
            model: root.sky === null ? [] : root.sky.todayCrossings

            delegate: Text {
                id: crossing

                required property var modelData

                readonly property real at: picture.px(Sky.sun(crossing.modelData.time, root.latitude, root.longitude).bearing)

                x: Math.max(0, Math.min(picture.width - width, crossing.at - width / 2))
                y: picture.height - height
                text: root.hhmm(crossing.modelData.time)
                color: Theme.textMuted
                font: root.technical(root.metrics.fontMeta)
            }
        }

        // Blank: why, where the sky would be.
        Text {
            visible: root.blank
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14 * root.factor
            anchors.rightMargin: 14 * root.factor
            y: (picture.horizon - height) / 2
            text: root.reason
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: Math.round(14 * root.factor)
            font.italic: true
        }
    }

    // ---- The words below -------------------------------------------------------------

    Item {
        id: footer

        y: parent.height - height
        width: parent.width
        height: phase.implicitHeight

        Row {
            id: phase

            visible: !root.blank
            spacing: 8 * root.factor

            Text {
                id: phaseName
                text: root.sky === null ? "" : Sky.phaseName(root.sky.light.phase)
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: Math.round(14 * root.factor)
            }

            Text {
                anchors.baseline: phaseName.baseline
                text: root.sky === null ? "" : `${Math.round(root.sky.light.fraction * 100)} %`
                color: Theme.textMuted
                font: root.technical(root.metrics.fontMeta)
            }
        }

        Text {
            visible: !root.blank
            anchors.right: parent.right
            anchors.verticalCenter: phase.verticalCenter
            text: `DAY ${root.duration(root.dayMinutes)}`
            color: Theme.textMuted
            font: root.technical(root.metrics.fontMeta)
        }
    }
}
