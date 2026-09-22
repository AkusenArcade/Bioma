import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Two things hang under this cell, and never both.
//
// The pointer brings **the notification**: the application in the machine's
// voice, the title and the body in the human one, and the actions it carries.
// A press brings **the history**: what has been said, grouped by application,
// most recent first — people come back looking for "that browser thing", not
// "that 14:32 thing" — and do-not-disturb lives there rather than in settings,
// because that is where somebody is looking when notifications are bothering
// them.
//
// See docs/design/CELLS.md §10.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property bool history: root.cell ? root.cell.history : false
    readonly property var shout: Notifications.current

    readonly property real panelWidth: 340 * factor
    readonly property real padding: 14 * factor
    readonly property real rowHeight: 38 * factor
    readonly property real actionHeight: 26 * factor

    // At most three actions: past that the first two and the rest belong to
    // the history, because a row of five buttons is a dialog.
    readonly property var actions: {
        const carried = root.shout && root.shout.actions ? root.shout.actions : [];
        return carried.length > 3 ? carried.slice(0, 2) : carried;
    }

    // ---- What the body needs -------------------------------------------------

    TextMetrics {
        id: titleMetrics
        text: root.shout ? (root.shout.summary || "") : ""
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontTitle
    }

    readonly property real bodyWidth: panelWidth - padding * 2
    readonly property real bodyHeight: bodyText.implicitHeight

    readonly property real notifyHeight: padding * 2 + appLine.height + 4 * factor
                                       + titleMetrics.height + (root.bodyHeight > 0
                                                                ? root.bodyHeight + 6 * factor : 0)
                                       + (root.actions.length > 0
                                          ? root.actionHeight + 10 * factor : 0)

    // ---- What the history needs ----------------------------------------------

    readonly property int shownRows: 7
    readonly property real headerHeight: 34 * factor

    // The well and the list inside it have margins of their own, and the rows
    // are grouped by application — a label every few rows. Counting the rows
    // alone gave a panel that held five of the seven it promised, with nothing
    // left to scroll in. All of it is counted here, and the same figures are
    // what the well and the list are drawn with.
    readonly property real wellInset: 10 * factor
    readonly property real listMargin: 8 * factor
    readonly property real sectionHeight: 20 * factor
    readonly property int shownSections: 2

    readonly property real historyHeight: padding * 2 + headerHeight + 8 * factor
                                        + wellInset * 2 + listMargin * 2
                                        + Math.max(1, Math.min(Notifications.history.length,
                                                               root.shownRows)) * rowHeight
                                        + root.shownSections * root.sectionHeight
                                        + 8 * factor

    readonly property real panelHeight: root.history ? root.historyHeight : root.notifyHeight

    readonly property real gap: metrics.gap
    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    implicitWidth: panelWidth
    implicitHeight: panelHeight

    width: implicitWidth
    height: implicitHeight

    // ---- The shape -----------------------------------------------------------

    Panel {
        id: panel

        metrics: root.metrics
        padding: root.padding
        targetWidth: root.panelWidth
        targetHeight: root.panelHeight
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        anchorX: 0
        anchorY: 0
        nodeX: root.width / 2
        nodeY: root.upward ? root.height : 0

        // The one urgent outline in the shell that is not a cell's: a critical
        // notification's body is as urgent as its title.
        Rectangle {
            parent: panel
            anchors.fill: parent
            visible: !root.history && Notifications.isCritical(root.shout)
            radius: panel.radius
            color: "transparent"
            border.width: Metrics.crisp(1.5 * root.factor, Screen.devicePixelRatio)
            border.color: Theme.alert
            antialiasing: true
        }

        // ---- The notification ------------------------------------------------

        Item {
            anchors.fill: parent
            visible: !root.history

            // Who is speaking, in the machine's voice: it is a name the system
            // knows, not a sentence somebody wrote.
            Text {
                id: appLine
                anchors.left: parent.left
                anchors.top: parent.top
                text: root.shout ? (root.shout.appName || "") : ""
                color: Theme.textFaint
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                         Typography.labelTracking)
                })
            }

            Text {
                id: titleText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: appLine.bottom
                anchors.topMargin: 4 * root.factor
                text: root.shout ? (root.shout.summary || "") : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontTitle
            }

            // Three lines and then an ellipsis: the rest is in the history,
            // and a membrane is not a page.
            Text {
                id: bodyText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: titleText.bottom
                anchors.topMargin: 6 * root.factor
                visible: text.length > 0
                text: root.shout ? (root.shout.body || "") : ""
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 3
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
                lineHeight: 19 / 13.5
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 8 * root.factor
                visible: root.actions.length > 0

                Repeater {
                    model: root.actions

                    delegate: Item {
                        id: act

                        required property var modelData

                        width: actText.implicitWidth + 28 * root.factor
                        height: root.actionHeight

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            color: "transparent"
                            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                            border.color: Theme.line
                            antialiasing: true
                        }

                        // An action's label was written by the application, so
                        // it is human language whatever it says.
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: act.modelData.text || act.modelData.identifier
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        TapHandler {
                            onTapped: Notifications.invoke(act.modelData)
                        }
                    }
                }
            }
        }

        // ---- The history -----------------------------------------------------

        Item {
            anchors.fill: parent
            visible: root.history

            Text {
                id: historyLabel
                anchors.left: parent.left
                anchors.verticalCenter: quiet.verticalCenter
                text: "HISTORY"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontLabel,
                                                         Typography.labelTracking)
                })
            }

            // Do not disturb, where it is looked for, and said in a word:
            // beside a bare "Clear" the switch read as the control *for* it.
            Switch {
                id: quiet
                anchors.right: parent.right
                anchors.top: parent.top
                factor: root.factor
                on: Notifications.quiet
                onToggled: value => Notifications.setQuiet(value)
            }

            Text {
                id: quietLabel

                anchors.right: quiet.left
                anchors.rightMargin: 8 * root.factor
                anchors.verticalCenter: quiet.verticalCenter
                text: "QUIET"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                         Typography.labelTracking)
                })
            }

            // Emptying the history is an **action**, so it wears the shape of
            // one. As a bare word beside a switch it was taken for the
            // switch's label — Akusen, 2026-09-22.
            Item {
                id: clear

                readonly property real inset: 9 * root.factor
                // Orbitron paints a little wider than it measures at this
                // size; the trailing margin carries the difference.
                readonly property real tail: 5 * root.factor

                anchors.right: quietLabel.left
                anchors.rightMargin: 14 * root.factor
                anchors.verticalCenter: quiet.verticalCenter
                visible: Notifications.history.length > 0
                width: clear.inset * 2 + clearLabel.implicitWidth + clear.tail
                height: 22 * root.factor

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusFor(height, root.metrics)
                    antialiasing: true
                    color: clearHover.hovered ? Qt.alpha(Theme.text, 0.08) : "transparent"
                    border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                    border.color: clearHover.hovered ? Theme.text : Theme.line
                }

                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "CLEAR"
                    color: clearHover.hovered ? Theme.text : Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }

                HoverHandler { id: clearHover }

                TapHandler {
                    onTapped: Notifications.forget()
                }
            }

            Well {
                id: well

                metrics: root.metrics
                inset: root.wellInset
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: quiet.bottom
                anchors.topMargin: 8 * root.factor
                anchors.bottom: parent.bottom

                Text {
                    anchors.centerIn: parent
                    visible: Notifications.history.length === 0
                    text: "Nothing has been said"
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }

                ListView {
                    id: past

                    anchors.fill: parent
                    anchors.margins: root.listMargin
                    model: Notifications.history
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    // Grouped by application: the label appears on the first
                    // of a run rather than on every row, so a burst from one
                    // application reads as one block.
                    section.property: "appName"
                    section.criteria: ViewSection.FullString
                    section.delegate: Text {
                        required property string section

                        width: ListView.view.width
                        height: root.sectionHeight
                        verticalAlignment: Text.AlignVCenter
                        text: section
                        color: Theme.textFaint
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "weight": Typography.weightLabel,
                            "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                 Typography.labelTracking)
                        })
                    }

                    delegate: Item {
                        id: entry

                        required property var modelData

                        width: ListView.view.width
                        height: root.rowHeight

                        Text {
                            id: when
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notifications.since(entry.modelData.at)
                            color: Theme.textMuted
                            font: Typography.tabular(Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta
                            }))
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: when.left
                            anchors.rightMargin: 10 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.summary || entry.modelData.body || ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }
                    }
                }
            }
        }
    }

    function shapes() {
        return [{ "item": panel, "radius": panel.radius }];
    }
}
