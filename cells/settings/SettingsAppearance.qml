import QtQuick
import Quickshell
import qs.core
import qs.components

// How the shell looks: the handful of numbers the whole of it is drawn from.
//
// Every row writes straight into the override layer, and every surface in the
// shell is bound to those values — so a slider moved here is the desktop
// changing under the hand, not a preview of one. That is also why there is no
// apply button: there is nothing to apply.
//
// Sliders are controls, so they keep the primary for their whole travel.
// Nothing here is a measurement and nothing here has a threshold.
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 44 * factor
    readonly property real labelWidth: 92 * factor
    readonly property real sliderWidth: 150 * factor

    // Each row: what it is called, where it is kept, its range, and how it
    // says itself. `step` snaps a travel to values that mean something — the
    // density scale has three, not a hundred.
    readonly property var rows: [
        { "label": "OPACITY", "key": "cell.opacity", "from": 0.3, "to": 1, "step": 0.01,
          "unit": "%", "scale": 100, "fallback": 0.72 },
        { "label": "RADIUS", "key": "appearance.radius", "from": 0, "to": 100, "step": 1,
          "unit": "%", "scale": 1, "fallback": 100 },
        { "label": "EDGE", "key": "appearance.edge", "from": 0, "to": 32, "step": 1,
          "unit": " px", "scale": 1, "fallback": 12 },
        { "label": "TISSUE", "key": "appearance.tissue", "from": 2, "to": 12, "step": 1,
          "unit": " px", "scale": 1, "fallback": 2 },
        { "label": "GAP", "key": "appearance.gap", "from": 8, "to": 48, "step": 1,
          "unit": " px", "scale": 1, "fallback": 24 }
    ]

    Column {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.rows

            delegate: Item {
                id: row

                required property var modelData

                readonly property real value: Config.get(row.modelData.key, row.modelData.fallback)

                width: parent.width
                height: root.rowHeight

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.labelWidth
                    text: row.modelData.label
                    color: Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary,
                        "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                             Typography.labelTracking)
                    })
                }

                Slider {
                    id: travel

                    anchors.left: parent.left
                    anchors.leftMargin: root.labelWidth + 12 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.sliderWidth
                    factor: root.factor

                    readonly property real span: row.modelData.to - row.modelData.from

                    value: (row.value - row.modelData.from) / travel.span

                    onMoved: fraction => {
                        const raw = row.modelData.from + fraction * travel.span;
                        const snapped = Math.round(raw / row.modelData.step) * row.modelData.step;
                        Config.set(row.modelData.key,
                                   Math.round(snapped * 1000) / 1000);
                    }
                }

                // The figure is a measurement, so it is written in the machine's
                // voice with tabular numerals: it changes while it is read.
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Math.round(row.value * row.modelData.scale)}${row.modelData.unit}`
                    color: Theme.textMuted
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary
                    }))
                }
            }
        }

        // Blur is not a number here. niri owns the radius of it — the shell
        // declares *where* to blur and the compositor decides how much — so
        // what Bioma can honestly offer is whether its cells are glass at all.
        Item {
            width: parent.width
            height: root.rowHeight

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelWidth
                text: "BLUR"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontSecondary,
                    "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                         Typography.labelTracking)
                })
            }

            Switch {
                anchors.left: parent.left
                anchors.leftMargin: root.labelWidth + 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                factor: root.factor
                on: Config.get("cell.blur", true)
                onToggled: value => Config.set("cell.blur", value)
            }
        }

        // The density step, which is three values and not a range: a slider
        // with three stops is a segmented control that has forgotten it.
        Item {
            width: parent.width
            height: root.rowHeight

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelWidth
                text: "SCALE"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontSecondary,
                    "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                         Typography.labelTracking)
                })
            }

            Segmented {
                anchors.left: parent.left
                anchors.leftMargin: root.labelWidth + 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                options: [
                    { "key": "compact", "label": "Compact" },
                    { "key": "normal", "label": "Normal" },
                    { "key": "comfortable", "label": "Comfortable" }
                ]
                current: Config.get("appearance.scale", "normal")
                onChose: key => Config.set("appearance.scale", key)
            }
        }

        // One set of durations, moved together: the shell has a tempo rather
        // than a hundred timings, and this is that tempo.
        Item {
            width: parent.width
            height: root.rowHeight

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelWidth
                text: "TIMING"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontSecondary,
                    "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                         Typography.labelTracking)
                })
            }

            Segmented {
                anchors.left: parent.left
                anchors.leftMargin: root.labelWidth + 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                options: [
                    { "key": "slow", "label": "Slow" },
                    { "key": "normal", "label": "Normal" },
                    { "key": "fast", "label": "Fast" }
                ]
                current: {
                    const speed = Config.get("timing.speed", 1);
                    return speed > 1.15 ? "slow" : speed < 0.85 ? "fast" : "normal";
                }
                onChose: key => Config.set("timing.speed",
                                           key === "slow" ? 1.4 : key === "fast" ? 0.7 : 1)
            }
        }
    }
}
