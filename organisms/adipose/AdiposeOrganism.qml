import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Adipose: the disks, as the cells that store.
//
// An adipocyte is a cell that keeps: a droplet of fat inside it grows until it
// fills the cell and presses the nucleus flat against the membrane. Here each
// filesystem is one such cell, its membrane the disk's capacity and its
// droplet what is used — the droplet's area is the used share of the cell's —
// so a full disk looks full: no room left, the nucleus squeezed to the rim.
//
// A larger disk is a larger cell, by the square root of its size and never
// less than half the largest, so a small partition stays legible beside a
// large one. Colour is the fill's state: calm with room, active when little
// is left, alert when nearly nothing is — or, with `colour: "theme"`, the
// theme's primary, as the lava lamp and the cytoplasm can be.
//
// It is still. A disk fills in days, so the cells change when a reading does
// and not in between; a drive plugged in arrives as a new cell at the next
// reading, and one taken out leaves.
//
// See docs/design/ORGANISMS.md §15.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    Component.onCompleted: Storage.hold(root, true)
    Component.onDestruction: Storage.hold(root, false)

    // The partitions the machine boots from only when asked for.
    readonly property bool system: root.entry.system === true

    // Four at most, the largest: a fifth cell in two units is a dot.
    property var disks: Storage.disks.filter(disk => root.system || !disk.system).slice(0, 4)

    readonly property bool present: Storage.loaded && root.disks.length > 0

    readonly property bool themed: root.entry.colour === "theme"

    // Room, little room, nearly none. Not the load thresholds: a disk a third
    // full is not busy, it is a third full.
    function tint(fill) {
        if (root.themed)
            return Theme.primary;
        if (fill >= 0.95)
            return Theme.alert;
        if (fill >= 0.85)
            return Theme.active;
        return Theme.calm;
    }

    // ---- Where the cells are -----------------------------------------------------------

    readonly property bool single: root.disks.length === 1

    // One disk: the cell in the square on the left, the figures beside it, as
    // the nucleus has them. More: a column each, the figures under the cell.
    readonly property real captionHeight: root.single ? 0 : 40 * root.factor
    readonly property real column: root.single ? Math.min(root.height, root.width / 2)
                                               : root.width / Math.max(1, root.disks.length)
    readonly property real largest: root.disks.reduce((most, disk) => Math.max(most, disk.size), 0)
    readonly property real reach: Math.min(root.column, root.height - root.captionHeight) / 2
                                  - (root.single ? 10 : 6) * root.factor

    function radiusOf(disk) {
        if (root.largest <= 0)
            return root.reach;
        return root.reach * Math.max(0.5, Math.sqrt(disk.size / root.largest));
    }

    function centreOf(index) {
        return Qt.point(root.column * index + root.column / 2,
                        (root.height - root.captionHeight) / 2);
    }

    // Where each cell keeps its nucleus: a fixed angle of its own, from its
    // device's name, so two cells do not look stamped from one mould.
    function angleOf(disk) {
        let h = 0;
        for (let i = 0; i < disk.device.length; i++)
            h = (h * 31 + disk.device.charCodeAt(i)) % 9973;
        return h / 9973 * Math.PI * 2;
    }

    onDisksChanged: tissue.requestPaint()

    // ---- The cells -------------------------------------------------------------------

    Canvas {
        id: tissue

        anchors.fill: parent
        antialiasing: true

        // Repainted when the colours change too: the theme retints the fat.
        readonly property color ink: Theme.text
        readonly property color calm: Theme.calm
        readonly property color active: Theme.active
        readonly property color alert: Theme.alert
        readonly property color primary: Theme.primary
        readonly property bool themed: root.themed
        onInkChanged: tissue.requestPaint()
        onPrimaryChanged: tissue.requestPaint()
        onThemedChanged: tissue.requestPaint()
        onCalmChanged: tissue.requestPaint()
        onActiveChanged: tissue.requestPaint()
        onAlertChanged: tissue.requestPaint()
        onWidthChanged: tissue.requestPaint()
        onHeightChanged: tissue.requestPaint()

        function cell(ctx, disk, index) {
            const f = root.factor;
            const centre = root.centreOf(index);
            const radius = root.radiusOf(disk);
            const inner = radius - 2 * f;
            const tint = root.tint(disk.fill);
            const angle = root.angleOf(disk);
            const away = { "x": Math.cos(angle), "y": Math.sin(angle) };

            // The membrane: the disk's capacity.
            ctx.beginPath();
            ctx.arc(centre.x, centre.y, radius, 0, Math.PI * 2);
            ctx.fillStyle = Qt.alpha(tissue.ink, 0.03);
            ctx.fill();
            ctx.lineWidth = 1.5 * f;
            ctx.strokeStyle = Qt.alpha(tissue.ink, 0.22);
            ctx.stroke();

            // The droplet: what is used, as its share of the cell's area. It
            // sits off the centre, away from the nucleus, and moves back to
            // the centre as it grows into the whole cell.
            const drop = inner * Math.sqrt(Math.max(0, Math.min(1, disk.fill)));
            const shift = (inner - drop) * 0.35;
            const dx = centre.x - away.x * shift;
            const dy = centre.y - away.y * shift;
            if (drop > 0.5) {
                ctx.beginPath();
                ctx.arc(dx, dy, drop, 0, Math.PI * 2);
                ctx.fillStyle = Qt.alpha(tint, 0.42);
                ctx.fill();
                ctx.lineWidth = 1.2 * f;
                ctx.strokeStyle = Qt.alpha(tint, 0.9);
                ctx.stroke();
            }

            // The nucleus: in the room the droplet leaves against the
            // membrane, round while there is room and flattened against the
            // rim as there is less — its area kept, so it reads as squeezed.
            const room = inner - (drop - shift);
            const whole = Math.max(2.5 * f, 0.13 * radius);
            const depth = Math.max(1.2 * f, Math.min(whole, room / 2 - 1 * f));
            const breadth = whole * whole / depth;
            const distance = inner - depth;
            ctx.save();
            ctx.translate(centre.x + away.x * distance, centre.y + away.y * distance);
            ctx.rotate(angle);
            ctx.scale(depth, Math.min(breadth, radius * 0.6));
            ctx.beginPath();
            ctx.arc(0, 0, 1, 0, Math.PI * 2);
            ctx.restore();
            ctx.fillStyle = Qt.alpha(tissue.ink, 0.55);
            ctx.fill();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const disks = root.disks;
            for (let i = 0; i < disks.length; i++)
                tissue.cell(ctx, disks[i], i);
        }
    }

    // Blank, while arranging with nothing to show.
    Text {
        visible: !root.present
        anchors.centerIn: parent
        text: "No disks"
        color: Theme.textFaint
        font.family: Typography.expressive
        font.pixelSize: Math.round(14 * root.factor)
        font.italic: true
    }

    // ---- The figures ------------------------------------------------------------------

    function percent(disk) {
        return `${Math.round(disk.fill * 100)}%`;
    }

    // One disk: its name, the figure lit in its state, what of what.
    Column {
        visible: root.present && root.single
        x: root.column + 14 * root.factor
        width: root.width - x
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6 * root.factor

        readonly property var disk: root.disks[0] ?? null

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: parent.disk ? parent.disk.name : ""
            color: Theme.text
            font: Qt.font({
                "family": Typography.expressive,
                "pixelSize": root.metrics.fontLabel,
                "weight": Typography.weightSecondary
            })
        }

        LitText {
            text: parent.disk ? root.percent(parent.disk) : ""
            base: parent.disk ? root.tint(parent.disk.fill) : Theme.calm
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": Math.round(40 * root.factor),
                "weight": Typography.weightValue
            }))
        }

        Text {
            text: parent.disk ? `${Storage.bytes(parent.disk.used)} OF ${Storage.bytes(parent.disk.size)}` : ""
            color: Theme.textMuted
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "weight": Typography.weightSecondary
            }))
        }
    }

    // More: under each cell, its name and its figure.
    Repeater {
        model: root.single ? [] : root.disks

        Column {
            id: label

            required property var modelData
            required property int index

            x: root.column * label.index + 4 * root.factor
            width: root.column - 8 * root.factor
            y: root.height - root.captionHeight + 6 * root.factor
            spacing: 3 * root.factor

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: label.modelData.name
                color: Theme.text
                font: Qt.font({
                    "family": Typography.expressive,
                    "pixelSize": root.metrics.fontSecondary,
                    "weight": Typography.weightSecondary
                })
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6 * root.factor

                LitText {
                    text: root.percent(label.modelData)
                    base: root.tint(label.modelData.fill)
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightValue
                    }))
                }

                Text {
                    visible: root.disks.length === 2
                    text: Storage.bytes(label.modelData.size)
                    color: Theme.textMuted
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightSecondary
                    }))
                }
            }
        }
    }
}
