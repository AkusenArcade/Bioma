import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services
import qs.cells

// Quick actions: a ring of macros around the pointer.
//
// Asked for, never there by itself, and never placed: its key brings it to
// the point the hand is at, on whichever monitor that is (core/Focus.qml,
// `seek`), and a pointer too near an edge for the whole ring moves it inward
// until it fits. The pill in the middle says QUICK ACTIONS, then the name of
// the macro the pointer points at; up to eight round capsules sit on an
// circle around it, each tied to the pill by a thread, each the icon of one
// macro. The ring grows out of the pill and goes back into it: every capsule
// leaves the pill's edge as a point and travels out to its place on the
// circle, growing as it goes, its thread drawn out behind it; closing, they
// all come back in and only then does the pill go.
//
// Pointing chooses by direction: anywhere in the ring's field, the capsule
// nearest the pointer's angle lights, and a press there runs it — on the
// capsule itself or on the way to it. One to eight run the matching macro,
// the arrows walk the capsules, Enter runs the one reached, Escape closes. The
// ring goes first and the macro runs once it has gone, so a step that
// switches this monitor off does not take the ring's surface from under it.
//
// With no macro written yet there is one capsule, which opens Settings on the
// page where they are written (services/Actions.qml, SettingsActions.qml).
//
// Akusen's idea, 2026-10-18: the pointer-positioned slot withdrawn on 10-15,
// reused for the one cell that is born from the pointer.
//
// See docs/design/CELLS.md §20.
Cell {
    id: root

    domain: "actions"

    readonly property real f: metrics.factor
    readonly property real glyphSize: 20 * f
    // The ring's capsules and their icons, twice a cell's: they are what is
    // chosen from, and they are read at a glance (Akusen, 2026-10-18).
    readonly property real capsule: 80 * f
    readonly property real capsuleGlyph: 40 * f
    readonly property real gapShape: metrics.gap

    // The widest the pill may grow for a name: the ring is laid out for it,
    // so a long name elides rather than reaching the capsules at its sides.
    // Wide enough for QUICK ACTIONS, and no wider: the circle's radius
    // follows it (Akusen, 2026-10-18: a circle, not the ellipse it was).
    readonly property real pillMax: 216 * f
    readonly property real radiusRing: pillMax / 2 + gapShape + capsule / 2

    surroundX: radiusRing + capsule / 2
    surroundY: radiusRing + capsule / 2

    // ---- What it holds -------------------------------------------------------

    readonly property bool empty: Actions.ring.length === 0
    readonly property var entries: root.empty
        ? [{ "name": "Write quick actions", "icon": "edit", "settings": true }]
        : Actions.ring.map(macro => ({ "name": macro.name, "icon": Actions.iconOf(macro),
                                       "settings": false }))

    // The capsule the pointer points at, or the arrows have reached; -1 for
    // none.
    property int pointed: -1
    readonly property int marked: {
        for (let i = 0; i < satellites.count; i++)
            if (Focus.marked !== null && Focus.marked === satellites.itemAt(i))
                return i;
        return -1;
    }
    readonly property int chosen: root.marked >= 0 ? root.marked : root.pointed

    readonly property string label: root.chosen >= 0 && root.chosen < root.entries.length
                                    ? root.entries[root.chosen].name : ""

    // ---- The pill ------------------------------------------------------------

    paddingLeading: (metrics.cellHeight - glyphSize) / 2
    paddingTrailing: 16 * f
    // The texts' own natural widths: a TextMetrics leaves the tracking out,
    // and the title came out elided by exactly that much.
    contentWidth: Math.min(pillMax - paddingLeading - paddingTrailing,
                           glyphSize + 12 * f + Math.ceil(root.label.length > 0 ? name.implicitWidth
                                                                               : title.implicitWidth))

    wantsKeyboard: root.placed
    interactive: false

    Icon {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        width: root.glyphSize
        height: width
        name: "actions"
        gradient: true
    }

    Item {
        anchors.left: glyph.right
        anchors.leftMargin: 12 * root.f
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: metrics.cellHeight

        Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            opacity: root.label.length > 0 ? 0 : 1
            text: "QUICK ACTIONS"
            color: Theme.text
            elide: Text.ElideRight
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontLabel,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
            })

            Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        }

        // A macro's name is somebody's word, so it is in the human voice.
        Text {
            id: name
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            opacity: root.label.length > 0 ? 1 : 0
            text: root.label
            color: Theme.text
            elide: Text.ElideRight
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
            font.weight: Typography.weightTitle

            Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        }
    }

    // ---- The ring --------------------------------------------------------------

    // Where capsule `i` sits, from the pill's centre: clockwise from the top,
    // evenly round the circle.
    function angleOf(i) {
        return -Math.PI / 2 + i * 2 * Math.PI / Math.max(1, root.entries.length);
    }

    // Where a ray from the pill's centre leaves it. The pill is a stadium:
    // the straight sides, or one of the caps.
    function pillExit(ux, uy) {
        const halfWidth = root.width / 2;
        const r = Math.min(root.radius, root.height / 2);
        const a = Math.max(0, halfWidth - r);
        if (Math.abs(uy) > 1e-6) {
            const t = r / Math.abs(uy);
            if (Math.abs(t * ux) <= a)
                return t;
        }
        const sa = ux >= 0 ? a : -a;
        const b = ux * sa;
        return b + Math.sqrt(Math.max(0, b * b - a * a + r * r));
    }

    // The ring is drawn in the cell's own frame, not the content's, which is
    // inset by the leading padding.
    Item {
        id: ring

        x: -root.paddingLeading
        y: 0
        width: root.width
        height: root.height

        readonly property real cx: width / 2
        readonly property real cy: height / 2

        // The field: what the pointer is given between and around the
        // capsules, so it can point at one by direction and press on the way.
        Item {
            id: field

            width: 2 * root.surroundX
            height: 2 * root.surroundY
            x: ring.cx - width / 2
            y: ring.cy - height / 2

            HoverHandler {
                id: pointing
                onPointChanged: root.point(point.position.x - field.width / 2,
                                           point.position.y - field.height / 2)
                onHoveredChanged: if (!hovered) root.pointed = -1
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: if (root.pointed >= 0) root.choose(root.pointed)
            }
        }

        Repeater {
            id: satellites

            model: root.entries

            delegate: Item {
                id: satellite

                required property var modelData
                required property int index

                readonly property real angle: root.angleOf(index)
                readonly property real sx: Math.cos(angle) * root.radiusRing
                readonly property real sy: Math.sin(angle) * root.radiusRing
                readonly property real distance: Math.sqrt(sx * sx + sy * sy)
                readonly property real ux: sx / distance
                readonly property real uy: sy / distance

                // Where it leaves the pill, and how far out its centre has
                // come: from that point on the pill's edge to its place on
                // the circle, as the ring spreads.
                readonly property real start: root.pillExit(ux, uy)
                readonly property real reach: start + (distance - start) * root.spread

                // The thread runs from the pill's edge to the capsule's.
                readonly property real end: reach - width / 2

                readonly property bool lit: root.chosen === index

                // A stop for the arrows, and Enter runs it.
                readonly property bool navigable: root.spread > 0.5
                function activate() { root.choose(satellite.index); }

                width: root.capsule * root.spread
                height: width
                x: ring.cx + ux * reach - width / 2
                y: ring.cy + uy * reach - height / 2

                Shape {
                    // In the ring's frame, drawn from the satellite's: the
                    // thread belongs to the capsule it feeds.
                    x: -satellite.x
                    y: -satellite.y
                    width: ring.width
                    height: ring.height
                    preferredRendererType: Shape.CurveRenderer
                    visible: root.spread > 0

                    ShapePath {
                        strokeColor: Theme.line
                        strokeWidth: Metrics.crisp(Metrics.thread, Screen.devicePixelRatio)
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap

                        startX: ring.cx + satellite.ux * satellite.start
                        startY: ring.cy + satellite.uy * satellite.start

                        PathLine {
                            x: ring.cx + satellite.ux * satellite.end
                            y: ring.cy + satellite.uy * satellite.end
                        }
                    }
                }

                // The nodes: on the pill, and travelling with the capsule.
                Rectangle {
                    readonly property real at: satellite.start
                    width: Metrics.nodeSize * 2
                    height: width
                    radius: width / 2
                    color: Theme.node
                    antialiasing: true
                    visible: root.spread > 0
                    x: ring.cx + satellite.ux * at - satellite.x - width / 2
                    y: ring.cy + satellite.uy * at - satellite.y - height / 2
                }

                Rectangle {
                    readonly property real at: satellite.end
                    width: Metrics.nodeSize * 2
                    height: width
                    radius: width / 2
                    color: Theme.node
                    antialiasing: true
                    visible: root.spread > 0
                    x: ring.cx + satellite.ux * at - satellite.x - width / 2
                    y: ring.cy + satellite.uy * at - satellite.y - height / 2
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.alpha(satellite.lit ? Theme.lift(Theme.cell, 0.05) : Theme.cell,
                                    root.cellOpacity)
                    antialiasing: true
                    visible: root.spread > 0

                    Behavior on color { ColorAnimation { duration: Timing.transition } }
                }

                Rim {
                    anchors.fill: parent
                    radius: width / 2
                    visible: root.spread > 0
                    topColour: satellite.lit ? Theme.lift(Theme.rim, 0.10) : Theme.rim
                    bottomColour: satellite.lit ? Theme.lift(Theme.line, 0.06) : Theme.line
                }

                // Content arrives once the shape is at size, and leaves
                // before it shrinks.
                Icon {
                    anchors.centerIn: parent
                    width: root.capsuleGlyph
                    height: width
                    name: satellite.modelData.icon
                    colour: Theme.text
                    gradient: satellite.lit
                    opacity: root.spread > 0.98 && !root.leaving ? 1 : 0

                    Behavior on opacity {
                        enabled: !root.leaving
                        NumberAnimation { duration: Timing.contentFade }
                    }
                }
            }
        }
    }

    // Glass, blur and input for every capsule, and the field for the pointer.
    function gather() {
        const out = [];
        for (let i = 0; i < satellites.count; i++) {
            const item = satellites.itemAt(i);
            if (item)
                out.push({ "item": item, "radius": root.capsule / 2 });
        }
        root.outlying = out;
        root.reaching = [{ "item": field, "radius": field.height / 2 }];
    }

    Connections {
        target: satellites
        function onCountChanged() { root.gather(); }
    }

    Component.onCompleted: {
        root.gather();
        if (root.placed)
            root.unfold();
    }

    // ---- Spreading and retracting ---------------------------------------------

    // How far the ring has come out of the pill: 0 folded into it, 1 in place.
    // Every capsule together — the ring is one form opening, not eight
    // arriving.
    property real spread: 0

    // It opens with the pill, and goes back into it before the pill goes: the
    // pill waits for half the retraction, so the ring is seen going home.
    withdrawal: Timing.close / 2

    NumberAnimation {
        id: spreading
        target: root
        property: "spread"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        // Small capsules: the overshoot is allowed here.
        easing.bezierCurve: Timing.easeOpen
    }

    NumberAnimation {
        id: retracting
        target: root
        property: "spread"
        to: 0
        duration: Timing.close
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeClose
    }

    // Heard as a cell's panel is: the ring is this cell's opening, and it is
    // only ever asked for (services/Sounds.qml).
    function unfold() {
        retracting.stop();
        spreading.restart();
        keys.forceActiveFocus();
        Sounds.cell(true);
    }

    function fold() {
        spreading.stop();
        retracting.restart();
        Sounds.cell(false);
    }

    onPlacedChanged: if (root.placed && !root.leaving) root.unfold()
    onLeavingChanged: if (root.leaving) root.fold()

    // ---- Choosing --------------------------------------------------------------

    // The capsule whose direction is nearest the pointer's.
    // Inside the pill nothing is pointed at: that is where the hand starts.
    function point(dx, dy) {
        if (Math.abs(dx) <= root.width / 2 && Math.abs(dy) <= root.height / 2) {
            root.pointed = -1;
            return;
        }
        const angle = Math.atan2(dy, dx);
        let best = -1;
        let nearest = Infinity;
        for (let i = 0; i < root.entries.length; i++) {
            let apart = Math.abs(angle - root.angleOf(i)) % (2 * Math.PI);
            if (apart > Math.PI)
                apart = 2 * Math.PI - apart;
            if (apart < nearest) {
                nearest = apart;
                best = i;
            }
        }
        root.pointed = best;
    }

    // Run once the ring has gone.
    property var pending: null

    function choose(index) {
        if (index < 0 || index >= root.entries.length || root.pending)
            return;
        root.pending = root.entries[index];
        root.visibility.invoked = false;
    }

    // After the host has let the ring go, not while it is saying so: the
    // settings cell, placed nowhere, is summoned into the same host, and
    // asked for inside `gone` it was let go with the ring.
    onGone: {
        const entry = root.pending;
        root.pending = null;
        if (!entry)
            return;
        const output = root.output;
        Qt.callLater(() => {
            if (entry.settings) {
                SettingsPlace.category = "actions";
                Focus.invoke("settings", output);
            } else {
                Actions.run(entry.name);
            }
        });
    }

    // One to eight run the matching capsule. Everything else goes on up to
    // the tissue: the arrows travel, Escape closes.
    Item {
        id: keys
        focus: true

        Keys.onPressed: event => {
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                return;
            const index = event.key - Qt.Key_1;
            if (index >= 0 && index < 8) {
                root.choose(index);
                event.accepted = true;
            }
        }
    }
}
