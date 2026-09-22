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
    readonly property real gap: metrics.gap

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
            // The opening curve run backwards is not a closing curve: it
            // starts fast and ends slow, so the shapes fell out of the
            // composition in the first fifty milliseconds and then crawled the
            // rest of the way. Closing takes the closing curve — it opens
            // calmly and closes quickly.
            pods.easing.bezierCurve = root.cell.open ? Timing.easeOpenFlat
                                                     : Timing.easeClose;
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
        id: podList
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
            radius: Metrics.radiusFor(root.podHeight, root.metrics)
            padding: 23 * root.factor
            targetWidth: root.podWidth
            targetHeight: root.podHeight
            growth: progress
            contentReady: progress > 0.999

            // It is born from the node where its own thread meets the panel —
            // and the panel is a moving shape, not a coordinate. Bound to where
            // that edge *is*, the pod grows out of the panel as it opens and
            // goes back into it as it closes; bound to where it will be, the
            // pod retracted into empty space once the panel had left.
            readonly property real centre: index * (root.podHeight + root.gap) + root.podHeight / 2

            anchorX: 0
            anchorY: index * (root.podHeight + root.gap)
            nodeX: list.x
            nodeY: Math.max(list.y, Math.min(list.y + list.height, pod.centre))

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

    // One thread per pod, from the pod's cap to the panel's edge, both ends
    // bound to the shape they touch. A thread computed from the coordinates the
    // shapes will end up at is right only while they are at rest — and at rest
    // is the one moment a thread is not being looked at.
    Repeater {
        model: root.domains

        delegate: Thread {
            id: link

            required property int index

            // `count` is read first on purpose: `itemAt` notifies nothing, so a
            // binding that does not depend on the count is evaluated once, while
            // the Repeater is still empty, and stays null for ever — which is a
            // thread of length zero.
            readonly property Item pod: link.index < podList.count
                                        ? podList.itemAt(link.index) : null
            readonly property real from: link.pod ? link.pod.x + link.pod.width : list.x

            vertical: false
            progress: root.cell ? root.cell.threadProgress : 0
            x: link.from
            y: (link.pod ? link.pod.y + link.pod.height / 2 : list.y) - height / 2
            width: Math.max(0, list.x - link.from)
            height: implicitHeight
        }
    }

    // ---- The list ----------------------------------------------------------

    Panel {
        id: list

        // The pointer over this panel is what asks the membrane for the
        // keyboard — see the note in Vitals.qml. The pods are not part of it:
        // nothing in them is typed into.
        HoverHandler {
            onHoveredChanged: if (root.cell) root.cell.panelHovered = hovered
        }

        metrics: root.metrics
        targetWidth: root.panelWidth
        targetHeight: root.height
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        // It grows out of the node of the cell's own thread, which lands on the
        // edge facing the cell — the top one on a membrane at the top of the
        // screen, the bottom one on a membrane at the bottom of it.
        anchorX: root.podWidth + root.gap
        anchorY: 0
        nodeX: root.width - (root.cell ? root.cell.width / 2 : 0)
        nodeY: root.cell && !root.cell.opensDown ? root.height : 0

        Column {
            anchors.top: parent.top
            spacing: 10 * root.factor

            // The search field is the launcher's: a lens in the primary, no
            // well of its own, and the sort said in words on the other side.
            Item {
                width: root.panelWidth - 20 * root.factor
                height: root.metrics.fieldHeight

                // Pressing the field keeps the keyboard after the pointer has
                // wandered off the panel; Escape, or closing the cell, gives
                // it back.
                TapHandler {
                    onTapped: {
                        if (root.cell)
                            root.cell.fieldEngaged = true;
                        filter.forceActiveFocus();
                    }
                }

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

                        Keys.onEscapePressed: {
                            filter.focus = false;
                            if (root.cell)
                                root.cell.fieldEngaged = false;
                        }

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

                Scroller {
                    flick: processes
                    factor: root.factor
                    x: well.width - width - 4 * root.factor
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
                    radius: Metrics.radiusFor(height, root.metrics)
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
                            radius: Metrics.radiusFor(height, root.metrics)
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

    // What the membrane has to mask and blur: every surface, never the threads.
    //
    // The pods belong in here as much as the panel does. Left out, they were
    // drawn but not declared: no blur behind them, and no claim on the presses
    // that sort the list by one of them either.
    function shapes() {
        const out = [{ "item": list, "radius": list.radius }];
        for (let i = 0; i < podList.count; i++) {
            const pod = podList.itemAt(i);
            if (pod && pod.growth > 0)
                out.push({ "item": pod, "radius": pod.radius });
        }
        return out;
    }
}
