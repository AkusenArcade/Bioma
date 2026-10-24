import QtQuick
import qs.core

// How far through the current minute the wall clock is, 0 to 1, moving
// continuously rather than once a second.
//
// The clock's disc used to be fed the seconds: a value that changed once a
// second, eased for a fifth of it and then still, which read as a tick
// (Akusen, 2026-09-27). This runs the minute as one linear animation on Qt's
// own frame clock, from wherever the minute is when it starts, and sets
// itself against the system time again every minute, so it never drifts
// further than one minute's worth of frame timing.
//
// It is still a live value: the disc is where the second hand is, not at a
// rate chosen to look alive.
//
// In performance mode it ticks again, once a second on the second: one frame
// a second instead of one at every refresh (core/Performance.qml).
Item {
    id: root

    property real value: 0

    readonly property bool ticking: Performance.still
    onTickingChanged: root.sync()

    function sync() {
        const now = new Date();
        const into = now.getSeconds() * 1000 + now.getMilliseconds();
        sweep.stop();
        tick.stop();
        if (root.ticking) {
            root.value = now.getSeconds() / 60;
            tick.interval = Math.max(1, 1000 - now.getMilliseconds());
            tick.start();
            return;
        }
        root.value = into / 60000;
        sweep.from = root.value;
        sweep.duration = Math.max(1, 60000 - into);
        sweep.start();
    }

    // Set against the wall clock at every tick, so it never drifts off the
    // second.
    Timer {
        id: tick
        onTriggered: root.sync()
    }

    NumberAnimation {
        id: sweep
        target: root
        property: "value"
        to: 1
        easing.type: Easing.Linear
        onFinished: root.sync()
    }

    Component.onCompleted: root.sync()
}
