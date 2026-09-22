import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// The cell the utility cell generates.
//
// A recording has a duration, and what has a duration deserves a cell of its
// own: it must be stoppable without going through whoever started it. The
// capture cell stays where it is and keeps working while this one counts — if
// it had changed shape instead, taking a screenshot during a recording would
// have become impossible.
//
// The dot is the one place in the shell where the alert colour says no load at
// all. Here the machine really is measuring something — it is writing to disk —
// and that has to be visible from the other side of the room. It beats once per
// counted second, so the movement is the count and not a decoration.
//
// See docs/design/CELLS.md §06.
Cell {
    id: root

    domain: "recording"

    // Recording, then the question. The cell stands for both, because the file
    // it is asking about is the one it just made.
    readonly property bool confirming: !Capture.recording && Capture.pendingVideo.length > 0

    condition: Capture.recording || confirming ? 1 : 0

    readonly property real dotSize: 9 * metrics.factor
    readonly property real stopSize: 26 * metrics.factor
    readonly property real spacing: 11 * metrics.factor
    readonly property int fontTime: Math.round(14 * metrics.factor)
    readonly property int fontButton: Math.round(12 * metrics.factor)

    paddingLeading: 16 * metrics.factor
    // The question ends in a control, and a control sits closer to the cap than
    // a figure does: the pill's own curve is the margin.
    paddingTrailing: confirming ? 6 * metrics.factor : 16 * metrics.factor

    readonly property string elapsed: {
        const total = Capture.elapsed;
        const minutes = Math.floor(total / 60);
        const seconds = total % 60;
        return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
    }

    contentWidth: confirming ? question.implicitWidth : counter.implicitWidth

    // ---- While it records ---------------------------------------------------

    Row {
        id: counter

        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing
        visible: !root.confirming

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.dotSize * 1.6
            height: width

            Rectangle {
                id: dot

                property real size: root.dotSize

                anchors.centerIn: parent
                width: dot.size
                height: dot.size
                radius: width / 2
                antialiasing: true

                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.gradientTop(Theme.alert) }
                    GradientStop { position: 1; color: Theme.gradientBottom(Theme.alert) }
                }
            }

            // One beat per second counted. Width and height rather than a
            // scale, like every other growth in the shell.
            SequentialAnimation {
                id: beat

                NumberAnimation {
                    target: dot
                    property: "size"
                    to: root.dotSize * 1.45
                    duration: Timing.grow
                    easing.type: Easing.OutQuad
                }

                NumberAnimation {
                    target: dot
                    property: "size"
                    to: root.dotSize
                    duration: Timing.transition
                    easing.type: Easing.InOutQuad
                }
            }

            Connections {
                target: Capture
                function onElapsedChanged() {
                    if (Capture.recording)
                        beat.restart();
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.elapsed
            color: Theme.text
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.fontTime,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.fontTime, Typography.labelTracking)
            }))
        }

        // The stop control, in the colour of what it stops.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.stopSize
            height: width

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                border.color: Qt.alpha(Theme.alert, 0.55)
                antialiasing: true
            }

            Rectangle {
                anchors.centerIn: parent
                width: 10 * root.metrics.factor
                height: width
                radius: 2 * root.metrics.factor
                antialiasing: true

                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.gradientTop(Theme.alert) }
                    GradientStop { position: 1; color: Theme.gradientBottom(Theme.alert) }
                }
            }

            TapHandler { onTapped: Capture.stopRecording() }
        }
    }

    // ---- And then asks ------------------------------------------------------
    //
    // Save or discard is not a dialog. It grows from the cell that produced the
    // file, the same way the kill confirmation grows from the process list: the
    // same question, always in the same place. The video sits in a temporary
    // directory until the answer arrives, so "discard" can mean the file never
    // existed.

    component Choice: Item {
        id: choice

        property string label: ""
        property bool primary: false

        width: text.implicitWidth + 24 * root.metrics.factor
        height: 26 * root.metrics.factor

        // Two shapes rather than one with a conditional fill: a Gradient is a
        // declared object, not a value to switch between.
        Rectangle {
            anchors.fill: parent
            visible: !choice.primary
            radius: Metrics.radiusFor(height, root.metrics)
            color: "transparent"
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: Theme.line
            antialiasing: true
        }

        Rectangle {
            anchors.fill: parent
            visible: choice.primary
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true

            gradient: Gradient {
                GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
            }
        }

        Text {
            id: text
            anchors.centerIn: parent
            text: choice.label
            color: choice.primary ? Theme.background : Qt.alpha(Theme.text, 0.72)
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.fontButton,
                "weight": choice.primary ? Typography.weightTitle : Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.fontButton, 0.04)
            })
        }
    }

    Row {
        id: question

        anchors.verticalCenter: parent.verticalCenter
        spacing: 12 * metrics.factor
        visible: root.confirming

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Save recording?"
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
        }

        Choice {
            anchors.verticalCenter: parent.verticalCenter
            label: "Discard"
            TapHandler { onTapped: Capture.discardRecording() }
        }

        Choice {
            anchors.verticalCenter: parent.verticalCenter
            label: "Save"
            primary: true
            TapHandler { onTapped: Capture.saveRecording() }
        }
    }
}
