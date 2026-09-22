import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.cells

// When each cell exists.
//
// One row per cell in the catalogue, with its visibility as a small segmented
// control: always, conditional, invoked only. **Invoked only is named that way
// because every cell is invokable** — a shortcut opens it whatever it is. What
// the option decides is whether the cell exists *without* being asked for.
//
// Options a cell cannot wear stay in the track, dimmed: a window title with no
// window has nothing to say, so it is conditional and nothing else, and seeing
// that is how the shell explains itself.
//
// A cell that is in no tissue at all is invoked only and can be nothing else
// from here — the other two answers need somewhere to be, and giving it a
// place is the Structure page's work, not this one's.
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
                    if (cells[c].type === type)
                        return { "list": "membranes", "m": m, "t": t, "c": c, "entry": cells[c] };
            }
        }
        for (let f = 0; f < root.floats.length; f++) {
            const cells = root.floats[f].cells || [];
            for (let c = 0; c < cells.length; c++)
                if (cells[c].type === type)
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
                "state": found ? (rule.type || "always") : "invoked"
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
                        if (entry.type !== type)
                            continue;
                        entry.visibility = root.ruled(entry.visibility, kind);
                        touched = true;
                    }
                }
            }

            if (touched)
                Config.set(list, copy);
        }
    }

    // A condition needs thresholds, and a block that has only ever been
    // "always" carries none: without them the enter threshold is zero, every
    // condition is already met, and "conditional" would mean "always" with
    // extra words. What the block already says is kept — a cell put back to
    // conditional comes back to its own grammar, not to a default one.
    function ruled(existing, kind) {
        const rule = Object.assign({}, existing || ({}));
        rule.type = kind;

        if (kind === "conditional") {
            if (rule.enter === undefined) rule.enter = 1;
            if (rule.exit === undefined) rule.exit = 1;
            if (rule.confirm === undefined) rule.confirm = 0;
            if (rule.dwell === undefined) rule.dwell = 2000;
        }
        return rule;
    }

    ListView {
        id: list

        anchors.fill: parent
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

            Segmented {
                id: choice

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                buttonHeight: 22 * root.factor
                buttonPadding: 10 * root.factor

                current: row.modelData.state

                options: [
                    { "key": "always", "label": "Always",
                      "dimmed": !row.modelData.placed || !Registry.allows(row.modelData.type, "always") },
                    { "key": "conditional", "label": "Conditional",
                      "dimmed": !row.modelData.placed || !Registry.allows(row.modelData.type, "conditional") },
                    { "key": "invoked", "label": "Invoked only",
                      "dimmed": !row.modelData.placed || !Registry.allows(row.modelData.type, "invoked") }
                ]

                onChose: key => root.apply(row.modelData.type, key)
            }
        }
    }
}
