import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// What was copied, kept — and put back with a press.
//
// At rest it is its glyph and nothing else: the history is somebody's text,
// and a cell that showed the last thing copied would be reading it out on the
// membrane. Conditional, it is there for a moment after a copy, as the sign
// that it was kept. Open, it is the list: newest first, a filter above it, and
// a press on a row puts that back on the clipboard.
//
// Placed nowhere by default: the clipboard is something asked for, and a key
// brings it up in the middle of the screen.
Cell {
    id: root

    domain: "clipboard"

    readonly property real glyphSize: 20 * metrics.factor

    paddingLeading: (metrics.cellHeight - glyphSize) / 2
    paddingTrailing: paddingLeading
    contentWidth: glyphSize

    Connections {
        target: Clipboard
        function onCopied() { root.pulse(); }
    }

    condition: root.pulsing ? 1 : 0

    headerTitle: "CLIPBOARD"
    headerMarkSize: glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "clipboard"
            gradient: true
        }
    }
    replacesContent: true

    // The filter is typed into, so the keyboard is asked for over the panel
    // and kept while the field is being used — the vitals rule.
    property bool panelHovered: false
    property bool fieldEngaged: false
    wantsKeyboard: root.open && (root.panelHovered || root.fieldEngaged || root.floating)

    onOpenChanged: if (!root.open) {
        root.panelHovered = false;
        root.fieldEngaged = false;
    }

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("ClipboardPanel.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }

    Icon {
        anchors.centerIn: parent
        width: root.glyphSize
        height: width
        name: "clipboard"
        colour: Theme.textMuted
    }
}
