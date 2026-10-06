import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.structure

// The organisms of one monitor: the desktop's own furniture.
//
// On the Bottom layer — above the wallpaper, under every window — so they are
// seen on an empty workspace and between the windows, and gone under them the
// moment there is work on screen. The surface covers the output and never
// resizes, like every full-screen surface here; at rest it reserves nothing,
// never takes the keyboard, and its input region is empty, so a click meant
// for the desktop is never stolen.
//
// They live in the **free area**: the screen minus what the membranes hold,
// measured to the line the windows begin on — the same line a floating tissue
// anchored to an edge sits on (`Strips.windowLine`).
//
// While they are being placed (`Arranging`) the same surface comes up to the
// Top layer, dims the windows behind, draws the grid, takes the pointer and
// lets them be dragged onto it. The organisms are not copied for it: they are
// lifted.
//
// See docs/design/ORGANISMS.md.
PanelWindow {
    id: root

    required property var screenItem

    // Every organism in the configuration — or in the list being edited. This
    // surface holds one for each and shows the ones that belong on its screen.
    property var all: []

    readonly property bool arranging: Arranging.active

    screen: screenItem
    color: "transparent"
    exclusiveZone: -1

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: root.arranging ? WlrLayer.Top : WlrLayer.Bottom
    WlrLayershell.namespace: "bioma-organisms"
    // The keyboard on demand, never exclusively: niri gives it to the surface
    // that is pressed, and Escape is heard from then on. Held exclusively by
    // the screen the mode was asked on, a press on the other screen was
    // cancelled the moment it landed — every press, once an organism had been
    // carried there — and handing the exclusive hold from screen to screen
    // under the pointer cancelled them all (2026-10-04). Before the first
    // press, Done and the same keybind leave.
    WlrLayershell.keyboardFocus: root.arranging ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // At rest nothing here takes the pointer; while arranging, all of it does.
    Region { id: nothing }
    Region { id: everything; item: sheet }
    mask: root.arranging ? everything : nothing

    // The membranes' density, for the organisms that do not say their own.
    readonly property var metrics: Strips.stripMetrics(root.screenItem, Metrics.step("normal"))
    readonly property real factor: root.metrics.factor

    readonly property real lineTop: Strips.windowLine(root.screenItem, "top", root.metrics)
    readonly property real lineBottom: Strips.windowLine(root.screenItem, "bottom", root.metrics)
    readonly property real lineLeft: Strips.windowLine(root.screenItem, "left", root.metrics)
    readonly property real lineRight: Strips.windowLine(root.screenItem, "right", root.metrics)

    readonly property rect free: Qt.rect(root.lineLeft, root.lineTop,
                                         Math.max(0, root.width - root.lineLeft - root.lineRight),
                                         Math.max(0, root.height - root.lineTop - root.lineBottom))

    Item {
        id: sheet
        anchors.fill: parent

        // Escape leaves the mode, from whichever screen holds the keyboard.
        focus: root.arranging
        Keys.onEscapePressed: Arranging.finish()

        // The wheel makes the grid finer or coarser — up for larger squares,
        // down for smaller — anywhere on any screen, over an organism too:
        // the hand that places them does not take the wheel.
        WheelHandler {
            enabled: root.arranging
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            property real turned: 0

            onWheel: event => {
                turned += event.angleDelta.y;
                while (Math.abs(turned) >= 120) {
                    Arranging.finer(turned > 0 ? -1 : 1);
                    turned -= turned > 0 ? 120 : -120;
                }
            }
        }
    }

    onArrangingChanged: if (root.arranging) sheet.forceActiveFocus()

    // ---- Arranging: what is drawn behind the organisms ------------------------------

    // The windows behind, dimmed: what is being worked on now is the desktop.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("#000000", 0.55)
        opacity: root.arranging ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Timing.transition } }
    }

    // Where they may go: the free area, as a place rather than a content.
    DashedSlot {
        x: root.free.x
        y: root.free.y
        width: root.free.width
        height: root.free.height
        radius: root.metrics.radiusPanel
        colour: Theme.line
        dash: 10 * root.factor
        space: 8 * root.factor
        opacity: root.arranging ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Timing.transition } }
    }

    // ---- The grid ---------------------------------------------------------------------

    // One module is a template's unit and the gap beside it, at the
    // membranes' step; the wheel divides it into squares (`Arranging.grid`).
    // An organism covers whole modules — its panel and half a gap around it —
    // so at every division its edges fall on the lines.
    readonly property real module: root.metrics.organismUnit + root.metrics.gap
    readonly property real square: root.module / Arranging.grid
    readonly property real finest: root.module / Arranging.divisions[Arranging.divisions.length - 1]

    // The free area to the finest square, the little that is left over shared
    // on both sides. Every division counts from the same corner, so the
    // wheel never moves what has been placed.
    readonly property rect grid: {
        const w = Math.floor(root.free.width / root.finest + 1e-6) * root.finest;
        const h = Math.floor(root.free.height / root.finest + 1e-6) * root.finest;
        return Qt.rect(root.free.x + (root.free.width - w) / 2, root.free.y + (root.free.height - h) / 2,
                       Math.max(0, w), Math.max(0, h));
    }

    // Where an organism covering `w` × `h` lands when its top-left corner is
    // wanted at (`left`, `top`): on the nearest line of the grid as it is
    // divided now, and wholly inside it. In modules from the grid's corner.
    // One too large for the area sits in its middle.
    function point(w, h, left, top) {
        const axis = (start, extent, size, wanted) => {
            const room = extent - size;
            if (room < 0)
                return room / 2 / root.module;
            const most = Math.floor(room / root.square + 1e-6);
            const at = Math.max(0, Math.min(most, Math.round((wanted - start) / root.square)));
            return at * root.square / root.module;
        };
        return {
            "col": axis(root.grid.x, root.grid.width, w, left),
            "row": axis(root.grid.y, root.grid.height, h, top)
        };
    }

    // A point as it was written, held inside the grid as it is now — a
    // smaller screen, a membrane added — but not moved onto the present
    // division: a point written on a finer grid stays where it was put.
    function kept(w, h, col, row) {
        const axis = (extent, size, at) => {
            const room = extent - size;
            if (room < 0)
                return room / 2 / root.module;
            const most = Math.floor(room / root.finest + 1e-6) * root.finest / root.module;
            return Math.max(0, Math.min(most, at));
        };
        return {
            "col": axis(root.grid.width, w, Number(col) || 0),
            "row": axis(root.grid.height, h, Number(row) || 0)
        };
    }

    function corner(col, row) {
        return Qt.point(root.grid.x + col * root.module, root.grid.y + row * root.module);
    }

    // The lines, while arranging: every square faint, every module a little
    // stronger, so the units of the templates can be counted.
    readonly property real hairline: Metrics.crisp(1, Screen.devicePixelRatio)

    Item {
        id: lines

        x: root.grid.x
        y: root.grid.y
        width: root.grid.width
        height: root.grid.height
        opacity: root.arranging ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Timing.transition } }

        Repeater {
            model: lines.visible ? Math.floor(lines.width / root.square + 1e-6) + 1 : 0

            delegate: Rectangle {
                required property int index
                x: Math.round(index * root.square - width / 2)
                width: root.hairline
                height: lines.height
                color: Qt.alpha(Theme.primary, index % Arranging.grid === 0 ? 0.22 : 0.08)
            }
        }

        Repeater {
            model: lines.visible ? Math.floor(lines.height / root.square + 1e-6) + 1 : 0

            delegate: Rectangle {
                required property int index
                y: Math.round(index * root.square - height / 2)
                width: lines.width
                height: root.hairline
                color: Qt.alpha(Theme.primary, index % Arranging.grid === 0 ? 0.22 : 0.08)
            }
        }
    }

    // Where the one in the hand will land: its own shape, lit faintly on the
    // squares it will cover.
    property rect landing: Qt.rect(0, 0, 0, 0)
    property real landingRadius: 0

    Rectangle {
        visible: root.arranging && root.landing.width > 0
        x: root.landing.x
        y: root.landing.y
        width: root.landing.width
        height: root.landing.height
        radius: root.landingRadius
        color: Qt.alpha(Theme.primary, 0.14)
        border.width: root.hairline
        border.color: Qt.alpha(Theme.primary, 0.55)
    }

    // ---- The organisms ----------------------------------------------------------------

    // By position in the list, not by block: the configuration hands out a
    // fresh object on every change, and a model that changed identity would
    // rebuild every organism — each one shrinking away and growing back —
    // whenever any of them moved. An organism reads its own block instead.
    //
    // One for every organism, on every screen, each shown only where it
    // belongs. Filtered to this screen, the list lost a delegate whenever an
    // organism was carried away — destroyed inside the release that let it
    // go — and a drag on that screen was then cancelled the moment it was
    // pressed, now and then (2026-10-04).
    //
    // Kept by each block's `id`, not by its place: taken away from the middle
    // of the list, an organism must not hand its delegate to the one after
    // it, which would vanish and grow back somewhere else. A block written by
    // hand without an `id` is known by its place until the list is next
    // written from the shell.
    readonly property var keys: root.all.map((entry, i) => entry.id ? String(entry.id) : `@${i}`)

    ListModel { id: rows }

    function sync() {
        const keys = root.keys;
        for (let i = rows.count - 1; i >= 0; i--)
            if (keys.indexOf(rows.get(i).key) < 0)
                rows.remove(i);
        for (let i = 0; i < keys.length; i++) {
            if (i < rows.count && rows.get(i).key === keys[i])
                continue;
            let found = -1;
            for (let j = i + 1; j < rows.count; j++)
                if (rows.get(j).key === keys[i]) {
                    found = j;
                    break;
                }
            if (found >= 0)
                rows.move(found, i, 1);
            else
                rows.insert(i, { "key": keys[i] });
        }
    }

    onKeysChanged: root.sync()

    Repeater {
        id: organisms

        model: rows

        delegate: Organism {
            required property string key

            surface: root
            place: root.keys.indexOf(key)
            entry: root.all[place] ?? ({})
            here: Strips.belongs(entry, root.screenItem)
            baseMetrics: root.metrics
            arranging: root.arranging

            onVisibleShapeChanged: Qt.callLater(root.refreshRegions)
        }

        onItemAdded: root.refreshRegions()
        onItemRemoved: root.refreshRegions()
    }

    // Leaving: a button, in the shell's own vocabulary, on every screen — at
    // the top of the free area, where it covers none of the places an
    // organism is likely to be put.
    Choice {
        id: done
        visible: root.arranging
        metrics: root.metrics
        kind: "primary"
        label: "Done"
        x: root.free.x + (root.free.width - width) / 2
        y: root.free.y + 16 * root.factor
        onActivated: Arranging.finish()
    }

    // How finely the grid is divided, and that the wheel changes it.
    Text {
        visible: root.arranging
        anchors.horizontalCenter: done.horizontalCenter
        y: done.y + done.height + 8 * root.factor
        text: `GRID ${Arranging.grid === 1 ? "1" : "1/" + Arranging.grid} · SCROLL TO CHANGE`
        color: Theme.textMuted
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontMeta,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
        })
    }


    // ---- The glass ----------------------------------------------------------------------

    // Blur on each organism's own shape, through `ext-background-effect` — the
    // leaves follow the panels' geometry by themselves, so the tree is rebound
    // only when an organism appears or leaves.
    property var blurRegion: null
    BackgroundEffect.blurRegion: blurRegion

    readonly property bool blurs: Config.get("cell.blur", true)

    function refreshRegions() {
        const shapes = [];
        if (root.blurs)
            for (let i = 0; i < organisms.count; i++) {
                const organism = organisms.itemAt(i);
                // One on its way out is still counted for a moment, and no
                // longer answers.
                if (organism && typeof organism.shapes === "function")
                    for (const shape of organism.shapes())
                        shapes.push(shape);
            }
        root.blurRegion = Regions.rebind(root, root.blurRegion, shapes);
    }

    onBlursChanged: root.refreshRegions()

    Component.onCompleted: {
        root.sync();
        Arranging.register(root);
        root.refreshRegions();
    }

    Component.onDestruction: Arranging.unregister(root)
}
