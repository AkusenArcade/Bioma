import QtQuick

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
Item {
    id: root

    property real value: 0

    function sync() {
        const now = new Date();
        const into = now.getSeconds() * 1000 + now.getMilliseconds();
        sweep.stop();
        root.value = into / 60000;
        sweep.from = root.value;
        sweep.duration = Math.max(1, 60000 - into);
        sweep.start();
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
