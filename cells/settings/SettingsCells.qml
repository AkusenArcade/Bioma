import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.cells

// When each cell exists.
//
// One row per cell in the catalogue, with its visibility as a small segmented
// control: always, or conditional. **Every cell answers a keybind** whatever
// this says — on a membrane it opens where it is, in a floating slot it appears
// there, and placed nowhere on the monitor it comes up in the middle — so the
// only question left here is whether it is on screen without being asked for.
// Where it is, is the Structure page's.
//
// Options a cell cannot wear stay in the track, dimmed: a window title with no
// window has nothing to say, so it is conditional and nothing else, and seeing
// that is how the shell explains itself.
//
// A cell that is in no tissue at all has neither answer — both need somewhere
// to be — and its row says it is reached by keybind only.
//
// What "conditional" means is different for every cell, so each row can say
// it: the question mark beside the choice opens the sentence under the row,
// grown out of it, one row at a time. The sentences are the Registry's.
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real listRow: 38 * factor
    readonly property real indexWidth: 26 * factor

    // The row whose condition is being read, by type.
    property string explained: ""

    readonly property real helpSize: 18 * factor
    readonly property real notePadding: 10 * factor
    readonly property real noteGap: 6 * factor

    readonly property var membranes: Config.get("membranes", [])
    readonly property var floats: Config.get("floating", [])

    // The catalogue's own order, which is the order the cells were built in
    // and reads as a tour of the shell rather than an alphabet.
    readonly property var order: Object.keys(Registry.names)

    // Where a cell is declared, if it is declared anywhere. The first
    // declaration wins: the same cell on two monitors is one answer here,
    // because the visibility of a domain is a property of the domain.
    function find(type) {
        for (let m = 0; m < root.membranes.length; m++) {
            const tissues = root.membranes[m].tissues || [];
            for (let t = 0; t < tissues.length; t++) {
                const cells = tissues[t].cells || [];
                for (let c = 0; c < cells.length; c++)
                    if (Registry.canonical(cells[c].type) === type)
                        return { "list": "membranes", "m": m, "t": t, "c": c, "entry": cells[c] };
            }
        }
        for (let f = 0; f < root.floats.length; f++) {
            const cells = root.floats[f].cells || [];
            for (let c = 0; c < cells.length; c++)
                if (Registry.canonical(cells[c].type) === type)
                    return { "list": "floating", "m": f, "t": -1, "c": c, "entry": cells[c] };
        }
        return null;
    }

    readonly property var rows: {
        const out = [];
        for (const type of root.order) {
            const found = root.find(type);
            const rule = found ? (found.entry.visibility || ({})) : ({});
            const floating = found !== null && found.list === "floating";
            const fixed = floating ? Registry.fixedWhenFloating(type) : "";
            out.push({
                "type": type,
                "name": Registry.nameOf(type),
                "placed": found !== null,
                "floating": floating,
                "state": found ? (fixed || rule.type || "always") : ""
            });
        }
        return out;
    }

    // Writing it back means writing the whole list: a membrane list is one
    // value to the merge (arrays replace, they do not append), and what lands
    // in the override is the layout as it stands with one word changed.
    //
    // **Every** declaration of that cell changes, on every monitor. This page
    // has one row per cell because when a cell exists is a property of the
    // cell, not of the copy of it on the second screen — a clock that is
    // always on one edge and invoked on the other is not a setting anybody
    // asked for, it is one of the two having been missed.
    function apply(type, kind) {
        for (const list of ["membranes", "floating"]) {
            const whole = list === "membranes" ? root.membranes : root.floats;
            const copy = JSON.parse(JSON.stringify(whole));
            let touched = false;

            for (let i = 0; i < copy.length; i++) {
                const groups = list === "membranes" ? (copy[i].tissues || []) : [copy[i]];
                for (const group of groups) {
                    for (const entry of (group.cells || [])) {
                        if (Registry.canonical(entry.type) !== type)
                            continue;
                        entry.visibility = root.ruled(entry.visibility, kind, type);
                        touched = true;
                    }
                }
            }

            if (touched)
                Config.set(list, Registry.renamed(copy));
        }
    }

    // Only the kind is written. What a condition means — its thresholds, how
    // long it waits to be believed and how long the cell stays — is the
    // domain's, in `Registry.grammar`, and figures copied into the block
    // would freeze it: the next time a condition is redefined, a cell that
    // was switched here would keep the old one. Switching also drops figures
    // an earlier version of this page copied in.
    function ruled(existing, kind, type) {
        const rule = Object.assign({}, existing || ({}));
        rule.type = kind;
        delete rule.enter;
        delete rule.exit;
        delete rule.confirm;
        delete rule.dwell;
        delete rule.invocable;
        return rule;
    }

    Scroller {
        flick: list
        factor: root.factor
        x: root.width - width
    }

    ListView {
        id: list

        anchors.fill: parent
        anchors.rightMargin: 8 * root.factor
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        delegate: Item {
            id: row

            required property var modelData
            required property int index

            readonly property bool open: root.explained === row.modelData.type
            readonly property string condition: Registry.conditionOf(row.modelData.type)

            // 0 closed, 1 open: the note under the row grows by height from
            // the row itself, and its words arrive once it is there.
            property real growth: row.open ? 1 : 0
            Behavior on growth {
                NumberAnimation {
                    duration: row.open ? Timing.grow : Timing.close
                    easing.type: Easing.Bezier
                    easing.bezierCurve: row.open ? Timing.easeOpen : Timing.easeClose
                }
            }

            readonly property real noteHeight: noteText.implicitHeight + root.notePadding * 2

            // The row's own line, which everything in it is centred on while
            // the note grows under it.
            Item {
                id: line
                width: parent.width
                height: root.listRow
            }

            width: ListView.view.width
            height: root.listRow + (root.noteGap + row.noteHeight) * row.growth

            // The number is the machine counting, so it is tabular and faint:
            // it is there to make the list countable, not to be read.
            Text {
                id: ordinal

                anchors.left: parent.left
                anchors.verticalCenter: line.verticalCenter
                width: root.indexWidth
                text: String(row.index + 1).padStart(2, "0")
                color: Theme.textFaint
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta
                }))
            }

            Text {
                anchors.left: ordinal.right
                anchors.right: extra.visible ? extra.left : help.left
                anchors.rightMargin: 12 * root.factor
                anchors.verticalCenter: line.verticalCenter
                text: row.modelData.name
                elide: Text.ElideRight
                color: row.modelData.placed ? Theme.text : Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: 14 * root.factor
            }

            // Placed nowhere, it has no rest state to choose — it is there
            // when it is asked for, and that is what the row says.
            Text {
                id: keybindOnly
                anchors.right: parent.right
                anchors.rightMargin: 6 * root.factor
                anchors.verticalCenter: line.verticalCenter
                visible: !row.modelData.placed
                text: "KEYBIND ONLY"
                color: Theme.textFaint
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                         Typography.labelTracking)
                })
            }

            // What a cell may carry beyond when it appears. The dock, only: the
            // launcher at its head (`dock.launcher`).
            Row {
                id: extra

                anchors.right: help.left
                anchors.rightMargin: 12 * root.factor
                anchors.verticalCenter: line.verticalCenter
                spacing: 8 * root.factor
                visible: row.modelData.type === "dock" && row.modelData.placed

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "LAUNCHER"
                    color: Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }

                Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    factor: root.factor
                    on: Config.get("dock.launcher", false)
                    onToggled: value => Config.set("dock.launcher", value)
                }
            }

            // The question: what "conditional" means for this one.
            Item {
                id: help

                anchors.right: row.modelData.placed ? choice.left : keybindOnly.left
                anchors.rightMargin: 10 * root.factor
                anchors.verticalCenter: line.verticalCenter
                width: root.helpSize
                height: width
                visible: row.condition.length > 0

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: row.open ? Qt.alpha(Theme.primary, 0.16) : "transparent"
                    border.width: Metrics.rim(Screen.devicePixelRatio)
                    border.color: row.open ? Theme.primary : helpHover.hovered ? Theme.text : Theme.line
                }

                Text {
                    anchors.centerIn: parent
                    text: "?"
                    color: row.open || helpHover.hovered ? Theme.text : Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightLabel
                    })
                }

                HoverHandler { id: helpHover }
                TapHandler {
                    onTapped: root.explained = row.open ? "" : row.modelData.type
                }
            }

            Segmented {
                id: choice

                anchors.right: parent.right
                anchors.verticalCenter: line.verticalCenter

                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                buttonHeight: 22 * root.factor
                buttonPadding: 10 * root.factor

                current: row.modelData.state

                visible: row.modelData.placed

                options: [
                    { "key": "always", "label": "Always",
                      "dimmed": !Registry.allowsIn(row.modelData.type, "always", row.modelData.floating) },
                    { "key": "conditional", "label": "Conditional",
                      "dimmed": !Registry.allowsIn(row.modelData.type, "conditional", row.modelData.floating) }
                ]

                onChose: key => root.apply(row.modelData.type, key)
            }

            // The note: a well under the row, as tall as the growth allows,
            // with the sentence arriving once it is whole.
            Well {
                x: ordinal.width
                y: root.listRow + root.noteGap * row.growth
                width: parent.width - ordinal.width
                height: row.noteHeight * row.growth
                visible: row.growth > 0
                metrics: root.metrics
                inset: 10 * root.factor

                Text {
                    id: noteText
                    x: root.notePadding
                    y: root.notePadding
                    width: parent.width - root.notePadding * 2
                    text: row.condition
                    wrapMode: Text.WordWrap
                    opacity: row.growth > 0.999 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }
            }
        }
    }
}
