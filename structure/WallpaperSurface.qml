import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

// The wallpaper for one monitor. One of these per screen, on the Background
// layer, below everything.
//
// Two image layers rather than one. Prisma declared `Behavior on source` with a
// `SequentialAnimation` over a string property, which cannot interpolate: the
// image swapped hard while the opacity animation ran against the already-swapped
// picture. A real crossfade needs the incoming image loaded and ready before
// anything fades, which is what the pair below is for.
PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "bioma-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "black"

    readonly property string screenName: root.screen?.name ?? ""
    readonly property string source: Wallpaper.pathForScreen(screenName)
    readonly property bool spanning: Wallpaper.mode === "span"
    readonly property var span: spanning ? Wallpaper.spanGeometry(screenName) : null

    // Which of the two layers is currently showing.
    property bool showingSecond: false

    onSourceChanged: root.present(source)

    function present(imagePath) {
        if (imagePath.length === 0)
            return;

        const showing = root.showingSecond ? second : first;
        if (showing.source === imagePath)
            return;

        // Going back to the image the idle layer still holds — the common case
        // when the user steps back and forth through a folder. It is already
        // decoded, so reveal it rather than reloading it.
        const incoming = root.showingSecond ? first : second;
        if (incoming.source === imagePath) {
            root.reveal(incoming);
            return;
        }

        incoming.source = imagePath;
        // The swap happens in the layer's own onReady, once the image is
        // decoded — never here.
    }

    function reveal(layer) {
        root.showingSecond = (layer === second);
    }

    component Layer: Item {
        id: layer

        property string source: ""
        signal ready()

        anchors.fill: parent
        clip: root.spanning

        readonly property var geometry: root.span

        Image {
            id: image

            // In span mode the item is the bounding box of every monitor,
            // shifted so this screen shows its own portion. In every other mode
            // it simply fills the screen.
            width: layer.geometry
                ? layer.width * (layer.geometry.totalWidth / layer.geometry.screenWidth)
                : layer.width
            height: layer.geometry
                ? layer.height * (layer.geometry.totalHeight / layer.geometry.screenHeight)
                : layer.height
            x: layer.geometry
                ? -layer.width * (layer.geometry.offsetX / layer.geometry.screenWidth)
                : 0
            y: layer.geometry
                ? -layer.height * (layer.geometry.offsetY / layer.geometry.screenHeight)
                : 0

            source: layer.source.length > 0 ? "file://" + layer.source : ""
            // The box is covered, never stretched: an L of a 3440 × 1440
            // screen over a 1920 × 1080 one is a 3440 × 2520 box, and a 21:9
            // photograph forced into that is a photograph squashed by half.
            // Cropped from the centre, the image keeps its proportions and the
            // slices still line up across the seam — the same cover-then-slice
            // the span mode does in Noctalia.
            fillMode: Wallpaper.fillModeForScreen()
            asynchronous: true
            cache: false
            smooth: true

            // Decode at the size actually needed. A 6000 px photograph on a
            // 1920 px monitor otherwise costs its full decoded size in memory,
            // once per screen.
            sourceSize.width: Math.round(width * (root.screen?.devicePixelRatio ?? 1))
            sourceSize.height: Math.round(height * (root.screen?.devicePixelRatio ?? 1))

            onStatusChanged: {
                if (status === Image.Ready)
                    layer.ready();
                else if (status === Image.Error && layer.source.length > 0)
                    console.warn("Wallpaper: cannot load", layer.source, "on", root.screenName);
            }
        }
    }

    Layer {
        id: first
        opacity: root.showingSecond ? 0 : 1
        onReady: root.reveal(first)
        Behavior on opacity { NumberAnimation { duration: Timing.wallpaper; easing.type: Easing.InOutQuad } }
    }

    Layer {
        id: second
        opacity: root.showingSecond ? 1 : 0
        onReady: root.reveal(second)
        Behavior on opacity { NumberAnimation { duration: Timing.wallpaper; easing.type: Easing.InOutQuad } }
    }

    Component.onCompleted: first.source = root.source
}
