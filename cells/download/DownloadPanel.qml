pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The download cell, opened: each download on its own row — its name, its
// own thread running at its own speed, and the figures: how much has come,
// and how fast. A press shows the file where it is being written.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 52 * factor

    // Kept while the cell closes after the last download has finished.
    property var rows: []
    readonly property var live: Downloads.files
    onLiveChanged: if (root.live.length > 0) root.rows = root.live
    Component.onCompleted: root.rows = root.live

    implicitWidth: 340 * factor
    implicitHeight: Math.max(1, root.rows.length) * root.rowHeight + 12 * factor
    width: implicitWidth
    height: implicitHeight

    Well {
        metrics: root.metrics
        anchors.fill: parent

        Column {
            x: 6 * root.factor
            y: 6 * root.factor
            width: parent.width - 12 * root.factor

            Repeater {
                model: root.rows

                delegate: Item {
                    id: row

                    required property var modelData

                    width: parent.width
                    height: root.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: 10 * root.factor
                        color: hover.hovered ? Qt.alpha(Theme.primary, 0.08) : "transparent"
                    }

                    Text {
                        id: name
                        x: 10 * root.factor
                        y: 8 * root.factor
                        width: parent.width - 20 * root.factor
                        text: row.modelData.name
                        elide: Text.ElideMiddle
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: Math.round(14 * root.factor)
                    }

                    RateThread {
                        id: thread
                        x: 10 * root.factor
                        anchors.verticalCenter: figures.verticalCenter
                        width: parent.width - 30 * root.factor - figures.width
                        rate: row.modelData.rate
                        factor: root.factor
                    }

                    Text {
                        id: figures
                        anchors.right: parent.right
                        anchors.rightMargin: 10 * root.factor
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8 * root.factor
                        text: `${Downloads.bytes(row.modelData.size)} · ${row.modelData.rate >= 1024 ? Downloads.bytes(row.modelData.rate) + "/S" : "STALLED"}`
                        color: Theme.textMuted
                        font: Typography.tabular(Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "weight": Typography.weightSecondary
                        }))
                    }

                    HoverHandler { id: hover }
                    TapHandler { onTapped: Files.reveal(row.modelData.path) }
                }
            }
        }
    }
}
