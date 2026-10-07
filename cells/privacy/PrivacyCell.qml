import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Who is taking the microphone, a camera or the screen — there only while
// something is.
//
// Contracted, it is a glyph for each thing being taken and the names of the
// applications taking them, in the expressive voice: an application's name
// is what the cell exists to say, the way the window title's is (Akusen's
// list, 2026-10-05: "indica quale app"). The glyphs are in the active
// colour — something is happening — and never the alert one: a call that
// lasts an afternoon is not an afternoon of alarm.
//
// Open, it is the list: each use on its own row, the device or the output
// beside it. There is nothing to press: the shell cannot take a microphone
// back from an application, and pretending to would be worse than saying so.
//
// See docs/design/CELLS.md §14.
Cell {
    id: root

    domain: "privacy"

    readonly property real glyphSize: 18 * metrics.factor
    readonly property real glyphGap: 6 * metrics.factor
    readonly property real spacing: 10 * metrics.factor

    Component.onCompleted: Privacy.hold(root, true)
    Component.onDestruction: Privacy.hold(root, false)

    condition: Privacy.inUse ? 1 : 0

    // Which kinds are in use, in a fixed order, and who.
    readonly property var kinds: ["microphone", "camera", "screen"].filter(kind => Privacy.uses.some(u => u.kind === kind))

    readonly property string names: {
        const out = [];
        for (const use of Privacy.uses)
            if (use.app.length > 0 && out.indexOf(use.app) < 0)
                out.push(use.app);
        return out.join(" · ");
    }

    // What is drawn while the cell leaves after the last use has gone: kept,
    // so the pill does not empty before it fades — the notification cell's
    // rule.
    property var heldKinds: []
    property string heldNames: ""
    onKindsChanged: if (root.kinds.length > 0) root.heldKinds = root.kinds
    onNamesChanged: if (root.names.length > 0) root.heldNames = root.names
    readonly property var shownKinds: root.kinds.length > 0 ? root.kinds : root.heldKinds
    readonly property string shownNames: root.names.length > 0 ? root.names : root.heldNames

    readonly property real glyphsWidth: root.shownKinds.length * root.glyphSize
                                        + Math.max(0, root.shownKinds.length - 1) * root.glyphGap

    paddingLeading: 12 * metrics.factor
    paddingTrailing: 16 * metrics.factor
    contentWidth: root.glyphsWidth + root.spacing + label.implicitWidth

    readonly property real available: Math.max(0, width - paddingLeading - paddingTrailing
                                                 - root.glyphsWidth - root.spacing)

    headerTitle: "PRIVACY"
    headerMarkSize: root.glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: root.shownKinds.length > 0 ? root.shownKinds[0] : "microphone"
            colour: Theme.active
        }
    }
    replacesContent: true

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("PrivacyPanel.qml")
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
            model: root.shownKinds

            delegate: Icon {
                required property string modelData
                width: root.glyphSize
                height: width
                name: modelData
                colour: Theme.active
            }
        }
    }

    Text {
        id: label
        anchors.left: glyphs.right
        anchors.leftMargin: root.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: root.available
        text: root.shownNames
        elide: Text.ElideRight
        maximumLineCount: 1
        color: Theme.text
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontTitle
    }
}
