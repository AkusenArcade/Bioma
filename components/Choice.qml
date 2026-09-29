import QtQuick
import qs.core

// A button: the word a command answers to, in a capsule.
//
// A control is the machine's vocabulary, so its label takes the technical
// voice whatever it says — even when the application wrote it, as a
// notification's actions are. The question beside it is addressed to a
// person and stays in the human voice; the answers are commands.
//
// Three kinds, and the fill says which. `plain` is an outline: the way back
// out, or one of several equal choices. `primary` is filled in the primary
// gradient: the choice that keeps something. `alert` is filled red, and only
// on the button that performs a loss — shutting down, closing a process.
//
// It was written by hand in four cells before it was one file, and two of
// them had drifted into the human voice (Akusen, 2026-09-27).
Item {
    id: root

    property var metrics: null
    property string label: ""
    property string kind: "plain"       // "plain" | "primary" | "alert"

    signal activated()

    readonly property real factor: metrics ? metrics.factor : 1
    readonly property bool filled: kind !== "plain"
    readonly property int fontSize: Math.round(12 * factor)

    implicitWidth: text.implicitWidth + 24 * factor
    implicitHeight: 26 * factor
    width: implicitWidth
    height: implicitHeight

    // Two shapes rather than one with a conditional fill: a Gradient is a
    // declared object, not a value to switch between.
    Rectangle {
        anchors.fill: parent
        visible: !root.filled
        radius: Metrics.radiusFor(height, root.metrics)
        color: "transparent"
        border.width: Metrics.rim(Screen.devicePixelRatio)
        border.color: Theme.line
        antialiasing: true
    }

    Rectangle {
        anchors.fill: parent
        visible: root.filled
        radius: Metrics.radiusFor(height, root.metrics)
        antialiasing: true

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Theme.gradientTop(root.kind === "alert" ? Theme.alert : Theme.primary)
            }
            GradientStop {
                position: 1
                color: Theme.gradientBottom(root.kind === "alert" ? Theme.alert : Theme.primary)
            }
        }
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.filled ? Theme.background : Qt.alpha(Theme.text, 0.72)
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.fontSize,
            "weight": root.filled ? Typography.weightTitle : Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.fontSize, 0.04)
        })
    }

    TapHandler { onTapped: root.activated() }
}
