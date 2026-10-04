import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.structure

// The organisms of one monitor: the desktop's own furniture.
//
// On the Bottom layer — above the wallpaper, under every window — so they are
// seen on an empty workspace and between the windows, and gone under them the
// moment there is work on screen. The surface covers the output and never
// resizes, like every full-screen surface here; it reserves nothing, never
// takes the keyboard, and its input region is empty, so a click meant for the
// desktop is never stolen.
//
// They live in the **free area**: the screen minus what the membranes hold,
// measured to the line the windows begin on — the same line a floating tissue
// anchored to an edge sits on (`Strips.windowLine`).
//
// See docs/design/ORGANISMS.md.
PanelWindow {
    id: root

    required property var screenItem

    // The configuration's organisms that belong on this screen.
    property var entries: []

    screen: screenItem
    color: "transparent"
    exclusiveZone: -1

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "bioma-organisms"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Nothing here takes the pointer.
    Region { id: nothing }
    mask: nothing

    // The membranes' density, for the organisms that do not say their own.
    readonly property var metrics: Strips.stripMetrics(root.screenItem, Metrics.step("normal"))

    readonly property real lineTop: Strips.windowLine(root.screenItem, "top", root.metrics)
    readonly property real lineBottom: Strips.windowLine(root.screenItem, "bottom", root.metrics)
    readonly property real lineLeft: Strips.windowLine(root.screenItem, "left", root.metrics)
    readonly property real lineRight: Strips.windowLine(root.screenItem, "right", root.metrics)

    readonly property rect free: Qt.rect(root.lineLeft, root.lineTop,
                                         Math.max(0, root.width - root.lineLeft - root.lineRight),
                                         Math.max(0, root.height - root.lineTop - root.lineBottom))

    // By position in the list, not by block: the configuration hands out a
    // fresh object on every change, and a model that changed identity would
    // rebuild every organism — each one shrinking away and growing back —
    // whenever any of them moved. An organism reads its own block instead.
    Repeater {
        id: organisms

        model: root.entries.length

        delegate: Organism {
            required property int index

            entry: root.entries[index] ?? ({})
            free: root.free
            baseMetrics: root.metrics

            onVisibleShapeChanged: root.refreshRegions()
        }

        onItemAdded: root.refreshRegions()
        onItemRemoved: root.refreshRegions()
    }

    // ---- The glass ----------------------------------------------------------------

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
                if (organism)
                    for (const shape of organism.shapes())
                        shapes.push(shape);
            }
        root.blurRegion = Regions.rebind(root, root.blurRegion, shapes);
    }

    onBlursChanged: root.refreshRegions()

    Component.onCompleted: root.refreshRegions()
}
