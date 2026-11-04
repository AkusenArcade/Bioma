import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// A download, while one is coming in: the glyph and a thread the bytes run
// along.
//
// The thread is the cell's whole measure. Its light runs along it as fast as
// the bytes come — on a logarithmic scale, since a download goes from a few
// kilobytes a second to a hundred megabytes — and stops when they stop: a
// stalled download is a still thread. No figure at rest; the open cell has
// them.
//
// There is no progress to draw, because there is none to know: neither
// Firefox nor Chromium writes the total anywhere outside itself. How much has
// come and how fast it is coming are what the files say (services/
// Downloads.qml).
//
// See docs/design/CELLS.md §16.
Cell {
    id: root

    domain: "download"

    readonly property real glyphSize: 18 * metrics.factor
    readonly property real threadWidth: 44 * metrics.factor
    readonly property real spacing: 10 * metrics.factor

    Component.onCompleted: Downloads.hold(root, true)
    Component.onDestruction: Downloads.hold(root, false)

    condition: Downloads.downloading ? 1 : 0

    paddingLeading: 12 * metrics.factor
    paddingTrailing: 16 * metrics.factor
    contentWidth: root.glyphSize + root.spacing + root.threadWidth

    headerTitle: "DOWNLOADS"
    headerMarkSize: root.glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "download"
            gradient: true
        }
    }
    replacesContent: true

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("DownloadPanel.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }

    Icon {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.glyphSize
        height: width
        name: "download"
        gradient: true
    }

    RateThread {
        anchors.left: glyph.right
        anchors.leftMargin: root.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: root.threadWidth
        rate: Downloads.rate
        running: root.shown
        factor: root.metrics.factor
    }
}
