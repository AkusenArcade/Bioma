import QtQuick
import qs.core

// A family switched on or off: the pill with the knob, in the primary gradient
// when it is on.
//
// It says what the machine is, not what the press did — so it follows the
// value it is given and never moves on its own. A radio takes a moment to
// answer, and for that moment the switch stays where it is and dims: a control
// that snapped to the new state and back would be lying twice.
Item {
    id: root

    property bool on: false
    property bool settling: false
    property real factor: 1

    signal toggled(bool on)

    implicitWidth: 42 * factor
    implicitHeight: 24 * factor

    readonly property real knobSize: 16 * factor

    // What is left over on each side once the knob is in: the knob is round
    // and centred in a pill, so the same distance holds it off the top, the
    // bottom and whichever end it is at.
    readonly property real inset: (root.implicitHeight - knobSize) / 2

    opacity: settling ? 0.6 : 1
    Behavior on opacity { NumberAnimation { duration: Timing.transition } }

    // Off: a dark well with the structural outline. The two states are two
    // surfaces rather than one that changes fill, because one of them carries
    // a gradient and the other a border.
    Rectangle {
        anchors.fill: parent
        radius: Metrics.shaped(height / 2)
        antialiasing: true
        opacity: root.on ? 0 : 1
        color: Qt.alpha(Theme.lift(Theme.background, -0.01), 0.9)
        border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
        border.color: Theme.line

        Behavior on opacity { NumberAnimation { duration: Timing.transition } }
    }

    Rectangle {
        anchors.fill: parent
        radius: Metrics.shaped(height / 2)
        antialiasing: true
        opacity: root.on ? 1 : 0

        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
            GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
        }

        Behavior on opacity { NumberAnimation { duration: Timing.transition } }
    }

    // The knob travels; it does not appear at the other end.
    Rectangle {
        width: root.knobSize
        height: width
        radius: Metrics.shaped(width / 2)
        antialiasing: true
        y: (root.height - height) / 2
        x: root.on ? root.width - width - root.inset : root.inset
        color: root.on ? Theme.background : Qt.alpha(Theme.text, 0.45)

        Behavior on x {
            NumberAnimation {
                duration: Timing.transition
                easing.type: Easing.Bezier
                easing.bezierCurve: Timing.easeOpenFlat
            }
        }

        Behavior on color { ColorAnimation { duration: Timing.transition } }
    }

    TapHandler {
        onTapped: root.toggled(!root.on)
    }
}
