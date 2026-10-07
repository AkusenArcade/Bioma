pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The timer cell, opened: what is left, how long, and the two things that
// can be done to it.
//
// The figure is what the wheel turns while the timer is still, a minute a
// notch, as on the clock; the presets set it at a press. START, PAUSE or
// RESUME, as the timer is; STOP ends it and puts it back to its length, and
// the cell goes with it.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    implicitWidth: 280 * factor
    implicitHeight: column.implicitHeight + 28 * factor
    width: implicitWidth
    height: implicitHeight

    function technical(size, weight) {
        return Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": size,
            "weight": weight === undefined ? Typography.weightSecondary : weight
        }));
    }

    function figure(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const rest = seconds % 60;
        const mm = String(minutes).padStart(2, "0");
        const ss = String(rest).padStart(2, "0");
        return hours > 0 ? `${hours}:${mm}:${ss}` : `${mm}:${ss}`;
    }

    Well {
        metrics: root.metrics
        anchors.fill: parent

        Column {
            id: column

            x: 14 * root.factor
            y: 14 * root.factor
            width: parent.width - 28 * root.factor
            spacing: 12 * root.factor

            LitText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.figure(Time.left)
                opacity: Time.running ? 1 : 0.6
                font: root.technical(Math.round(34 * root.factor), Typography.weightValue)

                WheelHandler {
                    enabled: !Time.running && !Time.paused
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => Time.setLength(Time.length + (event.angleDelta.y > 0 ? 60 : -60))
                }
            }

            Row {
                visible: !Time.running && !Time.paused
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6 * root.factor

                Repeater {
                    model: [5, 10, 25, 60]

                    delegate: Item {
                        id: preset

                        required property int modelData
                        readonly property bool lit: Time.length === preset.modelData * 60

                        width: presetText.implicitWidth + 22 * root.factor
                        height: 24 * root.factor

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            antialiasing: true
                            color: preset.lit ? Qt.alpha(Theme.primary, 0.16) : "transparent"
                            border.width: Metrics.rim(Screen.devicePixelRatio)
                            border.color: preset.lit ? Theme.primary : presetHover.hovered ? Theme.text : Theme.line
                        }

                        Text {
                            id: presetText
                            anchors.centerIn: parent
                            text: preset.modelData < 60 ? `${preset.modelData} M` : "1 H"
                            color: preset.lit ? Theme.text : Theme.textMuted
                            font: root.technical(root.metrics.fontMeta)
                        }

                        HoverHandler { id: presetHover }
                        TapHandler { onTapped: Time.setLength(preset.modelData * 60) }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8 * root.factor

                Choice {
                    metrics: root.metrics
                    kind: "primary"
                    label: Time.running ? "PAUSE" : (Time.paused ? "RESUME" : "START")
                    onActivated: Time.running ? Time.pause() : Time.start()
                }

                Choice {
                    visible: Time.running || Time.paused
                    metrics: root.metrics
                    label: "STOP"
                    onActivated: Time.reset()
                }
            }
        }
    }
}
