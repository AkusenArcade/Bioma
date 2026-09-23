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
// See docs/design/CELLS.md §12.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real listRow: 38 * factor
    readonly property real indexWidth: 26 * factor

    readonly property var bands: Config.get("membranes", [])
    readonly property var floats: Config.get("floating", [])

    // The catalogue's own order, which is the order the cells were built in
    // and reads as a tour of the shell rather than an alphabet.
    readonly property var order: Object.keys(Registry.names)

    // Where a cell is declared, if it is declared anywhere. The first
    // declaration wins: the same cell on two monitors is one answer here,
    // because the visibility of a domain is a property of the domain.
    function find(type) {
        for (let m = 0; m < root.bands.length; m++) {
            const tissues = root.bands[m].tissues || [];
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
            out.push({
                "type": type,
                "name": Registry.nameOf(type),
                "placed": found !== null,
                "state": found ? (rule.type || "always") : ""
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
            const whole = list === "membranes" ? root.bands : root.floats;
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

            width: ListView.view.width
            height: root.listRow

            // The number is the machine counting, so it is tabular and faint:
            // it is there to make the list countable, not to be read.
            Text {
                id: ordinal

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
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
                anchors.right: choice.left
                anchors.rightMargin: 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                elide: Text.ElideRight
                color: row.modelData.placed ? Theme.text : Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: 14 * root.factor
            }

            // Placed nowhere, it has no rest state to choose — it is there
            // when it is asked for, and that is what the row says.
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 6 * root.factor
                anchors.verticalCenter: parent.verticalCenter
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

            Segmented {
                id: choice

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                buttonHeight: 22 * root.factor
                buttonPadding: 10 * root.factor

                current: row.modelData.state

                visible: row.modelData.placed

                options: [
                    { "key": "always", "label": "Always",
                      "dimmed": !Registry.allows(row.modelData.type, "always") },
                    { "key": "conditional", "label": "Conditional",
                      "dimmed": !Registry.allows(row.modelData.type, "conditional") }
                ]

                onChose: key => root.apply(row.modelData.type, key)
            }
        }
    }
}
