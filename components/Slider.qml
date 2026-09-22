import QtQuick
import qs.core

// A scale the hand moves: a 3 px track, the travelled part in the primary
// gradient, and a 14 px handle at the head of it.
//
// A control, never an indicator — so it keeps the primary for its whole run and
// never takes a state colour, whatever it is set to (STYLE_GUIDE §3).
//
// It reports rather than sets: `moved` carries the new value and whoever owns
// the number decides what to do with it. A slider that wrote straight into the
// service would fight the service's own reply on the next frame.
Item {
    id: root

    // 0 to 1. What it is a fraction *of* is the caller's business.
    property real value: 0

    // Muting does not zero a volume, so a muted row keeps its slider where it
    // was and only dims it.
    property bool dimmed: false

    property color base: Theme.primary
    property real factor: 1

    readonly property real trackHeight: 3 * factor
    readonly property real handleSize: 14 * factor

    signal moved(real value)

    implicitWidth: 120 * factor
    implicitHeight: handleSize

    opacity: dimmed ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: Timing.transition } }

    readonly property real travel: Math.max(0, Math.min(1, root.value))

    function report(x) {
        root.moved(Math.max(0, Math.min(1, x / Math.max(1, root.width))));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackHeight
        radius: Metrics.shaped(height / 2)
        color: Qt.alpha(Theme.line, 0.55)
        antialiasing: true
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: root.width * root.travel
        height: root.trackHeight
        radius: Metrics.shaped(height / 2)
        antialiasing: true

        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradientTop(root.base) }
            GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: root.handleSize
        height: width
        radius: Metrics.shaped(width / 2)
        x: root.width * root.travel - width / 2
        antialiasing: true

        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradientTop(root.base) }
            GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
        }
    }

    // A press anywhere on the bar goes there, and the drag continues from
    // wherever it started: the handle is a sign of where the value is, not the
    // only part that answers.
    TapHandler {
        onTapped: event => root.report(event.position.x)
    }

    DragHandler {
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onCentroidChanged: if (active) root.report(centroid.position.x)
    }
}
