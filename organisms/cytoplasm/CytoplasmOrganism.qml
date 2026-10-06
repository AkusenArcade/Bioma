import QtQuick
import QtQuick.Effects
import Quickshell
import qs.core
import qs.components
import qs.services

// The applications that are running, drawn as cells pressed together in a
// cytoplasm.
//
// Each application is one cell (the biological kind) and each of its heaviest
// processes a lobe of it: a browser is a body with its content processes
// melted into its side, Telegram a single round cell. Lobes of one application
// fuse; two applications never do — they press against each other and keep
// the seam between them. So what melts together is what belongs together,
// which is the one condition on which Bioma draws metaballs at all.
//
// Size is memory. A cell's area is its share of the machine's memory, so the
// cytoplasm fills as the memory fills; past 45% of the panel everything is
// scaled down together, and the proportions stay true.
//
// Motion is processor. Lobes circle their cell at a rate proportional to the
// application's processor load — cytoplasmic streaming — so an idle
// application is still and a busy one turns. An application that starts grows
// from nothing where there is room; one that closes is taken back in, its
// radius falling to nothing, and the others close over the space it left.
//
// The grouping of processes into applications is AppLoad's.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    readonly property bool bleeds: true
    readonly property bool present: AppLoad.apps.length > 0

    // Two units by one.

    Component.onCompleted: AppLoad.hold(root, true)
    Component.onDestruction: AppLoad.hold(root, false)

    // How many applications are drawn, the heaviest; six at most, which is
    // what the shader holds.
    readonly property int count: Math.max(1, Math.min(6, root.entry.count ?? 6))

    readonly property bool themed: root.entry.colour === "theme"

    // ---- The cells ------------------------------------------------------------------

    // Constants of the simulation: rates per second and pixels at factor 1.
    readonly property var physics: ({
        "fill": 1.0,        // the panel's area that the machine's whole memory would fill
        "ceiling": 0.45,    // the most of the panel the cells may take together
        "growth": 3.0,      // how fast a radius reaches its target, per second
        "streaming": 0.03,  // radians per second per percent of one core
        "fastest": 3.0,     // radians per second, however busy
        "nesting": 0.6,     // a lobe's distance from the body, as a share of the two radii
        "smallest": 0.08,   // the least share of a cell's memory that is a lobe of its own
        "gap": 2,           // between two cells
        "pull": 0.6,        // towards the centre, per second
        "inset": 10         // from the glass
    })

    // Six slots, each one application or empty. An application keeps its slot
    // for as long as it is drawn, so it keeps its place and its colour.
    property var slots: []
    property var tints: [Theme.primary, Theme.primary, Theme.primary, Theme.primary, Theme.primary, Theme.primary]

    function emptySlot(index) {
        const angle = index / 6 * Math.PI * 2;
        return {
            "key": "",
            "name": "",
            "ram": 0,
            "leaving": true,
            "x": root.width / 2 + Math.cos(angle) * root.width * 0.25,
            "y": root.height / 2 + Math.sin(angle) * root.height * 0.25,
            "radii": [0, 0, 0, 0],
            "targets": [0, 0, 0, 0],
            "angle": index * 1.3,
            "cpu": 0,
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
        const apps = AppLoad.apps.slice(0, root.count);
        const total = SystemMonitor.ramTotal;
        if (total <= 0)
            return;

        const area = root.width * root.height * root.physics.fill;
        const shown = apps.reduce((sum, app) => sum + app.ram, 0) / total;
        const scale = shown > root.physics.ceiling ? root.physics.ceiling / shown : 1;

        // Those still drawn keep their slots; those gone start leaving.
        const wanted = {};
        for (const app of apps)
            wanted[app.key] = app;
        for (const slot of root.slots)
            if (slot.key.length > 0 && !wanted[slot.key])
                slot.leaving = true;

        for (const app of apps) {
            let slot = root.slots.find(s => s.key === app.key);
            if (!slot) {
                // A free slot — one empty, or one whose cell has gone.
                const free = root.slots.findIndex(s => s.leaving && s.radii.every(r => r < 0.5));
                if (free < 0)
                    continue;
                slot = root.slots[free] = root.emptySlot(free);
                slot.key = app.key;
                root.place(slot);
            }
            slot.leaving = false;
            slot.name = app.name;
            slot.ram = app.ram;
            slot.cpu = app.cpu;

            // The heaviest three processes and the rest, each a lobe whose
            // area is its share of the cell's. A share too small to be more
            // than a speck joins the body: a lobe of a few pixels drew a ring
            // inside its cell rather than a lobe (2026-10-05).
            const cellArea = app.ram / total * area * scale;
            const least = app.ram * root.physics.smallest;
            const shares = app.processes.slice(0, 3).map(p => p.ram);
            shares.push(app.processes.slice(3).reduce((sum, p) => sum + p.ram, 0));
            while (shares.length < 4)
                shares.push(0);
            for (let i = 1; i < 4; i++) {
                if (shares[i] < least) {
                    shares[0] += shares[i];
                    shares[i] = 0;
                }
            }
            slot.targets = shares.map(share => app.ram > 0
                ? Math.sqrt(share / app.ram * cellArea / Math.PI) : 0);
        }
        for (const slot of root.slots)
            if (slot.leaving)
                slot.targets = [0, 0, 0, 0];

        root.tints = root.slots.map(slot => root.themed ? Theme.primary
                                                        : Theme.stateFor(Math.min(1, (slot.cpu || 0) / 100)));
        root.label();
        root.moving = true;
    }

    // A new cell starts where there is most room: the free point farthest
    // from every cell already drawn, among a few candidates.
    function place(slot) {
        let best = null;
        let bestRoom = -1;
        for (let i = 0; i < 24; i++) {
            const x = root.width * (0.2 + 0.6 * ((i * 7) % 24) / 23);
            const y = root.height * (0.2 + 0.6 * ((i * 11) % 24) / 23);
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

    Connections {
        target: AppLoad
        function onAppsChanged() { root.ingest(); }
    }

    onThemedChanged: root.ingest()
    onCountChanged: root.ingest()

    // ---- Motion ---------------------------------------------------------------------

    property bool moving: false

    // Where a cell's lobes are: the first at its centre, the others around it.
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
            const spin = Math.min(p.fastest, p.streaming * (slot.cpu || 0));
            if (spin > 0.005 && slot.radii[0] > 0.5) {
                slot.angle += spin * dt;
                moving = true;
            }
            slot.extent = slot.radii[0] > 0
                ? Math.max(...root.lobesOf(slot).map(l => Math.hypot(l.x - slot.x, l.y - slot.y) + l.r))
                : 0;
        }

        // Cells pressed together: each pulled to the centre, pushed apart
        // where two would overlap, held inside the glass.
        const live = root.slots.filter(s => s.extent > 0.5);
        for (const slot of live) {
            const dx = (root.width / 2 - slot.x) * p.pull * dt;
            const dy = (root.height / 2 - slot.y) * p.pull * dt;
            slot.x += dx;
            slot.y += dy;
        }
        // Lobe against lobe, not cell against cell: a cell is lobed, and a
        // circle around it would hold its neighbours off its narrow sides.
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
        const inset = p.inset * f;
        for (const slot of live) {
            const reach = Math.min(slot.extent + inset, Math.min(root.width, root.height) / 2);
            slot.x = Math.max(reach, Math.min(root.width - reach, slot.x));
            slot.y = Math.max(reach, Math.min(root.height - reach, slot.y));
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
            tag.x = slot.x - tag.width / 2;
            tag.y = slot.y - tag.height / 2;
            tag.shown = root.labels && !slot.leaving && slot.radii[0] > 0 && slot.extent >= root.labelled;
        }
    }

    // Names and figures, refreshed with each sample rather than each frame.
    function label() {
        for (let i = 0; i < 6; i++) {
            const tag = names.itemAt(i);
            const slot = root.slots[i];
            if (!tag || !slot || slot.key.length === 0)
                continue;
            tag.name = slot.name;
            tag.figure = slot.ram >= 1024 ? `${(slot.ram / 1024).toFixed(1)} GB` : `${Math.round(slot.ram)} MB`;
        }
    }

    // Names and figures on the cells, unless `labels: false`: the tissue
    // alone, read by its shapes.
    readonly property bool labels: root.entry.labels !== false
    onLabelsChanged: root.draw()

    // A cell this small carries no name: it would be wider than the cell.
    readonly property real labelled: 24 * root.factor

    FrameAnimation {
        running: root.moving && root.visible && root.present
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    onWidthChanged: root.ingest()
    onHeightChanged: root.ingest()

    ShaderEffect {
        id: tissue

        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("cytoplasm.frag.qsb")

        readonly property size extent: Qt.size(width, height)
        readonly property real radius: root.metrics.radiusPanel
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

        delegate: Column {
            id: tag

            property string name: ""
            property string figure: ""
            property bool shown: false

            opacity: tag.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }

            // Over translucent wax of any colour the words need ground of
            // their own (Akusen, 2026-10-05): a shadow in the theme's
            // background, close and soft — not coloured, so not the halo the
            // style guide forbids.
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

    Text {
        visible: !root.present
        anchors.centerIn: parent
        text: "No applications"
        color: Theme.textFaint
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontSecondary,
            "weight": Typography.weightSecondary
        })
    }
}
