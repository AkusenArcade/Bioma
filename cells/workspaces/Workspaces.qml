import QtQuick
import Quickshell
import qs.core
import qs.structure
import qs.services
import qs.components

// The workspace this monitor is on.
//
// One cell per monitor, each listing its own screen — decided against PRD §9.3:
// grouping every screen into one cell would force labelling the groups, and a
// label says worse what position already says.
//
// At rest it is the mark and a name: the workspace's own name in the expressive
// face, because a name is human language, and its number in the technical one
// when it has none. The width changes only when the workspace changes.
//
// See docs/design/CELLS.md §03.
Cell {
    id: root

    domain: "workspaces"

    paddingLeading: 16
    paddingTrailing: 16

    readonly property real spacing: 11 * metrics.factor
    readonly property real markSize: 16 * metrics.factor

    // Reading the list inside the call is what binds this to the compositor:
    // the service fills its models on first binding, never on first access.
    readonly property var workspace: {
        Niri.workspaceList;
        return Niri.activeWorkspaceForOutput(root.output);
    }

    // Conditional, it is there for a moment after the workspace changes —
    // told by its id, because the service hands out a fresh object on every
    // event and a new object is not a new workspace.
    readonly property var workspaceId: workspace ? workspace.id : -1
    onWorkspaceIdChanged: root.pulse()
    condition: root.pulsing ? 1 : 0

    readonly property bool named: workspace && workspace.name
    readonly property string label: workspace ? (workspace.name || String(workspace.idx)) : ""

    // Open, the capsule stops naming the workspace and names itself: the cell
    // is the title of the list hanging under it, so it takes the technical
    // face — a label, not a name.
    headerTitle: "WORKSPACES"
    headerMarkSize: markSize
    headerMark: Component {
        WorkspaceBars {
            anchors.fill: parent
        }
    }

    contentWidth: markSize + spacing + (named ? name.implicitWidth : number.implicitWidth)
    readonly property real available: Math.max(0, width - paddingLeading - paddingTrailing - markSize - spacing)

    // ---- The confirmation -------------------------------------------------
    //
    // Even when nothing touched the cell, the mark steps in the direction of
    // the jump. It is the answer to a keyboard shortcut, for someone whose eye
    // was not on the membrane.

    property int lastIndex: -1

    onWorkspaceChanged: {
        if (!workspace)
            return;
        if (lastIndex >= 0 && workspace.idx !== lastIndex)
            mark.shift(workspace.idx > lastIndex ? 1 : -1);
        lastIndex = workspace.idx;
    }

    // ---- Interaction ------------------------------------------------------

    // The panel's content lives in its own file beside this one, and arrives
    // through a Loader: Quickshell generates no QML module for a cell's own
    // directory, so a sibling type cannot be imported — but a URL resolved
    // against this file can be loaded.
    panel: Component {
        Loader {
            id: listLoader
            source: Qt.resolvedUrl("WorkspaceList.qml")

            onLoaded: {
                item.output = Qt.binding(() => root.output);
                item.metrics = Qt.binding(() => root.metrics);
            }

            Connections {
                target: listLoader.item
                function onJumped() { root.open = false; }
            }
        }
    }

    WheelHandler {
        // Previous and next workspace without opening anything.
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y > 0)
                Niri.focusWorkspaceUp();
            else if (event.angleDelta.y < 0)
                Niri.focusWorkspaceDown();
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing

        WorkspaceBars {
            id: mark
            anchors.verticalCenter: parent.verticalCenter
            width: root.markSize
            height: root.markSize
        }

        // A name is human language and takes the expressive face; a number is
        // the machine's own count and takes the technical one. They never swap.
        Text {
            id: name
            anchors.verticalCenter: parent.verticalCenter
            visible: root.named
            text: root.label
            width: root.available
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
        }

        Text {
            id: number
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.named
            text: root.label
            color: Theme.text
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontLabel,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
            }))
        }
    }
}
