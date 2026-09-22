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

    // The one cell so far with a field to type in: the process filter.
    //
    // Asking for the keyboard costs the window its focus — a focusable layer
    // surface is one niri moves the focus to as the pointer crosses it, ring
    // and all — so the cell asks only where the keyboard could be wanted: over
    // its own panel, and afterwards for as long as the field is engaged. The
    // pointer on the *other* cells of the same membrane no longer disturbs the
    // window at all.
    //
    // Asking only on the press was tried first and cannot work: the press that
    // makes the surface focusable is the press that should have reached the
    // field. Arriving over the panel is what earns the focus, and by the time
    // the field is pressed the surface already has it.
    property bool panelHovered: false
    property bool fieldEngaged: false

    wantsKeyboard: root.open && (root.panelHovered || root.fieldEngaged)

    paddingLeading: 14
    paddingTrailing: 14

    readonly property real indicator: 26 * metrics.factor
    readonly property real pitch: 10 * metrics.factor

    // Open, the capsule names itself rather than the machine's parts, and a
    // label is machine language: the technical face, like the workspaces cell.
    headerTitle: "MACHINE VITALS & TASKS"
    headerMarkSize: 22 * metrics.factor
    headerMark: Component {
        Vital {
            anchors.fill: parent
            kind: "cpu"
            load: SystemMonitor.cpuPercent / 100
            rate: SystemMonitor.cpuClockFraction
        }
    }

    readonly property bool showsGpu: option("gpu", true) && SystemMonitor.gpuPresent
    readonly property bool showsBattery: SystemMonitor.hasBattery
    readonly property int count: 2 + (showsGpu ? 1 : 0) + (showsBattery ? 1 : 0)

    // As wide as its indicators; open, `Cell` makes it as wide as its own name.
    // Either way the tissue is anchored to the end of the membrane, so the cell
    // keeps its right edge and grows leftwards.
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

    // ---- Open ---------------------------------------------------------------
    //
    // The mini indicators fade and the cell becomes the header of its own
    // expansion: this is the cell PRD §6.7 describes, where the contracted
    // content is entirely replaced.

    replacesContent: true

    // The process list is the one sample that costs something, so the service
    // takes it only while it is being looked at — and a cell that closes lets
    // go of everything, the keyboard with it.
    onOpenChanged: {
        SystemMonitor.listProcesses = root.open;
        if (!root.open) {
            root.panelHovered = false;
            root.fieldEngaged = false;
        }
    }

    // The expansion is a composition — pods, threads and a panel — so it lives
    // in its own file beside this one and arrives through a Loader: a cell's
    // directory is not a QML module.
    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("VitalsExpansion.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            // The cell asks whatever it loaded for the shapes it occupies; the
            // loader is in the middle and passes the question on.
            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
    }
}
