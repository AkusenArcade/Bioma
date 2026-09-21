import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// What is captured above, where it is captured from below.
//
// Two independent choices, never a list of six: three things to capture times
// three places to capture them from is nine labels to read, and the pair is
// what the user is actually holding in their head. The last pair used stays
// selected, so the common case is one press.
//
// The press on a source is the press that acts. There is no confirm button:
// the panel has nothing else in it, and a screenshot tool that asks twice is a
// screenshot tool that is never used.
//
// See docs/design/CELLS.md §06.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property real buttonWidth: 112 * factor
    readonly property real buttonHeight: 92 * factor
    readonly property real buttonGap: 8 * factor
    readonly property real rowGap: 12 * factor

    width: buttonWidth * 3 + buttonGap * 2
    height: kinds.height + rowGap + buttonHeight

    readonly property string what: root.cell ? root.cell.what : "image"
    readonly property string from: root.cell ? root.cell.from : "screen"

    Segmented {
        id: kinds

        anchors.horizontalCenter: parent.horizontalCenter
        metrics: root.metrics
        options: [
            { "key": "image", "label": "Image" },
            { "key": "video", "label": "Video" },
            { "key": "text", "label": "Text" }
        ]
        current: root.what

        // Choosing what to capture does not capture anything: it is the first
        // half of the pair, and the second half is the press that acts.
        onChose: key => Config.set("capture.what", key)
    }

    // The three sources. A pair the machine cannot do is drawn as unavailable
    // rather than offered and then refused — the recorder takes an output or a
    // region and never a window, and text is recognised from a region, which a
    // window does not have here.
    component Source: Item {
        id: source

        property string key: ""
        property string label: ""
        property string icon: ""

        readonly property bool chosen: root.from === source.key
        readonly property bool available: root.cell ? root.cell.supports(root.what, source.key) : true

        width: root.buttonWidth
        height: root.buttonHeight
        opacity: source.available ? 1 : 0.38

        Behavior on opacity { NumberAnimation { duration: Timing.transition } }

        Rectangle {
            anchors.fill: parent
            radius: root.metrics.radiusPanel
            antialiasing: true

            // Chosen, it is a control and carries the primary at a whisper;
            // otherwise it is a well with the outline family around it.
            color: source.chosen ? Qt.alpha(Theme.primary, 0.13)
                                 : Qt.alpha(Theme.lift(Theme.background, -0.01), 0.8)
            border.width: source.chosen ? 0 : Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: Theme.line

            Behavior on color { ColorAnimation { duration: Timing.transition } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 12 * root.factor

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: source.icon
                width: 28 * root.factor
                height: width
                // The icon says what the source is; the gradient says which one
                // is active. An icon never takes a state colour, because it
                // measures nothing.
                gradient: source.chosen
                colour: Qt.alpha(Theme.text, 0.62)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: source.label
                color: Theme.text
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": Math.round(11 * root.factor),
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(Math.round(11 * root.factor), 0.08)
                })
            }
        }

        TapHandler {
            enabled: source.available
            onTapped: if (root.cell) root.cell.capture(root.what, source.key)
        }
    }

    Row {
        anchors.bottom: parent.bottom
        spacing: root.buttonGap

        Source { key: "screen"; label: "SCREEN"; icon: "screen" }
        Source { key: "window"; label: "WINDOW"; icon: "window" }
        Source { key: "region"; label: "REGION"; icon: "region" }
    }
}
