import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// What something else has to say, said once and then let go.
//
// The only cell where **hover is a state** rather than a courtesy: the actions
// live in it, so "interaction suspends disappearance" is not optional here —
// it is what stops a notification with two buttons from vanishing while
// somebody decides which one to press. Time does not run while the pointer is
// on it, and on exit it resumes where it stopped rather than starting again.
//
// At rest it is the icon and one line, in the expressive voice. The body stays
// outside until the pointer comes near, or the membrane becomes a page.
//
// See docs/design/CELLS.md §10, PRD §9.10.
Cell {
    id: root

    domain: "notifications"

    readonly property real iconSize: 20 * metrics.factor
    readonly property real spacing: 10 * metrics.factor

    paddingLeading: 10 * metrics.factor
    paddingTrailing: 14 * metrics.factor

    readonly property var shout: Notifications.current
    readonly property bool flooding: Notifications.flooding && Notifications.current === null

    // A cell exists when it has something to say, and this one has something
    // to say only when something happened.
    condition: Notifications.present ? 1 : 0

    // Urgency is an outline, never a fill: a red surface would make the text
    // unreadable and the shell look broken, and the outline is where Bioma
    // already puts light.
    readonly property bool critical: Notifications.isCritical(root.shout)

    // The title is a line of somebody's language, which is why this cell is
    // the second exception to the silence rule — without it a notification is
    // nothing. A flood is a count instead, and a count is a measurement.
    readonly property string line: root.flooding
        ? `${Notifications.collapsed} notifications`
        : (root.shout ? (root.shout.summary || root.shout.appName || "") : "")

    contentWidth: iconSize + spacing + label.implicitWidth

    readonly property real available: Math.max(0, width - paddingLeading - paddingTrailing
                                                 - iconSize - spacing)

    // ---- Time ---------------------------------------------------------------
    //
    // The pointer stops the clock — see `onHoveredChanged` below. The service
    // keeps the remainder, because it owns the queue and the cell is only
    // where it is being read.

    // ---- Open ---------------------------------------------------------------
    //
    // Two different things hang under this cell, and which one depends on how
    // it was asked. The pointer brings the body and the actions; a press
    // brings the history, and only that press is the shell's attention being
    // claimed — a body appearing under the pointer is not.

    property bool history: false

    claimsFocus: root.history
    opensOnTap: false

    // `open` is set rather than bound. A press outside closes a cell by
    // assigning to it, and an assignment onto a binding destroys the binding —
    // the cell would open once and never again.
    function settle() {
        root.open = root.history || (root.hovered && root.shout !== null);
    }

    onHoveredChanged: {
        Notifications.holding = root.hovered;
        root.settle();
    }

    onHistoryChanged: root.settle()
    onShoutChanged: root.settle()

    onOpenChanged: if (!root.open) root.history = false

    TapHandler {
        onTapped: root.history = !root.history
    }

    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("NotificationExpansion.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
    }

    // ---- Contracted ---------------------------------------------------------

    // The urgent outline, over the cell's own rim.
    Rectangle {
        anchors.fill: parent
        visible: root.critical
        radius: root.radius
        color: "transparent"
        border.width: Metrics.crisp(1.5 * root.metrics.factor, Screen.devicePixelRatio)
        border.color: Theme.alert
        antialiasing: true
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing

        Item {
            id: badge
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: width

            readonly property string source: root.flooding ? "" : Notifications.iconFor(root.shout)

            Image {
                anchors.fill: parent
                visible: badge.source !== ""
                source: badge.source
                sourceSize.width: Math.round(parent.width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(parent.height * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            // A flood is the shell speaking about itself, so it takes the
            // shell's own glyph rather than an application's.
            Icon {
                anchors.centerIn: parent
                visible: badge.source === ""
                width: parent.width * 0.9
                height: width
                name: "bell"
                colour: root.critical ? Theme.alert : Theme.textMuted
            }
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: root.available
            elide: Text.ElideRight
            maximumLineCount: 1
            text: root.line
            color: Theme.text
            // A count is a measurement and a title is a sentence, and the two
            // voices never swap.
            font.family: root.flooding ? Typography.technical : Typography.expressive
            font.pixelSize: root.metrics.fontTitle
        }
    }
}
