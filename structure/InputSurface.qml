import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// The full-screen transparent surface, one per monitor.
//
// PRD §8 calls it the most uncertain piece in the project, and three things
// need it: closing an open cell when the pointer lands somewhere else, cells
// positioned at the pointer, and Bioma's own selection rectangle for capture —
// because Wayland gives a client no other way to learn where the pointer is.
//
// It is only alive while a cell is open. Its input region is **the screen minus
// everything the shell already claims**, so the membranes keep their own clicks
// whatever the stacking order happens to be: the two regions never overlap, and
// nothing has to be layered above anything else for the right surface to
// receive a press.
PanelWindow {
    id: root

    required property var screenItem

    screen: screenItem
    color: "transparent"

    // Never reserve, never hide anything: it is a sheet of glass over the
    // desktop and it exists only while it has something to catch. -1 rather
    // than 0, because 0 asks the compositor to keep the surface clear of every
    // other exclusive zone — which it does by shrinking it, leaving the sheet
    // smaller than the screen and its coordinates offset from the output's.
    // The holes punched in its input region are computed from items on other
    // surfaces, and the pointer position it exists to report is read straight
    // out of it.
    exclusiveZone: -1
    visible: Focus.anyOpen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Layer-shell surfaces of the same layer stack in creation order, which is
    // not something to build a behaviour on. The mask is what makes this
    // correct instead of lucky.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "bioma-input"

    property var catchRegion: null

    // The same rule as the membrane's: before the holes are punched the sheet
    // claims nothing, rather than claiming the screen.
    Region { id: nothing }

    mask: catchRegion ? catchRegion : nothing

    Item {
        id: sheet
        anchors.fill: parent

        MouseArea {
            id: catcher
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true

            // The press is the moment the user's attention moved, so the cell
            // closes then rather than on release. The event stops here: a
            // dismissing press does not also act on whatever is underneath.
            onPressed: event => {
                Focus.dismiss();
                event.accepted = true;
            }
        }
    }

    // What a pointer-positioned cell and the capture rectangle will read. This
    // is the only way a Wayland client learns where the pointer is, and it only
    // knows while this surface is up.
    readonly property real pointerX: catcher.mouseX
    readonly property real pointerY: catcher.mouseY
    readonly property bool pointerInside: catcher.containsMouse

    function rebuild() {
        if (!root.visible) {
            root.catchRegion = null;
            return;
        }
        const rects = Focus.claimed(root.screenItem ? root.screenItem.name : "");
        root.catchRegion = Regions.rebindHoleRects(root, root.catchRegion, sheet, rects);
    }

    onVisibleChanged: rebuild()

    // The sheet is 500 × 500 until the compositor has configured the surface,
    // and a region bound to rectangles does not follow it afterwards the way a
    // region bound to an item would.
    onWidthChanged: rebuild()
    onHeightChanged: rebuild()

    Component.onCompleted: rebuild()

    Connections {
        target: Focus
        // The shapes changed shape only in number; their geometry follows the
        // items themselves.
        function onRevisionChanged() { root.rebuild(); }
    }
}
