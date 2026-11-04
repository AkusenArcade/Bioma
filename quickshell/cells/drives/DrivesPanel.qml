pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The drives cell, opened: each drive on its own row — its name, what is on
// it, whether it is still being written to — with OPEN and EJECT.
//
// Eject is the whole point of the row. It unmounts, which waits for the last
// of the writing, and then cuts the power, so the drive leaves the list when
// it is really safe to pull and not a moment before. While it waits, the row
// says so with the loader where the buttons were; when it cannot — a file
// still open on the stick — it says why, under the row, in the alert colour.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 56 * factor
    readonly property real errorHeight: 22 * factor

    // Kept while the cell closes after the last drive has gone.
    property var rows: []
    readonly property var live: Drives.drives
    onLiveChanged: if (root.live.length > 0) root.rows = root.live
    Component.onCompleted: root.rows = root.live

    implicitWidth: 380 * factor
    implicitHeight: list.height + 12 * factor
    width: implicitWidth
    height: implicitHeight

    Well {
        metrics: root.metrics
        anchors.fill: parent

        Column {
            id: list
            x: 6 * root.factor
            y: 6 * root.factor
            width: parent.width - 12 * root.factor

            Repeater {
                model: root.rows

                delegate: Item {
                    id: row

                    required property var modelData

                    readonly property string doing: Drives.busy[row.modelData.id] || ""
                    readonly property string error: Drives.errors[row.modelData.id] || ""
                    readonly property bool writing: Drives.writing(row.modelData)
                    readonly property bool mounted: Drives.mounted(row.modelData)
                    readonly property var volume: row.modelData.volumes[0] || ({})

                    width: parent.width
                    height: root.rowHeight + (row.error.length > 0 ? root.errorHeight : 0)

                    Behavior on height { NumberAnimation { duration: Timing.transition } }

                    Icon {
                        id: glyph
                        x: 10 * root.factor
                        y: (root.rowHeight - height) / 2
                        width: 20 * root.factor
                        height: width
                        name: "drive"
                        gradient: row.mounted
                        colour: Theme.textMuted
                    }

                    // The drive's name is what was written on it, or what its
                    // maker called it: human language either way.
                    Text {
                        id: name
                        anchors.left: glyph.right
                        anchors.leftMargin: 12 * root.factor
                        anchors.right: actions.left
                        anchors.rightMargin: 10 * root.factor
                        y: 9 * root.factor
                        text: row.volume.label || row.modelData.name
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: Math.round(14 * root.factor)
                    }

                    // Its size and kind, and whether it is mounted — the
                    // machine's own words, in the technical voice. While it is
                    // written to, that is the only thing worth saying, and the
                    // thread beside it says how fast.
                    Text {
                        id: meta
                        anchors.left: name.left
                        y: root.rowHeight - height - 9 * root.factor
                        width: Math.min(implicitWidth, actions.x - 10 * root.factor - x)
                        elide: Text.ElideRight
                        text: row.writing
                              ? `WRITING · ${Drives.bytes(row.modelData.rate)}/S`
                              : [Drives.bytes(Drives.size(row.modelData)),
                                 (row.volume.type || "").toUpperCase(),
                                 row.mounted ? "MOUNTED" : ""]
                                .filter(part => part.length > 0).join(" · ")
                        color: Theme.textMuted
                        font: Typography.tabular(Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "weight": Typography.weightSecondary
                        }))
                    }

                    // Still being written to: the light runs as fast as the
                    // bytes land, and the stick is not to be pulled.
                    RateThread {
                        anchors.left: meta.right
                        anchors.leftMargin: 10 * root.factor
                        anchors.right: actions.left
                        anchors.rightMargin: 10 * root.factor
                        anchors.verticalCenter: meta.verticalCenter
                        visible: row.writing && width > 12 * root.factor
                        rate: row.modelData.rate
                        running: row.writing
                        factor: root.factor
                    }

                    Row {
                        id: actions
                        anchors.right: parent.right
                        anchors.rightMargin: 8 * root.factor
                        y: (root.rowHeight - height) / 2
                        spacing: 8 * root.factor
                        visible: row.doing.length === 0

                        Choice {
                            metrics: root.metrics
                            label: "Open"
                            onActivated: {
                                Drives.open(row.modelData, Proxy.environment);
                                if (root.cell)
                                    root.cell.open = false;
                            }
                        }

                        Choice {
                            metrics: root.metrics
                            label: "Eject"
                            onActivated: Drives.eject(row.modelData)
                        }
                    }

                    // Unmounting waits for the writing to end, and there is no
                    // telling how long that is.
                    Sweep {
                        anchors.right: parent.right
                        anchors.rightMargin: 16 * root.factor
                        y: (root.rowHeight - height) / 2
                        width: 18 * root.factor
                        height: width
                        visible: row.doing.length > 0
                        running: visible
                    }

                    Row {
                        anchors.left: name.left
                        y: root.rowHeight - 4 * root.factor
                        spacing: 8 * root.factor
                        visible: row.error.length > 0

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14 * root.factor
                            height: width
                            name: "error"
                            colour: Theme.alert
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.error
                            color: Theme.alert
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }
                    }
                }
            }
        }
    }
}
