import QtQuick
import qs.core

// A segmented control: two or three options, one of them chosen.
//
// The selection **slides** to the chosen option with the opening timings. It
// does not vanish on one side and appear on the other — that, the switch's knob
// and the slider's travel are the only movements in the shell that answer a
// gesture, and without them the interface looks broken rather than restrained.
//
// The chosen option carries the primary gradient and takes the colour of the
// fill it sits on. It is a control, not a surface: it never takes the rim.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    // [{ "key": "image", "label": "Image" }, …]
    //
    // An option may carry `"dimmed": true`: it stays in the track, at faint
    // weight, and does not answer a press. A choice a thing cannot make is
    // shown rather than removed — seeing that the window title is only ever
    // conditional teaches how the shell is built (CELLS §12).
    property var options: []
    property string current: ""

    signal chose(string key)

    readonly property real factor: metrics.factor

    property int fontSize: Math.round(12 * factor)
    property real buttonHeight: 26 * factor
    property real buttonPadding: 14 * factor
    property real trackPadding: 3 * factor
    property real spacing: 2 * factor

    implicitWidth: track.width
    implicitHeight: track.height

    // Every option is measured at the weight the chosen one uses, so the pill
    // does not resize itself on selection: that would be a second animation
    // over the one meant to be seen.
    readonly property var buttonFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.fontSize,
        "weight": Typography.weightTitle,
        "letterSpacing": Typography.tracking(root.fontSize, 0.04)
    })

    Rectangle {
        id: track

        width: buttons.width + root.trackPadding * 2
        height: root.buttonHeight + root.trackPadding * 2
        radius: Metrics.radiusFor(height, root.metrics)
        antialiasing: true

        color: Qt.alpha(Theme.lift(Theme.background, -0.01), 0.8)
        border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
        border.color: Theme.line

        Rectangle {
            id: selection

            readonly property int index: {
                for (let i = 0; i < root.options.length; i++)
                    if (root.options[i].key === root.current)
                        return i;
                return -1;
            }

            readonly property Item chosenItem: selection.index >= 0 && selection.index < buttonList.count
                                               ? buttonList.itemAt(selection.index) : null

            x: root.trackPadding + (selection.chosenItem ? selection.chosenItem.x : 0)
            y: root.trackPadding
            width: selection.chosenItem ? selection.chosenItem.width : 0
            height: root.buttonHeight
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            visible: width > 0

            gradient: Gradient {
                GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
            }

            Behavior on x {
                NumberAnimation {
                    duration: Timing.transition
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Timing.easeOpenFlat
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: Timing.transition
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Timing.easeOpenFlat
                }
            }
        }

        Row {
            id: buttons
            x: root.trackPadding
            y: root.trackPadding
            spacing: root.spacing

            Repeater {
                id: buttonList
                model: root.options

                delegate: Item {
                    id: button

                    required property var modelData

                    readonly property bool chosen: button.modelData.key === root.current
                    readonly property bool dimmed: button.modelData.dimmed === true

                    width: label.implicitWidth + root.buttonPadding * 2
                    height: root.buttonHeight

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: button.modelData.label
                        color: button.chosen ? Theme.background
                             : button.dimmed ? Theme.textFaint : Theme.textMuted
                        font: root.buttonFont
                    }

                    TapHandler {
                        enabled: !button.dimmed
                        onTapped: root.chose(button.modelData.key)
                    }
                }
            }
        }
    }
}
