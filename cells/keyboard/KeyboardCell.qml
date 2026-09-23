import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// The keyboard's layout: which one is on, switching it, and which ones there
// are.
//
// At rest it is the layout's code — US, IT — in the machine's voice, the way
// the workspace number is: a name the system gives, not a sentence. Whether it
// is always there or only for a moment after the layout changes is the Cells
// page's choice, like every cell's (Akusen, 2026-09-23); conditional is for the
// person who switches rarely and wants to be told when it happened.
//
// Open, it is the list: a press switches, a cross removes, and a field adds
// any layout this machine knows. See `services/Keyboard.qml` for where that is
// written.
Cell {
    id: root

    domain: "keyboard"

    readonly property real glyphSize: 20 * metrics.factor

    paddingLeading: 12 * metrics.factor
    paddingTrailing: 12 * metrics.factor
    contentWidth: Math.max(code.implicitWidth, glyphSize)

    Connections {
        target: Keyboard
        function onSwitched() { root.pulse(); }
    }

    condition: root.pulsing ? 1 : 0

    headerTitle: "KEYBOARD"
    headerMarkSize: glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "keyboard"
            gradient: true
        }
    }
    replacesContent: true

    // A layout is found by typing its name, so the keyboard is asked for over
    // the panel and kept while the field is being used — the vitals rule.
    property bool panelHovered: false
    property bool fieldEngaged: false
    wantsKeyboard: root.open && (root.panelHovered || root.fieldEngaged || root.floating)

    onOpenChanged: if (!root.open) {
        root.panelHovered = false;
        root.fieldEngaged = false;
    }

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("KeyboardPanel.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }

    Text {
        id: code
        anchors.centerIn: parent
        text: Keyboard.currentCode
        color: Theme.text
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontLabel,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
        })
    }
}
