import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The vitals, opened: a pod for each domain, and the machine's processes
// beside them.
//
// The pods hang off the panel rather than off each other, each on its own
// thread, and their bottoms align with it — three pods of 108 with 24 between
// them is exactly the panel's 372. The indicators inside them are the same
// shapes the contracted cell showed, larger: the cell does not present a new
// vocabulary when it opens, it presents the same one with room.
//
// Clicking an indicator sorts the list by that domain. The sort never changes
// by itself, not even when a domain goes critical: it is the user's choice
// about what they are looking for.
//
// See docs/design/CELLS.md §02.
Item {
    id: root

    // The cell this grew out of, for its cascade and its metrics.
    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real podWidth: 236 * factor
    readonly property real podHeight: 108 * factor
    readonly property real panelWidth: 372 * factor
    readonly property real gap: 24 * factor

    implicitWidth: podWidth + gap + panelWidth
    implicitHeight: panelWidth   // 372: three pods of 108 and two gaps of 24

    width: implicitWidth
    height: implicitHeight

    // "cpu" | "ram" | "gpu" | "battery"
    property string sort: "ram"
    property int pendingKill: -1
    readonly property var pending: {
        for (const process of SystemMonitor.processes)
            if (process.pid === root.pendingKill)
                return process;
        return null;
    }

    // ---- The domains -------------------------------------------------------

    readonly property var domains: {
        const out = [
            { "key": "cpu", "label": "CPU" },
            { "key": "ram", "label": "RAM" }
        ];
        if (SystemMonitor.gpuPresent)
            out.push({ "key": "gpu", "label": "GPU" });
        if (SystemMonitor.hasBattery)
            out.push({ "key": "battery", "label": "BATTERY" });
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

    // The figure the domain is actually measured by, and under it the one that
    // says why: a clock, a quantity of memory, a time.
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
            return `${SystemMonitor.ramUsedGb}/${SystemMonitor.ramTotalGb} GB`;
        if (key === "gpu")
            return SystemMonitor.gpuClock > 0 ? `${(SystemMonitor.gpuClock / 1000).toFixed(1)} GHz` : "";
        return SystemMonitor.batteryStateName;
    }

    // ---- The cascade -------------------------------------------------------
    //
    // The panel grows first, on the cell's own thread; then the pods, sixteen
    // milliseconds apart, each out of the node where its thread meets the
    // panel. The figure in the style guide is reached by tightening this, never
    // by shortening a single growth.

    property real cascade: 0

    function podProgress(index) {
        const span = Timing.grow + Timing.stagger * Math.max(0, root.domains.length - 1);
        const started = root.cascade * span - index * Timing.stagger;
        return Math.max(0, Math.min(1, started / Timing.grow));
    }

    Connections {
        target: root.cell
        function onOpenChanged() {
            pods.stop();
            pods.to = root.cell.open ? 1 : 0;
            pods.duration = root.cell.open ? Timing.open : Timing.close;
            pods.start();
        }
    }

    NumberAnimation {
        id: pods
        target: root
        property: "cascade"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    // The cell is assigned after this item is built — a Loader sets its
    // properties on `loaded`, which is later than `Component.onCompleted` — so
    // the cascade starts when the cell arrives, not when the item does.
    onCellChanged: {
        if (root.cell && root.cell.open) {
            pods.to = 1;
            pods.restart();
        }
    }

    // ---- The pods ----------------------------------------------------------

    Repeater {
        model: root.domains

        delegate: Panel {
            id: pod

            required property var modelData
            required property int index

            readonly property string key: modelData.key
            readonly property real progress: root.podProgress(index)
            readonly property bool sorted: root.sort === pod.key

            metrics: root.metrics
            // Up to the pill ceiling the cap is still a border rather than a
            // shape that dictates the content, so a pod is a full pill — and
            // its content is held off the cap by rather more than a panel's
            // padding, or the indicator sits in the curve.
            radius: root.podHeight / 2
            padding: 23 * root.factor
            targetWidth: root.podWidth
            targetHeight: root.podHeight
            growth: progress
            contentReady: progress > 0.999

            // It is born from the node where its own thread meets the panel.
            anchorX: 0
            anchorY: index * (root.podHeight + root.gap)
            nodeX: root.podWidth
            nodeY: index * (root.podHeight + root.gap) + root.podHeight / 2

            TapHandler {
                // The indicators double as the sort control.
                onTapped: root.sort = pod.key
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14 * root.factor

                Vital {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 62 * root.factor
                    height: width
                    kind: pod.key
                    load: root.loadOf(pod.key)
                    rate: root.rateOf(pod.key)
                    level: root.levelOf(pod.key)
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.factor

                    Row {
                        spacing: 7 * root.factor

                        Text {
                            text: pod.modelData.label
                            color: Theme.text
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontLabel,
                                "weight": Typography.weightLabel,
                                "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
                            })
                        }

                        // Which domain the list is sorted by, said where the
                        // domain is named rather than in a legend.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pod.sorted
                            width: 6 * root.factor
                            height: width
                            radius: width / 2
                            color: Theme.primary
                            antialiasing: true
                        }
                    }

                    Text {
                        text: root.readingOf(pod.key)
                        color: Theme.stateFor(root.loadOf(pod.key))
                        font: Typography.tabular(Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontValue,
                            "weight": Typography.weightValue
                        }))
                    }

                    Text {
                        text: root.detailOf(pod.key)
                        visible: text !== ""
                        color: Qt.alpha(Theme.stateFor(root.loadOf(pod.key)), 0.8)
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

    // One thread per pod, from the pod's cap to the panel's edge. They are
    // drawn before the pods and stay attached while the pods grow, because
    // their ends are bound to the geometry of both shapes.
    Repeater {
        model: root.domains

        delegate: Thread {
            required property int index

            vertical: false
            progress: root.cell ? root.cell.threadProgress : 0
            x: root.podWidth
            y: index * (root.podHeight + root.gap) + root.podHeight / 2 - height / 2
            width: root.gap
            height: implicitHeight
        }
    }

    // ---- The list ----------------------------------------------------------

    Panel {
        id: list

        metrics: root.metrics
        targetWidth: root.panelWidth
        targetHeight: root.height
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        // It grows out of the node of the cell's own thread, which lands on its
        // top edge under the cell.
        anchorX: root.podWidth + root.gap
        anchorY: 0
        nodeX: root.width - (root.cell ? root.cell.width / 2 : 0)
        nodeY: 0

        Column {
            anchors.top: parent.top
            spacing: 10 * root.factor

            // The search field is the launcher's: a lens in the primary, no
            // well of its own, and the sort said in words on the other side.
            Item {
                width: root.panelWidth - 20 * root.factor
                height: root.metrics.fieldHeight

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10 * root.factor

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        width: 16 * root.factor
                        height: width
                        gradient: true
                    }

                    TextInput {
                        id: filter
                        anchors.verticalCenter: parent.verticalCenter
                        width: 180 * root.factor
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontTitle
                        selectByMouse: true

                        Text {
                            anchors.fill: parent
                            visible: filter.text === ""
                            text: "Search tasks"
                            color: Theme.textMuted
                            font: filter.font
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: `sorted by ${root.sort.toUpperCase()}`
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }
            }

            Well {
                id: well
                metrics: root.metrics
                width: root.panelWidth - 20 * root.factor
                height: root.height - 20 * root.factor - root.metrics.fieldHeight - 10 * root.factor
                        - (confirmation.visible ? confirmation.height + 10 * root.factor : 0)

                // The scrollbar lives inside the well and only while the list
                // is moving: at rest the shell does not speak, and a bar that
                // stays is a figure nobody asked for.
                Rectangle {
                    z: 1
                    visible: processes.contentHeight > processes.height
                    opacity: processes.moving || processes.flicking || processes.dragging ? 1 : 0
                    width: 3 * root.factor
                    radius: width / 2
                    color: Theme.line
                    x: well.width - width - 4 * root.factor
                    height: Math.max(width * 4, processes.height * processes.height
                                     / Math.max(1, processes.contentHeight))
                    y: processes.contentHeight > processes.height
                       ? processes.y + (processes.contentY / (processes.contentHeight - processes.height))
                         * (processes.height - height)
                       : 0

                    Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
                }

                ListView {
                    id: processes
                    anchors.fill: parent
                    anchors.margins: 6 * root.factor
                    model: root.sorted
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    delegate: Item {
                        id: processRow

                        required property var modelData

                        width: ListView.view.width
                        height: root.metrics.rowHeight

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12 * root.factor

                            // A process is not always an application: `ps`
                            // gives an executable name, and half of them are
                            // helpers and daemons with no desktop file. Where
                            // one resolves, the application's own icon goes in
                            // the circle — untinted, because it belongs to the
                            // application — and where none does, the neutral
                            // glyph, which does follow the palette. Never
                            // another application's logo.
                            Item {
                                id: processIcon
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20 * root.factor
                                height: width

                                readonly property string source: Apps.iconFor(processRow.modelData.name)

                                Ring {
                                    anchors.fill: parent
                                    radius: width / 2
                                    thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                                    colour: Theme.line
                                }

                                Image {
                                    anchors.centerIn: parent
                                    visible: processIcon.source !== ""
                                    width: parent.width * 0.62
                                    height: width
                                    source: processIcon.source
                                    sourceSize.width: width * Screen.devicePixelRatio
                                    sourceSize.height: height * Screen.devicePixelRatio
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                Icon {
                                    anchors.centerIn: parent
                                    visible: processIcon.source === ""
                                    width: parent.width * 0.58
                                    height: width
                                    name: "app-fallback"
                                    colour: Theme.textMuted
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150 * root.factor
                                text: processRow.modelData.name
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Typography.expressive
                                font.pixelSize: root.metrics.fontSecondary
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10 * root.factor

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${processRow.modelData.memMb >= 1024
                                        ? (processRow.modelData.memMb / 1024).toFixed(1) + " GB"
                                        : processRow.modelData.memMb + " MB"} · ${Math.round(processRow.modelData.cpu)}%`
                                color: Theme.textMuted
                                font: Typography.tabular(Qt.font({
                                    "family": Typography.technical,
                                    "pixelSize": root.metrics.fontSecondary,
                                    "weight": Typography.weightSecondary
                                }))
                            }

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14 * root.factor
                                height: width
                                name: "close"
                                gradient: true

                                TapHandler {
                                    onTapped: root.pendingKill = processRow.modelData.pid
                                }
                            }
                        }
                    }
                }
            }

            // The confirmation grows out of the list rather than arriving as a
            // dialog from somewhere else, and it says which process it is
            // about: nothing is terminated on one click.
            Item {
                id: confirmation
                visible: root.pending !== null
                width: root.panelWidth - 20 * root.factor
                height: 44 * root.factor

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "transparent"
                    border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                    border.color: Theme.alert
                    antialiasing: true
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pending ? `Close ${root.pending.name}?` : ""
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontTitle
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 6 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.factor

                    Item {
                        width: cancelText.width + 24 * root.factor
                        height: 32 * root.factor

                        Text {
                            id: cancelText
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        TapHandler { onTapped: root.pendingKill = -1 }
                    }

                    Item {
                        width: closeText.width + 28 * root.factor
                        height: 32 * root.factor

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            antialiasing: true
                            gradient: Gradient {
                                GradientStop { position: 0; color: Theme.gradientTop(Theme.alert) }
                                GradientStop { position: 1; color: Theme.gradientBottom(Theme.alert) }
                            }
                        }

                        Text {
                            id: closeText
                            anchors.centerIn: parent
                            text: "Close"
                            color: Theme.background
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        TapHandler {
                            onTapped: {
                                SystemMonitor.terminate(root.pendingKill);
                                root.pendingKill = -1;
                            }
                        }
                    }
                }
            }
        }
    }

    // The list is sorted here rather than by running `ps` again: changing the
    // order is a change of view.
    readonly property var sorted: {
        const term = filter.text.toLowerCase();
        const list = SystemMonitor.processes.filter(p => term === "" || p.name.toLowerCase().indexOf(term) >= 0);
        const by = root.sort;
        return list.slice().sort((a, b) => by === "cpu" ? b.cpu - a.cpu : b.memMb - a.memMb);
    }

    // What the membrane has to mask and blur: the surfaces, never the threads.
    function shapes() {
        const out = [{ "item": list, "radius": list.radius }];
        return out;
    }
}
