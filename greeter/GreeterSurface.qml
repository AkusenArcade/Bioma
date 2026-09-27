import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components

// The greeter on one monitor: the threshold (components/Gate.qml) on an
// overlay surface. Only the primary screen — the one niri focuses at start —
// holds the field and takes the keys; the others show the wallpaper, blurred,
// and nothing that answers a press (Akusen, 2026-09-24).
PanelWindow {
    id: root

    required property var greeterState

    readonly property bool primary: root.screen && root.greeterState.active === root.screen.name

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: Theme.background

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bioma-greeter"
    WlrLayershell.keyboardFocus: root.primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Gate {
        id: gate
        gate: root.greeterState
        screen: root.screen
        movable: false
    }

    onVisibleChanged: if (root.visible) gate.focusField()
    onPrimaryChanged: gate.focusField()
}
