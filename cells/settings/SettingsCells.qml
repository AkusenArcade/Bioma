import QtQuick
import QtQuick.Effects
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

    // ---- The effect dropdown ---------------------------------------------------
    //
    // How the media band draws the sound. A dropdown rather than a segmented
    // control: the effects grow, and a row of buttons ran out of room beside
    // the visibility at the third (Akusen, 2026-10-11). Its list is born from
    // the dropdown's bottom edge, over the page, as the Structure page's
    // presets are.
    readonly property var effects: [
        { "key": "bars", "label": "BARS" },
        { "key": "plasma", "label": "PLASMA" },
        { "key": "vesicles", "label": "VESICLES" },
        { "key": "eardrum", "label": "EARDRUM" }
    ]
    readonly property string effect: Config.get("sinestesia.effect", "bars")
    readonly property string effectLabel: {
        for (const option of root.effects)
            if (option.key === root.effect)
                return option.label;
        return "BARS";
    }

    // Orbitron 12, the dropdown's figure in CELLS.md §07.
    readonly property int fontControl: Math.round(12 * factor)
    readonly property real effectWidth: 132 * factor
    readonly property real effectPadding: 6 * factor

    property bool effectsOpen: false
    property Item effectDrop: null
    property real effectOriginX: 0
    property real effectOriginY: 0

    function toggleEffects(drop) {
        if (root.effectsOpen) {
            root.effectsOpen = false;
            return;
        }
        root.effectDrop = drop;
        const at = drop.mapToItem(root, 0, drop.height);
        root.effectOriginX = at.x;
        root.effectOriginY = at.y;
        root.effectsOpen = true;
    }

    function chooseEffect(key) {
        root.effectsOpen = false;
        if (key !== root.effect)
            Config.set("sinestesia.effect", key);
    }

    property real effectGrowth: root.effectsOpen ? 1 : 0

    Behavior on effectGrowth {
        NumberAnimation {
            duration: root.effectsOpen ? Timing.grow : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.effectsOpen ? Timing.easeOpen : Timing.easeClose
        }
    }

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

    // While the effect list is out, its shape is cut out of the page: the list
    // draws a blurred copy of what it covers, and under its translucent glass
    // the sharp original showed through (cells/settings/SettingsStructure.qml).
    Item {
        id: cutout

        anchors.fill: parent
        layer.enabled: root.effectGrowth > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: effectHole
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

            onContentYChanged: root.effectsOpen = false

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

                // What a cell may carry beyond when it appears. The dock: the
                // launcher at its head (`dock.launcher`). Media: how the band draws
                // the sound (`sinestesia.effect`), which the media organism follows
                // too — so it is offered even when the cell is placed nowhere.
                Row {
                    id: extra

                    anchors.right: help.left
                    anchors.rightMargin: 12 * root.factor
                    anchors.verticalCenter: line.verticalCenter
                    spacing: 8 * root.factor
                    visible: (row.modelData.type === "dock" && row.modelData.placed)
                             || row.modelData.type === "media"

                    readonly property bool dock: row.modelData.type === "dock"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: extra.dock ? "LAUNCHER" : "EFFECT"
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
                        visible: extra.dock
                        factor: root.factor
                        on: Config.get("dock.launcher", false)
                        onToggled: value => Config.set("dock.launcher", value)
                    }

                    // Always the same width: only what it says changes.
                    Item {
                        id: effectDrop

                        anchors.verticalCenter: parent.verticalCenter
                        visible: !extra.dock
                        width: root.effectWidth
                        height: 22 * root.factor

                        readonly property bool navigable: visible

                        function activate() {
                            root.toggleEffects(effectDrop);
                        }

                        KeyMark {
                            factor: root.factor
                            outset: 3 * root.factor
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            antialiasing: true
                            color: "transparent"
                            border.width: Metrics.rim(Screen.devicePixelRatio)
                            border.color: root.effectsOpen ? Theme.primary
                                        : effectDropHover.hovered ? Theme.text : Theme.line
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10 * root.factor
                            anchors.right: effectChevron.left
                            anchors.rightMargin: 6 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.effectLabel
                            elide: Text.ElideRight
                            color: Theme.text
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "weight": Typography.weightLabel,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta, 0.04)
                            })
                        }

                        Icon {
                            id: effectChevron
                            anchors.right: parent.right
                            anchors.rightMargin: 10 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            width: 9 * root.factor
                            height: width
                            name: "chevron-down"
                            colour: Qt.alpha(Theme.text, 0.6)
                        }

                        HoverHandler { id: effectDropHover }

                        TapHandler {
                            onTapped: root.toggleEffects(effectDrop)
                        }
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

                    readonly property bool navigable: true

                    function activate() {
                        root.explained = row.open ? "" : row.modelData.type;
                    }

                    KeyMark {
                        factor: root.factor
                        outset: 3 * root.factor
                    }

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

    // ---- The list the effect dropdown opens ----------------------------------

    // A press anywhere else on the page puts the list away. Passive: what was
    // pressed still answers, as it would with no list out.
    TapHandler {
        parent: list.contentItem
        onTapped: point => {
            if (!root.effectsOpen)
                return;
            const inside = (item) => {
                if (!item)
                    return false;
                const at = item.mapFromItem(list.contentItem, point.position.x, point.position.y);
                return at.x >= 0 && at.y >= 0 && at.x <= item.width && at.y <= item.height;
            };
            if (!inside(effectList) && !inside(root.effectDrop))
                root.effectsOpen = false;
        }
    }

    // The list's shape, for the cut.
    Item {
        id: effectHole

        anchors.fill: parent
        opacity: 0
        layer.enabled: root.effectGrowth > 0

        Rectangle {
            x: effectList.x
            y: effectList.y
            width: effectList.width
            height: effectList.height
            radius: effectList.radius
            antialiasing: true
        }
    }

    Panel {
        id: effectList

        metrics: root.metrics
        radius: root.metrics.radiusWell
        padding: root.effectPadding
        targetWidth: root.effectWidth
        targetHeight: root.effects.length * root.metrics.rowHeight + root.effectPadding * 2
        growth: root.effectGrowth
        contentReady: root.effectGrowth > 0.999
        visible: root.effectGrowth > 0
        over: list

        // While it is out the arrows stay in it, and Escape puts it away
        // (see `Focus`).
        readonly property bool keyScope: root.effectsOpen

        function close() {
            root.effectsOpen = false;
            Focus.marked = root.effectDrop;
        }

        anchorX: root.effectOriginX
        anchorY: root.effectOriginY + 6 * root.factor
        nodeX: root.effectOriginX + root.effectWidth / 2
        nodeY: root.effectOriginY

        // Glass over the page, and the page under it deaf while it is there.
        HoverHandler { blocking: true }
        TapHandler { gesturePolicy: TapHandler.WithinBounds }

        Column {
            width: effectList.targetWidth - root.effectPadding * 2

            Repeater {
                model: root.effects

                delegate: Item {
                    id: option

                    required property var modelData

                    readonly property bool current: root.effect === option.modelData.key

                    width: parent.width
                    height: root.metrics.rowHeight

                    readonly property bool navigable: true

                    function activate() {
                        root.chooseEffect(option.modelData.key);
                    }

                    KeyMark {
                        factor: root.factor
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        antialiasing: true
                        color: optionHover.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent"
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10 * root.factor
                        anchors.right: optionDot.left
                        anchors.rightMargin: 8 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: option.modelData.label
                        elide: Text.ElideRight
                        color: option.current ? Theme.text : Theme.textMuted
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
                        anchors.right: parent.right
                        anchors.rightMargin: 10 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: option.current ? 1 : 0
                        width: 6 * root.factor
                        height: width
                        radius: width / 2
                        color: Theme.primary
                        antialiasing: true
                    }

                    HoverHandler { id: optionHover }

                    TapHandler {
                        gesturePolicy: TapHandler.WithinBounds
                        onTapped: option.activate()
                    }
                }
            }
        }
    }
}
