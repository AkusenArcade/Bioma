import QtQuick
import QtQuick.Effects
import Quickshell
import qs.core
import qs.components
import qs.services

// Vacuole: the notifications nobody has read yet, stored in a sac.
//
// Each application is one body in the sac and each of its unread
// notifications a drop of it: the drops of one application melt together, as
// the cytoplasm's lobes do, and two applications never do — they press
// against each other and keep the seam. So a chat that wrote five times is one
// swollen body, and five applications that wrote once are five small ones.
//
// A notification arrives unread and stays so until it is read (Akusen,
// 2026-10-07): closed by the user or by its sender, or all of them at once by
// opening the history. Read, its drop is taken back in — the body shrinks, or
// goes, and the others close over the space. Expiring is not reading.
//
// Nothing moves but that: a drop growing in when a notification arrives, a
// drop taken in when one is read. Between the two the sac is still. With
// nothing unread there is no vacuole.
//
// The tissue is the cytoplasm's shader (§08), for the same reason: what melts
// together is what belongs together. A body is primary; one holding a
// critical notification is alert.
//
// See docs/design/ORGANISMS.md §12.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    readonly property bool present: Notifications.unread.length > 0

    // Two units by two: the sac as large as the square leaves once the
    // figures have their line, centred across it.
    readonly property bool figures: root.entry.figures !== false
    readonly property real gap: 14 * root.factor
    readonly property real sac: Math.max(0, Math.min(root.width,
        root.height - (root.figures ? root.gap + caption.implicitHeight : 0)))
    readonly property real sacX: (root.width - root.sac) / 2

    // ---- The bodies -------------------------------------------------------------------

    // Constants of the sac: shares of its radius and area, rates per second,
    // pixels at factor 1.
    readonly property var physics: ({
        "drop": 0.2,        // a lone drop's radius, as a share of the sac's
        "ceiling": 0.45,    // the most of the sac the bodies may fill together
        "growth": 3.0,      // how fast a radius reaches its target, per second
        "nesting": 0.6,     // a lobe's distance from the body, as a share of the two radii
        "gap": 2,           // between two bodies
        "pull": 0.6,        // towards the centre, per second
        "inset": 6,         // from the membrane
        "membrane": 1.5     // its thickness
    })

    // Unread, by application, most first: { key, name, count, critical }.
    readonly property var apps: {
        const byApp = ({});
        const order = [];
        for (const entry of Notifications.unread) {
            const key = entry.appName || "?";
            if (!byApp[key]) {
                byApp[key] = { "key": key, "name": entry.appName || "Unknown", "count": 0, "critical": false };
                order.push(byApp[key]);
            }
            byApp[key].count++;
            byApp[key].critical = byApp[key].critical || entry.critical;
        }
        return order.sort((a, b) => b.count - a.count);
    }

    readonly property var oldest: Notifications.unread.length > 0 ? Notifications.unread[0].at : 0

    // Six slots, each one application or empty. An application keeps its slot
    // for as long as it has unread drops, so it keeps its place.
    property var slots: []
    property var tints: [Theme.primary, Theme.primary, Theme.primary, Theme.primary, Theme.primary, Theme.primary]

    function emptySlot(index) {
        const angle = index / 6 * Math.PI * 2;
        return {
            "key": "",
            "name": "",
            "count": 0,
            "critical": false,
            "leaving": true,
            "x": root.sac / 2 + Math.cos(angle) * root.sac * 0.2,
            "y": root.sac / 2 + Math.sin(angle) * root.sac * 0.2,
            "radii": [0, 0, 0, 0],
            "targets": [0, 0, 0, 0],
            // Where the lobes sit around the body: fixed per slot, so the
            // sac does not turn while nothing arrives.
            "angle": index * 1.3 - Math.PI / 2,
            "extent": 0
        };
    }

    function ensureSlots() {
        if (root.slots.length === 6)
            return;
        const out = [];
        for (let i = 0; i < 6; i++)
            out.push(root.emptySlot(i));
        root.slots = out;
    }

    function ingest() {
        root.ensureSlots();
        if (root.sac <= 0)
            return;
        const p = root.physics;
        const apps = root.apps.slice(0, 6);
        const inner = root.sac / 2 - p.membrane * root.factor - p.inset * root.factor;
        const dropArea = Math.PI * Math.pow(p.drop * inner, 2);
        const drops = apps.reduce((sum, app) => sum + app.count, 0);
        const room = p.ceiling * Math.PI * inner * inner;
        const scale = drops * dropArea > room ? room / (drops * dropArea) : 1;

        const wanted = {};
        for (const app of apps)
            wanted[app.key] = app;
        for (const slot of root.slots)
            if (slot.key.length > 0 && !wanted[slot.key])
                slot.leaving = true;

        for (const app of apps) {
            let slot = root.slots.find(s => s.key === app.key);
            if (!slot) {
                const free = root.slots.findIndex(s => s.leaving && s.radii.every(r => r < 0.5));
                if (free < 0)
                    continue;
                slot = root.slots[free] = root.emptySlot(free);
                slot.key = app.key;
                root.place(slot);
            }
            slot.leaving = false;
            slot.name = app.name;
            slot.count = app.count;
            slot.critical = app.critical;

            // The drops dealt round the four lobes: one drop is one lobe,
            // five are a body of two with three around it.
            slot.targets = [0, 1, 2, 3].map(i => {
                const share = app.count > i ? Math.floor((app.count - i + 3) / 4) : 0;
                return Math.sqrt(share * dropArea * scale / Math.PI);
            });
        }
        for (const slot of root.slots)
            if (slot.leaving)
                slot.targets = [0, 0, 0, 0];

        root.tints = root.slots.map(slot => slot.critical ? Theme.alert : Theme.primary);
        root.label();
        root.moving = true;
    }

    // A new body starts where there is most room: the point inside the sac
    // farthest from every body already there, among a few candidates.
    function place(slot) {
        const c = root.sac / 2;
        let best = { "x": c, "y": c };
        let bestRoom = -Infinity;
        for (let i = 0; i < 24; i++) {
            const angle = i * 2.39996;
            const distance = c * 0.55 * Math.sqrt((i + 0.5) / 24);
            const x = c + Math.cos(angle) * distance;
            const y = c + Math.sin(angle) * distance;
            let room = Infinity;
            for (const other of root.slots)
                if (other !== slot && other.key.length > 0 && !other.leaving)
                    room = Math.min(room, Math.hypot(other.x - x, other.y - y) - other.extent);
            if (room > bestRoom) {
                bestRoom = room;
                best = { "x": x, "y": y };
            }
        }
        slot.x = best.x;
        slot.y = best.y;
    }

    onAppsChanged: root.ingest()
    onSacChanged: root.ingest()
    // The last drop read takes the sac with it: drawn empty at once, not a
    // frame later.
    onPresentChanged: root.draw()

    // ---- Motion -------------------------------------------------------------------------

    property bool moving: false

    function lobesOf(slot) {
        const r = slot.radii;
        const out = [{ "x": slot.x, "y": slot.y, "r": r[0] }];
        for (let i = 1; i < 4; i++) {
            const angle = slot.angle + (i - 1) * Math.PI * 2 / 3;
            const distance = root.physics.nesting * (r[0] + r[i]);
            out.push({
                "x": slot.x + Math.cos(angle) * distance,
                "y": slot.y + Math.sin(angle) * distance,
                "r": r[i]
            });
        }
        return out;
    }

    function step(dt) {
        const p = root.physics;
        const f = root.factor;
        const c = root.sac / 2;
        let moving = false;

        for (const slot of root.slots) {
            for (let i = 0; i < 4; i++) {
                const gap = slot.targets[i] - slot.radii[i];
                if (Math.abs(gap) > 0.2) {
                    slot.radii[i] += gap * Math.min(1, p.growth * dt);
                    moving = true;
                } else {
                    slot.radii[i] = slot.targets[i];
                }
            }
            slot.extent = slot.radii[0] > 0
                ? Math.max(...root.lobesOf(slot).map(l => Math.hypot(l.x - slot.x, l.y - slot.y) + l.r))
                : 0;
        }

        // Bodies pressed together: each drawn to the centre, pushed apart
        // where two would overlap, held inside the membrane.
        const live = root.slots.filter(s => s.extent > 0.5);
        for (const slot of live) {
            slot.x += (c - slot.x) * p.pull * dt;
            slot.y += (c - slot.y) * p.pull * dt;
        }
        const shapes = live.map(slot => root.lobesOf(slot).filter(l => l.r > 0.5));
        for (let a = 0; a < live.length; a++) {
            for (let b = a + 1; b < live.length; b++) {
                let px = 0;
                let py = 0;
                for (const one of shapes[a]) {
                    for (const two of shapes[b]) {
                        let dx = two.x - one.x;
                        let dy = two.y - one.y;
                        let d = Math.hypot(dx, dy);
                        if (d < 0.01) {
                            dx = 1;
                            dy = 0;
                            d = 1;
                        }
                        const overlap = one.r + two.r + p.gap * f - d;
                        if (overlap > 0) {
                            px += dx / d * overlap;
                            py += dy / d * overlap;
                        }
                    }
                }
                const push = Math.min(1, 10 * dt) / 2;
                live[a].x -= px * push;
                live[a].y -= py * push;
                live[b].x += px * push;
                live[b].y += py * push;
                if (Math.hypot(px, py) * push > 0.05)
                    moving = true;
            }
        }
        const inner = c - (p.membrane + p.inset) * f;
        for (const slot of live) {
            const reach = Math.max(0, inner - slot.extent);
            const dx = slot.x - c;
            const dy = slot.y - c;
            const d = Math.hypot(dx, dy);
            if (d > reach && d > 0) {
                slot.x = c + dx / d * reach;
                slot.y = c + dy / d * reach;
            }
        }

        root.moving = moving;
        root.draw();
    }

    function draw() {
        root.ensureSlots();
        const lobes = [];
        for (const slot of root.slots)
            for (const lobe of root.lobesOf(slot))
                lobes.push(Qt.vector4d(lobe.x, lobe.y, root.present ? lobe.r : 0, 0));
        tissue.l0 = lobes[0]; tissue.l1 = lobes[1]; tissue.l2 = lobes[2]; tissue.l3 = lobes[3];
        tissue.l4 = lobes[4]; tissue.l5 = lobes[5]; tissue.l6 = lobes[6]; tissue.l7 = lobes[7];
        tissue.l8 = lobes[8]; tissue.l9 = lobes[9]; tissue.l10 = lobes[10]; tissue.l11 = lobes[11];
        tissue.l12 = lobes[12]; tissue.l13 = lobes[13]; tissue.l14 = lobes[14]; tissue.l15 = lobes[15];
        tissue.l16 = lobes[16]; tissue.l17 = lobes[17]; tissue.l18 = lobes[18]; tissue.l19 = lobes[19];
        tissue.l20 = lobes[20]; tissue.l21 = lobes[21]; tissue.l22 = lobes[22]; tissue.l23 = lobes[23];

        for (let i = 0; i < 6; i++) {
            const tag = names.itemAt(i);
            if (!tag)
                continue;
            const slot = root.slots[i];
            tag.x = root.sacX + slot.x;
            tag.y = slot.y;
            tag.shown = root.labels && !slot.leaving && slot.radii[0] > 0 && slot.extent >= root.labelled;
            // A name wider than its body would run into the next one: a
            // small body says only how many.
            tag.named = tag.nameWidth <= 2 * slot.extent + 6 * root.factor;
        }
    }

    function label() {
        for (let i = 0; i < 6; i++) {
            const tag = names.itemAt(i);
            const slot = root.slots[i];
            if (!tag || !slot || slot.key.length === 0)
                continue;
            tag.name = slot.name;
            tag.figure = String(slot.count);
        }
    }

    // Names and counts on the bodies, unless `labels: false`.
    readonly property bool labels: root.entry.labels !== false
    onLabelsChanged: root.draw()

    // A body this small carries no name: it would be wider than the body.
    readonly property real labelled: 22 * root.factor

    FrameAnimation {
        running: root.moving && root.visible
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    // ---- The sac --------------------------------------------------------------------

    // The membrane: the sac's own edge, a hairline of text over a breath of
    // fill, so an empty sac in arranging still reads as a sac.
    Rectangle {
        x: root.sacX
        width: root.sac
        height: root.sac
        radius: root.sac / 2
        antialiasing: true
        color: Qt.alpha(Theme.text, 0.03)
        border.width: root.physics.membrane * root.factor
        border.color: Qt.alpha(Theme.text, 0.22)
    }

    ShaderEffect {
        id: tissue

        x: root.sacX
        width: root.sac
        height: root.sac
        fragmentShader: Qt.resolvedUrl("../cytoplasm/cytoplasm.frag.qsb")

        readonly property size extent: Qt.size(width, height)
        // The shader cuts its tissue to a rounded box; a box rounded by half
        // its side is the sac.
        readonly property real radius: root.sac / 2
        readonly property color core: Theme.text

        property color c0: root.tints[0]
        property color c1: root.tints[1]
        property color c2: root.tints[2]
        property color c3: root.tints[3]
        property color c4: root.tints[4]
        property color c5: root.tints[5]

        Behavior on c0 { ColorAnimation { duration: Timing.theme } }
        Behavior on c1 { ColorAnimation { duration: Timing.theme } }
        Behavior on c2 { ColorAnimation { duration: Timing.theme } }
        Behavior on c3 { ColorAnimation { duration: Timing.theme } }
        Behavior on c4 { ColorAnimation { duration: Timing.theme } }
        Behavior on c5 { ColorAnimation { duration: Timing.theme } }

        property vector4d l0; property vector4d l1; property vector4d l2; property vector4d l3
        property vector4d l4; property vector4d l5; property vector4d l6; property vector4d l7
        property vector4d l8; property vector4d l9; property vector4d l10; property vector4d l11
        property vector4d l12; property vector4d l13; property vector4d l14; property vector4d l15
        property vector4d l16; property vector4d l17; property vector4d l18; property vector4d l19
        property vector4d l20; property vector4d l21; property vector4d l22; property vector4d l23
    }

    Repeater {
        id: names

        model: 6

        // Placed by its centre, so a name coming or going does not move it.
        delegate: Item {
            id: tag

            property string name: ""
            property string figure: ""
            property bool shown: false
            property bool named: true
            readonly property real nameWidth: nameText.implicitWidth

            opacity: tag.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }

            Column {
                anchors.centerIn: parent

                // The cytoplasm's ground for words over tissue (§08).
                layer.enabled: tag.shown
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Theme.background
                    shadowOpacity: 1.0
                    shadowBlur: 0.6
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 1
                }

                Text {
                    id: nameText
                    visible: tag.named
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tag.name.toUpperCase()
                    color: Theme.text
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightLabel,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                    })
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tag.figure
                    color: Theme.text
                    opacity: 0.8
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightSecondary
                    }))
                }
            }
        }
    }

    // Blank, while arranging with nothing unread.
    Text {
        visible: !root.present
        x: root.sacX
        width: root.sac
        y: (root.sac - height) / 2
        horizontalAlignment: Text.AlignHCenter
        text: "Nothing unread"
        color: Theme.textFaint
        font.family: Typography.expressive
        font.pixelSize: Math.round(14 * root.factor)
        font.italic: true
    }

    // ---- The figures ------------------------------------------------------------------

    function since(at) {
        const date = new Date(at);
        const now = new Date();
        const pad = n => String(n).padStart(2, "0");
        const time = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
        if (date.toDateString() === now.toDateString())
            return time;
        const months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        return `${date.getDate()} ${months[date.getMonth()]} ${time}`;
    }

    Item {
        id: caption

        visible: root.figures && root.present
        x: root.sacX
        y: root.sac + root.gap
        width: root.sac
        implicitHeight: count.implicitHeight

        Row {
            id: count
            spacing: 8 * root.factor

            Text {
                anchors.baseline: value.baseline
                text: "UNREAD"
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
                text: String(Notifications.unread.length)
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
            text: root.oldest > 0 ? `SINCE ${root.since(root.oldest)}` : ""
            color: Theme.textMuted
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "weight": Typography.weightSecondary
            }))
        }
    }
}
