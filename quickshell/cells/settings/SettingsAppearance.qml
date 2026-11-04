import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// How the shell looks: the handful of numbers the whole of it is drawn from.
//
// Every row writes straight into the override layer, and every surface in the
// shell is bound to those values — so a slider moved here is the desktop
// changing under the hand, not a preview of one. That is also why there is no
// apply button: there is nothing to apply.
//
// Sliders are controls, so they keep the primary for their whole travel.
// Nothing here is a measurement and nothing here has a threshold.
//
// Under the numbers, the palettes: Bioma's and the user's own, chosen with a
// press, and the user's edited in place — a name and the four interface roles,
// each by its hex, by hue, saturation and value, or by niri's eyedropper
// (services/Palettes.qml; Akusen, 2026-10-18).
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var cell: null

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 44 * factor
    readonly property real labelWidth: 92 * factor
    // The figures are right-aligned in a column of their own, wide enough for
    // the longest of them, and the sliders run from the labels to it: the
    // panel is one width for every category, and a longer travel is a finer
    // control (Akusen, 2026-10-15).
    readonly property real valueWidth: 56 * factor
    readonly property real sliderWidth: Math.max(0, page.width - labelWidth - valueWidth - 24 * factor)

    // Each row: what it is called, where it is kept, its range, and how it
    // says itself. `step` snaps a travel to values that mean something — the
    // density scale has three, not a hundred.
    readonly property var rows: [
        { "label": "OPACITY", "key": "cell.opacity", "from": 0.3, "to": 1, "step": 0.01,
          "unit": "%", "scale": 100, "fallback": 0.72 },
        { "label": "RADIUS", "key": "appearance.radius", "from": 0, "to": 100, "step": 1,
          "unit": "%", "scale": 1, "fallback": 100 },
        { "label": "EDGE", "key": "appearance.edge", "from": 0, "to": 32, "step": 1,
          "unit": " px", "scale": 1, "fallback": 12 },
        { "label": "TISSUE", "key": "tissue.padding", "from": 2, "to": 12, "step": 1,
          "unit": " px", "scale": 1, "fallback": 2 },
        { "label": "GAP", "key": "appearance.gap", "from": 8, "to": 48, "step": 1,
          "unit": " px", "scale": 1, "fallback": 24 }
    ]

    // Scale is a **membrane** property, not a global one — a smaller second
    // monitor may run `compact` — so there is no `appearance.scale` to write
    // and a row that wrote one moved nothing at all. This moves every membrane
    // together, which is what a person asking for a denser shell means; the
    // per-membrane choice belongs to the Structure page, beside the edge it
    // applies to.
    readonly property var membranes: Config.get("membranes", [])

    readonly property string density: {
        for (const membrane of root.membranes)
            if (membrane.scale)
                return membrane.scale;
        return "normal";
    }

    // The floating tissues go with them: a denser shell whose notifications
    // stayed at the normal step was not denser.
    function setDensity(name) {
        const copy = JSON.parse(JSON.stringify(root.membranes));
        for (const membrane of copy)
            membrane.scale = name;
        Config.set("membranes", copy);

        const floats = JSON.parse(JSON.stringify(Config.get("floating", [])));
        for (const tissue of floats)
            tissue.scale = name;
        Config.set("floating", floats);
    }

    // ---- The palettes ------------------------------------------------------------

    readonly property real inset: 14 * factor
    readonly property real headerHeight: 28 * factor
    readonly property real gap: 10 * factor
    readonly property real chipHeight: 28 * factor
    readonly property real roleRow: 34 * factor

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

    // The role whose hue, saturation and value are under the hand.
    property string role: "primary"

    readonly property var roleLabels: ({
        "background": "BACKGROUND",
        "text": "TEXT",
        "primary": "PRIMARY",
        "secondary": "SECONDARY"
    })

    readonly property var roleLines: ({
        "background": "The glass of every cell and tissue, and what the surfaces, the outlines and the shadows are made from. Light or dark follows it.",
        "text": "Everything that is read: content, labels, figures.",
        "primary": "Icons, controls, selections, and the indicators that have no state to say.",
        "secondary": "The supporting accent, beside the primary."
    })

    readonly property string roleColour: Palettes.colours[root.role] || "#000000"

    // A grey has no hue of its own; the one it last had is kept, so taking the
    // saturation down and back up does not turn the colour red.
    property real hue: 0
    readonly property color roleQt: root.roleColour
    onRoleQtChanged: if (root.roleQt.hsvHue >= 0) root.hue = root.roleQt.hsvHue

    function setHsv(h, sat, val) {
        Palettes.setRole(root.role, Palettes.hex(Qt.hsva(h, sat, val, 1)));
    }

    readonly property string nameProblem: {
        const name = nameField.text.trim();
        if (name.length === 0)
            return "A palette needs a name.";
        if (Palettes.nameTaken(name))
            return "Another palette already has this name.";
        return "";
    }

    property bool deleting: false

    function remove() {
        if (!root.deleting) {
            root.deleting = true;
            return;
        }
        root.deleting = false;
        Palettes.remove();
    }

    readonly property string editedFile: Palettes.editable ? Palettes.current.file : ""
    onEditedFileChanged: {
        root.deleting = false;
        nameField.text = Palettes.colours.name || "";
    }

    readonly property string editedName: Palettes.colours.name || ""
    onEditedNameChanged: if (!nameField.input.activeFocus) nameField.text = root.editedName

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

    // A palette to choose: its four colours and its name.
    component Swatches: Item {
        id: swatches

        property var palette: ({})
        property bool chosen: false
        signal pressed()

        width: dots.width + chipName.implicitWidth + 30 * root.factor
        height: root.chipHeight

        readonly property bool navigable: true
        function activate() { swatches.pressed(); }

        KeyMark {
            factor: root.factor
            outset: 3 * root.factor
        }

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            color: swatches.chosen ? Qt.alpha(Theme.primary, 0.14) : "transparent"
            border.width: Metrics.rim(Screen.devicePixelRatio)
            border.color: swatches.chosen ? Theme.primary
                        : swatchHover.hovered ? Theme.text : Theme.line
        }

        Row {
            id: dots
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            spacing: -3 * root.factor

            Repeater {
                model: Palettes.roles

                delegate: Rectangle {
                    required property string modelData
                    width: 12 * root.factor
                    height: width
                    radius: width / 2
                    antialiasing: true
                    color: (swatches.palette.colours || {})[modelData] || "transparent"
                    border.width: Metrics.rim(Screen.devicePixelRatio)
                    border.color: Theme.line
                }
            }
        }

        Text {
            id: chipName
            anchors.left: dots.right
            anchors.leftMargin: 8 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: String(swatches.palette.name || "").toUpperCase()
            color: Theme.text
            font: root.metaFont
        }

        HoverHandler { id: swatchHover }
        TapHandler { onTapped: swatches.pressed() }
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

    // A one-line field, outlined. `technical` for a hex, which is the
    // machine's spelling of a colour; the human voice for a name.
    component Field: Rectangle {
        id: field

        property alias text: input.text
        property alias input: input
        property string placeholder: ""
        property bool wrong: false
        property bool technical: false
        property int maximumLength: 32767
        signal accepted()
        signal released()
        signal edited()

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
            font: field.technical ? root.metaFont
                                  : Qt.font({ "family": Typography.expressive,
                                              "pixelSize": root.metrics.fontSecondary })
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
            onTextEdited: field.edited()
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

    // A small press on a row: the eyedropper.
    component Tool: Item {
        id: tool

        property string icon: ""
        property bool lit: false
        signal pressed()

        width: 22 * root.factor
        height: width

        readonly property bool navigable: true
        function activate() { tool.pressed(); }

        KeyMark {
            factor: root.factor
        }

        Icon {
            anchors.centerIn: parent
            width: 13 * root.factor
            height: width
            name: tool.icon
            colour: toolHover.hovered || tool.lit ? Theme.primary : Theme.text
        }

        HoverHandler { id: toolHover }
        TapHandler { onTapped: tool.activate() }
    }

    // One of hue, saturation and value: its name, the travel, the figure.
    component Channel: Item {
        id: channel

        property string label: ""
        property real value: 0
        property real scale: 100
        property string unit: "%"
        signal moved(real value)

        width: parent ? parent.width : 0
        height: root.chipHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: channel.label
            color: Theme.text
            font: root.metaFont
        }

        Slider {
            anchors.left: parent.left
            anchors.leftMargin: root.labelWidth
            anchors.verticalCenter: parent.verticalCenter
            width: channel.width - root.labelWidth - root.valueWidth - 12 * root.factor
            factor: root.factor
            value: channel.value
            step: 0.01
            onMoved: fraction => channel.moved(fraction)
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.valueWidth
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(channel.value * channel.scale)}${channel.unit}`
            color: Theme.text
            font: Typography.tabular(Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontSecondary
            }))
        }
    }

    // ---- The page ------------------------------------------------------------------

    // The panel is one height for every category; the palettes scroll under
    // the numbers when they are taller than it.
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
            spacing: 0

            Repeater {
                model: root.rows

                delegate: Item {
                    id: row

                    required property var modelData

                    readonly property real value: Config.get(row.modelData.key, row.modelData.fallback)

                    width: parent.width
                    height: root.rowHeight

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.labelWidth
                        text: row.modelData.label
                        color: Theme.text
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontSecondary,
                            "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                                 Typography.labelTracking)
                        })
                    }

                    Slider {
                        id: travel

                        anchors.left: parent.left
                        anchors.leftMargin: root.labelWidth + 12 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.sliderWidth
                        factor: root.factor

                        readonly property real span: row.modelData.to - row.modelData.from

                        value: (row.value - row.modelData.from) / travel.span

                        onMoved: fraction => {
                            const raw = row.modelData.from + fraction * travel.span;
                            const snapped = Math.round(raw / row.modelData.step) * row.modelData.step;
                            Config.set(row.modelData.key,
                                       Math.round(snapped * 1000) / 1000);
                        }
                    }

                    // The figure is a measurement, so it is written in the machine's
                    // voice with tabular numerals: it changes while it is read.
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.valueWidth
                        horizontalAlignment: Text.AlignRight
                        text: `${Math.round(row.value * row.modelData.scale)}${row.modelData.unit}`
                        color: Theme.text
                        font: Typography.tabular(Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontSecondary
                        }))
                    }
                }
            }

            // Whether the cells are glass at all, and how strong the glass is. The
            // shell declares *where* to blur; how much is niri's, in a section
            // that is global, so the strength is a step written into niri's
            // configuration (services/Looks.qml) and it moves every blurred
            // surface niri draws. One row, because the strength of glass that is
            // off means nothing: the slider dims with the switch.
            Item {
                width: parent.width
                height: root.rowHeight

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.labelWidth
                    text: "BLUR"
                    color: Theme.text
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary,
                        "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                             Typography.labelTracking)
                    })
                }

                Switch {
                    id: glass

                    anchors.left: parent.left
                    anchors.leftMargin: root.labelWidth + 12 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    factor: root.factor
                    on: Config.get("cell.blur", true)
                    onToggled: value => Config.set("cell.blur", value)
                }

                // It ends where the sliders above end, so the column holds.
                Slider {
                    id: strength

                    readonly property int steps: Metrics.blurSteps.length

                    anchors.left: glass.right
                    anchors.leftMargin: 12 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.sliderWidth - glass.width - 12 * root.factor
                    factor: root.factor
                    dimmed: !glass.on

                    value: (Metrics.blurStrength - 1) / (strength.steps - 1)
                    onMoved: fraction => Looks.setBlur(1 + fraction * (strength.steps - 1))
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.valueWidth
                    horizontalAlignment: Text.AlignRight
                    text: String(Metrics.blurStrength)
                    color: Theme.text
                    opacity: glass.on ? 1 : 0.45
                    font: Typography.tabular(Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary
                    }))
                }
            }

            // The density step, which is three values and not a range: a slider
            // with three stops is a segmented control that has forgotten it.
            Item {
                width: parent.width
                height: root.rowHeight

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.labelWidth
                    text: "SCALE"
                    color: Theme.text
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary,
                        "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                             Typography.labelTracking)
                    })
                }

                Segmented {
                    anchors.left: parent.left
                    anchors.leftMargin: root.labelWidth + 12 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    metrics: root.metrics
                    fontSize: root.metrics.fontMeta
                    options: [
                        { "key": "compact", "label": "Compact" },
                        { "key": "normal", "label": "Normal" },
                        { "key": "comfortable", "label": "Comfortable" }
                    ]
                    current: root.density
                    onChose: key => root.setDensity(key)
                }
            }

            // One set of durations, moved together: the shell has a tempo rather
            // than a hundred timings, and this is that tempo.
            Item {
                width: parent.width
                height: root.rowHeight

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.labelWidth
                    text: "TIMING"
                    color: Theme.text
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontSecondary,
                        "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                             Typography.labelTracking)
                    })
                }

                Segmented {
                    anchors.left: parent.left
                    anchors.leftMargin: root.labelWidth + 12 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    metrics: root.metrics
                    fontSize: root.metrics.fontMeta
                    options: [
                        { "key": "slow", "label": "Slow" },
                        { "key": "normal", "label": "Normal" },
                        { "key": "fast", "label": "Fast" }
                    ]
                    current: {
                        const speed = Config.get("timing.speed", 1);
                        return speed > 1.15 ? "slow" : speed < 0.85 ? "fast" : "normal";
                    }
                    onChose: key => Config.set("timing.speed",
                                               key === "slow" ? 1.4 : key === "fast" ? 0.7 : 1)
                }
            }

            Item {
                width: parent.width
                height: root.gap
            }

            Section {
                label: "PALETTE"

                Flow {
                    width: parent.width
                    spacing: 6 * root.factor

                    Repeater {
                        model: Theme.palettes

                        delegate: Swatches {
                            required property var modelData
                            palette: modelData
                            chosen: Palettes.current !== null && Palettes.current.file === modelData.file
                            onPressed: Palettes.choose(modelData.file)
                        }
                    }

                    Offer {
                        label: "NEW"
                        onPressed: Palettes.create()
                    }
                }

                Line {
                    text: Theme.source === "matugen"
                          ? "The colours on screen come from the wallpaper. A palette chosen here sets them by hand instead; NEW keeps the wallpaper's as a palette of your own, to change."
                          : Palettes.editable
                          ? `Yours, kept in ~/.config/bioma/palettes/${Palettes.current.file}.json — a file you can copy to somebody else.`
                          : "Bioma's own palettes are kept as they ship. NEW starts one of your own from the colours on screen now."
                }
            }

            Item {
                width: parent.width
                height: root.gap
                visible: Palettes.editable
            }

            Section {
                visible: Palettes.editable
                label: "YOUR PALETTE"

                trailing: Choice {
                    anchors.verticalCenter: parent.verticalCenter
                    metrics: root.metrics
                    label: root.deleting ? "DELETE?" : "DELETE"
                    kind: root.deleting ? "alert" : "plain"
                    onActivated: root.remove()
                }

                Field {
                    id: nameField
                    width: parent.width
                    placeholder: "A name for the theme cell's list"
                    wrong: root.nameProblem.length > 0
                    maximumLength: 32
                    onAccepted: Palettes.rename(nameField.text)
                    onReleased: Palettes.rename(nameField.text)
                }

                Problem {
                    text: root.nameProblem
                }

                Column {
                    width: parent.width
                    spacing: 2 * root.factor

                    Repeater {
                        model: Palettes.roles

                        delegate: Item {
                            id: roleRow

                            required property string modelData

                            readonly property bool chosen: root.role === roleRow.modelData
                            readonly property string hex: Palettes.colours[roleRow.modelData] || ""

                            onHexChanged: if (!hexField.input.activeFocus) hexField.text = roleRow.hex
                            Component.onCompleted: hexField.text = roleRow.hex

                            width: parent.width
                            height: root.roleRow

                            readonly property bool navigable: true
                            function activate() { root.role = roleRow.modelData; }

                            KeyMark { factor: root.factor }

                            Rectangle {
                                anchors.fill: parent
                                radius: Metrics.radiusFor(height, root.metrics)
                                color: roleRow.chosen ? Qt.alpha(Theme.primary, 0.10)
                                     : roleHover.hovered ? Qt.alpha(Theme.text, 0.05) : "transparent"
                            }

                            HoverHandler { id: roleHover }
                            TapHandler { onTapped: roleRow.activate() }

                            Rectangle {
                                id: swatch
                                x: 10 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18 * root.factor
                                height: width
                                radius: width / 2
                                antialiasing: true
                                color: roleRow.hex.length > 0 ? roleRow.hex : "transparent"
                                border.width: Metrics.rim(Screen.devicePixelRatio)
                                border.color: Theme.line
                            }

                            Text {
                                anchors.left: swatch.right
                                anchors.leftMargin: 12 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.roleLabels[roleRow.modelData]
                                color: Theme.text
                                font: root.metaFont
                            }

                            Field {
                                id: hexField
                                anchors.right: dropper.left
                                anchors.rightMargin: 8 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                width: 112 * root.factor
                                technical: true
                                maximumLength: 7
                                // Red only once there is a whole colour's worth of
                            // it: a hex half typed is not yet wrong.
                            wrong: hexField.text.replace("#", "").length >= 6
                                   && Palettes.parse(hexField.text).length === 0
                                onEdited: {
                                    root.role = roleRow.modelData;
                                    Palettes.setRole(roleRow.modelData, hexField.text);
                                }
                                onReleased: hexField.text = roleRow.hex
                            }

                            Tool {
                                id: dropper
                                anchors.right: parent.right
                                anchors.rightMargin: 6 * root.factor
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "picker"
                                lit: Palettes.picking === roleRow.modelData
                                onPressed: {
                                    root.role = roleRow.modelData;
                                    Palettes.pick(roleRow.modelData);
                                }
                            }
                        }
                    }
                }

                Channel {
                    label: "HUE"
                    value: root.hue
                    scale: 360
                    unit: "°"
                    onMoved: fraction => {
                        root.hue = Math.min(fraction, 0.999);
                        root.setHsv(root.hue, root.roleQt.hsvSaturation, root.roleQt.hsvValue);
                    }
                }

                Channel {
                    label: "SATURATION"
                    value: root.roleQt.hsvSaturation
                    onMoved: fraction => root.setHsv(root.hue, fraction, root.roleQt.hsvValue)
                }

                Channel {
                    label: "VALUE"
                    value: root.roleQt.hsvValue
                    onMoved: fraction => root.setHsv(root.hue, root.roleQt.hsvSaturation, fraction)
                }

                Line {
                    text: root.roleLines[root.role]
                    color: Theme.textMuted
                }
            }

            Item {
                width: parent.width
                height: root.gap
            }
        }
    }

    Component.onCompleted: nameField.text = root.editedName
}
