import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components

// The lock screen on one monitor: the threshold (components/Gate.qml) on a
// session-lock surface, starting from the photograph of the desktop it covers.
// The field is only on the primary monitor, as at the greeter.
WlSessionLockSurface {
    id: root

    required property var lockState

    color: Theme.background

    Gate {
        id: gate
        gate: root.lockState
        screen: root.screen
        movable: false
    }

    onVisibleChanged: if (root.visible) gate.focusField()
}
