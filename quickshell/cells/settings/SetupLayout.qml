import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The setup's first step: one of the three layouts Bioma ships.
//
// Choosing one applies it, live: the desktop recomposes behind the panel, and
// the panel stays where it is, because every shipped preset keeps the
// settings cell at the right end of the top membrane. A layout kept under no
// name — the setup run again over a composition of the user's — is asked
// about first, in its own row, as on the Structure page.
//
// Each row draws its preset: the monitor as an outline, the tissues as bars on
// their edges, the organisms as the panels they are. A name and a sentence
// cannot say how much a layout puts on the screen; the drawing does at once.
//
// See docs/design/SETUP.md, step 1.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    property string armed: ""

    function choose(name) {
        if (Presets.active === name && !Presets.changed) {
            Setup.note("layout", name);
            return;
        }
        if (!Presets.kept && root.armed !== name) {
            root.armed = name;
            return;
        }
        root.armed = "";
        Presets.apply(name);
        Setup.note("layout", name);
    }

    // The layout on screen is the step's answer, however it got there.
    readonly property string summary: Presets.active.length === 0 ? ""
        : Presets.active + (Presets.changed ? ", changed" : "")
    onSummaryChanged: if (root.summary.length > 0) Setup.note("layout", root.summary)
    Component.onCompleted: if (root.summary.length > 0) Setup.note("layout", root.summary)

    // The primary screen's proportions, for the drawing.
    readonly property var screen: {
        for (const screen of Quickshell.screens)
            if (screen.name === Monitors.primary)
                return screen;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }
    readonly property real screenWidth: root.screen ? root.screen.width : 1920
    readonly property real screenHeight: root.screen ? root.screen.height : 1080

    // An organism's panel, in units, by kind (docs/design/ORGANISMS.md).
    function template(entry) {
        switch (entry.type) {
        case "lava":
        case "osmosis":
            return [1, 2];
        case "media":
        case "calendar":
        case "agenda":
        case "rings":
        case "vacuole":
        case "sediment":
            return [2, 2];
        case "vitals":
            return entry.layout === "square" ? [2, 2] : [2, 1];
        default:
            return [2, 1];
        }
    }

    Column {
        anchors.fill: parent
        spacing: 10 * root.factor

        Repeater {
            model: Presets.shipped

            delegate: Item {
                id: row

                required property var modelData

                readonly property bool chosen: Presets.active === row.modelData.name && !Presets.changed
                readonly property bool asking: root.armed === row.modelData.name

                width: parent.width
                height: 76 * root.factor

                readonly property bool navigable: true
                readonly property bool keyed: Focus.marked === row

                onKeyedChanged: if (!row.keyed && !hover.hovered && row.asking) root.armed = ""

                function activate() {
                    root.choose(row.modelData.name);
                }

                KeyMark {
                    factor: root.factor
                }

                Rectangle {
                    anchors.fill: parent
                    radius: root.metrics.radiusWell
                    antialiasing: true
                    color: row.asking ? Qt.alpha(Theme.alert, 0.12)
                         : hover.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent"
                    border.width: Metrics.rim(Screen.devicePixelRatio)
                    border.color: row.asking ? Theme.alert
                                : row.chosen ? Theme.primary : Qt.alpha(Theme.line, 0.7)
                }

                // The schematic: the monitor, its membranes' tissues as bars,
                // its organisms as panels.
                Item {
                    id: schematic

                    anchors.left: parent.left
                    anchors.leftMargin: 11 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96 * root.factor
                    height: 54 * root.factor

                    readonly property real scaleX: width / root.screenWidth
                    readonly property real scaleY: height / root.screenHeight
                    readonly property color ink: row.chosen ? Theme.primary : Theme.textMuted
                    readonly property real bar: 4 * root.factor
                    readonly property real inset: 4 * root.factor

                    Rectangle {
                        anchors.fill: parent
                        radius: 6 * root.factor
                        color: "transparent"
                        border.width: Metrics.rim(Screen.devicePixelRatio)
                        border.color: Theme.line
                        antialiasing: true
                    }

                    // Every tissue on a horizontal edge, placed by its anchor
                    // and its share of the edge.
                    Repeater {
                        model: {
                            const out = [];
                            for (const membrane of row.modelData.membranes || []) {
                                const edge = membrane.edge || "top";
                                if (edge !== "top" && edge !== "bottom")
                                    continue;
                                const tissues = membrane.tissues || [];
                                const span = schematic.width - schematic.inset * 2;
                                let start = schematic.inset;
                                let end = schematic.width - schematic.inset;
                                tissues.forEach((tissue, index) => {
                                    const anchor = tissue.anchor
                                        || (tissue.growth === "symmetric" ? "centre"
                                            : index === 0 ? "start"
                                            : index === tissues.length - 1 ? "end" : "centre");
                                    const length = Math.max(6 * root.factor,
                                                            span * (tissue.percentage || 30) / 100 * 0.7);
                                    let x = (schematic.width - length) / 2;
                                    if (anchor === "start") {
                                        x = start;
                                        start += length + 2 * root.factor;
                                    } else if (anchor === "end") {
                                        x = end - length;
                                        end -= length + 2 * root.factor;
                                    }
                                    out.push({ "x": x, "width": length, "bottom": edge === "bottom" });
                                });
                            }
                            return out;
                        }

                        delegate: Rectangle {
                            required property var modelData
                            x: modelData.x
                            y: modelData.bottom ? schematic.height - schematic.inset - schematic.bar
                                                : schematic.inset
                            width: modelData.width
                            height: schematic.bar
                            radius: height / 2
                            color: schematic.ink
                            antialiasing: true
                        }
                    }

                    // The organisms, on their grid points. A module is a unit
                    // and a gap, 224 at the normal step; the grid starts under
                    // the top membrane.
                    Repeater {
                        model: row.modelData.organisms || []

                        delegate: Rectangle {
                            required property var modelData

                            readonly property var size: root.template(modelData)
                            readonly property real module: 224
                            readonly property real originY: 60

                            x: (24 + (modelData.col || 0) * module) * schematic.scaleX
                            y: (originY + (modelData.row || 0) * module) * schematic.scaleY
                            width: (size[0] * 224 - 24) * schematic.scaleX
                            height: (size[1] * 224 - 24) * schematic.scaleY
                            radius: 1.5 * root.factor
                            color: Qt.alpha(schematic.ink, 0.35)
                            antialiasing: true
                        }
                    }
                }

                Column {
                    anchors.left: schematic.right
                    anchors.leftMargin: 16 * root.factor
                    anchors.right: dot.left
                    anchors.rightMargin: 12 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * root.factor

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.asking ? "DISCARD THE LAYOUT ON SCREEN?"
                                         : row.modelData.name.toUpperCase()
                        color: row.asking ? Theme.alert : row.chosen ? Theme.primary : Theme.text
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": Math.round(12 * root.factor),
                            "weight": row.chosen ? Typography.weightTitle : Typography.weightLabel,
                            "letterSpacing": Typography.tracking(Math.round(12 * root.factor), 0.04)
                        })
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: row.asking ? "It is kept under no name. Press again to replace it."
                                         : row.modelData.line
                        color: Theme.textMuted
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }
                }

                // The choice is exclusive, so the mark may be a dot.
                Rectangle {
                    id: dot
                    anchors.right: parent.right
                    anchors.rightMargin: 16 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6 * root.factor
                    height: width
                    radius: width / 2
                    color: Theme.primary
                    opacity: row.chosen ? 1 : 0
                    antialiasing: true
                }

                HoverHandler {
                    id: hover
                    onHoveredChanged: if (!hovered && row.asking) root.armed = ""
                }

                TapHandler {
                    onTapped: row.activate()
                }
            }
        }

        SetupLine {
            metrics: root.metrics
            visible: Quickshell.screens.length > 1
            color: Theme.textMuted
            text: "These are for the primary screen. The others start empty; compose them in Settings → Structure."
        }
    }
}
