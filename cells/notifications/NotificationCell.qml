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
    readonly property real closeSize: 14 * metrics.factor

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

    contentWidth: iconSize + spacing + label.implicitWidth + spacing + closeSize

    readonly property real available: Math.max(0, width - paddingLeading - paddingTrailing
                                                 - iconSize - spacing
                                                 - spacing - closeSize)

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

    // A critical notification has no clock, so there has to be a way to say
    // "read". The middle button is that way here, as it is everywhere else in
    // the shell: the gesture that acts without opening anything. It is the
    // whole pill, which is why it is the cell's and not the content's.
    acceptsMiddle: true
    onMiddleTapped: Notifications.dismiss()

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

    // Urgency is an outline, and the cell draws it on its own shape.
    outline: root.critical ? Theme.alert : "transparent"

    // ---- Contracted ---------------------------------------------------------

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing

        Item {
            id: badge
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: width

            readonly property string wanted: root.flooding ? "" : Notifications.iconFor(root.shout)

            // An icon that resolves to a path and then fails to load is worse
            // than none: what is drawn is the loader's own missing-texture
            // square. The glyph takes over the moment the image gives up.
            property bool broken: false
            readonly property string source: badge.broken ? "" : badge.wanted

            onWantedChanged: badge.broken = false

            Image {
                anchors.fill: parent
                visible: badge.source !== ""
                source: badge.source
                onStatusChanged: if (status === Image.Error) badge.broken = true
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

    // The way out, always there. A notification that can only be answered by
    // a gesture nobody told you about is a notification you cannot put down —
    // the middle button does the same thing, and this is the one you can see.
    // Akusen's call, 2026-09-22.
    Item {
        id: close

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.closeSize
        height: width

        Icon {
            anchors.fill: parent
            name: "close"
            colour: shut.containsMouse ? Theme.text : Theme.textFaint
        }

        // A mouse area rather than a handler, because this one has to *take*
        // the press: a tap handler here would dismiss the notification and
        // let the press through to the cell underneath, which would open the
        // history of a notification that had just gone.
        MouseArea {
            id: shut
            anchors.fill: parent
            anchors.margins: -4 * root.metrics.factor
            hoverEnabled: true
            onClicked: Notifications.dismiss()
        }
    }
}
