import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Permission, asked for: the session's authentication agent made visible.
//
// Never placed and never asked for by a key: polkit asks, and the cell is
// summoned into the middle of the screen the keyboard is on (services/
// Polkit.qml). It wears AUTHENTICATION with the lock in its pill and hangs
// the request from it — the icon of the action, the message polkit was
// given, and the field, drawn as the lock screen draws it, because it is the
// same password and the same gesture. Enter answers; Escape, a press outside
// or CANCEL is "no", and polkit is told so at once rather than left to wait.
//
// See docs/design/CELLS.md §19.
Cell {
    id: root

    domain: "polkit"

    readonly property real glyphSize: 20 * metrics.factor

    paddingLeading: (metrics.cellHeight - glyphSize) / 2
    paddingTrailing: paddingLeading
    contentWidth: glyphSize

    headerTitle: "AUTHENTICATION"
    headerMarkSize: glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "lock"
            gradient: true
        }
    }
    replacesContent: true

    // A field and nothing else to type into: it holds the keys for as long
    // as it is open, and takes them outright where it is not floating.
    wantsKeyboard: root.open
    takesKeyboard: root.open && !root.floating

    Component.onCompleted: Polkit.shown = true
    Component.onDestruction: {
        Polkit.shown = false;
        Polkit.cancel();
    }

    // Closed by the user is cancelled; closed because the request ended is
    // nothing to cancel, and `cancel` knows the difference.
    onOpenChanged: if (!root.open) Polkit.cancel()

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("PolkitPanel.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
                item.takeCaret();
            }
        }
    }

    Icon {
        anchors.centerIn: parent
        width: root.glyphSize
        height: width
        name: "lock"
        gradient: true
    }
}
