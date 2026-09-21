import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.core
import qs.services

// Bioma's own selection rectangle, one surface per monitor.
//
// PRD §9.6 asks for this rather than `slurp`, and the reason is not pride: the
// selector covers the entire desktop, so it is the largest surface Bioma ever
// draws, and a different program's rectangle there is a different shell for as
// long as it is up. What is built here is only the selection layer — `grim` and
// the recorder still take the picture.
//
// It is up only while the capture service is asking for a region, and it takes
// the keyboard for exactly that long, because Escape has to mean cancel.
PanelWindow {
    id: root

    required property var screenItem

    screen: screenItem
    color: "transparent"

    visible: Capture.selecting
    exclusiveZone: 0

    anchors { top: true; bottom: true; left: true; right: true }

    // Over everything, including another shell's surfaces: the desktop is being
    // pointed at, and nothing may sit between the pointer and the rectangle.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bioma-selection"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property var metrics: Metrics.step("normal")

    // The desktop, dimmed. Four of these describe everything outside the
    // rectangle exactly, which is cheaper and sharper than a mask redrawn on
    // every pointer move.
    component Shade: Rectangle {
        color: Qt.alpha(Theme.background, 0.45)
    }

    // The rectangle as drawn, in this surface's coordinates.
    property real anchorX: 0
    property real anchorY: 0
    property real pointerX: 0
    property real pointerY: 0
    property bool drawing: false

    readonly property real selectionX: Math.min(root.anchorX, root.pointerX)
    readonly property real selectionY: Math.min(root.anchorY, root.pointerY)
    readonly property real selectionWidth: Math.abs(root.pointerX - root.anchorX)
    readonly property real selectionHeight: Math.abs(root.pointerY - root.anchorY)

    // A rectangle too small to be meant is a click, and a click is how someone
    // changes their mind. It cancels rather than capturing four pixels.
    readonly property real minimum: 6

    // The region goes out in the compositor's own coordinates, which is where
    // this surface's origin sits on the layout — the same string slurp printed.
    function region() {
        const x = Math.round((root.screenItem ? root.screenItem.x : 0) + root.selectionX);
        const y = Math.round((root.screenItem ? root.screenItem.y : 0) + root.selectionY);
        return `${x},${y} ${Math.round(root.selectionWidth)}x${Math.round(root.selectionHeight)}`;
    }

    onVisibleChanged: {
        root.drawing = false;
        root.anchorX = 0;
        root.anchorY = 0;
        root.pointerX = 0;
        root.pointerY = 0;
        if (visible)
            keys.forceActiveFocus();
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Capture.cancelSelection()

        // ---- The scrim -----------------------------------------------------
        //
        // Four pieces rather than one with a hole in it: the selection has to
        // be seen at its own brightness, and a mask over the whole screen is a
        // full-screen layer redrawn on every pointer move for a rectangle four
        // straight edges describe exactly.

        Shade {
            x: 0
            y: 0
            width: parent.width
            height: root.drawing ? root.selectionY : parent.height
        }

        Shade {
            visible: root.drawing
            x: 0
            y: root.selectionY + root.selectionHeight
            width: parent.width
            height: Math.max(0, parent.height - y)
        }

        Shade {
            visible: root.drawing
            x: 0
            y: root.selectionY
            width: root.selectionX
            height: root.selectionHeight
        }

        Shade {
            visible: root.drawing
            x: root.selectionX + root.selectionWidth
            y: root.selectionY
            width: Math.max(0, parent.width - x)
            height: root.selectionHeight
        }

        // ---- The rectangle -------------------------------------------------

        Item {
            id: selection

            visible: root.drawing
            x: root.selectionX
            y: root.selectionY
            width: root.selectionWidth
            height: root.selectionHeight

            // The same lit border every surface in the shell carries, at the
            // panel radius: the rectangle is Bioma's, and it says so in the one
            // way every other shape here says it.
            Rim {
                anchors.fill: parent
                radius: Math.min(root.metrics.radiusWell,
                                 Math.min(selection.width, selection.height) / 2)
            }

            // What the region actually is, in the technical voice, tabular so
            // the readout does not dance while the pointer moves. It sits
            // inside the rectangle when there is room and under it when there
            // is not — it never covers the edge being drawn.
            Item {
                id: readout

                readonly property real pad: 8 * root.metrics.factor
                readonly property bool below: selection.height < 48 * root.metrics.factor

                width: figure.implicitWidth + readout.pad * 2
                height: 26 * root.metrics.factor
                x: Math.max(0, selection.width - width - readout.pad)
                y: readout.below ? selection.height + readout.pad
                                 : selection.height - height - readout.pad

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(Theme.cell, Config.get("cell.opacity", 0.72))
                    antialiasing: true
                }

                Text {
                    id: figure
                    anchors.centerIn: parent
                    text: `${Math.round(selection.width)} × ${Math.round(selection.height)}`
                    color: Theme.text
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightSecondary
                    }))
                }
            }
        }

        // ---- The pointer ---------------------------------------------------

        MouseArea {
            id: pointer
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.CrossCursor

            onPressed: event => {
                if (event.button === Qt.RightButton) {
                    Capture.cancelSelection();
                    return;
                }
                root.anchorX = event.x;
                root.anchorY = event.y;
                root.pointerX = event.x;
                root.pointerY = event.y;
                root.drawing = true;
            }

            onPositionChanged: event => {
                if (!root.drawing)
                    return;
                root.pointerX = event.x;
                root.pointerY = event.y;
            }

            onReleased: event => {
                if (!root.drawing)
                    return;
                root.drawing = false;
                if (root.selectionWidth < root.minimum || root.selectionHeight < root.minimum) {
                    Capture.cancelSelection();
                    return;
                }
                Capture.regionChosen(root.region());
            }
        }
    }
}
