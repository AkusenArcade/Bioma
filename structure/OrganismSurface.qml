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
// Top layer, dims the windows behind, takes the pointer and lets them be
// dragged. The organisms are not copied for it: they are lifted.
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

    // The snap that holds, while one is being dragged.
    property real guideX: NaN
    property real guideY: NaN

    Rectangle {
        visible: root.arranging && !isNaN(root.guideX)
        x: Math.round(root.guideX - width / 2)
        y: root.free.y
        width: Metrics.crisp(1.3, Screen.devicePixelRatio)
        height: root.free.height
        color: Theme.primary
    }

    Rectangle {
        visible: root.arranging && !isNaN(root.guideY)
        x: root.free.x
        y: Math.round(root.guideY - height / 2)
        width: root.free.width
        height: Metrics.crisp(1.3, Screen.devicePixelRatio)
        color: Theme.primary
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
    Repeater {
        id: organisms

        model: root.all.length

        delegate: Organism {
            required property int index

            surface: root
            place: index
            entry: root.all[index] ?? ({})
            here: Strips.belongs(entry, root.screenItem)
            free: root.free
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
        visible: root.arranging
        metrics: root.metrics
        kind: "primary"
        label: "Done"
        x: root.free.x + (root.free.width - width) / 2
        y: root.free.y + 16 * root.factor
        onActivated: Arranging.finish()
    }

    // ---- Snapping -----------------------------------------------------------------------

    // The centre an organism dragged to (cx, cy) lands on: its edges and
    // centre pulled onto the free area's edges, the screen's centre lines, the
    // other organisms' edges and centres, and the 24 px gap beside them —
    // whichever is nearest within reach, on each axis on its own.
    function snap(organism, cx, cy) {
        const reach = 8 * root.factor;
        const gap = 24 * root.factor;
        const w = organism.targetWidth;
        const h = organism.targetHeight;

        const xs = [root.free.x, root.free.x + root.free.width, root.width / 2];
        const ys = [root.free.y, root.free.y + root.free.height, root.height / 2];
        for (let i = 0; i < organisms.count; i++) {
            const other = organisms.itemAt(i);
            if (!other || other === organism || !other.visibleShape)
                continue;
            const ow = other.targetWidth / 2;
            const oh = other.targetHeight / 2;
            xs.push(other.centreX - ow, other.centreX + ow, other.centreX,
                    other.centreX - ow - gap, other.centreX + ow + gap);
            ys.push(other.centreY - oh, other.centreY + oh, other.centreY,
                    other.centreY - oh - gap, other.centreY + oh + gap);
        }

        const nearest = (edges, targets) => {
            let best = null;
            for (const edge of edges)
                for (const target of targets) {
                    const d = target - edge;
                    if (Math.abs(d) <= reach && (best === null || Math.abs(d) < Math.abs(best.d)))
                        best = { "d": d, "at": target };
                }
            return best;
        };

        const sx = nearest([cx - w / 2, cx + w / 2, cx], xs);
        const sy = nearest([cy - h / 2, cy + h / 2, cy], ys);
        return {
            "x": cx + (sx ? sx.d : 0),
            "y": cy + (sy ? sy.d : 0),
            "guideX": sx ? sx.at : NaN,
            "guideY": sy ? sy.at : NaN
        };
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
        Arranging.register(root);
        root.refreshRegions();
    }

    Component.onDestruction: Arranging.unregister(root)
}
