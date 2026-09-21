import QtQuick
import Quickshell
import qs.core

ShellRoot {
    readonly property int open: Timing.open
    Timer {
        interval: 800; running: true
        onTriggered: {
            console.log("PROBE speed", Timing.speed, "open", Timing.open, "close", Timing.close,
                        "grow", Timing.grow, "reflow", Timing.reflow, "contentFade", Timing.contentFade);
            Qt.quit();
        }
    }
}
