pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The keyboard, opened: the layouts there are, and a field that finds more.
//
// With the field empty the well lists what niri has loaded, the active one
// marked; a press switches to it and the cross under the pointer removes it —
// never the last one. Typing turns the well into the catalogue, filtered by
// name or code, and a press adds what was found. One list at a time, in one
// place, because they are the same question: which layouts.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 40 * factor
    readonly property int shownRows: 6

    readonly property real listHeight: root.shownRows * root.rowHeight + 12 * factor

    implicitWidth: 360 * factor
    implicitHeight: root.metrics.fieldHeight + 10 * factor + listHeight
                    + (Keyboard.error.length > 0 ? errorLine.height + 8 * factor : 0)
    width: implicitWidth
    height: implicitHeight

    readonly property string wanted: search.text.trim().toLowerCase()
    readonly property bool finding: root.wanted.length > 0

    // What the catalogue offers for what was typed: a code typed in full comes
    // first, then names that start with it, then names that contain it.
    readonly property var found: {
        if (!root.finding)
            return [];
        const exact = [], starts = [], contains = [];
        for (const entry of Keyboard.catalogue) {
            const name = entry.name.toLowerCase();
            if (entry.layout === root.wanted && entry.variant === "")
                exact.push(entry);
            else if (name.startsWith(root.wanted))
                starts.push(entry);
            else if (name.includes(root.wanted))
                contains.push(entry);
        }
        return exact.concat(starts, contains).slice(0, 60);
    }

    function add(entry) {
        Keyboard.add(entry);
        search.text = "";
    }

    HoverHandler {
        onHoveredChanged: if (root.cell) root.cell.panelHovered = hovered
    }

    // Summoned by a key, the hand is on the keyboard: the field takes it.
    Component.onCompleted: if (root.cell && root.cell.floating) search.forceActiveFocus()
    onCellChanged: if (root.cell && root.cell.floating) search.forceActiveFocus()

    // ---- The field -------------------------------------------------------------

    Item {
        id: head

        width: parent.width
        height: root.metrics.fieldHeight

        TapHandler {
            onTapped: {
                if (root.cell)
                    root.cell.fieldEngaged = true;
                search.forceActiveFocus();
            }
        }

        Icon {
            id: lens
            anchors.left: parent.left
            anchors.leftMargin: 6 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            name: "plus"
            width: 14 * root.factor
            height: width
            gradient: true
        }

        TextInput {
            id: search
            anchors.left: lens.right
            anchors.leftMargin: 10 * root.factor
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
            clip: true

            Keys.onEscapePressed: {
                if (search.text.length > 0) {
                    search.text = "";
                    return;
                }
                if (root.cell)
                    root.cell.open = false;
            }
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onUpPressed: list.decrementCurrentIndex()
            onAccepted: if (root.found.length > 0) root.add(root.found[Math.max(0, list.currentIndex)])

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: "Add a layout"
                color: Theme.textMuted
                font: search.font
            }
        }
    }

    // ---- The list ----------------------------------------------------------------

    Well {
        id: well

        metrics: root.metrics
        y: head.height + 10 * root.factor
        width: parent.width
        height: root.listHeight

        Text {
            anchors.centerIn: parent
            visible: root.finding && root.found.length === 0
            text: "No layout by that name"
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: 6 * root.factor
            anchors.rightMargin: 12 * root.factor
            model: root.finding ? root.found : Keyboard.layouts
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: 0

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool active: !root.finding && row.index === Keyboard.currentIndex
                readonly property bool removable: !root.finding && Keyboard.layouts.length > 1
                                                  && row.modelData.layout.length > 0

                width: ListView.view.width
                height: root.rowHeight

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.shaped(8 * root.factor)
                    color: rowHover.hovered || (root.finding && row.ListView.isCurrentItem)
                           ? Qt.alpha(Theme.text, 0.05) : "transparent"
                }

                // The active layout is marked the way an exclusive choice is
                // everywhere in the shell: a dot.
                Rectangle {
                    id: dot
                    anchors.left: parent.left
                    anchors.leftMargin: 10 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6 * root.factor
                    height: width
                    radius: width / 2
                    visible: row.active
                    color: Theme.primary
                    antialiasing: true
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 26 * root.factor
                    anchors.right: code.left
                    anchors.rightMargin: 10 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: row.active || root.finding ? Theme.text : Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }

                Text {
                    id: code
                    anchors.right: drop.left
                    anchors.rightMargin: 8 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: Keyboard.codeOf(row.modelData)
                          + (row.modelData.variant ? ` · ${row.modelData.variant}` : "")
                    color: Theme.textFaint
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                    })
                }

                Item {
                    id: drop
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: row.removable ? 18 * root.factor : 0
                    height: 18 * root.factor
                    opacity: rowHover.hovered && row.removable ? 1 : 0

                    Icon {
                        anchors.centerIn: parent
                        width: 9 * root.factor
                        height: width
                        name: "close"
                        colour: dropHover.hovered ? Theme.alert : Theme.textMuted
                    }

                    HoverHandler { id: dropHover }
                    TapHandler {
                        enabled: row.removable
                        onTapped: Keyboard.remove(row.index)
                    }
                }

                HoverHandler { id: rowHover }

                TapHandler {
                    onTapped: {
                        if (root.finding)
                            root.add(row.modelData);
                        else
                            Keyboard.switchTo(row.index);
                    }
                }
            }
        }

        Scroller {
            flick: list
            factor: root.factor
            x: well.width - width - 4 * root.factor
        }
    }

    // What niri refused, in its words, under what was asked.
    Text {
        id: errorLine
        anchors.top: well.bottom
        anchors.topMargin: 8 * root.factor
        width: parent.width
        visible: Keyboard.error.length > 0
        text: Keyboard.error
        wrapMode: Text.Wrap
        color: Theme.alert
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontSecondary
    }
}
