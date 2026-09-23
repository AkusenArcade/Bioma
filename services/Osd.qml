pragma Singleton

import QtQuick
import Quickshell
import qs.core

// What the on-screen display is saying, and where.
//
// The shell answers a change in the volume or the brightness in the place that
// already speaks for it: the audio cell, where there is one. The display is for
// where there is none (CELLS §05, "Open"; Akusen's rule, 2026-09-23) — so it
// shows the brightness always, having no cell, and the volume only on a monitor
// that declares no audio cell. A declared one, conditional or always, is on
// screen already or about to be, and a second answer would be the same thing
// said twice.
//
// It shows on the monitor the keyboard is pointed at, which is where the key
// that changed it was pressed.
Singleton {
    id: root

    // "volume" | "brightness" | "" when nothing is being said.
    property string kind: ""
    property string output: ""

    readonly property real volume: Audio.volume
    readonly property bool muted: Audio.muted
    readonly property real brightness: Brightness.brightness

    onVolumeChanged: root.say("volume")
    onMutedChanged: root.say("volume")
    onBrightnessChanged: root.say("brightness")

    // A declared audio cell on that monitor, anywhere but in the middle of it
    // as a summoned copy.
    function covered(kind, output) {
        if (kind !== "volume")
            return false;
        for (const cell of Focus.known)
            if (cell && cell.domain === "audio" && cell.output === output
                    && cell.visibility.type !== "invoked")
                return true;
        return false;
    }

    function say(kind) {
        if (!root.settled)
            return;
        const output = Niri.focusedOutput;
        if (output.length === 0 || root.covered(kind, output))
            return;
        root.kind = kind;
        root.output = output;
        quiet.restart();
    }

    Timer {
        id: quiet
        interval: Timing.osd
        onTriggered: root.kind = ""
    }

    // The volume going from nothing to what it is while the services start is
    // not a change anybody made.
    property bool settled: false

    Timer {
        interval: Timing.settle
        running: true
        onTriggered: root.settled = true
    }
}
