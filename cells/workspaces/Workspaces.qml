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

    readonly property bool named: workspace && workspace.name
    readonly property string label: workspace ? (workspace.name || String(workspace.idx)) : ""

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

    TapHandler {
        // TODO Phase 2: opens the list downward, aligned left — a panel hung on
        // a 24 px thread from the cell's centre. The expansion machinery is
        // written but no cell has opened yet; this is the first that will.
        onTapped: root.open = !root.open
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
