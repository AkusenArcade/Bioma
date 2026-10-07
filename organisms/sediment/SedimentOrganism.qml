import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Sediment: the files used lately, laid down in strata.
//
// Each file is a layer, the newest on top. A layer is as thick as it is
// young: a file opened a moment ago is a wide band with its name in it, and as
// the days pass it is pressed down under what came after, thinner and
// thinner, until the oldest are a fine grain at the bottom. The column is
// always full: the layers share its height in proportion, as the growth
// rings share their disc.
//
// It moves when something is deposited — a new layer settles on top and the
// ones under it are pressed together — and otherwise it is still. Age
// presses the strata too, slowly: they are measured again every ten minutes
// and drawn once, never animated for it.
//
// The list is freedesktop's own (services/Recent.qml): what GTK applications,
// the file chooser and the file manager record.
//
// See docs/design/ORGANISMS.md §13.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    Component.onCompleted: Recent.hold(root, true)
    Component.onDestruction: Recent.hold(root, false)

    readonly property bool present: Recent.files.length > 0

    // How many files are laid down: 8, 16 or 32.
    readonly property int depth: [8, 16, 32].indexOf(root.entry.depth) >= 0 ? root.entry.depth : 16
    readonly property bool names: root.entry.names !== false
    readonly property bool figures: root.entry.figures !== false

    // Two units by two: the column as tall as the square leaves once the
    // figures have their line.
    readonly property real gap: 14 * root.factor
    readonly property real column: Math.max(0, root.height - (root.figures ? root.gap + caption.implicitHeight : 0))

    // ---- The strata -----------------------------------------------------------------

    // The clock the strata age by: every ten minutes is enough for a layer a
    // day old to have changed by a pixel.
    property double now: Date.now()

    Timer {
        interval: 10 * 60 * 1000
        repeat: true
        running: root.present
        onTriggered: root.now = Date.now()
    }

    readonly property var shown: Recent.files.slice(0, root.depth)

    // How thick a layer of this age is, before the column is shared out: one
    // for a file used now, a third for a day ago, a tenth for ten days — so a
    // week's files are pressed visibly harder than yesterday's (a gentler
    // curve laid every day-old file down alike, ruled like paper), without a
    // file opened a moment ago taking half the column and every other name.
    function weight(at) {
        const hours = Math.max(0, (root.now - at) / 3600000);
        return Math.pow(1 + hours / 6, -0.7);
    }

    // Where each layer lies: { key, y, h }, top down. Every layer keeps at
    // least a hairline and a gap, so the oldest stay countable.
    function lay(files, height) {
        const least = 2 * root.factor;
        const weights = files.map(file => root.weight(file.at));
        const total = weights.reduce((sum, w) => sum + w, 0);
        const room = Math.max(0, height - least * files.length);
        const out = [];
        let y = 0;
        for (let i = 0; i < files.length; i++) {
            const h = least + (total > 0 ? weights[i] / total * room : 0);
            out.push({ "key": files[i].path, "y": y, "h": h });
            y += h;
        }
        return out;
    }

    // The deposit: from where the layers lay to where they lie now. A new
    // layer starts with no thickness at the top; one pushed past the bottom
    // is pressed to nothing there.
    property var from: ({})
    property var to: []
    property real settling: 1

    function relay() {
        const next = root.lay(root.shown, root.column);
        const before = ({});
        const current = root.current();
        for (const layer of current)
            before[layer.key] = layer;
        // Something new on top — a file never seen, or one used again — is a
        // deposit: it settles there from nothing, rather than rising through
        // the strata from where it lay.
        const deposited = root.to.length > 0 && next.length > 0 && root.to[0].key !== next[0].key;
        if (deposited)
            before[next[0].key] = { "y": 0, "h": 0 };
        root.from = before;
        root.to = next;
        if (deposited) {
            settle.restart();
        } else {
            settle.stop();
            root.settling = 1;
        }
        strata.requestPaint();
    }

    // Where the layers are at this moment of the settling.
    function current() {
        const t = root.settling;
        const out = [];
        for (const layer of root.to) {
            const was = root.from[layer.key] || { "y": 0, "h": 0 };
            out.push({
                "key": layer.key,
                "y": was.y + (layer.y - was.y) * t,
                "h": was.h + (layer.h - was.h) * t
            });
        }
        return out;
    }

    NumberAnimation {
        id: settle
        target: root
        property: "settling"
        from: 0
        to: 1
        duration: Timing.open * 3
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    onSettlingChanged: strata.requestPaint()
    onShownChanged: root.relay()
    onNowChanged: root.relay()
    onColumnChanged: root.relay()

    // A small hash of a path, for each layer's own undulation.
    function seed(key) {
        let h = 0;
        for (let i = 0; i < key.length; i++)
            h = (h * 31 + key.charCodeAt(i)) % 9973;
        return h / 9973 * Math.PI * 2;
    }

    function age(at) {
        const minutes = Math.max(0, Math.round((root.now - at) / 60000));
        if (minutes < 60)
            return `${minutes} M`;
        const hours = Math.round(minutes / 60);
        if (hours < 48)
            return `${hours} H`;
        return `${Math.round(hours / 24)} D`;
    }

    Canvas {
        id: strata

        width: root.width
        height: root.column
        antialiasing: true

        readonly property color grain: Theme.primary
        onGrainChanged: strata.requestPaint()
        onWidthChanged: strata.requestPaint()

        // The surface between two layers: level on the whole, gently uneven,
        // each bed in its own way — flatter the more it has been pressed.
        function bed(ctx, y, key, amplitude, first) {
            const own = root.seed(key);
            const steps = 24;
            for (let i = 0; i <= steps; i++) {
                const x = i / steps * strata.width;
                const u = i / steps * Math.PI * 2;
                const dy = amplitude * (0.6 * Math.sin(u + own) + 0.4 * Math.sin(2.3 * u + own * 1.7));
                if (i === 0 && first)
                    ctx.moveTo(x, y + dy);
                else
                    ctx.lineTo(x, y + dy);
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const f = root.factor;
            const layers = root.current();

            for (let i = 0; i < layers.length; i++) {
                const layer = layers[i];
                if (layer.h < 0.3)
                    continue;
                // The bed undulates as much as the layer is thick enough to
                // carry, never more than a few pixels.
                const amplitude = Math.min(3 * f, layer.h * 0.12);
                const below = i + 1 < layers.length ? layers[i + 1] : null;
                const amplitudeBelow = below ? Math.min(3 * f, below.h * 0.12) : 0;
                const bottom = layer.y + layer.h;

                ctx.beginPath();
                strata.bed(ctx, layer.y, layer.key, i === 0 ? 0 : amplitude, true);
                // Back along the bed beneath it, right to left.
                const steps = 24;
                const own = below ? root.seed(below.key) : 0;
                for (let s = steps; s >= 0; s--) {
                    const x = s / steps * strata.width;
                    const u = s / steps * Math.PI * 2;
                    const dy = below ? amplitudeBelow * (0.6 * Math.sin(u + own) + 0.4 * Math.sin(2.3 * u + own * 1.7)) : 0;
                    ctx.lineTo(x, Math.min(strata.height, bottom + dy));
                }
                ctx.closePath();
                ctx.fillStyle = Qt.alpha(strata.grain, i === 0 ? 0.30 : (i % 2 === 0 ? 0.13 : 0.19));
                ctx.fill();

                // The bedding plane under it, darker.
                if (below) {
                    ctx.beginPath();
                    strata.bed(ctx, bottom, below.key, amplitudeBelow, true);
                    ctx.lineWidth = 1 * f;
                    ctx.strokeStyle = Qt.alpha(strata.grain, 0.45);
                    ctx.stroke();
                }
            }

            // The surface: what was laid down last, lit.
            if (layers.length > 0 && layers[0].h >= 0.3) {
                ctx.beginPath();
                ctx.moveTo(0, layers[0].y);
                ctx.lineTo(strata.width, layers[0].y);
                ctx.lineWidth = 1.5 * f;
                ctx.strokeStyle = strata.grain;
                ctx.stroke();
            }
        }

        // The names, in the layers thick enough to carry one.
        Repeater {
            model: root.names ? root.shown : []

            delegate: Item {
                id: label

                required property var modelData
                required property int index

                readonly property var stratum: {
                    root.settling;
                    const layers = root.current();
                    return label.index < layers.length ? layers[label.index] : null;
                }

                x: 12 * root.factor
                width: strata.width - 24 * root.factor
                y: label.stratum ? label.stratum.y : 0
                height: label.stratum ? label.stratum.h : 0
                visible: label.stratum !== null && label.stratum.h >= 22 * root.factor
                clip: true

                Text {
                    anchors.left: parent.left
                    anchors.right: when.left
                    anchors.rightMargin: 10 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: label.modelData.name
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(13 * root.factor)
                }

                Text {
                    id: when
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.age(label.modelData.at)
                    color: Theme.textMuted
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightSecondary
                    }))
                }
            }
        }

        // Blank, while arranging with nothing recorded.
        Text {
            visible: !root.present
            anchors.centerIn: parent
            text: "No recent files"
            color: Theme.textFaint
            font.family: Typography.expressive
            font.pixelSize: Math.round(14 * root.factor)
            font.italic: true
        }
    }

    // ---- The figures ------------------------------------------------------------------

    readonly property int today: {
        const midnight = new Date(root.now);
        midnight.setHours(0, 0, 0, 0);
        return Recent.files.filter(file => file.at >= midnight.getTime()).length;
    }

    readonly property string oldest: {
        if (root.shown.length === 0)
            return "";
        const date = new Date(root.shown[root.shown.length - 1].at);
        const months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        return `SINCE ${date.getDate()} ${months[date.getMonth()]}`;
    }

    Item {
        id: caption

        visible: root.figures && root.present
        y: root.column + root.gap
        width: root.width
        implicitHeight: count.implicitHeight

        Row {
            id: count
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
                text: String(root.today)
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightValue
                }))
            }
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: count.verticalCenter
            text: `${root.shown.length} FILES · ${root.oldest}`
            color: Theme.textMuted
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "weight": Typography.weightSecondary
            }))
        }
    }
}
