import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

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
        { "label": "TISSUE", "key": "tissue.padding", "from": 2, "to": 12, "step": 1,
          "unit": " px", "scale": 1, "fallback": 2 },
        { "label": "GAP", "key": "appearance.gap", "from": 8, "to": 48, "step": 1,
          "unit": " px", "scale": 1, "fallback": 24 }
    ]

    // Scale is a **membrane** property, not a global one — a smaller second
    // monitor may run `compact` — so there is no `appearance.scale` to write
    // and a row that wrote one moved nothing at all. This moves every membrane
    // together, which is what a person asking for a denser shell means; the
    // per-membrane choice belongs to the Structure page, beside the edge it
    // applies to.
    readonly property var membranes: Config.get("membranes", [])

    readonly property string density: {
        for (const membrane of root.membranes)
            if (membrane.scale)
                return membrane.scale;
        return "normal";
    }

    // The floating tissues go with them: a denser shell whose notifications
    // stayed at the normal step was not denser.
    function setDensity(name) {
        const copy = JSON.parse(JSON.stringify(root.membranes));
        for (const membrane of copy)
            membrane.scale = name;
        Config.set("membranes", copy);

        const floats = JSON.parse(JSON.stringify(Config.get("floating", [])));
        for (const tissue of floats)
            tissue.scale = name;
        Config.set("floating", floats);
    }

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

        // Whether the cells are glass at all, and how strong the glass is. The
        // shell declares *where* to blur; how much is niri's, in a section
        // that is global, so the strength is a step written into niri's
        // configuration (services/Looks.qml) and it moves every blurred
        // surface niri draws. One row, because the strength of glass that is
        // off means nothing: the slider dims with the switch.
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
                id: glass

                anchors.left: parent.left
                anchors.leftMargin: root.labelWidth + 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                factor: root.factor
                on: Config.get("cell.blur", true)
                onToggled: value => Config.set("cell.blur", value)
            }

            // It ends where the sliders above end, so the column holds.
            Slider {
                id: strength

                readonly property int steps: Metrics.blurSteps.length

                anchors.left: glass.right
                anchors.leftMargin: 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                width: root.sliderWidth - glass.width - 12 * root.factor
                factor: root.factor
                dimmed: !glass.on

                value: (Metrics.blurStrength - 1) / (strength.steps - 1)
                onMoved: fraction => Looks.setBlur(1 + fraction * (strength.steps - 1))
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: String(Metrics.blurStrength)
                color: Theme.textMuted
                opacity: glass.on ? 1 : 0.45
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontSecondary
                }))
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
                current: root.density
                onChose: key => root.setDensity(key)
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
