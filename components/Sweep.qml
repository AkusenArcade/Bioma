import QtQuick
import qs.core

// The loader: a segment travelling inside a track.
//
// It is the one moving thing in the shell that measures nothing, and it is
// allowed because the movement *is* the information — it means "no value yet".
// The moment the value exists the meaning is gone and so is the motion, which
// is why `running` binds to the wait itself and never to a timer.
//
// Drawn here rather than loaded from `assets/icons/loader.svg`: the file is the
// drawn source and is deliberately static, and an SVG cannot be moved without
// rasterising it again on every frame. The geometry below is the file's own,
// in its 24-unit space — track `3,8.5 18×7 r3.5` at stroke 1.5, segment
// `5.2,10.7 6×2.6 r1.3`, travel 7.6 — so the two stay the same drawing.
//
// Not called `Loader`: `QtQuick` exports a type of that name and it would be
// shadowed wherever QtQuick is imported, which is the same trap that cost
// `Scale` its name.
//
// The whole contract is docs/design/icons/LOADER.md.
Item {
    id: root

    // Bound to the wait — a property, a process state, a promise — never to a
    // timer, and never held on for a minimum display time.
    property bool running: false

    // It carries no colour of its own: it takes the row's, which is muted text
    // almost everywhere. A wait is not a warning, so never a state colour.
    property color colour: Theme.textMuted

    implicitWidth: 16
    implicitHeight: 16

    readonly property real unit: Math.min(width, height) / 24

    // The track never moves, never pulses, never changes opacity.
    Rectangle {
        x: 3 * root.unit
        y: 8.5 * root.unit
        width: 18 * root.unit
        height: 7 * root.unit
        radius: 3.5 * root.unit
        color: "transparent"
        border.width: Metrics.crisp(1.5 * root.unit, Screen.devicePixelRatio)
        border.color: root.colour
        antialiasing: true
    }

    Rectangle {
        id: segment

        // Where the segment is, in the icon's own 24-unit space: 5.2 at rest,
        // 12.8 at the far end.
        property real place: 5.2

        x: segment.place * root.unit
        y: 10.7 * root.unit
        width: 6 * root.unit
        height: 2.6 * root.unit
        radius: 1.3 * root.unit
        color: root.colour
        antialiasing: true

        // Symmetric easing: out of each end, across the middle at speed. It
        // reads as breathing rather than as a progress bar, which it must never
        // be taken for — there is no position within a known duration here.
        SequentialAnimation on place {
            running: root.running
            loops: Animation.Infinite

            NumberAnimation {
                from: 5.2
                to: 12.8
                duration: Timing.loader / 2
                easing.type: Easing.Bezier
                easing.bezierCurve: Timing.sweep
            }

            NumberAnimation {
                from: 12.8
                to: 5.2
                duration: Timing.loader / 2
                easing.type: Easing.Bezier
                easing.bezierCurve: Timing.sweep
            }
        }
    }

    // Stopped, it holds still at the left end — the file's own resting state.
    // The shape alone still says "not ready"; nothing is substituted for it.
    onRunningChanged: if (!running) segment.place = 5.2
}
