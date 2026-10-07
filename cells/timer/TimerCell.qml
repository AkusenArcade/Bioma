import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// A timer, while one runs: a ring that empties at the speed of time.
//
// Contracted, it is the dial and nothing else — the notification's clock run
// backwards, the disc on the rim with the lit trail behind it (Akusen,
// 2026-09-27): full when the timer starts and back at twelve when it ends.
// No figure at rest; the open cell has the minutes. Paused, the ring dims and
// stops where it is.
//
// The timer is the clock's own (services/Time.qml): one timer, wherever it
// is started — the clock cell, this cell, a key — and it ends in a critical
// notification and the alarm sound. The cell exists while it runs or waits,
// paused, to be resumed; a key opens it to start one.
//
// See docs/design/CELLS.md §15.
Cell {
    id: root

    domain: "timer"

    readonly property real dialSize: 22 * metrics.factor

    paddingLeading: (metrics.cellHeight - dialSize) / 2
    paddingTrailing: paddingLeading
    contentWidth: dialSize

    condition: Time.running || Time.paused ? 1 : 0

    // What is left, as a fraction, from the moment the timer ends rather
    // than from the second it last counted: the ring drains continuously. It
    // is read again whenever it has half a pixel to move, so a long timer
    // costs a frame every few seconds and a short one moves smoothly.
    property real remaining: Time.fractionLeft
    readonly property real circumference: Math.PI * root.dialSize * 0.75

    function measure() {
        root.remaining = Time.running && Time.length > 0
            ? Math.max(0, Math.min(1, (Time.endsAt - Date.now()) / (Time.length * 1000)))
            : Time.fractionLeft;
    }

    Timer {
        interval: Math.max(16, Time.length * 1000 / Math.max(1, root.circumference * 2))
        running: Time.running && root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: root.measure()
    }

    Connections {
        target: Time
        function onRunningChanged() { root.measure(); }
        function onLeftChanged() { if (!Time.running) root.measure(); }
    }

    headerTitle: "TIMER"
    headerMarkSize: root.dialSize
    headerMark: Component {
        Dial {
            anchors.fill: parent
            fraction: 0
            orbit: Math.min(root.remaining, 0.9999)
            eased: false
        }
    }
    replacesContent: true

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("TimerPanel.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }

    Dial {
        anchors.centerIn: parent
        width: root.dialSize
        height: width
        // Whole is drawn as just short of whole: the rim wraps at 1, and a
        // full one would read as empty.
        fraction: 0
        orbit: Math.min(root.remaining, 0.9999)
        eased: false
        opacity: Time.paused ? 0.45 : 1

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
    }
}
