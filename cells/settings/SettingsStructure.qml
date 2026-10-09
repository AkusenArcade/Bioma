import QtQuick
import QtQuick.Effects
import Quickshell
import qs.core
import qs.components
import qs.cells

// How the shell is laid out: which tissues exist on which edge, and what is in
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
// side the tissues get too narrow for a percentage to mean anything, and the
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
    // own control lines up with the end of its last tissue.
    readonly property real slotsWidth: 3 * slotWidth + 2 * slotGap
    readonly property real chipHeight: 26 * factor
    readonly property real threadLength: metrics.gap

    readonly property var places: ["start", "centre", "end"]
    readonly property var edges: ["top", "bottom"]

    // ---- What is declared ---------------------------------------------------

    readonly property var membranes: Config.get("membranes", [])

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
        return root.claimsOn(block, root.monitor);
    }

    function claimsOn(block, monitor) {
        if (!block)
            return false;
        if (block.monitor === monitor)
            return true;
        return block.monitor === "primary" && root.outputs.length > 0
            && root.outputs[0].name === monitor;
    }

    function membraneFor(edge) {
        for (const block of root.membranes)
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
        const copy = JSON.parse(JSON.stringify(root.membranes));
        if (change(copy) === false)
            return;
        Config.set("membranes", Registry.renamed(copy));
    }

    // ---- Floating tissues --------------------------------------------------
    //
    // The tissues with no membrane: over the windows, anchored to a corner, the
    // middle or the pointer. They are part of the layout as much as the tissues on
    // a membrane are, and a layout with a part that cannot be seen from here is a layout
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
    // columns lined up with a membrane's three tissues.
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
        console.info(`Bioma: removing the ${place} tissue of the ${edge} membrane on ${root.monitor}`);
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
    // membrane with cells missing from it. A tissue has to hold everything
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

    // The narrowest this tissue may be declared and still hold what is in it,
    // which is what the width slider is not allowed below.
    function floorFor(edge, tissue) {
        const usable = root.usableOn(edge);
        if (usable <= 0)
            return 0;
        return Math.ceil(root.roomFor(edge, tissue, "") / usable * 100);
    }

    // ---- Moving a tissue, or copying it --------------------------------------
    //
    // MOVE or COPY takes the chosen tissue in hand, and every free place on the
    // page becomes somewhere to put it — the dashed slots on either edge and
    // the free floating anchors, on this monitor or, through the tabs, on
    // another. A place is a place and not a content, so only free ones take
    // it; a lit slot pressed meanwhile puts the tissue back and is chosen.
    //
    // What goes is the tissue whole — its cells in their order, their rules,
    // its padding and opacity — less whatever the monitor it lands on already
    // has: one place per cell per monitor, the rule the add row keeps. Copying
    // onto its own monitor therefore has nothing left to carry, and the page
    // says so on the slot instead of offering an empty tissue.

    property string transfer: ""       // "" | "move" | "copy"
    property var transferFrom: null    // { monitor, edge, place, floatIndex, tissue }

    function startTransfer(kind) {
        if (root.transfer === kind || !root.chosen) {
            root.transfer = "";
            root.transferFrom = null;
            return;
        }
        root.transferFrom = {
            "monitor": root.monitor,
            "edge": root.chosenEdge,
            "place": root.chosenPlace,
            "floatIndex": root.floatingChosen ? root.chosenSlot : -1,
            "tissue": JSON.parse(JSON.stringify(root.chosen))
        };
        root.transfer = kind;
        root.picking = false;
    }

    function endTransfer() {
        root.transfer = "";
        root.transferFrom = null;
    }

    readonly property bool moving: root.transfer === "move"

    // Whether the tissue in hand is drawn on the monitor the page shows —
    // what it gives up there, a move takes out of the way.
    readonly property bool sourceHere: {
        const from = root.transferFrom;
        if (!from)
            return false;
        return from.edge === "floating" ? root.floatShownHere(from.tissue)
                                        : from.monitor === root.monitor;
    }

    function isSource(edge, place) {
        const from = root.transferFrom;
        return from !== null && from.edge === edge && from.place === place
            && from.monitor === root.monitor;
    }

    function isFloatSource(index) {
        const from = root.transferFrom;
        return from !== null && from.edge === "floating" && from.floatIndex === index;
    }

    // The cells that go, for a landing on this monitor.
    readonly property var transferCells: {
        const from = root.transferFrom;
        if (!from)
            return [];
        const taken = root.placedHere.slice();
        if (root.moving && root.sourceHere)
            for (const entry of (from.tissue.cells || [])) {
                const at = taken.indexOf(Registry.canonical(entry.type));
                if (at >= 0)
                    taken.splice(at, 1);
            }
        return (from.tissue.cells || []).filter(entry =>
            taken.indexOf(Registry.canonical(entry.type)) < 0);
    }

    // Nothing to carry: every cell is here already.
    readonly property bool transferEmpty: root.transferFrom !== null
        && root.transferCells.length === 0 && (root.transferFrom.tissue.cells || []).length > 0

    // The share a tissue on this monitor would be given, or -1 where it will not
    // fit. It keeps the share it had, raised to what its cells need on this
    // monitor's width and held to what the other tissues on the edge leave.
    function shareAt(edge, place) {
        const from = root.transferFrom;
        if (!from || root.transferEmpty)
            return -1;
        const block = root.membraneFor(edge);
        let others = 0;
        const tissues = block ? (block.tissues || []) : [];
        for (let i = 0; i < tissues.length; i++) {
            const at = root.placeOf(tissues[i], i, tissues.length);
            if (root.moving && root.isSource(edge, at))
                continue;
            others += tissues[i].percentage || 0;
        }
        const usable = root.usableOn(edge);
        if (usable <= 0)
            return -1;
        const floor = Math.ceil(Registry.roomFor(root.transferCells, root.stepOf(edge)) / usable * 100);
        const free = 100 - others;
        const wanted = from.edge !== "floating" && from.tissue.percentage ? from.tissue.percentage : 25;
        const share = Math.min(Math.max(wanted, floor), free);
        return share >= floor && share > 0 ? share : -1;
    }

    // What a tissue is, apart from where it is.
    function carried() {
        const out = {};
        for (const key of ["padding", "opacity"])
            if (root.transferFrom.tissue[key] !== undefined)
                out[key] = root.transferFrom.tissue[key];
        out.cells = JSON.parse(JSON.stringify(root.transferCells));
        return out;
    }

    // The one write, of both lists at once when both change: see
    // `Config.setMany`.
    function place(edge, where) {
        const from = root.transferFrom;
        if (!from || root.transferEmpty)
            return;
        const share = edge === "floating" ? 0 : root.shareAt(edge, where);
        if (edge !== "floating" && share < 0)
            return;

        const membranes = JSON.parse(JSON.stringify(root.membranes));
        const floats = JSON.parse(JSON.stringify(root.floats));
        let membranesChanged = false;
        let floatsChanged = false;

        if (root.moving) {
            if (from.edge === "floating") {
                floats.splice(from.floatIndex, 1);
                floatsChanged = true;
            } else {
                const block = membranes.find(b => root.claimsOn(b, from.monitor) && b.edge === from.edge);
                if (block) {
                    const tissues = block.tissues || [];
                    block.tissues = tissues.filter((t, i) =>
                        root.placeOf(t, i, tissues.length) !== from.place);
                    if (block.tissues.length === 0)
                        membranes.splice(membranes.indexOf(block), 1);
                    membranesChanged = true;
                }
            }
        }

        const tissue = root.carried();
        let chosenIndex = -1;
        if (edge === "floating") {
            // Everywhere stays everywhere when it only changes anchor.
            const everywhere = from.edge === "floating"
                && (from.tissue.monitor === "all" || from.tissue.monitor === "*");
            tissue.anchor = where;
            tissue.monitor = everywhere ? from.tissue.monitor : root.monitor;
            tissue.orientation = "vertical";
            floats.push(tissue);
            chosenIndex = floats.length - 1;
            floatsChanged = true;
        } else {
            let block = membranes.find(b => root.claims(b) && b.edge === edge);
            if (!block) {
                block = {
                    "monitor": root.monitor,
                    "edge": edge,
                    "reserve_space": edge === "top",
                    "auto_hide": false,
                    "scale": "normal",
                    "tissues": []
                };
                membranes.push(block);
            }
            tissue.anchor = where;
            tissue.percentage = share;
            tissue.growth = where === "centre" ? "symmetric" : "inward";
            tissue.orientation = "horizontal";
            block.tissues = (block.tissues || []).concat([tissue]);
            root.order(block);
            chosenIndex = root.places.indexOf(where);
            membranesChanged = true;
        }

        console.info(`Bioma: ${root.transfer === "move" ? "moving" : "copying"} a tissue from `
                     + `${from.monitor} ${from.edge}${from.place ? " " + from.place : ""} to `
                     + `${root.monitor} ${edge} ${where} — ${tissue.cells.length} of `
                     + `${(from.tissue.cells || []).length} cells`);

        const pairs = [];
        if (membranesChanged)
            pairs.push(["membranes", Registry.renamed(membranes)]);
        if (floatsChanged)
            pairs.push(["floating", Registry.renamed(floats)]);
        Config.setMany(pairs);

        root.endTransfer();
        root.choose(edge, chosenIndex);
    }

    // ---- Presets -----------------------------------------------------------
    //
    // See core/Presets.qml. A press that would throw away a layout kept under
    // no name arms first and acts on the second press; leaving the chip
    // disarms it.

    readonly property string blankKey: "\u0000new"

    property string presetArmed: ""
    property string presetRemoving: ""
    property bool naming: false

    // What the dropdown says: the preset in use, or that the layout is kept
    // under no name. Whether the page still matches it is said beside the
    // name rather than after it, where an elided name would take it along.
    readonly property string presetLabel: Presets.active.length > 0 ? Presets.active
        : Presets.empty ? "EMPTY" : "UNSAVED"

    // The list the dropdown opens, and where it is born: the dropdown's own
    // bottom edge, read when it is pressed. The page under it scrolls, so a
    // scroll puts the list away rather than leaving it standing over a slot
    // it no longer belongs to.
    property bool presetsOpen: false
    property real presetOriginX: 0
    property real presetOriginY: 0

    function togglePresets() {
        if (root.presetsOpen) {
            root.presetsOpen = false;
            return;
        }
        const at = presetDrop.mapToItem(root, 0, presetDrop.height);
        root.presetOriginX = at.x;
        root.presetOriginY = at.y;
        root.endTransfer();
        root.picking = false;
        root.presetsOpen = true;
    }

    onPresetsOpenChanged: if (!root.presetsOpen) {
        root.presetArmed = "";
        root.presetRemoving = "";
    }

    property real presetGrowth: root.presetsOpen ? 1 : 0

    Behavior on presetGrowth {
        NumberAnimation {
            duration: root.presetsOpen ? Timing.grow : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.presetsOpen ? Timing.easeOpen : Timing.easeClose
        }
    }

    // Orbitron 12, the dropdown's figure in CELLS.md §07: a control and its
    // list are one family wherever they are.
    readonly property int fontControl: Math.round(12 * factor)

    readonly property real presetRowHeight: metrics.rowHeight
    readonly property real presetPadding: 6 * factor
    readonly property int presetRows: 8

    // Choosing one: put back at once when the layout on the page is kept
    // somewhere, asked first when it is kept nowhere.
    function choosePreset(name) {
        root.presetRemoving = "";
        if (Presets.active === name && !Presets.changed) {
            root.presetsOpen = false;
            return;
        }
        if (!Presets.kept && root.presetArmed !== name) {
            root.presetArmed = name;
            return;
        }
        root.presetArmed = "";
        root.presetsOpen = false;
        root.leave(() => Presets.apply(name));
    }

    function forgetPreset(name) {
        root.presetArmed = "";
        if (root.presetRemoving !== name) {
            root.presetRemoving = name;
            return;
        }
        root.presetRemoving = "";
        Presets.remove(name);
        if (Presets.saved.length <= 1)
            root.presetsOpen = false;
    }

    function startNaming() {
        root.presetsOpen = false;
        root.endTransfer();
        root.picking = false;
        root.presetArmed = "";
        root.presetRemoving = "";
        nameField.text = Presets.active;
        root.naming = true;
        nameField.selectAll();
        nameField.forceActiveFocus();
    }

    function finishNaming() {
        if (Presets.saveAs(nameField.text))
            root.naming = false;
    }

    onNamingChanged: if (!root.naming) nameField.focus = false

    // Another layout replaces this one whole: whatever was chosen or in hand
    // on the page belonged to the old one.
    function leave(change) {
        root.endTransfer();
        root.picking = false;
        if (root.cell)
            root.cell.slot = -1;
        change();
    }

    // ---- The chips, and their order ----------------------------------------
    //
    // The order of the cells in a tissue **is** the order they sit in on the
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
        // Upper case, as the organisms' chips are: the two pages add and show
        // their contents the same way.
        return (Registry.nameOf(entry.type) + (shown ? " · " + shown : "")).toUpperCase();
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
    // tissue's contents are not worth losing to it.
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
                console.warn("Bioma: the settings cell refused a reorder that changed the tissue");
                return false;
            }

            tissue.cells = next;
            return true;
        });
    }

    // **One place per cell per monitor.** A cell is in one tissue of one
    // membrane or in one floating slot, and that place is where a keybind
    // opens it — two would make the keybind a guess. So the add row offers only
    // what is nowhere on this monitor yet: not in this tissue, not in another
    // tissue on a membrane, not floating.
    readonly property var placedHere: {
        const out = [];
        for (const block of root.membranes) {
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
    // `panelHeight`). This is the fallback for a tissue with more cells than
    // that was measured for — it never moves while the content fits.
    // Everything below is drawn into it and keeps its own coordinates.
    //
    // While the preset list is out, its shape is cut out of the page: the list
    // draws a blurred copy of what it covers, the compositor's blur being of
    // what is behind the shell's surface and not of the page on it, and under
    // its translucent glass the sharp original showed through the copy. The
    // theme cell's dropdown does the same (cells/theme/ThemeExpansion.qml).
    Item {
        id: cutout

        anchors.fill: parent
        layer.enabled: root.presetGrowth > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: presetHole
        }

        Flickable {
            id: scroller

            // As wide as the page: the page is as wide as the tissues it
            // draws, and the scrollbar only shows while the page is moving.
            anchors.fill: parent
            contentWidth: width
            contentHeight: Math.max(height, detail.visible ? detail.y + detail.height
                                                           : layout.y + layout.height)
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            // A reorder is a drag, and the page must not scroll under it.
            interactive: !root.carrying

            onContentYChanged: root.presetsOpen = false
        }
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

        // Saved layouts, above the monitor tabs because a preset is every
        // monitor at once: the dropdown puts one back, the dashed chip starts
        // from nothing, SAVE AS keeps what is on the page under a name. A
        // dropdown rather than a chip per preset: a row of chips runs out of
        // room at the fourth name (Akusen, 2026-10-09), and a name is what is
        // remembered, as with the theme cell's palettes.
        Item {
            id: presetRow

            width: layout.width
            height: root.chipHeight

            Text {
                id: presetTitle
                height: root.chipHeight
                verticalAlignment: Text.AlignVCenter
                text: "PRESET"
                color: Presets.saved.length > 0 ? Theme.text : Theme.textFaint
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                         Typography.labelTracking)
                })
            }

            Row {
                visible: !root.naming
                anchors.left: parent.left
                anchors.leftMargin: 76 * root.factor
                spacing: 6 * root.factor

                // Always the same width and in the same place: only what it
                // says changes. The name is elided here; the list shows it
                // whole.
                Item {
                    id: presetDrop

                    readonly property bool usable: Presets.saved.length > 0

                    width: 240 * root.factor
                    height: root.chipHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        antialiasing: true
                        color: "transparent"
                        border.width: Metrics.rim(Screen.devicePixelRatio)
                        border.color: root.presetsOpen ? Theme.primary
                                    : presetDrop.usable && presetDropHover.hovered ? Theme.text
                                    : presetDrop.usable ? Theme.line : Qt.alpha(Theme.line, 0.5)
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12 * root.factor
                        anchors.right: presetState.visible ? presetState.left : presetChevron.left
                        anchors.rightMargin: 7 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.presetLabel
                        elide: Text.ElideRight
                        color: Presets.active.length > 0 ? Theme.text : Theme.textMuted
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.fontControl,
                            "weight": Typography.weightLabel,
                            "letterSpacing": Typography.tracking(root.fontControl, 0.04)
                        })
                    }

                    Text {
                        id: presetState
                        visible: Presets.active.length > 0 && Presets.changed
                        anchors.right: presetChevron.left
                        anchors.rightMargin: 8 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CHANGED"
                        color: Theme.textMuted
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                 Typography.labelTracking)
                        })
                    }

                    Icon {
                        id: presetChevron
                        anchors.right: parent.right
                        anchors.rightMargin: 12 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.factor
                        height: width
                        name: "chevron-down"
                        colour: Qt.alpha(Theme.text, presetDrop.usable ? 0.6 : 0.25)
                    }

                    HoverHandler { id: presetDropHover }

                    TapHandler {
                        onTapped: {
                            if (presetDrop.usable)
                                root.togglePresets();
                        }
                    }
                }

                // A place rather than a content, like every dashed shape on
                // this page: what is there once it is pressed is nothing.
                Item {
                    id: blankChip

                    readonly property bool armed: root.presetArmed === root.blankKey

                    width: blankLabel.implicitWidth + blankPlus.width + 30 * root.factor
                    height: root.chipHeight

                    DashedSlot {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(parent.height, root.metrics)
                        colour: blankChip.armed ? Theme.alert
                              : blankHover.hovered ? Theme.primary : Qt.alpha(Theme.line, 0.7)
                    }

                    Icon {
                        id: blankPlus
                        anchors.left: parent.left
                        anchors.leftMargin: 11 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.factor
                        height: width
                        name: "plus"
                        colour: blankLabel.color
                    }

                    Text {
                        id: blankLabel
                        anchors.left: blankPlus.right
                        anchors.leftMargin: 7 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: blankChip.armed ? "DISCARD CHANGES?" : "NEW"
                        color: blankChip.armed ? Theme.alert
                             : blankHover.hovered ? Theme.primary : Theme.textMuted
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                 Typography.labelTracking)
                        })
                    }

                    HoverHandler {
                        id: blankHover
                        onHoveredChanged: if (!hovered && blankChip.armed) root.presetArmed = ""
                    }

                    TapHandler {
                        onTapped: {
                            root.presetsOpen = false;
                            if (Presets.empty && Presets.active.length === 0)
                                return;
                            if (!Presets.kept && !blankChip.armed) {
                                root.presetArmed = root.blankKey;
                                return;
                            }
                            root.presetArmed = "";
                            root.leave(() => Presets.blank());
                        }
                    }
                }

                // Lit while there is something kept nowhere: a layout changed
                // since its preset, or one that never had a name.
                Choice {
                    metrics: root.metrics
                    label: "SAVE AS"
                    kind: Presets.changed ? "primary" : "plain"
                    onActivated: root.startNaming()
                }
            }

            // Naming it, in place of the chips: the name of the one in use is
            // offered, so keeping a change to it is SAVE AS and Enter.
            Row {
                visible: root.naming
                anchors.left: parent.left
                anchors.leftMargin: 76 * root.factor
                spacing: 8 * root.factor

                Rectangle {
                    width: 220 * root.factor
                    height: root.chipHeight
                    radius: Metrics.radiusFor(height, root.metrics)
                    antialiasing: true
                    color: "transparent"
                    border.width: Metrics.rim(Screen.devicePixelRatio)
                    border.color: nameField.activeFocus ? Theme.primary : Theme.line

                    TextInput {
                        id: nameField

                        anchors.left: parent.left
                        anchors.leftMargin: 14 * root.factor
                        anchors.right: parent.right
                        anchors.rightMargin: 14 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                        clip: true
                        selectByMouse: true
                        maximumLength: 32
                        selectionColor: Qt.alpha(Theme.primary, 0.35)
                        selectedTextColor: Theme.text

                        onActiveFocusChanged: if (root.cell && activeFocus) root.cell.fieldEngaged = true
                        onAccepted: root.finishNaming()
                        Keys.onEscapePressed: root.naming = false

                        Text {
                            visible: nameField.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "A name for this layout"
                            color: Theme.textFaint
                            font: nameField.font
                        }
                    }
                }

                Choice {
                    metrics: root.metrics
                    // Saying what it will do: a name already in the list is
                    // that preset written over.
                    label: Presets.find(nameField.text.trim()) ? "REPLACE" : "SAVE"
                    kind: "primary"
                    onActivated: root.finishNaming()
                }

                Choice {
                    metrics: root.metrics
                    label: "CANCEL"
                    onActivated: root.naming = false
                }
            }
        }

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

        // While a tissue is in hand: the one it came from, and whether this
        // free place takes it.
        readonly property bool source: root.transfer !== "" && spot.lit
                                       && root.isFloatSource(spot.entry.index)
        readonly property bool target: root.transfer !== "" && !spot.lit && !root.transferEmpty

        readonly property string content: {
            if (!spot.lit && root.transfer !== "") {
                if (root.transferEmpty)
                    return "ALREADY HERE";
                const total = (root.transferFrom.tissue.cells || []).length;
                const part = root.transferCells.length < total
                           ? `${root.transferCells.length} OF ${total}` : "";
                return [spot.label, part].filter(t => t.length > 0).join("  ·  ");
            }
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
            colour: spot.target ? Theme.primary : Qt.alpha(Theme.line, 0.7)
        }

        Rectangle {
            anchors.fill: parent
            visible: spot.lit
            radius: Metrics.shaped(11 * root.factor)
            antialiasing: true
            color: Qt.alpha(Theme.lift(Theme.background, spot.chosen ? 0.04 : 0.015), 0.9)
            border.width: Metrics.rim(Screen.devicePixelRatio)
            border.color: spot.chosen || spot.source ? Theme.primary : Theme.line
        }

        Text {
            anchors.centerIn: parent
            width: parent.width - 16 * root.factor
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: spot.content.length > 0
            text: spot.content
            color: spot.target ? Theme.primary
                 : spot.chosen ? Theme.text : spot.lit ? Theme.textMuted : Theme.textFaint
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
            }))
        }

        Icon {
            anchors.centerIn: parent
            visible: !spot.lit && spot.content.length === 0
            width: 11 * root.factor
            height: width
            name: "plus"
            colour: spot.target ? Theme.primary : Theme.textFaint
        }

        TapHandler {
            onTapped: {
                if (root.transfer !== "") {
                    if (spot.target) {
                        root.place("floating", spot.anchor);
                    } else if (spot.lit) {
                        root.endTransfer();
                        root.choose("floating", spot.entry.index);
                    }
                    return;
                }
                if (spot.lit)
                    root.choose("floating", spot.entry.index);
                else
                    root.addFloatAt(spot.anchor);
            }
        }
    }

    // MOVE or COPY: a word in a pill, primary while the tissue is in hand.
    component TransferButton: Item {
        id: button

        property string kind: "move"
        property string label: ""

        readonly property bool lit: root.transfer === button.kind

        width: buttonLabel.implicitWidth + 16 * root.factor + 6 * root.factor
        height: 22 * root.factor

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            color: button.lit ? Qt.alpha(Theme.primary, 0.16) : "transparent"
            border.width: Metrics.rim(Screen.devicePixelRatio)
            border.color: button.lit ? Theme.primary : buttonHover.hovered ? Theme.text : Theme.line
        }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            color: button.lit ? Theme.text : Theme.textMuted
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                     Typography.labelTracking)
            })
        }

        HoverHandler { id: buttonHover }
        TapHandler { onTapped: root.startTransfer(button.kind) }
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

                        // While a tissue is in hand: where it came from, and
                        // the share it would have here — -1 where it will not
                        // fit or has nothing left to bring.
                        readonly property bool source: root.transfer !== ""
                            && root.isSource(edgeGroup.modelData, slot.modelData)
                        readonly property int share: root.transfer !== "" && !slot.lit
                            ? root.shareAt(edgeGroup.modelData, slot.modelData) : -1
                        readonly property bool target: slot.share >= 0

                        readonly property string offer: {
                            if (root.transfer === "" || slot.lit)
                                return "";
                            if (root.transferEmpty)
                                return "ALREADY HERE";
                            if (!slot.target)
                                return "NO ROOM";
                            const total = (root.transferFrom.tissue.cells || []).length;
                            const part = root.transferCells.length < total
                                       ? `  ·  ${root.transferCells.length} OF ${total}` : "";
                            return `${slot.share}%${part}`;
                        }

                        width: root.slotWidth
                        height: root.slotHeight

                        DashedSlot {
                            anchors.fill: parent
                            visible: !slot.lit
                            radius: Metrics.shaped(11 * root.factor)
                            colour: slot.target ? Theme.primary : Qt.alpha(Theme.line, 0.7)
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: slot.lit
                            radius: Metrics.shaped(11 * root.factor)
                            antialiasing: true
                            color: Qt.alpha(Theme.lift(Theme.background, slot.chosen ? 0.04 : 0.015),
                                            0.9)
                            border.width: Metrics.rim(Screen.devicePixelRatio)
                            border.color: slot.chosen || slot.source ? Theme.primary : Theme.line
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: slot.offer.length > 0
                            text: slot.offer
                            color: slot.target ? Theme.primary : Theme.textFaint
                            font: Typography.tabular(Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                     Typography.labelTracking)
                            }))
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
                            visible: !slot.lit && slot.offer.length === 0
                            width: 11 * root.factor
                            height: width
                            name: "plus"
                            colour: Theme.textFaint
                        }

                        TapHandler {
                            onTapped: {
                                if (root.transfer !== "") {
                                    if (slot.target) {
                                        root.place(edgeGroup.modelData, slot.modelData);
                                    } else if (slot.lit) {
                                        root.endTransfer();
                                        root.choose(edgeGroup.modelData, slot.index);
                                    }
                                    return;
                                }
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
        text: root.transfer !== ""
              ? "Pick a free place for it — here, or on another monitor"
              : "Pick a tissue to see what is in it"
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
        // what the tissue's place, its cells and the kinds being offered need.
        height: Math.max(root.height - y,
                         24 * root.factor + 30 * root.factor + 6 * root.factor + 22 * root.factor
                         + 12 * root.factor + root.chipRows * root.chipPitchY
                         + (root.picking ? 12 * root.factor + kindsRule.height + kinds.height : 0))

        Item {
            anchors.fill: parent
            anchors.margins: 12 * root.factor

            // What the tissue may be, and what it may not: the slider stops at
            // the width its own cells need, because a tissue narrower than that
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

                // Switching the tissue off. It sits here rather than on the slot
                // itself: a cross drawn inside the slot puts two tap handlers
                // under one press — the slot's own answered it as well and lit
                // the tissue again in the same frame, which read as the cross
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
                        border.width: Metrics.rim(Screen.devicePixelRatio)
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
                        text: "REMOVE TISSUE"
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

            // Taking the tissue somewhere else: moved, or copied to another
            // monitor. Lit while the tissue is in hand; pressed again, it puts
            // it back. A row of its own under the tissue's removal, the other
            // thing done to the tissue as a whole: the width row has no room
            // left for two more words beside its slider and its floor.
            Row {
                id: transferButtons

                anchors.top: width_.bottom
                anchors.topMargin: 6 * root.factor
                anchors.right: parent.right
                spacing: 8 * root.factor

                TransferButton { kind: "move"; label: "MOVE" }
                TransferButton { kind: "copy"; label: "COPY" }
            }

            // The cells in the tissue, in the order they are declared — which
            // is the order they sit in on the membrane, from the anchor
            // inward. Dragging one changes that order, the same gesture the
            // dock's icons answer to.
            Item {
                id: chips

                anchors.top: transferButtons.bottom
                anchors.topMargin: 12 * root.factor
                anchors.left: parent.left
                width: parent.width
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
                            border.width: Metrics.rim(Screen.devicePixelRatio)
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

            // ---- Adding one ------------------------------------------------
            //
            // The kinds that can still be placed, as a row of chips under the
            // tissue's own — the way an organism is added (Akusen, 2026-10-07:
            // one gesture for both pages). Only what is nowhere on this monitor
            // yet. One that will not fit stays in the row, dimmed and saying
            // so: seeing that the tissue is full is the answer to the question,
            // and hiding it would look like the cell not existing.

            // Where what is in the tissue ends and what could be added begins.
            DashedRule {
                id: kindsRule

                visible: root.picking
                anchors.top: chips.bottom
                anchors.topMargin: 2 * root.factor
                anchors.left: parent.left
                anchors.right: parent.right
            }

            Flow {
                id: kinds

                visible: root.picking
                anchors.top: kindsRule.bottom
                anchors.topMargin: 10 * root.factor
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6 * root.factor

                Text {
                    visible: root.absent.length === 0
                    text: "Every cell is on this monitor."
                    color: Theme.textFaint
                    font.family: Typography.expressive
                    font.pixelSize: 14 * root.factor
                    font.italic: true
                }

                Repeater {
                    model: root.absent

                    delegate: Item {
                        id: kind

                        required property var modelData

                        readonly property bool room: root.fits(root.chosenEdge, root.chosen, kind.modelData)

                        width: kindName.implicitWidth + 22 * root.factor
                        height: root.chipHeight

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            antialiasing: true
                            color: "transparent"
                            border.width: Metrics.rim(Screen.devicePixelRatio)
                            border.color: kind.room && kindHover.hovered ? Theme.primary
                                        : kind.room ? Theme.line : Qt.alpha(Theme.line, 0.5)
                        }

                        Text {
                            id: kindName
                            anchors.centerIn: parent
                            text: Registry.nameOf(kind.modelData).toUpperCase() + (kind.room ? "" : " · NO ROOM")
                            color: !kind.room ? Theme.textFaint
                                 : kindHover.hovered ? Theme.primary : Theme.text
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                     Typography.labelTracking)
                            })
                        }

                        HoverHandler { id: kindHover }

                        TapHandler {
                            enabled: kind.room
                            onTapped: root.addCell(kind.modelData)
                        }
                    }
                }
            }
        }
    }

    // ---- The list the preset dropdown opens ---------------------------------
    //
    // Born from the dropdown's bottom edge, over the page: one row per saved
    // layout, the one in use marked with a dot, a cross to forget one. A row
    // that would lose a layout kept under no name, or forget a preset, asks
    // first in its own place, and the second press answers.

    // A press anywhere else on the page puts the list away. Passive: what was
    // pressed still answers, as it would with no list out. On the page's
    // content rather than on the page: the Flickable takes the press, and a
    // handler on an item under it never hears of it.
    TapHandler {
        parent: scroller.contentItem
        onTapped: point => {
            if (!root.presetsOpen)
                return;
            const inside = (item) => {
                const at = item.mapFromItem(scroller.contentItem, point.position.x, point.position.y);
                return at.x >= 0 && at.y >= 0 && at.x <= item.width && at.y <= item.height;
            };
            if (!inside(presetList) && !inside(presetDrop))
                root.presetsOpen = false;
        }
    }

    TextMetrics {
        id: presetLongest
        text: Presets.saved.reduce((out, preset) => (preset.name || "").length > out.length
                                                    ? preset.name : out, "")
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.fontControl,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.fontControl, 0.04)
        })
    }

    // The list's shape, for the cut.
    Item {
        id: presetHole

        anchors.fill: parent
        visible: false
        layer.enabled: root.presetGrowth > 0

        Rectangle {
            x: presetList.x
            y: presetList.y
            width: presetList.width
            height: presetList.height
            radius: presetList.radius
            antialiasing: true
        }
    }

    Panel {
        id: presetList

        metrics: root.metrics
        radius: root.metrics.radiusWell
        padding: root.presetPadding
        // As wide as the dropdown, or as its longest name: the dropdown
        // elides, the list says it whole — as far as the page's edge. The
        // margins are the row's, plus what Orbitron paints past its measure.
        targetWidth: Math.min(Math.max(presetDrop.width,
                                       presetLongest.width + 72 * root.factor + root.presetPadding * 2),
                              root.width - root.presetOriginX)
        targetHeight: Math.min(Presets.saved.length, root.presetRows) * root.presetRowHeight
                      + root.presetPadding * 2
        growth: root.presetGrowth
        contentReady: root.presetGrowth > 0.999
        visible: root.presetGrowth > 0
        over: scroller

        anchorX: root.presetOriginX
        anchorY: root.presetOriginY + 6 * root.factor
        nodeX: root.presetOriginX + presetDrop.width / 2
        nodeY: root.presetOriginY

        // Glass over the page, and the page under it deaf while it is there:
        // in Qt 6 a press on an item does not stop the handlers of the items
        // below, so the list takes the pointer for itself.
        HoverHandler { blocking: true }
        TapHandler { gesturePolicy: TapHandler.WithinBounds }

        ListView {
            id: presetView

            width: presetList.targetWidth - root.presetPadding * 2
            height: Math.min(Presets.saved.length, root.presetRows) * root.presetRowHeight
            model: Presets.saved
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: option

                required property var modelData

                readonly property string name: option.modelData.name || ""
                readonly property bool current: Presets.active === option.name
                readonly property bool armed: root.presetArmed === option.name
                readonly property bool removing: root.presetRemoving === option.name
                readonly property bool alarmed: option.armed || option.removing

                width: presetView.width
                height: root.presetRowHeight

                // Lit under the pointer, red while it asks.
                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusFor(height, root.metrics)
                    antialiasing: true
                    color: option.alarmed ? Qt.alpha(Theme.alert, 0.12)
                         : optionHover.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent"
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10 * root.factor
                    anchors.right: optionDot.left
                    anchors.rightMargin: 8 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.removing ? "FORGET " + option.name.toUpperCase() + "?"
                        : option.armed ? "DISCARD CHANGES?"
                        : option.name
                    elide: Text.ElideRight
                    color: option.alarmed ? Theme.alert
                         : option.current ? Theme.text : Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.fontControl,
                        "weight": Typography.weightLabel,
                        "letterSpacing": Typography.tracking(root.fontControl, 0.04)
                    })
                }

                // The choice is exclusive, so the mark may be a dot.
                Rectangle {
                    id: optionDot
                    anchors.right: optionCross.left
                    anchors.rightMargin: 6 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: option.current ? 1 : 0
                    width: 6 * root.factor
                    height: width
                    radius: width / 2
                    color: Theme.primary
                    antialiasing: true
                }

                HoverHandler {
                    id: optionHover
                    onHoveredChanged: if (!hovered && option.alarmed) {
                        root.presetArmed = "";
                        root.presetRemoving = "";
                    }
                }

                // While it asks, the row **is** the question: a press
                // anywhere on it answers, the cross included.
                TapHandler {
                    gesturePolicy: TapHandler.WithinBounds
                    onTapped: {
                        if (option.removing)
                            root.forgetPreset(option.name);
                        else
                            root.choosePreset(option.name);
                    }
                }

                Item {
                    id: optionCross

                    anchors.right: parent.right
                    anchors.rightMargin: 4 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22 * root.factor
                    height: parent.height

                    Icon {
                        anchors.centerIn: parent
                        width: 9 * root.factor
                        height: width
                        name: "close"
                        colour: option.removing || optionCrossHover.hovered ? Theme.alert
                                                                            : Theme.textFaint
                    }

                    HoverHandler { id: optionCrossHover }

                    // Taking the press for itself: the row's own would put
                    // back the preset the cross was asked to forget.
                    TapHandler {
                        gesturePolicy: TapHandler.WithinBounds
                        onTapped: root.forgetPreset(option.name)
                    }
                }
            }
        }

        Scroller {
            flick: presetView
            factor: root.factor
            x: presetList.targetWidth - root.presetPadding * 2 - width
            visible: Presets.saved.length > root.presetRows
        }
    }
}
