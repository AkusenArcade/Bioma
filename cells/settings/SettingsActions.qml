import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.components
import qs.services

// Quick actions: the macros the ring at the pointer runs (services/Actions.qml,
// cells/actions).
//
// Four wells, top to bottom, the order a macro is made in. The macros, as the
// round capsules the ring shows, in the ring's order, and a dashed NEW. The
// one chosen: its name, its icon, RUN to try it and DELETE. Its steps, one row
// each, read as a sentence; a press opens the row on what that step holds,
// and the arrows beside it move it or remove it. And the steps that can be
// added, one dashed chip for each kind, as the Structure page offers cells.
//
// Everything is written as it is changed, as on every other page.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var cell: null

    readonly property real factor: metrics.factor
    readonly property real inset: 14 * factor
    readonly property real headerHeight: 28 * factor
    readonly property real gap: 10 * factor
    readonly property real chipHeight: 28 * factor
    readonly property real capsule: 36 * factor
    readonly property real stepRow: 34 * factor

    readonly property font labelFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontSecondary,
        "letterSpacing": Typography.tracking(root.metrics.fontSecondary, Typography.labelTracking)
    })

    readonly property font metaFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontMeta,
        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
    })

    // ---- The list ------------------------------------------------------------

    // Read raw, so a position on this page is a position in what is written.
    readonly property var macros: {
        const list = Config.get("actions.macros", []);
        return Array.isArray(list) ? list : [];
    }

    property int selected: 0
    readonly property var macro: root.selected >= 0 && root.selected < root.macros.length
                                 ? root.macros[root.selected] : null
    readonly property var steps: root.macro && Array.isArray(root.macro.steps) ? root.macro.steps : []

    // The step whose row is open, or -1.
    property int editing: -1

    onSelectedChanged: {
        root.editing = -1;
        root.deleting = false;
        nameField.text = root.macro ? root.macro.name : "";
    }

    onMacroChanged: if (!nameField.activeFocus) nameField.text = root.macro ? root.macro.name : ""

    // The open step brought into view: one added at the end of a long list
    // opened below the panel's edge, out of sight.
    function reveal(item) {
        if (!item)
            return;
        const top = item.mapToItem(column, 0, 0).y;
        const bottom = top + item.height + root.gap;
        if (bottom > page.contentY + page.height)
            page.contentY = Math.min(bottom - page.height, Math.max(0, page.contentHeight - page.height));
        if (top < page.contentY)
            page.contentY = Math.max(0, top - root.gap);
    }

    // A line put in the middle of a sentence.
    function lowered(line) {
        return line.length > 0 ? line.charAt(0).toLowerCase() + line.slice(1) : line;
    }

    function change(mutate) {
        const list = JSON.parse(JSON.stringify(root.macros));
        mutate(list);
        Actions.write(list);
    }

    function freeName(base) {
        let n = 1;
        let name = base;
        while (root.macros.some(macro => macro.name === name))
            name = `${base} ${++n}`;
        return name;
    }

    function addMacro() {
        if (root.macros.length >= Actions.ringSize)
            return;
        const icon = Actions.icons[root.macros.length % Actions.icons.length].name;
        root.change(list => list.push({ "name": root.freeName("Action"), "icon": icon, "steps": [] }));
        root.selected = root.macros.length - 1;
    }

    function moveMacro(delta) {
        const to = root.selected + delta;
        if (!root.macro || to < 0 || to >= root.macros.length)
            return;
        root.change(list => list.splice(to, 0, list.splice(root.selected, 1)[0]));
        root.selected = to;
    }

    property bool deleting: false

    function deleteMacro() {
        if (!root.macro)
            return;
        if (!root.deleting) {
            root.deleting = true;
            return;
        }
        const at = root.selected;
        root.deleting = false;
        root.change(list => list.splice(at, 1));
        root.selected = Math.max(0, Math.min(at, root.macros.length - 1));
    }

    // A name is the macro's address — the ring says it and the key runs it —
    // so it is neither empty nor another macro's.
    readonly property string nameProblem: {
        const name = nameField.text.trim();
        if (name.length === 0)
            return "A quick action needs a name.";
        if (root.macros.some((macro, i) => i !== root.selected && macro.name === name))
            return "Another quick action already has this name.";
        return "";
    }

    function rename() {
        if (!root.macro || root.nameProblem.length > 0)
            return;
        const name = nameField.text.trim();
        if (name !== root.macro.name)
            root.change(list => list[root.selected].name = name);
    }

    function setIcon(name) {
        root.change(list => list[root.selected].icon = name);
    }

    function setStep(index, patch) {
        root.change(list => Object.assign(list[root.selected].steps[index], patch));
    }

    function addStep(type) {
        const kind = Actions.kinds[type];
        if (!root.macro || !kind)
            return;
        root.change(list => {
            const macro = list[root.selected];
            macro.steps = (macro.steps || []).concat([kind.fresh()]);
        });
        root.editing = root.steps.length - 1;
    }

    function moveStep(index, delta) {
        const to = index + delta;
        if (to < 0 || to >= root.steps.length)
            return;
        root.change(list => {
            const steps = list[root.selected].steps;
            steps.splice(to, 0, steps.splice(index, 1)[0]);
        });
        if (root.editing === index)
            root.editing = to;
    }

    function removeStep(index) {
        root.change(list => list[root.selected].steps.splice(index, 1));
        if (root.editing === index)
            root.editing = -1;
        else if (root.editing > index)
            root.editing--;
    }

    // ---- Shapes this page is made of ----------------------------------------------

    component Section: Well {
        id: section

        property string label: ""
        property alias trailing: trailingSlot.data
        default property alias content: body.data

        metrics: root.metrics
        width: parent.width
        height: root.inset * 2 + root.headerHeight + body.childrenRect.height
                + (body.childrenRect.height > 0 ? 6 * root.factor : 0)

        Text {
            x: root.inset
            y: root.inset
            height: root.headerHeight
            verticalAlignment: Text.AlignVCenter
            text: section.label
            color: Theme.text
            font: root.labelFont
        }

        Row {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            y: root.inset
            height: root.headerHeight
            spacing: 6 * root.factor
        }

        Column {
            id: body
            x: root.inset
            y: root.inset + root.headerHeight + 6 * root.factor
            width: section.width - root.inset * 2
            spacing: 10 * root.factor
        }
    }

    // What a person reads, so the human voice.
    component Line: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        color: Theme.text
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontSecondary
        lineHeight: 1.15
    }

    // A round capsule with a glyph: a macro in the ring, or an icon to give it.
    component Glyph: Item {
        id: glyph

        property string icon: ""
        property bool chosen: false
        property real size: root.capsule
        signal pressed()

        width: size
        height: size

        readonly property bool navigable: true
        function activate() { glyph.pressed(); }

        KeyMark {
            factor: root.factor
            outset: 2 * root.factor
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            color: glyph.chosen ? Qt.alpha(Theme.primary, 0.14) : "transparent"
            border.width: Metrics.rim(Screen.devicePixelRatio)
            border.color: glyph.chosen ? Theme.primary
                        : glyphHover.hovered ? Theme.text : Theme.line
        }

        Icon {
            anchors.centerIn: parent
            width: 20 * root.factor
            height: width
            name: glyph.icon
            colour: Theme.text
            gradient: glyph.chosen
        }

        HoverHandler { id: glyphHover }
        TapHandler { onTapped: glyph.pressed() }
    }

    // A place for something not there yet, as on the Structure page.
    component Offer: Item {
        id: offer

        property string label: ""
        signal pressed()

        width: offerLabel.implicitWidth + offerPlus.width + 30 * root.factor
        height: root.chipHeight

        readonly property bool navigable: true
        function activate() { offer.pressed(); }

        KeyMark {
            factor: root.factor
            outset: 3 * root.factor
        }

        DashedSlot {
            anchors.fill: parent
            radius: Metrics.radiusFor(parent.height, root.metrics)
            colour: offerHover.hovered ? Theme.primary : Qt.alpha(Theme.line, 0.7)
        }

        Icon {
            id: offerPlus
            anchors.left: parent.left
            anchors.leftMargin: 11 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 9 * root.factor
            height: width
            name: "plus"
            colour: offerLabel.color
        }

        Text {
            id: offerLabel
            anchors.left: offerPlus.right
            anchors.leftMargin: 7 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: offer.label
            color: offerHover.hovered ? Theme.primary : Theme.text
            font: root.metaFont
        }

        HoverHandler { id: offerHover }
        TapHandler { onTapped: offer.pressed() }
    }

    // A one-line field, outlined, in the human voice.
    component Field: Rectangle {
        id: field

        property alias text: input.text
        property alias input: input
        property string placeholder: ""
        property bool wrong: false
        property int maximumLength: 32767
        signal accepted()
        signal released()

        height: root.chipHeight
        radius: Metrics.radiusFor(height, root.metrics)
        antialiasing: true
        color: "transparent"
        border.width: Metrics.rim(Screen.devicePixelRatio)
        border.color: field.wrong ? Theme.alert : input.activeFocus ? Theme.primary : Theme.line

        readonly property bool navigable: !input.activeFocus

        function activate() {
            if (root.cell)
                root.cell.fieldKeyed = true;
            Focus.type(input);
        }

        KeyMark {
            factor: root.factor
            outset: 2 * root.factor
        }

        TextInput {
            id: input

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
            selectionColor: Qt.alpha(Theme.primary, 0.35)
            selectedTextColor: Theme.text
            maximumLength: field.maximumLength

            onActiveFocusChanged: {
                if (root.cell && activeFocus)
                    root.cell.fieldEngaged = true;
                if (!activeFocus)
                    field.released();
            }
            onAccepted: {
                field.accepted();
                focus = false;
            }

            Text {
                visible: input.text.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                color: Theme.textFaint
                font: input.font
            }
        }
    }

    // An error lives where it happened, under the field, in Spectral.
    component Problem: Row {
        property string text: ""
        visible: text.length > 0
        spacing: 6 * root.factor
        height: visible ? implicitHeight : 0

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 12 * root.factor
            height: width
            name: "error"
            colour: Theme.alert
        }

        Text {
            text: parent.text
            color: Theme.alert
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }

    // A small press on a row: move. Removing is `RemoveTool`, which asks.
    component Tool: Item {
        id: tool

        property string icon: ""
        property real turn: 0
        property bool dimmed: false
        signal pressed()

        width: 22 * root.factor
        height: width

        readonly property bool navigable: !tool.dimmed
        function activate() { if (!tool.dimmed) tool.pressed(); }

        KeyMark {
            factor: root.factor
        }

        Icon {
            anchors.centerIn: parent
            width: 11 * root.factor
            height: width
            rotation: tool.turn
            name: tool.icon
            colour: Qt.alpha(toolHover.hovered && !tool.dimmed ? Theme.primary : Theme.text,
                             tool.dimmed ? 0.3 : 1)
        }

        HoverHandler { id: toolHover }
        TapHandler { onTapped: tool.activate() }
    }

    // A slider with its figure, for a value with a unit.
    component Amount: Row {
        id: amount

        property real value: 0
        property real from: 0
        property real to: 100
        property real step: 1
        property string unit: ""
        signal moved(real value)

        spacing: 12 * root.factor
        height: root.chipHeight

        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: amount.width - figure.width - amount.spacing
            factor: root.factor
            value: (amount.value - amount.from) / (amount.to - amount.from)
            onMoved: fraction => {
                const raw = amount.from + fraction * (amount.to - amount.from);
                amount.moved(Math.round(raw / amount.step) * amount.step);
            }
        }

        Text {
            id: figure
            anchors.verticalCenter: parent.verticalCenter
            width: 64 * root.factor
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(amount.value * 10) / 10}${amount.unit}`
            color: Theme.text
            font.family: Typography.technical
            font.pixelSize: root.metrics.fontSecondary
            font.features: { "tnum": 1 }
        }
    }

    // ---- What each kind of step is edited with -----------------------------------

    // Every editor is handed `step` and `index`, and writes through `setStep`.

    Component {
        id: launchEditor

        Column {
            id: editor
            property var entry: ({})
            property int index: -1
            spacing: 8 * root.factor

            readonly property var matches: {
                const query = search.text.trim().toLowerCase();
                const out = [];
                for (const entry of Apps.entries) {
                    if (!entry || entry.noDisplay)
                        continue;
                    if (query.length > 0 && (entry.name || "").toLowerCase().indexOf(query) < 0
                            && (entry.id || "").toLowerCase().indexOf(query) < 0)
                        continue;
                    out.push(entry);
                }
                out.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
                return out.slice(0, 5);
            }

            Field {
                id: search
                width: parent.width
                placeholder: "Search applications"
            }

            Repeater {
                model: editor.matches

                delegate: Item {
                    id: app
                    required property var modelData
                    readonly property bool chosen: editor.entry.app === app.modelData.id

                    width: editor.width
                    height: 30 * root.factor

                    readonly property bool navigable: true
                    function activate() { root.setStep(editor.index, { "app": app.modelData.id }); }

                    KeyMark { factor: root.factor }

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        color: app.chosen ? Qt.alpha(Theme.primary, 0.14)
                             : appHover.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent"
                    }

                    Image {
                        id: appIcon
                        x: 8 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20 * root.factor
                        height: width
                        sourceSize.width: width * 2
                        sourceSize.height: width * 2
                        source: app.modelData.icon ? Quickshell.iconPath(app.modelData.icon, true) : ""
                    }

                    Text {
                        anchors.left: appIcon.right
                        anchors.leftMargin: 10 * root.factor
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: app.modelData.name
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }

                    HoverHandler { id: appHover }
                    TapHandler { onTapped: app.activate() }
                }
            }

            Line {
                text: "It opens wherever niri's window rules put it: an open-on-workspace rule places it on a workspace."
                color: Theme.textMuted
            }
        }
    }

    Component {
        id: openEditor

        Column {
            id: editor
            property var entry: ({})
            property int index: -1
            spacing: 8 * root.factor

            Row {
                width: parent.width
                spacing: 8 * root.factor

                Field {
                    id: path
                    width: parent.width - choose.width - 8 * root.factor
                    text: editor.entry.path || ""
                    placeholder: "A file, or ~/a/file"
                    onAccepted: root.setStep(editor.index, { "path": path.text.trim() })
                }

                Choice {
                    id: choose
                    metrics: root.metrics
                    label: picker.running ? "CHOOSING" : "CHOOSE"
                    dimmed: picker.running
                    onActivated: if (!picker.running) picker.running = true
                }
            }

            Line {
                text: "Opened in the application that opens files of its kind."
                color: Theme.textMuted
            }

            Process {
                id: picker
                command: ["sh", "-c", 'command -v zenity >/dev/null || exit 127; '
                          + 'exec zenity --file-selection --title="A file to open"']
                stdout: StdioCollector {
                    id: picked
                    onStreamFinished: {
                        const chosen = picked.text.trim();
                        if (chosen.length > 0)
                            root.setStep(editor.index, { "path": chosen });
                    }
                }
            }
        }
    }

    Component {
        id: percentEditor

        Amount {
            property var entry: ({})
            property int index: -1
            width: parent ? parent.width : 0
            from: entry.type === "brightness" ? 1 : 0
            to: 100
            step: 5
            unit: "%"
            value: entry.percent ?? 50
            onMoved: value => root.setStep(index, { "percent": value })
        }
    }

    Component {
        id: settingsEditor

        Column {
            id: editor
            property var entry: ({})
            property int index: -1
            spacing: 8 * root.factor

            readonly property var groups: editor.entry.groups || []

            Row {
                spacing: 6 * root.factor

                Repeater {
                    model: Actions.groups

                    delegate: Choice {
                        required property var modelData
                        readonly property bool on: editor.groups.indexOf(modelData.key) >= 0
                        metrics: root.metrics
                        label: modelData.label
                        kind: on ? "primary" : "plain"
                        onActivated: {
                            const next = on ? editor.groups.filter(key => key !== modelData.key)
                                            : editor.groups.concat([modelData.key]);
                            const values = Object.assign({}, editor.entry.values || {});
                            // A group taken out takes its values with it; one
                            // put in is captured as it is now.
                            const group = Actions.groupOf(modelData.key);
                            if (on)
                                for (const path of group.paths)
                                    delete values[path];
                            else
                                Object.assign(values, Actions.capture([modelData.key]));
                            root.setStep(editor.index, { "groups": next, "values": values });
                        }
                    }
                }

                Choice {
                    metrics: root.metrics
                    label: "CAPTURE NOW"
                    onActivated: root.setStep(editor.index, { "values": Actions.capture(editor.groups) })
                }
            }

            Line {
                text: editor.groups.length === 0
                      ? "Nothing is kept: choose what this step puts back."
                      : `Puts back ${root.lowered(Actions.summary(editor.entry))}. CAPTURE NOW keeps the settings as they are this moment instead.`
            }
        }
    }

    Component {
        id: monitorEditor

        Column {
            id: editor
            property var entry: ({})
            property int index: -1
            spacing: 8 * root.factor

            readonly property var names: Monitors.outputs.map(output => output.name)
                .concat(Monitors.off.map(output => output.name))

            Segmented {
                metrics: root.metrics
                options: editor.names.map(name => ({ "key": name, "label": name }))
                current: editor.entry.output || ""
                onChose: key => root.setStep(editor.index, { "output": key })
            }

            Segmented {
                metrics: root.metrics
                options: [{ "key": "on", "label": "ON" }, { "key": "off", "label": "OFF" }]
                current: editor.entry.on ? "on" : "off"
                onChose: key => root.setStep(editor.index, { "on": key === "on" })
            }

            Line {
                text: "One monitor at a time, and never the last one on: a quick action cannot leave the desktop dark."
                color: Theme.textMuted
            }
        }
    }

    Component {
        id: presetEditor

        Flow {
            id: editor
            property var entry: ({})
            property int index: -1
            width: parent ? parent.width : 0
            spacing: 6 * root.factor

            Repeater {
                model: Presets.all

                delegate: Choice {
                    required property var modelData
                    metrics: root.metrics
                    label: modelData.name.toUpperCase()
                    kind: editor.entry.name === modelData.name ? "primary" : "plain"
                    onActivated: root.setStep(editor.index, { "name": modelData.name })
                }
            }
        }
    }

    Component {
        id: wallpaperEditor

        Column {
            id: editor
            property var entry: ({})
            property int index: -1
            spacing: 8 * root.factor

            Flow {
                width: parent.width
                spacing: 6 * root.factor
                visible: Wallpaper.favourites.length > 0

                Repeater {
                    model: Wallpaper.favourites

                    delegate: Item {
                        id: thumb
                        required property string modelData
                        readonly property bool chosen: editor.entry.path === thumb.modelData

                        width: 88 * root.factor
                        height: 54 * root.factor

                        readonly property bool navigable: true
                        function activate() { root.setStep(editor.index, { "path": thumb.modelData }); }

                        Component.onCompleted: Wallpaper.prepare(thumb.modelData)

                        Image {
                            anchors.fill: parent
                            anchors.margins: 3 * root.factor
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: width * 2
                            source: "file://" + Wallpaper.thumbnail(thumb.modelData)
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 6 * root.factor
                            color: "transparent"
                            antialiasing: true
                            border.width: Metrics.rim(Screen.devicePixelRatio)
                            border.color: thumb.chosen ? Theme.primary
                                        : thumbHover.hovered ? Theme.text : "transparent"
                        }

                        KeyMark { factor: root.factor }
                        HoverHandler { id: thumbHover }
                        TapHandler { onTapped: thumb.activate() }
                    }
                }
            }

            Line {
                text: Wallpaper.favourites.length > 0
                      ? "One of the favourites, starred in the theme cell's grid."
                      : "No favourites yet. Star wallpapers in the theme cell's grid and they are offered here."
                color: Theme.textMuted
            }
        }
    }

    Component {
        id: switchEditor

        Segmented {
            property var entry: ({})
            property int index: -1
            metrics: root.metrics
            options: [{ "key": "on", "label": "ON" }, { "key": "off", "label": "OFF" }]
            current: entry.on ? "on" : "off"
            onChose: key => root.setStep(index, { "on": key === "on" })
        }
    }

    Component {
        id: profileEditor

        Segmented {
            property var entry: ({})
            property int index: -1
            metrics: root.metrics
            options: [{ "key": "saver", "label": "SAVER" }, { "key": "balanced", "label": "BALANCED" },
                      { "key": "performance", "label": "PERFORMANCE" }]
            current: entry.profile || "balanced"
            onChose: key => root.setStep(index, { "profile": key })
        }
    }

    Component {
        id: timerEditor

        Amount {
            property var entry: ({})
            property int index: -1
            width: parent ? parent.width : 0
            from: 5
            to: 120
            step: 5
            unit: " min"
            value: entry.minutes ?? 25
            onMoved: value => root.setStep(index, { "minutes": value })
        }
    }

    Component {
        id: waitEditor

        Amount {
            property var entry: ({})
            property int index: -1
            width: parent ? parent.width : 0
            from: 0.5
            to: 30
            step: 0.5
            unit: " s"
            value: entry.seconds ?? 2
            onMoved: value => root.setStep(index, { "seconds": value })
        }
    }

    Component {
        id: commandEditor

        Column {
            id: editor
            property var entry: ({})
            property int index: -1
            spacing: 8 * root.factor

            Field {
                id: command
                width: parent.width
                text: editor.entry.command || ""
                placeholder: "A shell command"
                onAccepted: root.setStep(editor.index, { "command": command.text })
            }

            Line {
                text: "Run by sh, in the background. Enter keeps it."
                color: Theme.textMuted
            }
        }
    }

    readonly property var editors: ({
        "launch": launchEditor,
        "open": openEditor,
        "volume": percentEditor,
        "brightness": percentEditor,
        "settings": settingsEditor,
        "monitor": monitorEditor,
        "preset": presetEditor,
        "wallpaper": wallpaperEditor,
        "quiet": switchEditor,
        "profile": profileEditor,
        "performance": switchEditor,
        "timer": timerEditor,
        "wait": waitEditor,
        "command": commandEditor
    })

    // ---- The page ------------------------------------------------------------------

    Scroller {
        flick: page
        factor: root.factor
        x: root.width - width
    }

    Flickable {
        id: page

        anchors.fill: parent
        anchors.rightMargin: 8 * root.factor
        contentHeight: column.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column

            width: page.width
            spacing: root.gap

            Section {
                label: "QUICK ACTIONS"

                Flow {
                    width: parent.width
                    spacing: 8 * root.factor

                    Repeater {
                        model: root.macros

                        delegate: Glyph {
                            required property var modelData
                            required property int index
                            icon: Actions.iconOf(modelData)
                            chosen: index === root.selected
                            onPressed: root.selected = index
                        }
                    }

                    Offer {
                        visible: root.macros.length < Actions.ringSize
                        y: (root.capsule - height) / 2
                        label: "NEW"
                        onPressed: root.addMacro()
                    }
                }

                Line {
                    text: root.macros.length === 0
                          ? "None yet. A quick action is a list of steps run one after the other, from a ring that comes to the pointer on Mod+Alt+Space."
                          : root.macros.length > Actions.ringSize
                          ? `The first ${Actions.ringSize} are in the ring, in this order; the rest run from a key of their own.`
                          : root.macros.length === Actions.ringSize
                          ? `The ring is full: ${Actions.ringSize}, clockwise from the top. Delete one to write another.`
                          : "In the ring in this order, clockwise from the top. Each also runs from a key of its own: qs ipc call actions run and its name."
                }
            }

            Section {
                visible: root.macro !== null
                label: root.selected < Actions.ringSize ? `IN THE RING · ${root.selected + 1}` : "NOT IN THE RING"

                trailing: [
                    Tool {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "chevron-right"
                        turn: 180
                        dimmed: root.selected <= 0
                        onPressed: root.moveMacro(-1)
                    },
                    Tool {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "chevron-right"
                        dimmed: root.selected >= root.macros.length - 1
                        onPressed: root.moveMacro(1)
                    },
                    Choice {
                        anchors.verticalCenter: parent.verticalCenter
                        metrics: root.metrics
                        label: Actions.running === (root.macro ? root.macro.name : "") && Actions.running !== ""
                               ? "RUNNING" : "RUN"
                        dimmed: root.steps.length === 0
                        onActivated: if (root.macro) Actions.run(root.macro.name)
                    },
                    Choice {
                        anchors.verticalCenter: parent.verticalCenter
                        metrics: root.metrics
                        label: root.deleting ? "DELETE?" : "DELETE"
                        kind: root.deleting ? "alert" : "plain"
                        onActivated: root.deleteMacro()
                    }
                ]

                Field {
                    id: nameField
                    width: parent.width
                    placeholder: "A name for the ring"
                    wrong: root.nameProblem.length > 0
                    maximumLength: 32
                    onAccepted: root.rename()
                    onReleased: root.rename()
                }

                Problem {
                    text: root.nameProblem
                }

                Flow {
                    width: parent.width
                    spacing: 6 * root.factor

                    Repeater {
                        model: Actions.icons

                        delegate: Glyph {
                            required property var modelData
                            size: 32 * root.factor
                            icon: modelData.name
                            chosen: root.macro !== null && Actions.iconOf(root.macro) === modelData.name
                            onPressed: root.setIcon(modelData.name)
                        }
                    }
                }
            }

            Section {
                visible: root.macro !== null
                label: "STEPS"

                Line {
                    visible: root.steps.length === 0
                    text: "No steps yet: add them below. They run from the top, each once the one before has finished."
                }

                Repeater {
                    model: root.steps

                    delegate: Column {
                        id: stepRow

                        required property var modelData
                        required property int index

                        readonly property bool open: root.editing === stepRow.index

                        onOpenChanged: if (stepRow.open) Qt.callLater(root.reveal, stepRow)

                        width: parent.width
                        spacing: 8 * root.factor

                        Item {
                            id: headline

                            width: parent.width
                            height: root.stepRow

                            readonly property bool navigable: true
                            function activate() { root.editing = stepRow.open ? -1 : stepRow.index; }

                            KeyMark { factor: root.factor }

                            Rectangle {
                                anchors.fill: parent
                                radius: Metrics.radiusFor(height, root.metrics)
                                color: stepRow.open ? Qt.alpha(Theme.primary, 0.10)
                                     : rowHover.hovered ? Qt.alpha(Theme.text, 0.05) : "transparent"
                            }

                            Text {
                                id: number
                                x: 10 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18 * root.factor
                                text: stepRow.index + 1
                                color: Theme.textMuted
                                font: root.metaFont
                            }

                            Text {
                                id: kindLabel
                                anchors.left: number.right
                                anchors.leftMargin: 6 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                width: 118 * root.factor
                                text: Actions.labelOf(stepRow.modelData)
                                elide: Text.ElideRight
                                color: Theme.text
                                font: root.metaFont
                            }

                            Text {
                                anchors.left: kindLabel.right
                                anchors.leftMargin: 8 * root.factor
                                anchors.right: tools.left
                                anchors.rightMargin: 8 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                text: Actions.describe(stepRow.modelData)
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Typography.expressive
                                font.pixelSize: root.metrics.fontSecondary
                            }

                            Row {
                                id: tools
                                anchors.right: parent.right
                                anchors.rightMargin: 6 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2 * root.factor
                                opacity: rowHover.hovered || stepRow.open ? 1 : 0

                                Tool {
                                    icon: "chevron-down"
                                    turn: 180
                                    dimmed: stepRow.index === 0
                                    onPressed: root.moveStep(stepRow.index, -1)
                                }

                                Tool {
                                    icon: "chevron-down"
                                    dimmed: stepRow.index === root.steps.length - 1
                                    onPressed: root.moveStep(stepRow.index, 1)
                                }

                                RemoveTool {
                                    factor: root.factor
                                    onConfirmed: root.removeStep(stepRow.index)
                                }
                            }

                            HoverHandler { id: rowHover }
                            TapHandler { onTapped: headline.activate() }
                        }

                        Loader {
                            id: editorSlot

                            active: stepRow.open
                            visible: active
                            x: 34 * root.factor
                            width: parent.width - x - 10 * root.factor
                            sourceComponent: root.editors[stepRow.modelData.type] || null

                            onLoaded: {
                                Qt.callLater(root.reveal, stepRow);
                                item.index = Qt.binding(() => stepRow.index);
                                item.entry = Qt.binding(() => stepRow.modelData);
                                if (item.width !== undefined)
                                    item.width = Qt.binding(() => editorSlot.width);
                            }
                        }
                    }
                }
            }

            Section {
                visible: root.macro !== null
                label: "ADD A STEP"

                Flow {
                    width: parent.width
                    spacing: 6 * root.factor

                    Repeater {
                        model: Actions.order

                        delegate: Offer {
                            required property string modelData
                            label: Actions.kinds[modelData].label
                            onPressed: root.addStep(modelData)
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: nameField.text = root.macro ? root.macro.name : ""
}
