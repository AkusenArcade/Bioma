import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.cells

// How the shell is laid out: which bands exist on which edge, and what is in
// them.
//
// **Structure is composed, not listed.** Six slots drawn where they will
// actually be — three on the top membrane, three on the bottom — say at a
// glance what a list of tissues with percentages beside them never would, and
// they are the only form in which "add a tissue" has an obvious place: the
// empty slot. An unlit slot is dashed; click it to light it, empty it to
// switch it off.
//
// Six per monitor is a design limit, not a technical one: beyond three per
// side the bands get too narrow for a percentage to mean anything, and the
// membrane stops reading as a single line.
//
// The chosen slot feeds the detail below it through a thread — the same
// sentence the categories use, one level down.
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property real slotWidth: 196 * factor
    readonly property real slotHeight: 26 * factor
    readonly property real slotGap: 14 * factor

    // Three slots and two gaps: the page is drawn to this, so the membrane's
    // own control lines up with the end of its last band.
    readonly property real slotsWidth: 3 * slotWidth + 2 * slotGap
    readonly property real chipHeight: 26 * factor
    readonly property real rowHeight: 36 * factor
    readonly property real pickerWidth: 220 * factor
    readonly property real threadLength: metrics.gap

    readonly property var places: ["start", "centre", "end"]
    readonly property var edges: ["top", "bottom"]

    // ---- What is declared ---------------------------------------------------

    readonly property var bands: Config.get("membranes", [])

    // Bound rather than read inside a function: a compositor-backed model
    // answers empty to a call and fills to a binding.
    readonly property var outputs: {
        const out = [];
        for (const screen of Quickshell.screens)
            out.push(screen);
        return out;
    }

    readonly property string monitor: {
        const wanted = root.cell ? root.cell.monitor : "";
        for (const screen of root.outputs)
            if (screen.name === wanted)
                return wanted;
        return root.outputs.length > 0 ? root.outputs[0].name : "";
    }

    readonly property var screenItem: {
        for (const screen of root.outputs)
            if (screen.name === root.monitor)
                return screen;
        return null;
    }

    // A block may name a monitor or say `primary`, which is the first screen.
    function claims(block) {
        if (!block)
            return false;
        if (block.monitor === root.monitor)
            return true;
        return block.monitor === "primary" && root.outputs.length > 0
            && root.outputs[0].name === root.monitor;
    }

    function membraneFor(edge) {
        for (const block of root.bands)
            if (root.claims(block) && block.edge === edge)
                return block;
        return null;
    }

    // The same rule `Membrane.anchorFor` uses, so a slot is drawn where the
    // tissue will actually be. The page writes the anchor out explicitly from
    // then on: an empty middle slot must not move the two beside it.
    function placeOf(tissue, index, count) {
        if (tissue.anchor)
            return tissue.anchor;
        if (tissue.growth === "symmetric")
            return "centre";
        if (index === 0)
            return "start";
        if (index === count - 1)
            return "end";
        return "centre";
    }

    function tissueAt(edge, place) {
        const block = root.membraneFor(edge);
        if (!block)
            return null;
        const tissues = block.tissues || [];
        for (let i = 0; i < tissues.length; i++)
            if (root.placeOf(tissues[i], i, tissues.length) === place)
                return tissues[i];
        return null;
    }

    // What a percentage is worth on this membrane, in logical units.
    function stepOf(edge) {
        const block = root.membraneFor(edge);
        return Metrics.step(block && block.scale ? block.scale : "normal");
    }

    function usableOn(edge) {
        if (!root.screenItem)
            return 0;
        const step = root.stepOf(edge);
        return Math.max(0, root.screenItem.width - step.marginEdge * 2);
    }

    // ---- The chosen slot ----------------------------------------------------

    readonly property string chosenEdge: root.cell ? root.cell.slotEdge : "top"
    readonly property int chosenSlot: root.cell ? root.cell.slot : -1

    // A floating tissue is chosen by its place in the `floating` list — it
    // has no edge and no slot, and there may be any number of them.
    readonly property bool floatingChosen: root.chosenEdge === "floating"

    readonly property string chosenPlace: !root.floatingChosen && root.chosenSlot >= 0
                                          ? root.places[root.chosenSlot] : ""
    readonly property var chosen: {
        if (root.floatingChosen) {
            const entry = root.floatsHere.find(f => f.index === root.chosenSlot);
            return entry ? entry.block : null;
        }
        return root.chosenPlace.length > 0 ? root.tissueAt(root.chosenEdge, root.chosenPlace) : null;
    }

    function choose(edge, index) {
        if (!root.cell)
            return;
        root.cell.slotEdge = edge;
        root.cell.slot = index;
        root.picking = false;
    }

    property bool picking: false

    onChosenChanged: if (!root.chosen) root.picking = false;

    // ---- Writing it back ----------------------------------------------------
    //
    // Every change rewrites the whole list: an array is one value to the merge,
    // so what lands in the override is the layout as it stands with one thing
    // different in it.

    function edit(change) {
        const copy = JSON.parse(JSON.stringify(root.bands));
        if (change(copy) === false)
            return;
        Config.set("membranes", Registry.renamed(copy));
    }

    // ---- Floating tissues --------------------------------------------------
    //
    // The tissues with no membrane: over the windows, anchored to a corner, the
    // middle or the pointer. They are part of the layout as much as the bands
    // are, and a layout with a part that cannot be seen from here is a layout
    // somebody cannot fix — the default's notification column kept showing
    // every notification a second time on a desktop whose owner had put the
    // cell somewhere else, and nothing on this page said it was there.

    readonly property var floats: Config.get("floating", [])

    // A floating block names a monitor, says `primary` (the first screen) or
    // `all`; with nothing named it is the primary's.
    function floatShownHere(block) {
        const monitor = block.monitor || "primary";
        if (monitor === "all" || monitor === "*")
            return true;
        return root.claims({ "monitor": monitor });
    }

    readonly property var floatsHere: {
        const out = [];
        for (let i = 0; i < root.floats.length; i++)
            if (root.floatShownHere(root.floats[i]))
                out.push({ "index": i, "block": root.floats[i] });
        return out;
    }

    readonly property var anchorNames: ["top-left", "top", "top-right",
                                        "left", "centre", "right",
                                        "bottom-left", "bottom", "bottom-right"]

    // `center` is how the default layer spells it, and the surface reads both.
    function anchorOf(block) {
        const anchor = block && block.anchor ? block.anchor : "centre";
        return anchor === "center" ? "centre" : anchor;
    }

    function editFloats(change) {
        const copy = JSON.parse(JSON.stringify(root.floats));
        if (change(copy) === false)
            return;
        Config.set("floating", Registry.renamed(copy));
    }

    // **Where a floating tissue is, is which slot it is.** The nine anchors
    // are drawn as a small screen between the two edges, and the pointer as a
    // slot of its own: a row of slots whose order meant nothing, with the
    // place chosen somewhere else, drew a position that was not one. One
    // tissue per anchor on a monitor — two in one corner are drawn on top of
    // each other.
    function floatAt(anchor) {
        return root.floatsHere.find(f => root.anchorOf(f.block) === anchor) || null;
    }

    function addFloatAt(anchor) {
        if (root.floatAt(anchor))
            return;
        const at = root.floats.length;
        root.editFloats(copy => {
            copy.push({ "anchor": anchor, "monitor": root.monitor, "orientation": "vertical",
                        "cells": [] });
            return true;
        });
        root.choose("floating", at);
    }

    function removeFloat(index) {
        console.info(`Bioma: removing floating tissue ${index} on ${root.monitor}`);
        root.editFloats(copy => {
            if (index < 0 || index >= copy.length)
                return false;
            copy.splice(index, 1);
            return true;
        });
        if (root.cell)
            root.cell.slot = -1;
    }

    // Where an anchor sits on the small screen: its row and its column, the
    // columns lined up with the bands' own three.
    function spotOf(anchor) {
        const index = root.anchorNames.indexOf(anchor);
        return index < 0 ? { "row": 1, "column": 1 } : { "row": Math.floor(index / 3), "column": index % 3 };
    }

    // The chosen tissue, wherever it lives, changed in a copy of its list and
    // written back whole.
    function editChosen(change) {
        if (root.floatingChosen) {
            const index = root.chosenSlot;
            root.editFloats(copy => {
                const tissue = copy[index];
                return tissue ? change(tissue) : false;
            });
            return;
        }
        const edge = root.chosenEdge;
        const place = root.chosenPlace;
        root.edit(copy => {
            const block = root.blockIn(copy, edge, false);
            const tissue = block ? root.tissueIn(block, place) : null;
            return tissue ? change(tissue) : false;
        });
    }

    function blockIn(copy, edge, make) {
        for (const block of copy)
            if (root.claims(block) && block.edge === edge)
                return block;
        if (!make)
            return null;

        // A membrane the configuration has never mentioned: the top one cedes
        // a strip the way the default layer does, the bottom one does not —
        // only horizontal edges may reserve, and a dock that reserved would
        // keep a band of the screen for itself while it is away.
        const block = {
            "monitor": root.monitor,
            "edge": edge,
            "reserve_space": edge === "top",
            "auto_hide": false,
            "scale": "normal",
            "tissues": []
        };
        copy.push(block);
        return block;
    }

    function tissueIn(block, place) {
        const tissues = block.tissues || [];
        for (let i = 0; i < tissues.length; i++)
            if (root.placeOf(tissues[i], i, tissues.length) === place)
                return tissues[i];
        return null;
    }

    function order(block) {
        const rank = { "start": 0, "centre": 1, "end": 2 };
        block.tissues.sort((a, b) => rank[a.anchor || "centre"] - rank[b.anchor || "centre"]);
    }

    function light(edge, place) {
        root.edit(copy => {
            const block = root.blockIn(copy, edge, true);
            if (root.tissueIn(block, place))
                return false;
            block.tissues = (block.tissues || []).concat([{
                "anchor": place,
                "percentage": 25,
                "growth": place === "centre" ? "symmetric" : "inward",
                "orientation": "horizontal",
                "cells": []
            }]);
            root.order(block);
            return true;
        });
    }

    // Emptying a slot switches it off, and a membrane with no tissues left is
    // not a membrane: it goes, rather than staying as a surface with nothing
    // on it.
    function clear(edge, place) {
        console.info(`Bioma: removing the ${place} band of the ${edge} membrane on ${root.monitor}`);
        root.edit(copy => {
            const block = root.blockIn(copy, edge, false);
            if (!block)
                return false;
            const kept = [];
            const tissues = block.tissues || [];
            for (let i = 0; i < tissues.length; i++)
                if (root.placeOf(tissues[i], i, tissues.length) !== place)
                    kept.push(tissues[i]);
            block.tissues = kept;
            if (kept.length === 0)
                copy.splice(copy.indexOf(block), 1);
            return true;
        });
        if (root.chosenEdge === edge && root.chosenPlace === place && root.cell)
            root.cell.slot = -1;
    }

    function setPercentage(edge, place, value) {
        root.edit(copy => {
            const block = root.blockIn(copy, edge, false);
            const tissue = block ? root.tissueIn(block, place) : null;
            if (!tissue)
                return false;
            tissue.percentage = Math.round(value);
            return true;
        });
    }

    function setMode(edge, key) {
        root.edit(copy => {
            const block = root.blockIn(copy, edge, false);
            if (!block)
                return false;
            block.auto_hide = key === "hide";
            // Auto-hide implies reserving nothing: a strip kept for a membrane
            // that has slid out of view is a strip nobody can see or use.
            block.reserve_space = key === "fixed" && edge !== "left" && edge !== "right";
            return true;
        });
    }

    // A new block carries its kind and nothing else: what the condition
    // means is the domain's (`Registry.grammar`), and stays that way.
    function ruled(kind, type) {
        return { "type": kind };
    }

    function addCell(type) {
        root.editChosen(tissue => {
            const kind = Registry.allows(type, "always") ? "always" : "conditional";
            tissue.cells = (tissue.cells || []).concat([{
                "type": type,
                "enabled": true,
                // A conditional cell arrives with the grammar its domain
                // means, rather than with none — or with one generic figure.
                "visibility": root.ruled(kind, type)
            }]);
            return true;
        });
        root.picking = false;
    }

    function removeCell(index) {
        root.editChosen(tissue => {
            const kept = (tissue.cells || []).slice();
            kept.splice(index, 1);
            tissue.cells = kept;
            return true;
        });
    }

    // ---- Room ---------------------------------------------------------------
    //
    // The page refuses what will not fit rather than letting somebody build a
    // membrane with cells missing from it. A band has to hold everything
    // declared in it at every cell's narrowest — see `Registry.roomFor`.

    function grantedTo(edge, tissue) {
        return (tissue && tissue.percentage ? tissue.percentage : 0) / 100 * root.usableOn(edge);
    }

    function roomFor(edge, tissue, extra) {
        const cells = (tissue && tissue.cells ? tissue.cells : []).slice();
        if (extra)
            cells.push({ "type": extra, "enabled": true });
        return Registry.roomFor(cells, root.stepOf(edge));
    }

    // A floating tissue has no ceiling: nothing shares its surface.
    function fits(edge, tissue, extra) {
        if (edge === "floating")
            return true;
        return root.roomFor(edge, tissue, extra) <= root.grantedTo(edge, tissue) + 0.5;
    }

    // The narrowest this band may be declared and still hold what is in it,
    // which is what the width slider is not allowed below.
    function floorFor(edge, tissue) {
        const usable = root.usableOn(edge);
        if (usable <= 0)
            return 0;
        return Math.ceil(root.roomFor(edge, tissue, "") / usable * 100);
    }

    // ---- The chips, and their order ----------------------------------------
    //
    // The order of the cells in a band **is** the order they sit in on the
    // membrane, from the anchor inward, so changing it is changing the layout
    // — and it is changed by dragging one, the way the dock's icons are.
    //
    // The chips are uniform and laid out by hand rather than by a Flow: a row
    // that positions its own children cannot have one of them follow the
    // pointer, and equal widths make "which slot is the hand over" the same
    // arithmetic the dock uses rather than a search through varying widths.

    readonly property var cellsHere: root.chosen ? (root.chosen.cells || []) : []

    // Two cells of one domain in one tissue are told apart by what their
    // block asks of them — the notification column is an urgent cell above an
    // ordinary one.
    function chipLabel(entry) {
        const shown = entry.options && entry.options.show;
        return Registry.nameOf(entry.type) + (shown ? " · " + shown : "");
    }

    readonly property string longestName: {
        let out = "";
        for (const entry of root.cellsHere) {
            const name = root.chipLabel(entry);
            if (name.length > out.length)
                out = name;
        }
        return out;
    }

    TextMetrics {
        id: chipText
        text: root.longestName
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontMeta,
            "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
        })
    }

    readonly property real chipSpacing: 8 * factor
    readonly property real chipWidth: Math.max(62 * factor, chipText.width + 40 * factor)
    readonly property real chipPitchX: chipWidth + chipSpacing
    readonly property real chipPitchY: chipHeight + chipSpacing

    property real chipRoom: 0
    readonly property int perRow: Math.max(1, Math.floor((chipRoom + chipSpacing) / chipPitchX))
    readonly property int chipRows: Math.max(1, Math.ceil((cellsHere.length + 1) / perRow))

    function slotX(index) {
        return (index % root.perRow) * root.chipPitchX;
    }

    function slotY(index) {
        return Math.floor(index / root.perRow) * root.chipPitchY;
    }

    // ---- Carrying one -------------------------------------------------------

    property int held: -1
    property int gap: -1
    property real gripX: 0
    property real gripY: 0
    property real grabX: 0
    property real grabY: 0

    readonly property bool carrying: root.held >= 0

    // Where a chip sits while another is being carried: the ones between the
    // hole it left and the slot it is over move by one, and the rest do not
    // move at all.
    function restingIndex(index) {
        if (!root.carrying || index === root.held)
            return index;
        if (root.held < root.gap && index > root.held && index <= root.gap)
            return index - 1;
        if (root.held > root.gap && index >= root.gap && index < root.held)
            return index + 1;
        return index;
    }

    function take(index, x, y) {
        root.held = index;
        root.gap = index;
        root.gripX = x;
        root.gripY = y;
        root.grabX = x - root.slotX(index);
        root.grabY = y - root.slotY(index);
    }

    // The slot follows the pointer and may cross as many as the hand does: it
    // is the position divided by the pitch, not a step taken one neighbour at
    // a time.
    function carry(x, y) {
        if (!root.carrying)
            return;
        root.gripX = x;
        root.gripY = y;
        const column = Math.round((x - root.grabX) / root.chipPitchX);
        const row = Math.round((y - root.grabY) / root.chipPitchY);
        root.gap = Math.max(0, Math.min(root.cellsHere.length - 1,
                                        row * root.perRow + column));
    }

    // The one write, and it is refused unless the result is the same cells in
    // a different order: a reorder that has gained or lost one is a bug, and a
    // band's contents are not worth losing to it.
    function drop() {
        const from = root.held;
        const to = root.gap;
        root.held = -1;
        root.gap = -1;

        if (from < 0 || to < 0 || from === to)
            return;

        root.editChosen(tissue => {
            const next = (tissue.cells || []).slice();
            if (from >= next.length || to >= next.length)
                return false;
            next.splice(to, 0, next.splice(from, 1)[0]);

            const before = (tissue.cells || []).map(entry => entry.type).sort().join("\u0000");
            if (next.length !== (tissue.cells || []).length
                || before !== next.map(entry => entry.type).sort().join("\u0000")) {
                console.warn("Bioma: the settings cell refused a reorder that changed the band");
                return false;
            }

            tissue.cells = next;
            return true;
        });
    }

    // **One place per cell per monitor.** A cell is on one band of one
    // membrane or in one floating slot, and that place is where a keybind
    // opens it — two would make the keybind a guess. So the picker offers only
    // what is nowhere on this monitor yet: not in this tissue, not in another
    // band, not floating.
    readonly property var placedHere: {
        const out = [];
        for (const block of root.bands) {
            if (!root.claims(block))
                continue;
            for (const tissue of (block.tissues || []))
                for (const entry of (tissue.cells || []))
                    out.push(Registry.canonical(entry.type));
        }
        for (const f of root.floatsHere)
            for (const entry of (f.block.cells || []))
                out.push(Registry.canonical(entry.type));
        return out;
    }

    readonly property var absent: {
        const out = [];
        if (!root.chosen)
            return out;
        for (const type in Registry.files)
            if (root.placedHere.indexOf(type) < 0)
                out.push(type);
        return out;
    }


    // ---- Drawing ------------------------------------------------------------

    // The panel is sized so this page does not scroll (SettingsExpansion's
    // `panelHeight`). This is the fallback for a band with more cells than
    // that was measured for — it never moves while the content fits.
    // Everything below is drawn into it and keeps its own coordinates.
    Flickable {
        id: scroller

        // As wide as the page: the page is as wide as the bands it draws, and
        // the scrollbar only shows while the page is moving.
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, detail.visible ? detail.y + detail.height
                                                       : layout.y + layout.height)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        // A reorder is a drag, and the page must not scroll under it.
        interactive: !root.carrying
    }

    Scroller {
        flick: scroller
        factor: root.factor
        x: root.width - width
    }

    Column {
        id: layout

        parent: scroller.contentItem

        width: parent.width
        spacing: 10 * root.factor

        // One monitor at a time: six slots are already the most a person can
        // hold in their eye, and two monitors' worth side by side would be
        // twelve.
        Segmented {
            visible: root.outputs.length > 1
            metrics: root.metrics
            fontSize: root.metrics.fontMeta
            buttonHeight: 22 * root.factor
            buttonPadding: 12 * root.factor
            current: root.monitor
            options: {
                const out = [];
                for (const screen of root.outputs)
                    out.push({ "key": screen.name, "label": screen.name });
                return out;
            }
            onChose: key => {
                if (root.cell) {
                    root.cell.monitor = key;
                    root.cell.slot = -1;
                }
            }
        }

        Repeater {
            model: ["top"]
            delegate: edgeRow
        }

        // What floats over the screen sits between its two edges, where it
        // actually is: nine slots in three rows, the screen in small, each one
        // a place — lit when a tissue is anchored there, dashed and free when
        // not. The pointer is not a place on the screen, so it is a slot of
        // its own beside the name.
        Item {
            id: floatGroup

            width: layout.width
            height: floatTitle.height + 6 * root.factor + floatGrid.height

            Text {
                id: floatTitle
                height: 22 * root.factor
                verticalAlignment: Text.AlignVCenter
                text: "FLOATING"
                color: root.floatsHere.length > 0 ? Theme.text : Theme.textFaint
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                         Typography.labelTracking)
                })
            }

            FloatSlot {
                id: pointerSlot
                anchor: "pointer"
                label: "POINTER"
                x: root.slotsWidth - width
                width: root.slotWidth
                height: floatTitle.height
            }

            Grid {
                id: floatGrid

                y: floatTitle.height + 6 * root.factor
                columns: 3
                columnSpacing: root.slotGap
                rowSpacing: 6 * root.factor

                Repeater {
                    model: root.anchorNames

                    delegate: FloatSlot {
                        required property string modelData
                        anchor: modelData
                        width: root.slotWidth
                        height: root.slotHeight
                    }
                }
            }
        }

        Repeater {
            model: ["bottom"]
            delegate: edgeRow
        }
    }

    // One floating place. Lit, it says what is in it — the first cell and how
    // many more, and ALL when the tissue is on every monitor; dashed, it is
    // free and a press puts a tissue there.
    component FloatSlot: Item {
        id: spot

        property string anchor: "centre"
        property string label: ""

        readonly property var entry: root.floatAt(spot.anchor)
        readonly property bool lit: spot.entry !== null
        readonly property bool chosen: spot.lit && root.floatingChosen
                                       && root.chosenSlot === spot.entry.index

        readonly property string content: {
            if (!spot.lit)
                return spot.label;
            const cells = spot.entry.block.cells || [];
            const first = cells.length > 0 ? Registry.nameOf(cells[0].type).toUpperCase() : "EMPTY";
            const more = cells.length > 1 ? ` +${cells.length - 1}` : "";
            const monitor = spot.entry.block.monitor;
            const everywhere = monitor === "all" || monitor === "*" ? "  ·  ALL" : "";
            return (spot.label.length > 0 ? spot.label + "  ·  " : "") + first + more + everywhere;
        }

        DashedSlot {
            anchors.fill: parent
            visible: !spot.lit
            radius: Metrics.shaped(11 * root.factor)
        }

        Rectangle {
            anchors.fill: parent
            visible: spot.lit
            radius: Metrics.shaped(11 * root.factor)
            antialiasing: true
            color: Qt.alpha(Theme.lift(Theme.background, spot.chosen ? 0.04 : 0.015), 0.9)
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: spot.chosen ? Theme.primary : Theme.line
        }

        Text {
            anchors.centerIn: parent
            width: parent.width - 16 * root.factor
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: spot.content.length > 0
            text: spot.content
            color: spot.chosen ? Theme.text : spot.lit ? Theme.textMuted : Theme.textFaint
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
            }))
        }

        Icon {
            anchors.centerIn: parent
            visible: !spot.lit && spot.label.length === 0
            width: 11 * root.factor
            height: width
            name: "plus"
            colour: Theme.textFaint
        }

        TapHandler {
            onTapped: {
                if (spot.lit)
                    root.choose("floating", spot.entry.index);
                else
                    root.addFloatAt(spot.anchor);
            }
        }
    }

    // One membrane's row: its name, fixed or auto-hide, and its three slots.
    // Declared once and drawn above and below the floating row, because the
    // page is laid out the way the screen is.
    Component {
        id: edgeRow

        Column {
            id: edgeGroup

            required property var modelData

            // The page needs to know where each membrane's slots end, so the
            // thread can leave the one that was chosen.
            Component.onCompleted: {
                if (edgeGroup.modelData === "top")
                    root.topRow = edgeGroup;
                else
                    root.bottomRow = edgeGroup;
            }

            readonly property var block: root.membraneFor(edgeGroup.modelData)

            width: layout.width
            spacing: 6 * root.factor

            Item {
                width: root.slotsWidth
                height: 22 * root.factor

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: edgeGroup.modelData.toUpperCase()
                    color: edgeGroup.block ? Theme.text : Theme.textFaint
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightLabel,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }

                // Fixed or auto-hiding is the **membrane's** answer, not a
                // tissue's: it governs the whole edge, the dock included.
                Segmented {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: edgeGroup.block !== null
                    metrics: root.metrics
                    fontSize: root.metrics.fontMeta
                    buttonHeight: 22 * root.factor
                    buttonPadding: 10 * root.factor
                    options: [
                        { "key": "fixed", "label": "Fixed" },
                        { "key": "hide", "label": "Auto-hide" }
                    ]
                    current: edgeGroup.block && edgeGroup.block.auto_hide === true ? "hide" : "fixed"
                    onChose: key => root.setMode(edgeGroup.modelData, key)
                }
            }

            Row {
                spacing: root.slotGap

                Repeater {
                    model: root.places

                    delegate: Item {
                        id: slot

                        required property var modelData
                        required property int index

                        readonly property var tissue: root.tissueAt(edgeGroup.modelData,
                                                                    slot.modelData)
                        readonly property bool lit: slot.tissue !== null
                        readonly property bool chosen: root.chosenEdge === edgeGroup.modelData
                                                    && root.chosenSlot === slot.index

                        width: root.slotWidth
                        height: root.slotHeight

                        DashedSlot {
                            anchors.fill: parent
                            visible: !slot.lit
                            radius: Metrics.shaped(11 * root.factor)
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: slot.lit
                            radius: Metrics.shaped(11 * root.factor)
                            antialiasing: true
                            color: Qt.alpha(Theme.lift(Theme.background, slot.chosen ? 0.04 : 0.015),
                                            0.9)
                            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                            border.color: slot.chosen ? Theme.primary : Theme.line
                        }

                        // Empty, it says the slot is free. Lit, it says
                        // what is in it — the percentage and how many
                        // cells, which is the whole of a tissue.
                        Text {
                            anchors.centerIn: parent
                            visible: slot.lit
                            text: slot.lit
                                  ? `${slot.tissue.percentage || 0}%  ·  ${(slot.tissue.cells || []).length}`
                                  : ""
                            color: slot.chosen ? Theme.text : Theme.textMuted
                            font: Typography.tabular(Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta
                            }))
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: !slot.lit
                            width: 11 * root.factor
                            height: width
                            name: "plus"
                            colour: Theme.textFaint
                        }

                        TapHandler {
                            onTapped: {
                                if (!slot.lit)
                                    root.light(edgeGroup.modelData, slot.modelData);
                                root.choose(edgeGroup.modelData, slot.index);
                            }
                        }
                    }
                }
            }
        }
    }

    // With nothing chosen the page says what to do once, rather than showing
    // a large empty area under the slots.
    Text {
        parent: scroller.contentItem
        visible: root.chosen === null
        x: 0
        y: layout.y + layout.height + root.threadLength + 20 * root.factor
        width: scroller.width
        horizontalAlignment: Text.AlignHCenter
        text: "Pick a band or a floating tissue to see what is in it"
        color: Theme.textFaint
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontTitle
    }

    property Item topRow: null
    property Item bottomRow: null

    // Where the chosen slot ends, in the page's coordinates.
    readonly property real chosenBottom: {
        if (root.floatingChosen) {
            const anchor = root.chosen ? root.anchorOf(root.chosen) : "centre";
            if (anchor === "pointer")
                return layout.y + floatGroup.y + pointerSlot.y + pointerSlot.height;
            const row = root.spotOf(anchor).row;
            return layout.y + floatGroup.y + floatGrid.y
                 + (row + 1) * root.slotHeight + row * 6 * root.factor;
        }
        const group = root.chosenEdge === "bottom" ? root.bottomRow : root.topRow;
        return group ? layout.y + group.y + group.height : layout.y + layout.height;
    }

    // The thread from the chosen slot to what it opens, which is the same
    // sentence the categories use one level up. It leaves the slot itself and
    // runs *under* the rows below it, so it is never read as hanging from a
    // slot that was not chosen.
    Thread {
        id: link

        parent: scroller.contentItem
        visible: root.chosen !== null
        z: -1
        vertical: true
        progress: root.chosen !== null ? 1 : 0
        width: implicitWidth
        height: Math.max(0, layout.y + layout.height + root.threadLength - root.chosenBottom)
        x: {
            let place = Math.max(0, root.chosenSlot);
            if (root.floatingChosen) {
                const anchor = root.chosen ? root.anchorOf(root.chosen) : "centre";
                place = anchor === "pointer" ? 2 : root.spotOf(anchor).column;
            }
            return place * (root.slotWidth + root.slotGap) + root.slotWidth / 2 - width / 2;
        }
        y: root.chosenBottom
    }

    // ---- The chosen tissue --------------------------------------------------

    Well {
        id: detail

        parent: scroller.contentItem
        visible: root.chosen !== null
        metrics: root.metrics
        width: scroller.width
        y: layout.y + layout.height + root.threadLength
        // What is left of the page, or — past what the panel was sized for —
        // what the tissue's place and cells need. The picker is not counted:
        // it scrolls inside its own well.
        height: Math.max(root.height - y,
                         24 * root.factor + 30 * root.factor + 12 * root.factor
                         + root.chipRows * root.chipPitchY)

        Item {
            anchors.fill: parent
            anchors.margins: 12 * root.factor

            // What the band may be, and what it may not: the slider stops at
            // the width its own cells need, because a band narrower than that
            // draws a membrane with cells missing from it.
            Item {
                id: width_

                width: parent.width
                height: 30 * root.factor

                readonly property int floor: root.chosen && !root.floatingChosen
                    ? root.floorFor(root.chosenEdge, root.chosen) : 0

                // A floating tissue has no share of anything to set, and its
                // place is the slot it was chosen from; what is left to say is
                // where that is and on which monitors.
                Text {
                    visible: root.floatingChosen
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (!root.chosen || !root.floatingChosen)
                            return "";
                        const monitor = root.chosen.monitor || "primary";
                        const where = monitor === "all" || monitor === "*" ? "EVERY MONITOR"
                                    : monitor === "primary" ? "PRIMARY MONITOR" : monitor;
                        return root.anchorOf(root.chosen).toUpperCase() + "  ·  " + where;
                    }
                    color: Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }

                Text {
                    id: widthLabel
                    visible: !root.floatingChosen
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60 * root.factor
                    text: "WIDTH"
                    color: Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }

                Slider {
                    id: span

                    visible: !root.floatingChosen
                    anchors.left: widthLabel.right
                    anchors.leftMargin: 10 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: 180 * root.factor
                    factor: root.factor

                    value: root.chosen ? (root.chosen.percentage || 0) / 100 : 0
                    onMoved: fraction => {
                        const wanted = Math.max(width_.floor, Math.round(fraction * 100));
                        root.setPercentage(root.chosenEdge, root.chosenPlace, wanted);
                    }
                }

                Text {
                    visible: !root.floatingChosen
                    anchors.left: span.right
                    anchors.leftMargin: 10 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.chosen ? `${root.chosen.percentage || 0}%` : ""
                    color: Theme.textMuted
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary
                    }))
                }

                // The floor, said rather than only enforced: a slider that
                // stops with no reason given reads as a slider that is broken.
                Text {
                    anchors.right: douser.left
                    anchors.rightMargin: 14 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    visible: width_.floor > 0
                    text: `${width_.floor}% needed`
                    color: Theme.textFaint
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }

                // Switching the band off. It sits here rather than on the slot
                // itself: a cross drawn inside the slot puts two tap handlers
                // under one press — the slot's own answered it as well and lit
                // the band again in the same frame, which read as the cross
                // doing nothing at all. Here there is nothing above it.
                Item {
                    id: douser

                    // Measured rather than guessed: the leading margin, the
                    // cross, the space after it, the word, and the same margin
                    // on the other side. The guess was eleven pixels short and
                    // the word ran out of its own pill.
                    readonly property real inset: 8 * root.factor
                    readonly property real afterCross: 7 * root.factor

                    // Orbitron at this size paints wider than it measures —
                    // the last letter sat on the border with the arithmetic
                    // alone — so the trailing margin is given the difference.
                    readonly property real tail: 6 * root.factor

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: douser.inset * 2 + cross.width + douser.afterCross
                         + douserLabel.implicitWidth + douser.tail
                    height: 22 * root.factor

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        antialiasing: true
                        color: douserHover.hovered ? Qt.alpha(Theme.alert, 0.16) : "transparent"
                        border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                        border.color: douserHover.hovered ? Theme.alert : Theme.line
                    }

                    Icon {
                        id: cross

                        anchors.left: parent.left
                        anchors.leftMargin: douser.inset
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.factor
                        height: width
                        colour: douserHover.hovered ? Theme.alert : Theme.textMuted
                        name: "close"
                    }

                    Text {
                        id: douserLabel

                        anchors.left: cross.right
                        anchors.leftMargin: douser.afterCross
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.floatingChosen ? "REMOVE" : "REMOVE BAND"
                        color: douserHover.hovered ? Theme.alert : Theme.textMuted
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                 Typography.labelTracking)
                        })
                    }

                    HoverHandler { id: douserHover }

                    TapHandler {
                        onTapped: {
                            if (root.floatingChosen)
                                root.removeFloat(root.chosenSlot);
                            else
                                root.clear(root.chosenEdge, root.chosenPlace);
                        }
                    }
                }
            }

            // The cells in the band, in the order they are declared — which
            // is the order they sit in on the membrane, from the anchor
            // inward. Dragging one changes that order, the same gesture the
            // dock's icons answer to.
            Item {
                id: chips

                anchors.top: width_.bottom
                anchors.topMargin: 12 * root.factor
                anchors.left: parent.left
                width: parent.width - root.pickerWidth - root.threadLength - 12 * root.factor
                height: root.chipRows * root.chipPitchY

                Component.onCompleted: root.chipRoom = Qt.binding(() => chips.width)

                Repeater {
                    model: root.cellsHere

                    delegate: Item {
                        id: chip

                        required property var modelData
                        required property int index

                        readonly property bool carried: root.held === chip.index

                        width: root.chipWidth
                        height: root.chipHeight

                        // The one in the hand is above the others and follows
                        // the pointer; the rest travel to the slot the gap has
                        // left them.
                        z: chip.carried ? 2 : 1
                        x: chip.carried ? root.gripX - root.grabX
                                        : root.slotX(root.restingIndex(chip.index))
                        y: chip.carried ? root.gripY - root.grabY
                                        : root.slotY(root.restingIndex(chip.index))

                        Behavior on x {
                            enabled: !chip.carried
                            NumberAnimation {
                                duration: Timing.transition
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Timing.easeOpenFlat
                            }
                        }

                        Behavior on y {
                            enabled: !chip.carried
                            NumberAnimation {
                                duration: Timing.transition
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Timing.easeOpenFlat
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            antialiasing: true
                            color: Qt.alpha(Theme.lift(Theme.background,
                                                       chip.carried ? 0.05 : 0.02), 0.9)
                            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                            border.color: chip.carried ? Theme.primary : Theme.line
                        }

                        Text {
                            id: chipName
                            anchors.left: parent.left
                            anchors.leftMargin: 10 * root.factor
                            anchors.right: cross.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.chipLabel(chip.modelData)
                            elide: Text.ElideRight
                            color: Theme.text
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                     Typography.labelTracking)
                            })
                        }

                        Item {
                            id: cross

                            anchors.right: parent.right
                            anchors.rightMargin: 4 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18 * root.factor
                            height: parent.height

                            Icon {
                                anchors.centerIn: parent
                                width: 9 * root.factor
                                height: width
                                name: "close"
                                colour: crossArea.hovered ? Theme.text : Theme.textMuted
                            }

                            HoverHandler { id: crossArea }

                            TapHandler {
                                onTapped: root.removeCell(chip.index)
                            }
                        }

                        // Carried from where it was touched, not by its middle,
                        // and it may cross several slots in one movement.
                        DragHandler {
                            target: null

                            onActiveChanged: {
                                const here = chips.mapFromItem(null, centroid.scenePosition.x,
                                                               centroid.scenePosition.y);
                                if (active)
                                    root.take(chip.index, here.x, here.y);
                                else
                                    root.drop();
                            }

                            onCentroidChanged: {
                                if (!active)
                                    return;
                                const here = chips.mapFromItem(null, centroid.scenePosition.x,
                                                               centroid.scenePosition.y);
                                root.carry(here.x, here.y);
                            }
                        }
                    }
                }

                // The dashed chip adds one, and it is a place rather than a
                // content, exactly like the empty slot above. It keeps the
                // slot after the last cell, wherever the row happens to end.
                Item {
                    id: adder

                    width: 44 * root.factor
                    height: root.chipHeight
                    x: root.slotX(root.cellsHere.length)
                    y: root.slotY(root.cellsHere.length)

                    Behavior on x {
                        NumberAnimation {
                            duration: Timing.transition
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Timing.easeOpenFlat
                        }
                    }

                    DashedSlot {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(parent.height, root.metrics)
                        colour: root.picking ? Theme.primary : Qt.alpha(Theme.line, 0.7)
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: 11 * root.factor
                        height: width
                        name: "plus"
                        colour: root.picking ? Theme.primary : Theme.textFaint
                    }

                    TapHandler {
                        onTapped: root.picking = !root.picking
                    }
                }
            }

            // ---- The picker -----------------------------------------------
            //
            // It hangs off the add chip on a thread and lists only the cells
            // that are not in this band already. One that will not fit stays
            // on the list, dimmed and saying so: seeing that the band is full
            // is the answer to the question, and hiding it would look like the
            // cell not existing.

            Thread {
                id: pickerLink

                visible: root.picking
                vertical: false
                progress: root.picking ? 1 : 0
                width: root.threadLength
                height: implicitHeight
                x: chips.x + chips.width
                y: chips.y + root.chipHeight / 2 - height / 2
            }

            Well {
                id: picker

                visible: root.picking
                metrics: root.metrics
                inset: 6 * root.factor
                width: root.pickerWidth
                x: chips.x + chips.width + root.threadLength
                y: chips.y
                height: Math.min(parent.height - y, root.absent.length * root.rowHeight
                                 + 12 * root.factor)

                ListView {
                    id: options

                    anchors.fill: parent
                    anchors.margins: 6 * root.factor
                    model: root.absent
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    delegate: Item {
                        id: option

                        required property var modelData

                        readonly property bool room: root.fits(root.chosenEdge, root.chosen,
                                                               option.modelData)

                        width: ListView.view.width
                        height: root.rowHeight

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8 * root.factor
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: Registry.nameOf(option.modelData)
                            elide: Text.ElideRight
                            color: option.room ? Theme.text : Theme.textFaint
                            font.family: Typography.expressive
                            font.pixelSize: 14 * root.factor
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !option.room
                            text: "no room"
                            color: Theme.textFaint
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                     Typography.labelTracking)
                            })
                        }

                        TapHandler {
                            enabled: option.room
                            onTapped: root.addCell(option.modelData)
                        }
                    }
                }

                Scroller {
                    flick: options
                    factor: root.factor
                    x: picker.width - width - 4 * root.factor
                }
            }
        }
    }
}
