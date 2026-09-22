import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Audio, opened: the capsule that carries the level, and under it the three
// wells — where the sound goes, where it comes from, and who is making it.
//
// Three wells and not three tabs. Output, input and applications are looked at
// together: this cell is usually opened *because* the sound is coming out of
// the wrong place, and a tab would hide half of the answer.
//
// The heights are fixed rather than fitted. PipeWire nodes appear and
// disappear constantly — a notification sound is a node that lives for a
// second and a half — and a panel that resized around them would jump under
// the hand that is using it. Rows arrive and leave inside a well that does not
// move, and scroll when there are more than it holds.
//
// See docs/design/CELLS.md §05.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // ---- The capsule --------------------------------------------------------

    readonly property real capsuleWidth: 372 * factor
    readonly property real capsuleHeight: 88 * factor
    readonly property real dialSize: 56 * factor
    readonly property real figureWidth: 62 * factor
    readonly property real sliderWidth: 168 * factor
    readonly property real capsuleGap: 20 * factor

    // What is left once the three elements and the two gaps have taken their
    // measures: the handoff states the capsule and its contents, not the
    // padding, and a padding invented on top of them would widen the capsule.
    readonly property real capsulePadding:
        Math.max(0, (capsuleWidth - dialSize - figureWidth - sliderWidth - capsuleGap * 2) / 2)

    // ---- The panel ----------------------------------------------------------

    readonly property real panelWidth: 372 * factor
    readonly property real panelPadding: 10 * factor
    readonly property real wellPadding: 8 * factor
    readonly property real wellInset: 10 * factor
    readonly property real wellSpacing: 8 * factor
    readonly property real rowHeight: 38 * factor
    readonly property real gap: metrics.gap

    // How many rows a well shows before it starts scrolling. Three is what the
    // panel can hold three times over without becoming a page.
    readonly property int shownRows: 3

    readonly property var outputs: Audio.outputs
    readonly property var inputs: Audio.inputs
    readonly property var streams: Audio.streams

    TextMetrics {
        id: labelMetrics
        text: "OUTPUT"
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontMeta,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
        })
    }

    readonly property real labelHeight: labelMetrics.height + 2 * factor

    function wellHeight(rows) {
        return root.wellPadding * 2 + root.labelHeight
             + Math.max(1, Math.min(rows, root.shownRows)) * root.rowHeight;
    }

    readonly property real outputsHeight: wellHeight(outputs.length)
    readonly property real inputsHeight: wellHeight(inputs.length)
    // Fixed at its full three rows whatever is playing, which is the whole
    // point: this is the well things come and go from.
    readonly property real streamsHeight: wellHeight(root.shownRows)

    readonly property real panelHeight: panelPadding * 2 + wellSpacing * 2
                                      + outputsHeight + inputsHeight + streamsHeight

    // ---- Where the two shapes sit -------------------------------------------

    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    readonly property real capsuleY: upward ? panelHeight + gap : 0
    readonly property real panelY: upward ? 0 : capsuleHeight + gap
    readonly property real capsuleNear: upward ? capsuleY + capsuleHeight : capsuleY

    implicitWidth: Math.max(capsuleWidth, panelWidth)
    implicitHeight: capsuleHeight + gap + panelHeight

    width: implicitWidth
    height: implicitHeight

    // ---- The cascade --------------------------------------------------------

    property real cascade: 0

    function stage(index) {
        return Timing.stage(root.cascade, index, 2);
    }

    readonly property real linkProgress: stage(0)
    readonly property real panelProgress: stage(1)

    Connections {
        target: root.cell
        function onOpenChanged() {
            cascade.stop();
            cascade.to = root.cell.open ? 1 : 0;
            cascade.duration = root.cell.open ? Timing.open : Timing.close;
            // The opening curve run backwards is not a closing curve: it
            // starts fast and ends slow, so the shapes fell out of the
            // composition in the first fifty milliseconds and then crawled the
            // rest of the way. Closing takes the closing curve — it opens
            // calmly and closes quickly.
            cascade.easing.bezierCurve = root.cell.open ? Timing.easeOpenFlat
                                                     : Timing.easeClose;
            cascade.start();
        }
    }

    NumberAnimation {
        id: cascade
        target: root
        property: "cascade"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    onCellChanged: {
        if (root.cell && root.cell.open) {
            cascade.to = 1;
            cascade.restart();
        }
    }

    // ---- Pieces -------------------------------------------------------------

    // The label of a well: the domain, in the technical voice, said once.
    component WellLabel: Text {
        property var metrics: Metrics.step("normal")
        color: Theme.textFaint
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": metrics.fontMeta,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(metrics.fontMeta, Typography.labelTracking)
        })
    }

    // A device: the mark of what is chosen, its own name for itself, and how it
    // is attached to the machine.
    component DeviceRow: Item {
        id: device

        property var node: null
        property bool chosen: false
        property real factor: 1
        property var metrics: Metrics.step("normal")

        signal picked

        height: 38 * device.factor

        Item {
            id: mark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * device.factor
            height: width

            Ring {
                anchors.fill: parent
                visible: !device.chosen
                radius: width / 2
                thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                colour: Theme.line
            }

            Rectangle {
                anchors.fill: parent
                visible: device.chosen
                radius: width / 2
                antialiasing: true

                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                    GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
                }
            }

            // The hole in the middle of a chosen mark is the panel showing
            // through, not a second colour.
            Rectangle {
                anchors.centerIn: parent
                visible: device.chosen
                width: parent.width / 2
                height: width
                radius: width / 2
                color: Theme.background
                antialiasing: true
            }
        }

        Text {
            id: meta
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Audio.connection(device.node)
            color: Theme.textMuted
            font.family: Typography.technical
            font.pixelSize: device.metrics.fontMeta
        }

        // A device's own words for itself are human language, whoever wrote
        // them into the firmware.
        Text {
            anchors.left: mark.right
            anchors.leftMargin: 12 * device.factor
            anchors.right: meta.left
            anchors.rightMargin: 12 * device.factor
            anchors.verticalCenter: parent.verticalCenter
            text: Audio.describe(device.node)
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: device.metrics.fontSecondary
        }

        TapHandler {
            onTapped: device.picked()
        }
    }

    // An application: its own icon, its name, a short slider and the same cut
    // ring the cell wears, at a smaller size.
    component StreamRow: Item {
        id: stream

        property var node: null
        property real factor: 1
        property var metrics: Metrics.step("normal")

        readonly property string label: Audio.describeStream(stream.node)
        readonly property real level: stream.node?.audio?.volume ?? 0
        readonly property bool muted: stream.node?.audio?.muted ?? false
        readonly property string iconSource: Apps.iconFor(stream.label)

        height: 38 * stream.factor

        Item {
            id: badge
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * stream.factor
            height: width

            Ring {
                anchors.fill: parent
                radius: width / 2
                thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                colour: Theme.line
            }

            // An application's icon belongs to the application, so it is not
            // tinted; where none resolves, the neutral glyph, which does follow
            // the palette. Never another application's logo.
            Image {
                anchors.centerIn: parent
                visible: stream.iconSource !== ""
                width: parent.width * 0.62
                height: width
                source: stream.iconSource
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Icon {
                anchors.centerIn: parent
                visible: stream.iconSource === ""
                width: parent.width * 0.58
                height: width
                name: "app-fallback"
                colour: Theme.textMuted
            }
        }

        // The controls take their places from the right, and the name takes
        // what is left: a slider that shortened as a title grew would be a
        // different control on every row.
        Item {
            id: mute
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 22 * stream.factor
            height: width

            Icon {
                anchors.centerIn: parent
                width: 16 * stream.factor
                height: width
                name: stream.muted ? "sound-off" : "sound-on"
                colour: Theme.textMuted
                gradient: stream.muted
            }

            TapHandler {
                onTapped: Audio.toggleStreamMute(stream.node)
            }
        }

        Text {
            id: figure
            anchors.right: mute.left
            anchors.rightMargin: 12 * stream.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 34 * stream.factor
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(stream.level * 100)}%`
            color: Theme.textMuted
            opacity: stream.muted ? 0.45 : 1
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": stream.metrics.fontMeta
            }))
        }

        // Deliberately short: a fine adjustment, not the main one.
        Slider {
            id: level
            anchors.right: figure.left
            anchors.rightMargin: 12 * stream.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 80 * stream.factor
            factor: stream.factor
            value: stream.level
            dimmed: stream.muted
            onMoved: value => Audio.setStreamVolume(stream.node, value)
        }

        Text {
            anchors.left: badge.right
            anchors.leftMargin: 12 * stream.factor
            anchors.right: level.left
            anchors.rightMargin: 12 * stream.factor
            anchors.verticalCenter: parent.verticalCenter
            text: stream.label
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: stream.metrics.fontSecondary
        }
    }

    // ---- The capsule --------------------------------------------------------

    Panel {
        id: capsule

        metrics: root.metrics
        radius: Metrics.radiusFor(root.capsuleHeight, root.metrics)
        padding: root.capsulePadding
        targetWidth: root.capsuleWidth
        targetHeight: root.capsuleHeight
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        anchorX: 0
        anchorY: root.capsuleY
        nodeX: root.width / 2
        nodeY: root.capsuleNear

        Item {
            anchors.fill: parent

            Gauge {
                id: dial
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.dialSize
                height: width
                // The capsule's dial is drawn finer than the contracted one:
                // the same figures, at a size where 3 units would be a band.
                trackUnits: 1.5
                nodeUnits: 4
                fraction: Math.min(1, Audio.volume)
                overflow: Math.max(0, Audio.volume - 1)
                muted: Audio.muted
            }

            Text {
                id: reading
                anchors.left: dial.right
                anchors.leftMargin: root.capsuleGap
                anchors.verticalCenter: parent.verticalCenter
                width: root.figureWidth
                text: `${Audio.volumePercent}%`
                color: Theme.text
                opacity: Audio.muted ? 0.45 : 1
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontValue,
                    "weight": Typography.weightValue
                }))
            }

            // The travel is the travel: this slider runs to a hundred, and
            // what is above it was asked for deliberately with the wheel and
            // is shown on the dial's outer arc. A bar that silently held a
            // hundred and fifty would make every ordinary setting land in its
            // first two thirds.
            Slider {
                anchors.left: reading.right
                anchors.leftMargin: root.capsuleGap
                anchors.verticalCenter: parent.verticalCenter
                width: root.sliderWidth
                factor: root.factor
                value: Math.min(1, Audio.volume)
                dimmed: Audio.muted
                onMoved: value => Audio.setVolume(value)
            }
        }
    }

    // ---- The thread ---------------------------------------------------------

    Thread {
        id: descent

        readonly property real headY: root.upward ? devices.y + devices.height
                                                  : capsule.y + capsule.height
        readonly property real footY: root.upward ? capsule.y : devices.y

        vertical: true
        progress: root.linkProgress
        width: implicitWidth
        height: Math.max(0, descent.footY - descent.headY)
        x: root.width / 2 - width / 2
        y: descent.headY
    }

    // ---- The three wells ----------------------------------------------------

    Panel {
        id: devices

        metrics: root.metrics
        padding: root.panelPadding
        targetWidth: root.panelWidth
        targetHeight: root.panelHeight
        growth: root.panelProgress
        contentReady: root.panelProgress > 0.999

        anchorX: 0
        anchorY: root.panelY
        nodeX: root.width / 2
        nodeY: root.upward ? devices.anchorY + root.panelHeight : devices.anchorY

        Column {
            anchors.fill: parent
            spacing: root.wellSpacing

            // Where the sound goes.
            Well {
                id: outputWell
                metrics: root.metrics
                inset: root.wellInset
                width: parent.width
                height: root.outputsHeight

                WellLabel {
                    x: root.wellInset
                    y: root.wellPadding
                    metrics: root.metrics
                    text: "OUTPUT"
                }

                Scroller {
                    flick: outputList
                    factor: root.factor
                    x: outputWell.width - width - 4 * root.factor
                }

                ListView {
                    id: outputList
                    x: root.wellInset
                    y: root.wellPadding + root.labelHeight
                    width: outputWell.width - root.wellInset * 2
                    height: outputWell.height - y - root.wellPadding
                    model: root.outputs
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    delegate: DeviceRow {
                        required property var modelData

                        width: ListView.view.width
                        factor: root.factor
                        metrics: root.metrics
                        node: modelData
                        chosen: Audio.isDefaultOutput(modelData)
                        onPicked: Audio.setDefaultOutput(modelData)
                    }
                }
            }

            // Where it comes from.
            Well {
                id: inputWell
                metrics: root.metrics
                inset: root.wellInset
                width: parent.width
                height: root.inputsHeight

                WellLabel {
                    x: root.wellInset
                    y: root.wellPadding
                    metrics: root.metrics
                    text: "INPUT"
                }

                Scroller {
                    flick: inputList
                    factor: root.factor
                    x: inputWell.width - width - 4 * root.factor
                }

                ListView {
                    id: inputList
                    x: root.wellInset
                    y: root.wellPadding + root.labelHeight
                    width: inputWell.width - root.wellInset * 2
                    height: inputWell.height - y - root.wellPadding
                    model: root.inputs
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    delegate: DeviceRow {
                        required property var modelData

                        width: ListView.view.width
                        factor: root.factor
                        metrics: root.metrics
                        node: modelData
                        chosen: Audio.isDefaultInput(modelData)
                        onPicked: Audio.setDefaultInput(modelData)
                    }
                }
            }

            // Who is making it.
            Well {
                id: streamWell
                metrics: root.metrics
                inset: root.wellInset
                width: parent.width
                height: root.streamsHeight

                WellLabel {
                    x: root.wellInset
                    y: root.wellPadding
                    metrics: root.metrics
                    text: "APPLICATIONS"
                }

                Scroller {
                    flick: streamList
                    factor: root.factor
                    x: streamWell.width - width - 4 * root.factor
                }

                // The well keeps its height with nothing in it, and says why
                // it is empty rather than standing as a blank surface.
                Text {
                    anchors.centerIn: parent
                    visible: root.streams.length === 0
                    text: "Nothing is playing"
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }

                ListView {
                    id: streamList
                    x: root.wellInset
                    y: root.wellPadding + root.labelHeight
                    width: streamWell.width - root.wellInset * 2
                    height: streamWell.height - y - root.wellPadding
                    model: root.streams
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    delegate: StreamRow {
                        required property var modelData

                        width: ListView.view.width
                        factor: root.factor
                        metrics: root.metrics
                        node: modelData
                    }
                }
            }
        }
    }

    // What the membrane has to mask and blur: the surfaces, never the threads.
    function shapes() {
        return [
            { "item": capsule, "radius": capsule.radius },
            { "item": devices, "radius": devices.radius }
        ];
    }
}
