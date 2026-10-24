import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Performance mode, while it is on: the shell has stepped back, and this is
// the one thing it leaves saying so.
//
// Contracted, it is the glyph and nothing else — a dial with its needle all
// the way over — in the primary gradient. Kept on a membrane by an `always`
// visibility while the mode is off, the glyph is dim, as the connectivity
// cell's mark is with nothing connected.
//
// Open, it says why the mode is on, what it has quietened, and holds the
// switch. The on-screen display says each change both ways (services/Osd.qml):
// the cell goes with the mode, and could not say the going itself.
//
// See docs/design/CELLS.md §21.
Cell {
    id: root

    domain: "performance"

    readonly property real glyphSize: 20 * metrics.factor

    paddingLeading: (metrics.cellHeight - glyphSize) / 2
    paddingTrailing: paddingLeading
    contentWidth: glyphSize

    condition: Performance.active ? 1 : 0

    headerTitle: "PERFORMANCE"
    headerMarkSize: root.glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "performance"
            colour: Theme.line
            gradient: Performance.active
        }
    }
    replacesContent: true

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("PerformancePanel.qml")
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
        name: "performance"
        colour: Theme.line
        gradient: Performance.active
    }
}
