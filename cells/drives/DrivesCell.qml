import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// A removable drive, while one is attached: a stick for each, and — while
// one is being written to — the thread the bytes run along.
//
// The thread is what the cell is for. A copy finishes for the program that
// made it long before it finishes for the stick: the rest waits in memory and
// goes on being written, and a stick pulled out then is a file lost. So the
// light runs along the thread exactly as fast as the kernel is writing, and
// while it runs the stick is not safe to pull; still and gone, it is. No
// figure at rest; the open cell has them, and the eject.
//
// See docs/design/CELLS.md §18.
Cell {
    id: root

    domain: "drives"

    readonly property real glyphSize: 18 * metrics.factor
    readonly property real glyphGap: 6 * metrics.factor
    readonly property real threadWidth: 44 * metrics.factor
    readonly property real spacing: 10 * metrics.factor

    Component.onCompleted: Drives.hold(root, true)
    Component.onDestruction: Drives.hold(root, false)

    condition: Drives.attached ? 1 : 0

    // Kept while the cell fades after the last drive has gone, so it leaves
    // as what it was rather than as an empty pill.
    property int count: 0
    readonly property int live: Drives.drives.length
    // And the last one gone closes it: being open holds a cell on screen, and
    // a panel left listing a stick that was just ejected would say it is
    // still there — the one thing this cell must never get wrong.
    onLiveChanged: {
        if (root.live > 0)
            root.count = root.live;
        else if (root.open)
            root.open = false;
    }
    readonly property bool writing: Drives.rate >= 4096

    readonly property real glyphsWidth: Math.max(1, root.count) * root.glyphSize
                                        + Math.max(0, root.count - 1) * root.glyphGap

    // One stick is a round cell; more, or a stick being written to, a pill.
    paddingLeading: (root.count > 1 || root.writing ? 12 : 11) * metrics.factor
    paddingTrailing: (root.writing ? 16 : root.count > 1 ? 12 : 11) * metrics.factor
    contentWidth: root.glyphsWidth + (root.writing ? root.spacing + root.threadWidth : 0)

    headerTitle: "DRIVES"
    headerMarkSize: root.glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "drive"
            gradient: true
        }
    }
    replacesContent: true

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("DrivesPanel.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }

    Row {
        id: glyphs
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.glyphGap

        Repeater {
            model: Math.max(1, root.count)

            Icon {
                width: root.glyphSize
                height: width
                name: "drive"
                gradient: true
            }
        }
    }

    RateThread {
        anchors.left: glyphs.right
        anchors.leftMargin: root.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: root.threadWidth
        visible: root.writing
        rate: Drives.rate
        running: root.shown && root.writing
        factor: root.metrics.factor
    }
}
