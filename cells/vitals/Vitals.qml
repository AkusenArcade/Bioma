import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// The machine's vital signs.
//
// At rest they are only shapes that move: no digits, ever. The exact figure
// arrives on hover, or in the expansion — a contracted cell does not speak.
//
// The composition follows the hardware rather than the configuration: three
// indicators on a desktop, four where there is a battery. A domain that does
// not exist on this machine has no indicator, because a cell exists when it has
// something to say.
//
// See docs/design/CELLS.md §02.
Cell {
    id: root

    domain: "vitals"

    paddingLeading: 14
    paddingTrailing: 14

    readonly property real indicator: 26 * metrics.factor
    readonly property real pitch: 10 * metrics.factor

    readonly property bool showsGpu: option("gpu", true) && SystemMonitor.gpuPresent
    readonly property bool showsBattery: SystemMonitor.hasBattery
    readonly property int count: 2 + (showsGpu ? 1 : 0) + (showsBattery ? 1 : 0)

    contentWidth: count * indicator + (count - 1) * pitch

    // Conditional visibility, when it is configured that way, watches the worst
    // of the vitals rather than any one of them: the cell appears because the
    // machine is working hard, not because a particular part is.
    condition: Math.max(SystemMonitor.cpuPercent, SystemMonitor.ramPercent,
                        showsGpu ? SystemMonitor.gpuPercent : 0) / 100

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pitch

        // The processor: the beat is its clock, the colour its load.
        Vital {
            anchors.verticalCenter: parent.verticalCenter
            width: root.indicator
            height: root.indicator
            kind: "cpu"
            load: SystemMonitor.cpuPercent / 100
            rate: SystemMonitor.cpuClockFraction
        }

        // The memory: the level is what is in use, and the wave is the only
        // part running on a clock.
        Vital {
            anchors.verticalCenter: parent.verticalCenter
            width: root.indicator
            height: root.indicator
            kind: "ram"
            load: SystemMonitor.ramPercent / 100
            level: SystemMonitor.ramPercent / 100
        }

        // The graphics card: utilisation and clock diverge, so they are said by
        // two different properties of one shape.
        Vital {
            anchors.verticalCenter: parent.verticalCenter
            width: root.indicator
            height: root.indicator
            visible: root.showsGpu
            kind: "gpu"
            load: SystemMonitor.gpuPercent / 100
            rate: SystemMonitor.gpuClockFraction
        }

        // The battery, where there is one. Its scale is UPower's own and has
        // never run against real hardware here — see INVENTORY §16.6 — so it is
        // read as a fraction only if it looks like one.
        Vital {
            anchors.verticalCenter: parent.verticalCenter
            width: root.indicator
            height: root.indicator
            visible: root.showsBattery
            kind: "battery"
            level: SystemMonitor.batteryLevelRaw > 1
                   ? SystemMonitor.batteryLevelRaw / 100
                   : SystemMonitor.batteryLevelRaw
            load: 1 - level
        }
    }

    // TODO Phase 2: the expansion — three horizontal pods of 236 x 108 on a
    // desktop, four vertical ones in a 2 x 2 matrix where there is a battery,
    // and the process list beside them, with the indicators doubling as its
    // sort control.
}
