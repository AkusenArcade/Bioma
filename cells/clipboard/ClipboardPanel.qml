pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The clipboard, opened: a filter, then what was copied, newest first. Text is
// shown as its first words in Spectral — it is somebody's language — and an
// image as itself, small; how long ago in Orbitron, beside it. A press puts it
// back and closes the cell; the cross under the pointer drops one; CLEAR drops
// them all.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 48 * factor
    readonly property real imageRow: 72 * factor
    readonly property int shownRows: 7

    implicitWidth: 380 * factor
    implicitHeight: root.metrics.fieldHeight + 10 * factor + listHeight
    width: implicitWidth
    height: implicitHeight

    readonly property real listHeight: root.shownRows * root.rowHeight + 12 * factor

    SystemClock {
        id: now
        precision: SystemClock.Minutes
    }

    readonly property var shown: {
        const wanted = filter.text.trim().toLowerCase();
        if (wanted.length === 0)
            return Clipboard.entries;
        return Clipboard.entries.filter(e => !Clipboard.isImage(e)
                                             && String(e.preview).toLowerCase().includes(wanted));
    }

    function choose(entry) {
        Clipboard.restore(entry);
        if (root.cell) {
            root.cell.open = false;
            root.cell.visibility.invoked = false;
        }
    }

    HoverHandler {
        onHoveredChanged: if (root.cell) root.cell.panelHovered = hovered
    }

    // Summoned by a key, the hand is on the keyboard: the filter takes it.
    Component.onCompleted: if (root.cell && root.cell.floating) filter.forceActiveFocus()
    onCellChanged: if (root.cell && root.cell.floating) filter.forceActiveFocus()

    // ---- The filter ----------------------------------------------------------

    Item {
        id: head

        width: parent.width
        height: root.metrics.fieldHeight

        TapHandler {
            onTapped: {
                if (root.cell)
                    root.cell.fieldEngaged = true;
                filter.forceActiveFocus();
            }
        }

        Icon {
            id: lens
            anchors.left: parent.left
            anchors.leftMargin: 6 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            width: 16 * root.factor
            height: width
            gradient: true
        }

        TextInput {
            id: filter
            anchors.left: lens.right
            anchors.leftMargin: 10 * root.factor
            anchors.right: clear.left
            anchors.rightMargin: 12 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
            clip: true

            Keys.onEscapePressed: {
                if (filter.text.length > 0) {
                    filter.text = "";
                    return;
                }
                if (root.cell)
                    root.cell.open = false;
            }
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onUpPressed: list.decrementCurrentIndex()
            onAccepted: if (root.shown.length > 0) root.choose(root.shown[Math.max(0, list.currentIndex)])

            Text {
                anchors.fill: parent
                visible: filter.text === ""
                text: "Search what was copied"
                color: Theme.textMuted
                font: filter.font
            }
        }

        // Dropping everything asks, by asking again.
        Item {
            id: clear

            property bool armed: false

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: clearText.implicitWidth + 22 * root.factor
            height: 24 * root.factor
            visible: Clipboard.entries.length > 0

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusFor(height, root.metrics)
                antialiasing: true
                color: clear.armed ? Qt.alpha(Theme.alert, 0.16) : "transparent"
                border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                border.color: clear.armed ? Theme.alert : clearHover.hovered ? Theme.text : Theme.line
            }

            Text {
                id: clearText
                anchors.centerIn: parent
                text: clear.armed ? "CLEAR ALL?" : "CLEAR"
                color: clear.armed ? Theme.alert : Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                })
            }

            HoverHandler {
                id: clearHover
                onHoveredChanged: if (!hovered) clear.armed = false
            }

            TapHandler {
                onTapped: {
                    if (!clear.armed) {
                        clear.armed = true;
                        return;
                    }
                    clear.armed = false;
                    Clipboard.clear();
                }
            }
        }
    }

    // ---- What was copied -------------------------------------------------------

    Well {
        id: well

        metrics: root.metrics
        y: head.height + 10 * root.factor
        width: parent.width
        height: root.listHeight

        Text {
            anchors.centerIn: parent
            visible: root.shown.length === 0
            text: Clipboard.entries.length === 0 ? "Nothing copied yet" : "Nothing like that"
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: 6 * root.factor
            anchors.rightMargin: 12 * root.factor
            model: root.shown
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            currentIndex: 0

            delegate: Item {
                id: entry

                required property var modelData
                required property int index

                readonly property bool image: Clipboard.isImage(entry.modelData)
                readonly property bool current: ListView.isCurrentItem

                width: ListView.view.width
                height: entry.image ? root.imageRow : root.rowHeight

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.shaped(8 * root.factor)
                    color: entryHover.hovered || entry.current ? Qt.alpha(Theme.text, 0.05) : "transparent"
                }

                // An image, as itself: it is the owner's picture, so it is not
                // tinted, only shown small.
                Image {
                    id: picture
                    visible: entry.image
                    anchors.left: parent.left
                    anchors.leftMargin: 8 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.imageRow - 12 * root.factor
                    width: height * 1.6
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: entry.image ? "file://" + entry.modelData.file : ""
                    sourceSize.height: height * Screen.devicePixelRatio
                    horizontalAlignment: Image.AlignLeft
                }

                Text {
                    anchors.left: entry.image ? picture.right : parent.left
                    anchors.leftMargin: 10 * root.factor
                    anchors.right: meta.left
                    anchors.rightMargin: 10 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.image ? "" : entry.modelData.preview
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }

                Text {
                    id: meta
                    anchors.right: drop.left
                    anchors.rightMargin: 8 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        now.minutes;
                        return Clipboard.age(entry.modelData, Date.now());
                    }
                    color: Theme.textFaint
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                    }))
                }

                Item {
                    id: drop
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18 * root.factor
                    height: width
                    opacity: entryHover.hovered ? 1 : 0

                    Icon {
                        anchors.centerIn: parent
                        width: 9 * root.factor
                        height: width
                        name: "close"
                        colour: dropHover.hovered ? Theme.alert : Theme.textMuted
                    }

                    HoverHandler { id: dropHover }
                    TapHandler { onTapped: Clipboard.remove(entry.modelData) }
                }

                HoverHandler { id: entryHover }

                TapHandler {
                    onTapped: root.choose(entry.modelData)
                }
            }
        }

        Scroller {
            flick: list
            factor: root.factor
            x: well.width - width - 4 * root.factor
        }
    }
}
