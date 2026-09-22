import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The list of this monitor's workspaces, hung under the cell.
//
// Buttons left, names right: the button column reads at a glance — how many
// there are and where you are — and the names stay outside it, where they can
// be long without deforming anything. The number is machine and sits in the
// button in the technical face; the name is human and sits beside it in the
// expressive one. Two languages, kept apart in space as well.
//
// See docs/design/CELLS.md §03.
Item {
    id: root

    // Assigned after loading rather than required: a cell's own files are not
    // a QML module, so the panel arrives through a Loader.
    property string output: ""
    property var metrics: Metrics.step("normal")

    signal jumped()

    readonly property real rowHeight: 44 * metrics.factor
    readonly property real buttonSize: 36 * metrics.factor
    readonly property real rowPadding: 8 * metrics.factor
    readonly property int visibleRows: 5

    readonly property var list: {
        Niri.workspaceList;
        return Niri.workspacesForOutput(root.output);
    }

    // The panel is 236 wide and pads its content by 10 on each side.
    implicitWidth: 216 * metrics.factor
    implicitHeight: Math.min(Math.max(list.length, 1), visibleRows) * rowHeight

    // A name is the user's own word for the workspace. Without one, the window
    // it is showing says more than "Workspace 4" would beside a button with a
    // 4 in it.
    function describe(workspace) {
        if (workspace.name)
            return workspace.name;
        const window = Niri.windows[workspace.activeWindowId];
        return window && window.title ? window.title : "";
    }

    Well {
        id: well
        anchors.fill: parent
        metrics: root.metrics

        ListView {
            id: view
            anchors.fill: parent
            model: root.list
            boundsBehavior: Flickable.StopAtBounds
            // Past five rows it scrolls, and the active workspace stays inside.
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            currentIndex: {
                for (let i = 0; i < root.list.length; i++)
                    if (root.list[i].isActive)
                        return i;
                return 0;
            }

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool active: modelData.isActive
                readonly property string label: root.describe(modelData)
                // niri always keeps one empty workspace at the end. It is a
                // place, not a content.
                readonly property bool vacant: !modelData.name && modelData.activeWindowId < 0

                width: view.width
                height: root.rowHeight

                TapHandler {
                    // Jump and close: the action is done, and staying open
                    // would be noise.
                    onTapped: {
                        Niri.focusWorkspace(row.modelData.idx);
                        root.jumped();
                    }
                }

                Item {
                    id: button
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.rowPadding
                    width: root.buttonSize
                    height: root.buttonSize

                    // Three states, and they are shapes rather than colours:
                    // filled for where you are, a drawn ring for a workspace
                    // with something on it, a dashed one for the free place.
                    Disc {
                        anchors.fill: parent
                        visible: row.active
                    }

                    Ring {
                        anchors.fill: parent
                        visible: !row.active && !row.vacant
                        radius: width / 2
                        thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                        colour: Theme.line
                    }

                    DashedRing {
                        anchors.fill: parent
                        visible: row.vacant && !row.active
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(row.modelData.idx)
                        color: row.active ? Theme.background
                             : row.vacant ? Qt.alpha(Theme.text, 0.3)
                             : Qt.alpha(Theme.text, 0.72)
                        font: Typography.tabular(Qt.font({
                            "family": Typography.technical,
                            "pixelSize": Math.round(14 * root.metrics.factor),
                            "weight": row.active ? Font.DemiBold : Typography.weightValue
                        }))
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: button.x + button.width + 12 * root.metrics.factor
                    width: Math.max(0, view.width - x - root.rowPadding)
                    text: row.label || "empty"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: row.label ? (row.active ? Theme.text : Qt.alpha(Theme.text, 0.5))
                                     : Qt.alpha(Theme.text, 0.28)
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(14 * root.metrics.factor)
                    font.italic: !row.label
                }
            }
        }

        Scroller {
            flick: view
            factor: root.metrics.factor
            x: well.width - width - 4 * root.metrics.factor
        }
    }
}
