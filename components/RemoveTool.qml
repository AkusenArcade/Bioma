import QtQuick
import qs.core

// The press that takes a setting's row away for good — a workspace, a window
// rule, a startup line, a step — and asks once before it does.
//
// At rest it is the trash at the row's end, in the text colour: a cross read
// as "close", and at 11 px in a row it looked switched off (Akusen,
// 2026-10-24). The first press is the question: the tool grows out of the
// trash toward the row, alert, and says `REMOVE?`; the second press answers.
// Leaving it — the pointer, or the keyboard moving on — withdraws the question,
// as a preset's `FORGET …?` does. Red only while it asks (CELLS §08: red all
// the time is invisible exactly when it matters).
Item {
    id: tool

    property real factor: 1
    property bool dimmed: false
    property string question: "REMOVE?"
    signal confirmed()

    property bool asking: false
    onDimmedChanged: if (tool.dimmed) tool.asking = false

    readonly property real side: 22 * factor

    width: tool.asking ? tool.side + label.implicitWidth + 12 * factor : tool.side
    height: tool.side

    Behavior on width {
        NumberAnimation {
            duration: Timing.transition
            easing.type: Easing.Bezier
            easing.bezierCurve: Timing.easeOpenFlat
        }
    }

    // A stop for the keyboard (see `Focus`): Enter asks, Enter again answers.
    readonly property bool navigable: !tool.dimmed
    readonly property bool keyed: Focus.marked === tool
    onKeyedChanged: if (!tool.keyed && !hover.hovered) tool.asking = false

    function activate() {
        if (tool.dimmed)
            return;
        if (!tool.asking) {
            tool.asking = true;
            return;
        }
        tool.asking = false;
        tool.confirmed();
    }

    KeyMark {
        factor: tool.factor
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        color: Qt.alpha(Theme.alert, 0.12)
        opacity: tool.asking ? 1 : 0
    }

    Item {
        anchors.left: parent.left
        anchors.right: trash.left
        height: parent.height
        clip: true

        Text {
            id: label
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: tool.question
            color: Theme.alert
            opacity: tool.asking ? 1 : 0
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": Math.round(11 * tool.factor),
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(Math.round(11 * tool.factor), Typography.labelTracking)
            })
        }
    }

    Item {
        id: trash
        anchors.right: parent.right
        width: tool.side
        height: tool.side

        Icon {
            anchors.centerIn: parent
            width: 14 * tool.factor
            height: width
            name: "trash"
            colour: Qt.alpha(tool.asking ? Theme.alert
                             : hover.hovered && !tool.dimmed ? Theme.primary : Theme.text,
                             tool.dimmed ? 0.3 : 1)
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered && !tool.keyed) tool.asking = false
    }

    // While it asks, the whole tool is the answer, the word included.
    TapHandler {
        gesturePolicy: TapHandler.WithinBounds
        onTapped: tool.activate()
    }
}
