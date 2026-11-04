pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The privacy cell, opened: each use on its own row — what is being taken,
// by whom, and from which device or output.
//
// Nothing here can be pressed. The shell cannot take a microphone back from
// an application; the application's own controls can, and the row says
// which application to go to.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 40 * factor

    // Kept while the cell closes after the last use has gone.
    property var rows: []
    readonly property var live: Privacy.uses
    onLiveChanged: if (root.live.length > 0) root.rows = root.live
    Component.onCompleted: root.rows = root.live

    readonly property var words: ({
        "microphone": "MICROPHONE",
        "camera": "CAMERA",
        "screen": "SCREEN"
    })

    implicitWidth: 360 * factor
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

                    Icon {
                        id: glyph
                        x: 8 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.factor
                        height: width
                        name: row.modelData.kind
                        colour: Theme.active
                    }

                    Column {
                        anchors.left: glyph.right
                        anchors.leftMargin: 12 * root.factor
                        anchors.right: parent.right
                        anchors.rightMargin: 8 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * root.factor

                        Text {
                            width: parent.width
                            text: row.modelData.app
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: Math.round(14 * root.factor)
                        }

                        Text {
                            width: parent.width
                            text: root.words[row.modelData.kind]
                                  + (row.modelData.detail.length > 0 ? " · " + row.modelData.detail.toUpperCase() : "")
                            elide: Text.ElideRight
                            color: Theme.textMuted
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                            })
                        }
                    }
                }
            }
        }
    }
}
