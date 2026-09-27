import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.services

// The wallpaper for one monitor. One of these per screen, on the Background
// layer, below everything.
//
// Two image layers rather than one. Prisma declared `Behavior on source` with a
// `SequentialAnimation` over a string property, which cannot interpolate: the
// image swapped hard while the opacity animation ran against the already-swapped
// picture. A real crossfade needs the incoming image loaded and ready before
// anything fades, which is what the pair below is for.
//
// A second one per screen, `backdrop`, is the same picture blurred: niri puts
// it behind the workspaces in the overview (`place-within-backdrop`, in
// config/niri/bioma.kdl), where the wallpaper proper is drawn inside each
// workspace and the space between them would otherwise be a flat colour.
PanelWindow {
    id: root

    // The overview's backdrop rather than the wallpaper. Read once, when the
    // surface is made: a layer surface's namespace cannot change after.
    property bool backdrop: false

    // How far the blurred picture runs past the screen's edges. A blur fades to
    // nothing at the edge of what it blurs, and a picture blurred only to the
    // screen's edge would be a picture with a dark frame.
    readonly property real bleed: root.backdrop ? 96 : 0

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: root.backdrop ? "bioma-backdrop" : "bioma-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "black"

    readonly property string screenName: root.screen?.name ?? ""
    readonly property string source: Wallpaper.pathForScreen(screenName)
    readonly property bool spanning: Wallpaper.mode === "span"

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

        WallpaperImage {
            source: layer.source
            mode: Wallpaper.mode
            screen: root.screen
            // The backdrop is blurred anyway, so a quarter of the pixels is
            // all it needs.
            density: root.backdrop ? 0.25 : 1
            onStatusChanged: if (status === Image.Ready) layer.ready()
        }
    }

    Item {
        x: -root.bleed
        y: -root.bleed
        width: root.width + root.bleed * 2
        height: root.height + root.bleed * 2

        // Rendered once into a texture and blurred there; it is redrawn only
        // when the picture changes, so the overview costs nothing to hold.
        layer.enabled: root.backdrop
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            autoPaddingEnabled: false
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
    }

    Component.onCompleted: first.source = root.source
}
