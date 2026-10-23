pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// A few of niri's settings, without opening niri's files: the gaps, the focus
// ring, the focus following the pointer, the named workspaces, what starts
// with the session, and what the window rules say about each application
// (services/NiriSettings.qml).
//
// Akusen asked for it 2026-10-23. Laid out as the Actions page is: one well
// per setting, a line in Spectral saying what the current choice does and in
// which file it is written, rows that open on what they hold.
//
// A window rule is shown as the application it is about — every rule that
// matches an app-id, however many other matches it has — and only its
// opacity, its width and its workspace are edited here. The rest of what it
// says is counted and left alone; a rule that says nothing else can go.
//
// Everything is written as it is changed, into niri's own files; niri reads
// them again by itself.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var cell: null

    readonly property real factor: metrics.factor
    readonly property real inset: 14 * factor
    readonly property real headerHeight: 28 * factor
    readonly property real gap: 10 * factor
    readonly property real chipHeight: 28 * factor
    readonly property real row: 34 * factor

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

    readonly property bool busy: NiriSettings.busy

    // The row open in each list, by position, or -1.
    property int openWorkspace: -1
    property int openRule: -1

    // What is being added under the startup list: "", "app" or "command".
    property string addingStartup: ""
    property bool addingRule: false

    function fileName(path) {
        return String(path).split("/").pop();
    }

    // The files a set of items is written in, as a sentence's end.
    function writtenIn(list) {
        const names = [];
        for (const item of list) {
            const name = root.fileName(item.file);
            if (!names.includes(name))
                names.push(name);
        }
        return names.length === 0 ? root.fileName(NiriSettings.main) : names.join(" and ");
    }

    // The open row brought into view.
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

    // ---- Applications ------------------------------------------------------------

    // An app-id pattern as a person would say it: `^org\.gnome\.Nautilus$` is
    // org.gnome.Nautilus, `.*` is every window. One that is still a pattern
    // after that is shown as written — and so is one anchored at the start
    // only, `^org\.gnome\.`, which is a family of applications, not one.
    function plain(pattern) {
        const text = String(pattern);
        if (text === ".*" || text === "^.*$")
            return { "plain": true, "all": true, "id": "" };
        const prefix = text.startsWith("^") && !text.endsWith("$");
        const stripped = text.replace(/^\^/, "").replace(/\$$/, "").replace(/\\\./g, ".");
        return { "plain": !prefix && /^[A-Za-z0-9_ -][A-Za-z0-9._ -]*[A-Za-z0-9_-]$/.test(stripped),
                 "all": false, "id": stripped };
    }

    function ruleApp(rule) {
        const first = rule.matches.find(match => match["app-id"] !== undefined);
        const id = root.plain(first["app-id"]);
        if (id.all)
            return { "name": "Every window", "icon": "", "pattern": first["app-id"] };
        const entry = id.plain ? Apps.entryFor(id.id) : null;
        return {
            "name": entry ? entry.name : id.plain ? id.id : first["app-id"],
            "icon": entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "",
            "pattern": first["app-id"]
        };
    }

    function ruleSummary(rule) {
        const out = [];
        const apps = rule.matches.filter(match => match["app-id"] !== undefined).length;
        if (apps > 1)
            out.push(`and ${apps - 1} more`);
        if (rule.opacity !== null)
            out.push(`${Math.round(rule.opacity * 100)}% opaque`);
        if (rule.width !== null)
            out.push(root.widthWords(rule.width));
        if (rule.workspace !== null)
            out.push(`on ${rule.workspace}`);
        if (out.length === (apps > 1 ? 1 : 0))
            out.push("nothing set here");
        return out.join(" · ");
    }

    function widthWords(width) {
        if (width.kind === "proportion")
            return `${Math.round(width.value * 100)}% wide`;
        if (width.kind === "fixed")
            return `${Math.round(width.value)} px wide`;
        return "as wide as it asks";
    }

    // What else the rule says, which this page leaves alone.
    function ruleRest(rule) {
        const parts = [];
        const more = rule.matches.length - 1;
        if (more > 0)
            parts.push(`${more} more ${more === 1 ? "match" : "matches"}`);
        const titled = rule.matches.some(match => match.title !== undefined);
        if (titled)
            parts.push("titles");
        if (rule.excludes > 0)
            parts.push(`${rule.excludes} ${rule.excludes === 1 ? "exclusion" : "exclusions"}`);
        if (rule.others > 0)
            parts.push(`${rule.others} other ${rule.others === 1 ? "setting" : "settings"}`);
        return parts;
    }

    function startupApp(item) {
        if (item.sh)
            return { "name": item.args[0] || "", "icon": "", "command": "sh" };
        const program = String(item.args[0] || "").split("/").pop();
        const entry = Apps.entryFor(program);
        const command = item.args.join(" ");
        return {
            "name": entry ? entry.name : program,
            "icon": entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "",
            // Said once: `Telegram` started by `Telegram` is one word.
            "command": command.toLowerCase() === (entry ? entry.name : program).toLowerCase() ? "" : command
        };
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

    // A place for something not there yet, as on the Structure page.
    component Offer: Item {
        id: offer

        property string label: ""
        property bool dimmed: false
        signal pressed()

        width: offerLabel.implicitWidth + offerPlus.width + 30 * root.factor
        height: root.chipHeight
        opacity: offer.dimmed ? 0.45 : 1

        readonly property bool navigable: !offer.dimmed
        function activate() { if (!offer.dimmed) offer.pressed(); }

        KeyMark {
            factor: root.factor
            outset: 3 * root.factor
        }

        DashedSlot {
            anchors.fill: parent
            radius: Metrics.radiusFor(parent.height, root.metrics)
            colour: offerHover.hovered && !offer.dimmed ? Theme.primary : Qt.alpha(Theme.line, 0.7)
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
            color: offerHover.hovered && !offer.dimmed ? Theme.primary : Theme.text
            font: root.metaFont
        }

        HoverHandler { id: offerHover }
        TapHandler { onTapped: offer.activate() }
    }

    // A one-line field, outlined, in the human voice.
    component Field: Rectangle {
        id: field

        property alias text: input.text
        property alias input: input
        property string placeholder: ""
        property bool wrong: false
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

    // An error lives where it happened, in Spectral.
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

    // A small press on a row: move, remove.
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

    // A slider with its figure. `unset` is a value the configuration does not
    // say: the figure says so, and the slider waits, dimmed, where moving it
    // would start.
    component Amount: Row {
        id: amount

        property real value: 0
        property real from: 0
        property real to: 100
        property real step: 1
        property string unit: ""
        property bool unset: false
        signal moved(real value)

        spacing: 12 * root.factor
        height: root.chipHeight

        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: amount.width - figure.width - amount.spacing
            factor: root.factor
            dimmed: amount.unset
            step: amount.step / (amount.to - amount.from)
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
            text: amount.unset ? "—" : `${Math.round(amount.value * 10) / 10}${amount.unit}`
            color: amount.unset ? Theme.textFaint : Theme.text
            font.family: Typography.technical
            font.pixelSize: root.metrics.fontSecondary
            font.features: { "tnum": 1 }
        }
    }

    // A row that opens on what it holds: an icon, a name, a summary, and the
    // tools that appear under the pointer.
    component Headline: Item {
        id: headline

        property string icon: ""
        property string glyph: ""
        property string name: ""
        property string summary: ""
        property bool open: false
        property bool openable: true
        default property alias tools: toolSlot.data
        signal pressed()

        width: parent ? parent.width : 0
        height: root.row

        readonly property bool hovered: rowHover.hovered

        readonly property bool navigable: headline.openable
        function activate() { if (headline.openable) headline.pressed(); }

        KeyMark { factor: root.factor }

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            color: headline.open ? Qt.alpha(Theme.primary, 0.10)
                 : rowHover.hovered && headline.openable ? Qt.alpha(Theme.text, 0.05) : "transparent"
        }

        Item {
            id: picture
            x: 8 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * root.factor
            height: width

            Image {
                anchors.fill: parent
                visible: headline.icon.length > 0
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                source: headline.icon
            }

            Icon {
                anchors.centerIn: parent
                visible: headline.icon.length === 0
                width: 14 * root.factor
                height: width
                name: headline.glyph.length > 0 ? headline.glyph : "app-fallback"
                colour: Theme.textMuted
            }
        }

        Text {
            id: nameLabel
            anchors.left: picture.right
            anchors.leftMargin: 10 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, (headline.width - picture.width) * 0.45)
            text: headline.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }

        Text {
            anchors.left: nameLabel.right
            anchors.leftMargin: 10 * root.factor
            anchors.right: toolSlot.left
            anchors.rightMargin: 8 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: headline.summary
            elide: Text.ElideRight
            color: Theme.textMuted
            font: root.metaFont
        }

        Row {
            id: toolSlot
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.factor
        }

        HoverHandler { id: rowHover }
        TapHandler { onTapped: headline.activate() }
    }

    // Applications to choose from: the windows open now first — their app-id
    // is what a rule matches, without guessing — then the installed ones.
    component AppPicker: Column {
        id: picker

        property bool windows: false
        property string placeholder: "Search applications"
        signal chose(var choice)

        spacing: 8 * root.factor

        readonly property var matches: {
            const query = search.text.trim().toLowerCase();
            const fits = (...words) => query.length === 0
                || words.some(word => String(word || "").toLowerCase().indexOf(query) >= 0);
            const out = [];
            const seen = {};

            if (picker.windows) {
                for (const id in Niri.windows) {
                    const appId = Niri.windows[id].appId;
                    if (!appId || seen[appId.toLowerCase()])
                        continue;
                    const entry = Apps.entryFor(appId);
                    if (!fits(appId, entry ? entry.name : ""))
                        continue;
                    seen[appId.toLowerCase()] = true;
                    out.push({ "appId": appId, "entry": entry, "open": true,
                               "name": entry ? entry.name : appId, "icon": entry ? entry.icon : "" });
                }
            }

            const installed = [];
            for (const entry of Apps.entries) {
                if (!entry || entry.noDisplay)
                    continue;
                const appId = entry.startupClass || entry.id || "";
                if (seen[appId.toLowerCase()] || !fits(entry.name, entry.id))
                    continue;
                installed.push({ "appId": appId, "entry": entry, "open": false,
                                 "name": entry.name, "icon": entry.icon });
            }
            installed.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
            return out.concat(installed).slice(0, 6);
        }

        Field {
            id: search
            width: parent.width
            placeholder: picker.placeholder
            Component.onCompleted: activate()
        }

        Repeater {
            model: picker.matches

            delegate: Item {
                id: app
                required property var modelData

                width: picker.width
                height: 30 * root.factor

                readonly property bool navigable: true
                function activate() { picker.chose(app.modelData); }

                KeyMark { factor: root.factor }

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusFor(height, root.metrics)
                    color: appHover.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent"
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
                    id: appName
                    anchors.left: appIcon.right
                    anchors.leftMargin: 10 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, picker.width * 0.5)
                    text: app.modelData.name
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }

                Text {
                    anchors.left: appName.right
                    anchors.leftMargin: 10 * root.factor
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: app.modelData.open ? "OPEN NOW" : ""
                    horizontalAlignment: Text.AlignRight
                    color: Theme.textMuted
                    font: root.metaFont
                }

                HoverHandler { id: appHover }
                TapHandler { onTapped: app.activate() }
            }
        }
    }

    // ---- A rule's sliders, written when the hand rests --------------------------------

    // `{ index, key, value }` while a slider of an open rule is being moved.
    property var draft: null

    function drafted(index, key, fallback) {
        return root.draft && root.draft.index === index && root.draft.key === key ? root.draft.value : fallback;
    }

    function setDraft(index, key, value) {
        root.draft = { "index": index, "key": key, "value": value };
        ruleRest.restart();
    }

    Timer {
        id: ruleRest
        interval: 400
        onTriggered: {
            if (root.busy) {
                ruleRest.restart();
                return;
            }
            const asked = root.draft;
            const rule = asked ? NiriSettings.rules[asked.index] : null;
            if (rule) {
                if (asked.key === "opacity")
                    NiriSettings.setRuleOpacity(rule, asked.value / 100);
                else
                    NiriSettings.setRuleWidth(rule, asked.value / 100);
            }
            ruleSettle.restart();
        }
    }

    Timer {
        id: ruleSettle
        interval: 100
        onTriggered: {
            if (root.busy || ruleRest.running) {
                ruleSettle.restart();
                return;
            }
            root.draft = null;
        }
    }

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

            Problem {
                width: parent.width
                text: NiriSettings.error
            }

            Section {
                label: "GAPS"

                Amount {
                    width: parent.width
                    from: 0
                    to: 48
                    step: 1
                    unit: " px"
                    value: NiriSettings.gaps
                    onMoved: value => NiriSettings.setGaps(value)
                }

                Line {
                    readonly property var mine: NiriSettings.gapNodes.filter(found => !NiriSettings.own(found.file))
                    text: (NiriSettings.gaps === 0
                           ? "Windows touch each other and the edges of the screen. "
                           : `${NiriSettings.gaps} px between windows, and between them and the edges of the screen. `)
                          + `Written in ${root.writtenIn(mine)}.`
                }
            }

            Section {
                label: "FOCUS RING"

                Amount {
                    width: parent.width
                    from: 1
                    to: 8
                    step: 1
                    unit: " px"
                    value: NiriSettings.focusRing
                    onMoved: value => NiriSettings.setFocusRing(value)
                }

                Line {
                    text: (NiriSettings.focusRing === 2
                           ? "As wide as a cell's rim, which is how Bioma draws it. "
                           : `${NiriSettings.focusRing} px around the focused window. `)
                          + (NiriSettings.themed
                             ? "Lit like a cell's edge, from the theme's niri file, which wins over a width set in niri's own."
                             : `Written in ${root.writtenIn(NiriSettings.ringWidths(NiriSettings.items))}: Bioma's theme for niri is switched off in the theme cell's APPS.`)
                }
            }

            Section {
                label: "FOCUS FOLLOWS THE POINTER"

                trailing: Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    factor: root.factor
                    on: NiriSettings.followsMouse
                    dimmed: root.busy
                    onToggled: value => NiriSettings.setFollowsMouse(value)
                }

                Line {
                    text: NiriSettings.followsMouse
                          ? "The window under the pointer takes the focus as soon as the pointer is on it, without a click."
                          : "A window takes the focus when it is clicked, or reached from the keyboard."
                }
            }

            Section {
                label: "WORKSPACES"

                Line {
                    visible: NiriSettings.workspaces.length === 0
                    text: "None named: niri makes a workspace as soon as one is needed and drops it when it is empty. A named one is always there, and window rules can send windows to it."
                }

                Repeater {
                    model: NiriSettings.workspaces

                    delegate: Column {
                        id: wsRow

                        required property var modelData
                        required property int index

                        readonly property bool open: root.openWorkspace === wsRow.index

                        onOpenChanged: if (wsRow.open) {
                            nameField.text = wsRow.modelData.name;
                            Qt.callLater(root.reveal, wsRow);
                        }

                        width: parent.width
                        spacing: 8 * root.factor

                        Headline {
                            id: wsHead
                            glyph: "workspaces"
                            name: wsRow.modelData.name
                            summary: wsRow.modelData.output.length > 0 ? wsRow.modelData.output : "ANY MONITOR"
                            open: wsRow.open
                            onPressed: root.openWorkspace = wsRow.open ? -1 : wsRow.index

                            Row {
                                spacing: 2 * root.factor
                                opacity: wsHead.hovered || wsRow.open ? 1 : 0

                                Tool {
                                    icon: "chevron-down"
                                    turn: 180
                                    dimmed: root.busy || NiriSettings.neighbour(wsRow.modelData, -1) === null
                                    onPressed: {
                                        NiriSettings.moveWorkspace(wsRow.modelData, -1);
                                        if (wsRow.open)
                                            root.openWorkspace--;
                                    }
                                }

                                Tool {
                                    icon: "chevron-down"
                                    dimmed: root.busy || NiriSettings.neighbour(wsRow.modelData, 1) === null
                                    onPressed: {
                                        NiriSettings.moveWorkspace(wsRow.modelData, 1);
                                        if (wsRow.open)
                                            root.openWorkspace++;
                                    }
                                }

                                Tool {
                                    icon: "close"
                                    dimmed: root.busy
                                    onPressed: {
                                        NiriSettings.removeWorkspace(wsRow.modelData);
                                        root.openWorkspace = -1;
                                    }
                                }
                            }
                        }

                        Column {
                            visible: wsRow.open
                            x: 38 * root.factor
                            width: parent.width - x - 10 * root.factor
                            spacing: 8 * root.factor

                            readonly property string problem: NiriSettings.workspaceProblem(nameField.text, wsRow.modelData)

                            Field {
                                id: nameField
                                width: parent.width
                                placeholder: "A name"
                                wrong: parent.problem.length > 0
                                onAccepted: NiriSettings.renameWorkspace(wsRow.modelData, nameField.text)
                                onReleased: NiriSettings.renameWorkspace(wsRow.modelData, nameField.text)
                            }

                            Problem {
                                text: parent.problem
                            }

                            Flow {
                                width: parent.width
                                spacing: 6 * root.factor

                                Repeater {
                                    model: [""].concat(Monitors.outputs.map(output => output.name)
                                                       .concat(Monitors.off.map(output => output.name)))
                                               .concat(wsRow.modelData.output.length > 0
                                                       && !Monitors.outputs.concat(Monitors.off).some(output => output.name === wsRow.modelData.output)
                                                       ? [wsRow.modelData.output] : [])

                                    delegate: Choice {
                                        required property string modelData
                                        metrics: root.metrics
                                        label: modelData.length > 0 ? modelData : "ANY MONITOR"
                                        kind: wsRow.modelData.output === modelData ? "primary" : "plain"
                                        dimmed: root.busy
                                        onActivated: NiriSettings.setWorkspaceOutput(wsRow.modelData, modelData)
                                    }
                                }
                            }

                            Line {
                                text: `Renaming it renames it in the window rules and the keys that go to it. Windows already on it stay where they are. Written in ${root.fileName(wsRow.modelData.file)}.`
                                color: Theme.textMuted
                            }
                        }
                    }
                }

                Offer {
                    label: "NEW"
                    dimmed: root.busy
                    onPressed: {
                        NiriSettings.addWorkspace();
                        root.openWorkspace = NiriSettings.workspaces.length;
                    }
                }
            }

            Section {
                label: "AT STARTUP"

                Line {
                    visible: NiriSettings.startup.length === 0
                    text: "Nothing but Bioma starts with the session."
                }

                Repeater {
                    model: NiriSettings.startup

                    delegate: Headline {
                        id: spawnRow

                        required property var modelData

                        readonly property var app: root.startupApp(spawnRow.modelData)

                        icon: app.icon
                        glyph: spawnRow.modelData.sh ? "action-code" : ""
                        name: app.name
                        summary: spawnRow.modelData.sh ? "SHELL" : app.command
                        openable: false
                        opacity: spawnRow.modelData.on ? 1 : 0.55

                        Row {
                            spacing: 8 * root.factor

                            Tool {
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "close"
                                opacity: spawnRow.hovered ? 1 : 0
                                dimmed: root.busy
                                onPressed: NiriSettings.removeStartup(spawnRow.modelData)
                            }

                            Switch {
                                anchors.verticalCenter: parent.verticalCenter
                                factor: root.factor
                                on: spawnRow.modelData.on
                                dimmed: root.busy
                                onToggled: value => NiriSettings.setStartupOn(spawnRow.modelData, value)
                            }
                        }
                    }
                }

                Loader {
                    width: parent.width
                    active: root.addingStartup === "app"
                    visible: active

                    sourceComponent: AppPicker {
                        width: parent ? parent.width : 0
                        onChose: choice => {
                            const command = choice.entry && choice.entry.command ? Array.from(choice.entry.command) : [];
                            if (command.length > 0)
                                NiriSettings.addStartup(command, false);
                            root.addingStartup = "";
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: root.addingStartup === "command"
                    spacing: 8 * root.factor

                    Field {
                        id: commandField
                        width: parent.width
                        placeholder: "A shell command"
                        onAccepted: {
                            NiriSettings.addStartup(commandField.text, true);
                            commandField.text = "";
                            root.addingStartup = "";
                        }
                    }

                    Line {
                        text: "Run by sh when the session starts. Enter adds it."
                        color: Theme.textMuted
                    }
                }

                Row {
                    spacing: 6 * root.factor

                    Offer {
                        label: "APPLICATION"
                        dimmed: root.busy
                        onPressed: root.addingStartup = root.addingStartup === "app" ? "" : "app"
                    }

                    Offer {
                        label: "COMMAND"
                        dimmed: root.busy
                        onPressed: {
                            root.addingStartup = root.addingStartup === "command" ? "" : "command";
                            if (root.addingStartup === "command")
                                commandField.activate();
                        }
                    }
                }

                Line {
                    visible: NiriSettings.startup.length > 0
                    text: `Switched off, a line is commented out and kept. Changes take effect at the next login. Written in ${root.writtenIn(NiriSettings.startup)}.`
                    color: Theme.textMuted
                }
            }

            Section {
                label: "WINDOW RULES"

                Line {
                    visible: NiriSettings.rules.length === 0
                    text: "No rules for an application yet. A rule can make its windows see-through, open them at a width, or send them to a workspace."
                }

                Repeater {
                    model: NiriSettings.rules

                    delegate: Column {
                        id: ruleRow

                        required property var modelData
                        required property int index

                        readonly property bool open: root.openRule === ruleRow.index
                        readonly property var app: root.ruleApp(ruleRow.modelData)
                        readonly property var rest: root.ruleRest(ruleRow.modelData)

                        onOpenChanged: if (ruleRow.open) Qt.callLater(root.reveal, ruleRow)

                        width: parent.width
                        spacing: 8 * root.factor

                        Headline {
                            id: ruleHead
                            icon: ruleRow.app.icon
                            glyph: ruleRow.app.name === "Every window" ? "window" : ""
                            name: ruleRow.app.name
                            summary: root.ruleSummary(ruleRow.modelData).toUpperCase()
                            open: ruleRow.open
                            onPressed: root.openRule = ruleRow.open ? -1 : ruleRow.index

                            Tool {
                                icon: "close"
                                opacity: (ruleHead.hovered || ruleRow.open) && NiriSettings.removable(ruleRow.modelData) ? 1 : 0
                                dimmed: root.busy || !NiriSettings.removable(ruleRow.modelData)
                                onPressed: {
                                    NiriSettings.removeRule(ruleRow.modelData);
                                    root.openRule = -1;
                                }
                            }
                        }

                        Column {
                            visible: ruleRow.open
                            x: 38 * root.factor
                            width: parent.width - x - 10 * root.factor
                            spacing: 8 * root.factor

                            // niri's refusal, here as well as at the top of
                            // the page, which is out of sight down here.
                            Problem {
                                width: parent.width
                                text: NiriSettings.error
                            }

                            Text {
                                text: "OPACITY"
                                color: Theme.textMuted
                                font: root.metaFont
                            }

                            Row {
                                width: parent.width
                                spacing: 8 * root.factor

                                Amount {
                                    width: parent.width - clearOpacity.width - parent.spacing
                                    from: 10
                                    to: 100
                                    step: 5
                                    unit: "%"
                                    readonly property real held: root.drafted(ruleRow.index, "opacity", -1)
                                    unset: held < 0 && ruleRow.modelData.opacity === null
                                    value: held >= 0 ? held : ruleRow.modelData.opacity !== null
                                           ? Math.round(ruleRow.modelData.opacity * 100) : 100
                                    onMoved: value => root.setDraft(ruleRow.index, "opacity", value)
                                }

                                Choice {
                                    id: clearOpacity
                                    anchors.verticalCenter: parent.verticalCenter
                                    metrics: root.metrics
                                    label: "CLEAR"
                                    dimmed: root.busy || ruleRow.modelData.opacity === null
                                    onActivated: NiriSettings.setRuleOpacity(ruleRow.modelData, null)
                                }
                            }

                            Text {
                                text: "WIDTH WHEN IT OPENS"
                                color: Theme.textMuted
                                font: root.metaFont
                            }

                            Row {
                                width: parent.width
                                spacing: 8 * root.factor

                                Amount {
                                    readonly property var width_: ruleRow.modelData.width
                                    readonly property real held: root.drafted(ruleRow.index, "width", -1)
                                    width: parent.width - clearWidth.width - parent.spacing
                                    from: 10
                                    to: 100
                                    step: 5
                                    unit: "%"
                                    unset: held < 0 && (width_ === null || width_.kind !== "proportion")
                                    value: held >= 0 ? held : width_ !== null && width_.kind === "proportion"
                                           ? Math.round(width_.value * 100) : 50
                                    onMoved: value => root.setDraft(ruleRow.index, "width", value)
                                }

                                Choice {
                                    id: clearWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    metrics: root.metrics
                                    label: "CLEAR"
                                    dimmed: root.busy || ruleRow.modelData.width === null
                                    onActivated: NiriSettings.setRuleWidth(ruleRow.modelData, null)
                                }
                            }

                            Line {
                                visible: ruleRow.modelData.width !== null && ruleRow.modelData.width.kind !== "proportion"
                                text: ruleRow.modelData.width !== null && ruleRow.modelData.width.kind === "fixed"
                                      ? `${Math.round(ruleRow.modelData.width.value)} px for now: moving the slider makes it a share of the screen.`
                                      : "As wide as the window asks for now: moving the slider makes it a share of the screen."
                                color: Theme.textMuted
                            }

                            Text {
                                text: "OPENS ON"
                                color: Theme.textMuted
                                font: root.metaFont
                            }

                            Flow {
                                width: parent.width
                                spacing: 6 * root.factor

                                Repeater {
                                    model: [""].concat(NiriSettings.workspaces.map(ws => ws.name))
                                               .concat(ruleRow.modelData.workspace !== null
                                                       && !NiriSettings.workspaces.some(ws => ws.name === ruleRow.modelData.workspace)
                                                       ? [ruleRow.modelData.workspace] : [])

                                    delegate: Choice {
                                        required property string modelData
                                        metrics: root.metrics
                                        label: modelData.length > 0 ? modelData.toUpperCase() : "WHERE IT IS OPENED"
                                        kind: (ruleRow.modelData.workspace ?? "") === modelData ? "primary" : "plain"
                                        dimmed: root.busy
                                        onActivated: NiriSettings.setRuleWorkspace(ruleRow.modelData,
                                                                                   modelData.length > 0 ? modelData : null)
                                    }
                                }
                            }

                            Line {
                                text: (ruleRow.rest.length > 0
                                       ? `The rule also has ${ruleRow.rest.join(", ")}, left as they are. `
                                       : "")
                                      + (ruleRow.app.name === "Every window" ? "Applies to every window. "
                                         : `Applies to windows whose app-id matches ${ruleRow.app.pattern}. `)
                                      + `Written in ${root.fileName(ruleRow.modelData.file)}.`
                                color: Theme.textMuted
                            }
                        }
                    }
                }

                Loader {
                    width: parent.width
                    active: root.addingRule
                    visible: active

                    sourceComponent: AppPicker {
                        width: parent ? parent.width : 0
                        windows: true
                        placeholder: "Search applications and open windows"
                        onChose: choice => {
                            NiriSettings.addRule(choice.appId);
                            root.addingRule = false;
                            root.openRule = NiriSettings.rules.length;
                        }
                    }
                }

                Offer {
                    label: "APPLICATION"
                    dimmed: root.busy
                    onPressed: root.addingRule = !root.addingRule
                }

                Line {
                    visible: NiriSettings.otherRules > 0
                    text: `${NiriSettings.otherRules} more ${NiriSettings.otherRules === 1 ? "rule matches" : "rules match"} windows by something other than their application — focus, title, floating — and ${NiriSettings.otherRules === 1 ? "is" : "are"} edited in niri's files.`
                    color: Theme.textMuted
                }
            }
        }
    }
}
