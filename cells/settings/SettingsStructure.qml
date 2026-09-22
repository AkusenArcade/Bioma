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
    readonly property string chosenPlace: root.chosenSlot >= 0 ? root.places[root.chosenSlot] : ""
    readonly property var chosen: root.chosenPlace.length > 0
                                ? root.tissueAt(root.chosenEdge, root.chosenPlace) : null

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
        Config.set("membranes", copy);
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

    function addCell(edge, place, type) {
        root.edit(copy => {
            const block = root.blockIn(copy, edge, false);
            const tissue = block ? root.tissueIn(block, place) : null;
            if (!tissue)
                return false;
            tissue.cells = (tissue.cells || []).concat([{
                "type": type,
                "enabled": true,
                "visibility": { "type": Registry.allows(type, "always") ? "always" : "conditional" }
            }]);
            return true;
        });
        root.picking = false;
    }

    function removeCell(edge, place, index) {
        root.edit(copy => {
            const block = root.blockIn(copy, edge, false);
            const tissue = block ? root.tissueIn(block, place) : null;
            if (!tissue)
                return false;
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

    function fits(edge, tissue, extra) {
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

    readonly property var absent: {
        const out = [];
        if (!root.chosen)
            return out;
        const taken = [];
        for (const entry of (root.chosen.cells || []))
            taken.push(entry.type);
        for (const type in Registry.files)
            if (taken.indexOf(type) < 0)
                out.push(type);
        return out;
    }

    // ---- Drawing ------------------------------------------------------------

    Column {
        id: layout

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
            model: root.edges

            delegate: Column {
                id: edgeGroup

                required property var modelData

                readonly property var block: root.membraneFor(edgeGroup.modelData)

                width: layout.width
                spacing: 6 * root.factor

                Item {
                    width: parent.width
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
    }

    // With nothing chosen the page says what to do once, rather than showing
    // a large empty area under the slots.
    Text {
        visible: root.chosen === null
        x: 0
        y: layout.y + layout.height + root.threadLength + 20 * root.factor
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: "Pick a band to see what is in it"
        color: Theme.textFaint
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontTitle
    }

    // The thread from the chosen slot to what it opens, which is the same
    // sentence the categories use one level up.
    Thread {
        id: link

        visible: root.chosen !== null
        vertical: true
        progress: root.chosen !== null ? 1 : 0
        width: implicitWidth
        height: root.threadLength
        x: {
            const place = Math.max(0, root.chosenSlot);
            return place * (root.slotWidth + root.slotGap) + root.slotWidth / 2 - width / 2;
        }
        y: layout.y + layout.height
    }

    // ---- The chosen tissue --------------------------------------------------

    Well {
        id: detail

        visible: root.chosen !== null
        metrics: root.metrics
        width: root.width
        y: layout.y + layout.height + root.threadLength
        height: Math.max(0, root.height - y)

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

                readonly property int floor: root.chosen
                    ? root.floorFor(root.chosenEdge, root.chosen) : 0

                Text {
                    id: widthLabel
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

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: douserLabel.implicitWidth + 16 * root.factor + cross.width
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
                        anchors.leftMargin: 8 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.factor
                        height: width
                        colour: douserHover.hovered ? Theme.alert : Theme.textMuted
                        name: "close"
                    }

                    Text {
                        id: douserLabel

                        anchors.left: cross.right
                        anchors.leftMargin: 7 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: "REMOVE BAND"
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
                        onTapped: root.clear(root.chosenEdge, root.chosenPlace)
                    }
                }
            }

            // The cells in the band, in the order they are declared — which is
            // the order they sit in, from the anchor inward.
            Flow {
                id: chips

                anchors.top: width_.bottom
                anchors.topMargin: 12 * root.factor
                anchors.left: parent.left
                width: parent.width - root.pickerWidth - root.threadLength - 12 * root.factor
                spacing: 8 * root.factor

                Repeater {
                    model: root.chosen ? (root.chosen.cells || []) : []

                    delegate: Item {
                        id: chip

                        required property var modelData
                        required property int index

                        width: chipName.implicitWidth + 10 * root.factor + cross.width
                             + 8 * root.factor
                        height: root.chipHeight

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            antialiasing: true
                            color: Qt.alpha(Theme.lift(Theme.background, 0.02), 0.9)
                            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                            border.color: Theme.line
                        }

                        Text {
                            id: chipName
                            anchors.left: parent.left
                            anchors.leftMargin: 10 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: Registry.nameOf(chip.modelData.type)
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
                                onTapped: root.removeCell(root.chosenEdge, root.chosenPlace,
                                                          chip.index)
                            }
                        }
                    }
                }

                // The dashed chip adds one, and it is a place rather than a
                // content, exactly like the empty slot above.
                Item {
                    id: adder

                    width: 44 * root.factor
                    height: root.chipHeight

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
                            onTapped: root.addCell(root.chosenEdge, root.chosenPlace,
                                                   option.modelData)
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
