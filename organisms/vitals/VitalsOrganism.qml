import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The machine, read in full and never closed.
//
// The vitals cell's indicators gathered in one panel: the same rings, the same
// rhythms, the same state colours — an organism does not get a second
// vocabulary for the CPU. What it adds is the figures beside them, filled with
// their state's light, because a surface put on the desktop to be read may say
// what it measures.
//
// See docs/design/ORGANISMS.md §03.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})

    readonly property real factor: root.metrics.factor

    // In a row, or a 2 × 2 square.
    readonly property bool square: root.entry.layout === "square"

    readonly property var domains: {
        const out = [
            { "key": "cpu", "label": "CPU" },
            { "key": "ram", "label": "RAM" }
        ];
        if (SystemMonitor.gpuPresent)
            out.push({ "key": "gpu", "label": "GPU" });
        if (SystemMonitor.hasBattery)
            out.push({ "key": "battery", "label": "BAT" });
        return out;
    }

    function loadOf(key) {
        if (key === "cpu") return SystemMonitor.cpuPercent / 100;
        if (key === "ram") return SystemMonitor.ramPercent / 100;
        if (key === "gpu") return SystemMonitor.gpuPercent / 100;
        return 1 - root.levelOf("battery");
    }

    function rateOf(key) {
        if (key === "cpu") return SystemMonitor.cpuClockFraction;
        if (key === "gpu") return SystemMonitor.gpuClockFraction;
        return 0;
    }

    function levelOf(key) {
        if (key === "ram") return SystemMonitor.ramPercent / 100;
        if (key === "battery")
            return SystemMonitor.batteryLevelRaw > 1 ? SystemMonitor.batteryLevelRaw / 100
                                                     : SystemMonitor.batteryLevelRaw;
        return 0;
    }

    function readingOf(key) {
        if (key === "cpu") return `${Math.round(SystemMonitor.cpuPercent)}%`;
        if (key === "ram") return `${Math.round(SystemMonitor.ramPercent)}%`;
        if (key === "gpu") return `${Math.round(SystemMonitor.gpuPercent)}%`;
        return `${Math.round(root.levelOf("battery") * 100)}%`;
    }

    function detailOf(key) {
        if (key === "cpu")
            return SystemMonitor.cpuClock > 0 ? `${(SystemMonitor.cpuClock / 1000).toFixed(1)} GHz` : "";
        if (key === "ram")
            return `${SystemMonitor.ramUsedGb} / ${SystemMonitor.ramTotalGb} GB`;
        if (key === "gpu")
            return SystemMonitor.gpuClock > 0 ? `${(SystemMonitor.gpuClock / 1000).toFixed(1)} GHz` : "";
        return SystemMonitor.batteryStateName;
    }

    readonly property real column: 96 * root.factor
    readonly property real columnHeight: 136 * root.factor
    readonly property real gap: 16 * root.factor
    readonly property int columns: root.square ? 2 : root.domains.length

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    Grid {
        id: grid

        columns: root.columns
        columnSpacing: root.gap
        rowSpacing: root.gap

        Repeater {
            model: root.domains

            delegate: Column {
                id: pod

                required property var modelData
                readonly property string key: pod.modelData.key
                readonly property real load: root.loadOf(pod.key)

                // As wide as its widest line: `6.6 / 30.5 GB` is wider than the
                // ring, and a figure cut short is not a figure.
                width: Math.max(root.column, detail.implicitWidth)
                height: root.columnHeight

                Vital {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 62 * root.factor
                    height: width
                    kind: pod.key
                    load: pod.load
                    rate: root.rateOf(pod.key)
                    level: root.levelOf(pod.key)
                }

                Item { width: 1; height: 10 * root.factor }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pod.modelData.label
                    color: Theme.text
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontLabel,
                        "weight": Typography.weightLabel,
                        "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
                    })
                }

                Item { width: 1; height: 2 * root.factor }

                LitText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    base: Theme.stateFor(pod.load)
                    text: root.readingOf(pod.key)
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontValue,
                        "weight": Typography.weightValue
                    }))
                }

                Item { width: 1; height: 2 * root.factor }

                Text {
                    id: detail
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.detailOf(pod.key)
                    color: Theme.textMuted
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary,
                        "weight": Typography.weightSecondary
                    }))
                }
            }
        }
    }
}
