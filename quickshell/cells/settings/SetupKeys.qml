import QtQuick
import qs.core
import qs.components
import qs.services

// The setup's last step: the keys to know.
//
// Bioma says nothing at rest, so someone new does not know where to start.
// Seven keys, read from their own bioma-binds.kdl by the titles niri's hotkey
// overlay shows them under — what is drawn is what is actually bound — and the
// overlay itself for the rest.
//
// See docs/design/SETUP.md, step 7.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    Component.onCompleted: Setup.note("keys", "Seven to start with")

    component Keycap: Rectangle {
        property string label: ""

        width: Math.max(26 * root.factor, capText.implicitWidth + 14 * root.factor)
        height: 26 * root.factor
        radius: 6 * root.factor
        color: "transparent"
        border.width: Metrics.rim(Screen.devicePixelRatio)
        border.color: Theme.line
        antialiasing: true

        Text {
            id: capText
            anchors.centerIn: parent
            text: parent.label
            color: Theme.text
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta, 0.04)
            })
        }
    }

    Column {
        anchors.fill: parent
        spacing: 10 * root.factor

        SetupSection {
            metrics: root.metrics
            label: "TO START WITH"

            Repeater {
                model: Setup.keys

                delegate: Item {
                    id: keyRow

                    required property var modelData

                    width: parent.width
                    height: 28 * root.factor

                    Row {
                        id: caps
                        width: 170 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4 * root.factor

                        Repeater {
                            model: keyRow.modelData.caps

                            delegate: Row {
                                required property string modelData
                                required property int index
                                spacing: 4 * root.factor

                                Text {
                                    visible: index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "+"
                                    color: Theme.textMuted
                                    font.family: Typography.technical
                                    font.pixelSize: root.metrics.fontMeta
                                }

                                Keycap {
                                    label: modelData
                                }
                            }
                        }

                        Text {
                            visible: keyRow.modelData.caps.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "NOT BOUND"
                            color: Theme.textFaint
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                     Typography.labelTracking)
                            })
                        }
                    }

                    Text {
                        anchors.left: caps.right
                        anchors.leftMargin: 12 * root.factor
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: keyRow.modelData.line
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }
                }
            }

            SetupLine {
                metrics: root.metrics
                color: Theme.textMuted
                text: "Every key, at any time: Mod+Shift+/, niri's own list, where each of Bioma's has a title."
            }
        }
    }
}
