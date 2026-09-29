import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Screenshots, regions, text recognition, recording and dictation.
//
// The first purely functional cell: at rest it has nothing to represent, so it
// shows its icon and nothing else — no figure, no state colour, because it
// measures nothing.
//
// While it records, it is the recording. It used to generate a cell of its
// own for that, and a layout without that cell had no way to stop a recording
// at all (Akusen, 2026-09-27). So the count and the stop are here now, and so
// is the question that follows. What the separate cell was protecting still
// holds: only the stop stops; the rest of the pill opens the panel as ever, so
// a screenshot can still be taken while the recording runs.
//
// The dot is the one place in the shell where the alert colour says no load at
// all. Here the machine really is measuring something — it is writing to disk —
// and that has to be visible from the other side of the room. It beats once per
// counted second, so the movement is the count and not a decoration.
//
// While it listens for dictation it is the listening, in the same place and
// by the same rule: the microphone glyph says what, the alert dot says the
// microphone is open, and the dot's size is the voice — still in silence,
// swelling as the user speaks. Transcribing, the microphone is closed and the
// alert goes with it; the loader stands beside the glyph until the text is
// there, because the engine gives no progress for a take this short.
//
// See docs/design/CELLS.md §06.
Cell {
    id: root

    domain: "utility"

    // The icon is the whole content, so the padding is what makes the cell
    // square: 20 between two tens.
    readonly property real iconSize: 20 * metrics.factor

    // ---- Which of its three shapes -------------------------------------------

    readonly property bool recording: Capture.recording
    // Recording, then the question. The cell stands for both, because the file
    // it is asking about is the one it just made.
    readonly property bool confirming: !Capture.recording && Capture.pendingVideo.length > 0
    readonly property bool dictating: Dictation.active
    readonly property bool idle: !root.recording && !root.confirming && !root.dictating

    // Something is happening, and it must not be what a narrow tissue drops.
    busy: !root.idle

    readonly property real dotSize: 9 * metrics.factor
    readonly property real micSize: 18 * metrics.factor
    readonly property real stopSize: 26 * metrics.factor
    readonly property real spacing: 11 * metrics.factor
    readonly property int fontTime: Math.round(14 * metrics.factor)

    // A square around its glyph at rest. Counting, the figure keeps the
    // margins a figure keeps; asking, the question ends in a control, and a
    // control sits closer to the cap than a figure does: the pill's own curve
    // is the margin. What the cell wears when it opens keeps its own margins,
    // which the engine works out from the header's mark.
    paddingLeading: (root.idle ? 10 : 16) * metrics.factor
    paddingTrailing: (root.idle ? 10 : root.confirming ? 6 : 16) * metrics.factor

    function clock(total) {
        const minutes = Math.floor(total / 60);
        const seconds = total % 60;
        return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
    }

    readonly property string elapsed: root.clock(Capture.elapsed)

    // Open, the cell becomes the title of the panel it opened: the glyph of its
    // domain and its name, in the technical voice, like every other cell with
    // an expansion.
    //
    // Its category rather than what it does today. `CAPTURE` would be the truer
    // word for a cell that only captures, and the wrong one for a cell expected
    // to grow other functions — a title that has to be renamed when it does is
    // the wrong title. Akusen's call, 2026-09-22.
    // Conditional, it is there for a moment after a screenshot is taken —
    // by Bioma's own capture or by niri's — as the sign that it was.
    Connections {
        target: Capture
        function onCaptured() { root.pulse(); }
    }

    Connections {
        target: Niri
        function onScreenshotCaptured() { root.pulse(); }
    }

    condition: root.pulsing || !root.idle ? 1 : 0

    // The question is the whole pill, and its answers are in it: a press there
    // is an answer, never an opening.
    opensOnTap: root.confirming ? false : hasPanel

    headerTitle: "UTILITY"
    headerMarkSize: iconSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "capture"
            gradient: true
        }
    }

    contentWidth: root.confirming ? question.implicitWidth
                : root.recording ? counter.implicitWidth
                : root.dictating ? dictation.implicitWidth
                : iconSize

    replacesContent: true

    // Two independent choices — what is captured, and where from. They are two
    // rows rather than six buttons, and the last pair used stays selected,
    // which is why they are remembered in the configuration rather than in the
    // cell.
    readonly property string what: Config.get("capture.what", "image")
    readonly property string from: Config.get("capture.from", "screen")

    // Video is the recorder's, and it cannot record a window: `wl-screenrec`
    // takes an output or a region and nothing else. Text is `tesseract` over a
    // captured region, and a window has no region here — niri reports no window
    // position, so the compositor captures it by id. So under Text the middle
    // place is dictation's (PRD §9.6): OCR SCREEN · DICTATION · OCR REGION.
    //
    // And there is one capture at a time: a second recording while one runs,
    // or while the last one waits for its answer, would take the file being
    // asked about, and dictation would take the cell's one contracted form. A
    // pair that cannot be done is shown as unavailable rather than offered and
    // then refused — dictation too, when the engine or its model is missing.
    function supports(what, from) {
        if (what === "video" && !root.idle)
            return false;
        if (from !== "window")
            return true;
        if (what === "text")
            return root.idle && Dictation.available;
        return what === "image";
    }

    Icon {
        anchors.centerIn: parent
        visible: root.idle
        name: "capture"
        width: root.iconSize
        height: width
        gradient: true
    }

    // ---- While it records ---------------------------------------------------

    Row {
        id: counter

        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing
        visible: root.recording

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

        Clock {
            anchors.verticalCenter: parent.verticalCenter
            text: root.elapsed
        }

        Stop {
            anchors.verticalCenter: parent.verticalCenter
            onStopped: Capture.stopRecording()
        }
    }

    // The seconds counted, at the width of "00:00" whatever they read.
    // Orbitron has no tabular figures, so `tnum` changes nothing and a 1 is
    // narrower than a 0: the pill narrowed and widened every second, a
    // movement that measured nothing (Akusen, 2026-09-29).
    component Clock: Text {
        id: clock

        width: widest.advanceWidth
        horizontalAlignment: Text.AlignHCenter
        color: Theme.text
        font: Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": root.fontTime,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.fontTime, Typography.labelTracking)
        }))

        TextMetrics {
            id: widest
            font: clock.font
            text: "00:00"
        }
    }

    // The stop control, in the colour of what it stops. It takes the press
    // for itself, or the same press would stop the recording and open the
    // panel.
    component Stop: Item {
        id: stop

        signal stopped

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

        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
            onTapped: stop.stopped()
        }
    }

    // ---- While it listens ---------------------------------------------------
    //
    // The glyph, the open microphone, the seconds spoken, the stop. The dot
    // is the recording's, but what moves it is the voice rather than the
    // clock: its size follows the microphone's level, so silence is still.

    Row {
        id: dictation

        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing
        visible: root.dictating

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "microphone"
            width: root.micSize
            height: width
            gradient: true
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            visible: Dictation.listening
            width: root.dotSize * 1.6
            height: width

            Rectangle {
                id: voice

                // Width and height rather than a scale, like every other
                // growth in the shell; smoothed over one grow step so a
                // syllable reads as a swell and not a flicker.
                property real size: root.dotSize * (1 + 0.6 * Dictation.level)
                Behavior on size { NumberAnimation { duration: Timing.grow } }

                anchors.centerIn: parent
                width: voice.size
                height: voice.size
                radius: width / 2
                antialiasing: true

                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.gradientTop(Theme.alert) }
                    GradientStop { position: 1; color: Theme.gradientBottom(Theme.alert) }
                }
            }
        }

        Clock {
            anchors.verticalCenter: parent.verticalCenter
            visible: Dictation.listening
            text: root.clock(Dictation.elapsed)
        }

        Stop {
            anchors.verticalCenter: parent.verticalCenter
            visible: Dictation.listening
            onStopped: Dictation.stop()
        }

        // No value yet, and no way to know how long until there is one: the
        // loader, beside the glyph, and only for as long as the wait lasts.
        Sweep {
            anchors.verticalCenter: parent.verticalCenter
            visible: Dictation.transcribing
            running: Dictation.transcribing
            width: root.micSize
            height: width
        }
    }

    // ---- And then asks ------------------------------------------------------
    //
    // Save or discard is not a dialog. It grows from the cell that produced the
    // file, the same way the kill confirmation grows from the process list: the
    // same question, always in the same place. The video sits in a temporary
    // directory until the answer arrives, so "discard" can mean the file never
    // existed.

    Row {
        id: question

        anchors.verticalCenter: parent.verticalCenter
        spacing: 12 * root.metrics.factor
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
            metrics: root.metrics
            label: "Discard"
            onActivated: Capture.discardRecording()
        }

        Choice {
            anchors.verticalCenter: parent.verticalCenter
            metrics: root.metrics
            label: "Save"
            kind: "primary"
            onActivated: Capture.saveRecording()
        }
    }

    // ---- Doing it -----------------------------------------------------------

    function capture(what, from) {
        if (!root.supports(what, from))
            return;

        Config.set("capture.what", what);
        Config.set("capture.from", from);
        Capture.pendingAction = what === "video" ? "record"
                              : what === "text" ? "text" : "still";

        // The cell closes first and the capture follows, because the panel is
        // on the screen being photographed. The service holds its own frame of
        // settling for the same reason; this is the part of it the cell owns.
        root.open = false;

        if (from === "region") {
            Capture.selectRegion();
            return;
        }

        // Closing the panel first gives the focus back to the window the text
        // is for; the paste goes wherever the focus is when the text is ready.
        if (what === "text" && from === "window") {
            Dictation.start();
            return;
        }

        if (from === "window") {
            Capture.captureWindow(Niri.focusedWindow ? Niri.focusedWindow.id : 0);
            return;
        }

        if (what === "video")
            Capture.recordOutput(root.output);
        else if (what === "text")
            // A whole screen of text is a region like any other: the output's
            // own rectangle, in the layout coordinates grim wants.
            Capture.recogniseRegion(root.outputRegion());
        else
            Capture.captureOutput(root.output);
    }

    function outputRegion() {
        for (const screen of Quickshell.screens)
            if (screen.name === root.output)
                return `${screen.x},${screen.y} ${screen.width}x${screen.height}`;
        return "";
    }

    panel: Component {
        Loader {
            id: panelLoader
            source: Qt.resolvedUrl("UtilityPanel.qml")

            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }
}
