import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.components
import qs.services
import qs.structure
import qs.organisms

// The organisms: what is on each desktop, and how to place it.
//
// One well per monitor, its organisms as chips. A chip's × takes it away —
// it leaves the desktop the way everything in the shell leaves — and a
// press on its name shows its options under the row. The dashed chip adds
// one: it appears in the middle of that screen and the arranging mode
// begins, because an organism nobody has placed is not where anybody wants
// it. Where they are is never set here by figures: it is set by hand, in the
// mode, on the desktop itself.
//
// The weather's city is here too, because it belongs to the weather and not
// to one organism: two weather organisms read one place.
//
// See docs/design/ORGANISMS.md, Settings.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var cell: null

    readonly property real factor: metrics.factor
    readonly property real inset: 14 * factor
    readonly property real headerHeight: 28 * factor
    readonly property real gap: 10 * factor
    readonly property real chipHeight: 26 * factor

    readonly property font labelFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontSecondary,
        "letterSpacing": Typography.tracking(root.metrics.fontSecondary, Typography.labelTracking)
    })

    readonly property font chipFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontMeta,
        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
    })

    readonly property var organisms: Config.get("organisms", [])

    // Which organism's options are open, by its place in the list, and which
    // monitor is choosing a new one.
    property int chosen: -1
    property string picking: ""

    onOrganismsChanged: if (root.chosen >= root.organisms.length) root.chosen = -1

    function indicesOn(screen) {
        const out = [];
        for (let i = 0; i < root.organisms.length; i++)
            if (Strips.belongs(root.organisms[i], screen))
                out.push(i);
        return out;
    }

    // One key of one organism, written as the whole list — a list is one
    // value to the merge.
    function setOption(index, key, value) {
        const next = Arranging.named(JSON.parse(JSON.stringify(root.organisms)));
        if (!next[index])
            return;
        if (value === null)
            delete next[index][key];
        else
            next[index][key] = value;
        Config.set("organisms", next);
    }

    // Placing is done on the desktop, so the settings step out of the way.
    function arrange(from) {
        if (root.cell)
            root.cell.open = false;
        Arranging.start(from);
    }

    function add(type, screen) {
        root.picking = "";
        // A note has nothing to show until it has a file, so the settings
        // stay and open its options instead; it is placed once it has one.
        if (type === "note") {
            root.chosen = root.organisms.length;
            Arranging.add(type, screen.name, true);
            return;
        }
        if (root.cell)
            root.cell.open = false;
        Arranging.add(type, screen.name);
    }

    // ---- A note's file --------------------------------------------------------------

    readonly property string home: Quickshell.env("HOME")

    function expanded(path) {
        return path.startsWith("~") ? root.home + path.slice(1) : path;
    }

    function setFile(index, path) {
        Arranging.setFile(index, path);
    }

    // The picker is a window: the settings step out of its way, or the first
    // press on it would close them — and it lives in Arranging, so it outlives
    // them.
    function chooseFile(index) {
        if (root.cell)
            root.cell.open = false;
        Arranging.chooseFile(index);
    }

    // The service runs while this page is open, so a city typed here is
    // looked up at once and an error is said where it was typed.
    Component.onCompleted: Weather.hold(root, true)
    Component.onDestruction: Weather.hold(root, false)

    // A well: its label, perhaps its control on the same line, then what it
    // means — the Session page's layout.
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
            color: Theme.textMuted
            font: root.labelFont
        }

        Item {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            y: root.inset
            width: childrenRect.width
            height: root.headerHeight
        }

        Column {
            id: body
            x: root.inset
            y: root.inset + root.headerHeight + 6 * root.factor
            width: section.width - root.inset * 2
            spacing: 10 * root.factor
        }
    }

    component Line: Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.text
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontSecondary
        lineHeight: 1.15
    }

    // An option's row: what it is, and the choice beside it.
    component OptionRow: Item {
        id: optionRow

        property string label: ""
        default property alias control: controlSlot.data

        width: parent.width
        height: Math.max(26 * root.factor, controlSlot.childrenRect.height)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: optionRow.label
            color: Theme.textFaint
            font: root.chipFont
        }

        Item {
            id: controlSlot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

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

            // ---- Each monitor ---------------------------------------------------------

            Repeater {
                model: Quickshell.screens

                delegate: Section {
                    id: screenSection

                    required property var modelData
                    readonly property var here: root.indicesOn(screenSection.modelData)
                    readonly property bool choosing: root.picking === screenSection.modelData.name
                    readonly property int open: screenSection.here.indexOf(root.chosen) >= 0 ? root.chosen : -1

                    label: screenSection.modelData.name

                    Flow {
                        width: parent.width
                        spacing: 6 * root.factor

                        Repeater {
                            model: screenSection.here

                            delegate: Item {
                                id: chip

                                required property int modelData
                                readonly property var entry: root.organisms[chip.modelData] ?? ({})
                                readonly property bool lit: root.chosen === chip.modelData

                                width: chipName.implicitWidth + 40 * root.factor
                                height: root.chipHeight

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Metrics.radiusFor(height, root.metrics)
                                    antialiasing: true
                                    color: Qt.alpha(Theme.lift(Theme.background, chip.lit ? 0.05 : 0.02), 0.9)
                                    border.width: Metrics.rim(Screen.devicePixelRatio)
                                    border.color: chip.lit ? Theme.primary : Theme.line
                                }

                                Text {
                                    id: chipName
                                    x: 10 * root.factor
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (Organisms.names[chip.entry.type] || chip.entry.type || "").toUpperCase()
                                    color: Theme.text
                                    font: root.chipFont
                                }

                                // The name opens its options; the cross beside it
                                // takes it away. Two places that do not overlap,
                                // so a press is only ever one of the two.
                                Item {
                                    anchors.left: parent.left
                                    anchors.right: cross.left
                                    height: parent.height

                                    TapHandler {
                                        onTapped: root.chosen = chip.lit ? -1 : chip.modelData
                                    }
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
                                        colour: crossHover.hovered ? Theme.text : Theme.textMuted
                                    }

                                    HoverHandler { id: crossHover }

                                    TapHandler {
                                        onTapped: {
                                            if (root.chosen === chip.modelData)
                                                root.chosen = -1;
                                            Arranging.remove(chip.modelData);
                                        }
                                    }
                                }
                            }
                        }

                        // The dashed chip adds one: a place rather than a content.
                        Item {
                            width: 44 * root.factor
                            height: root.chipHeight

                            DashedSlot {
                                anchors.fill: parent
                                radius: Metrics.radiusFor(parent.height, root.metrics)
                                colour: screenSection.choosing ? Theme.primary : Qt.alpha(Theme.line, 0.7)
                            }

                            Icon {
                                anchors.centerIn: parent
                                width: 11 * root.factor
                                height: width
                                name: "plus"
                                colour: screenSection.choosing ? Theme.primary : Theme.textFaint
                            }

                            TapHandler {
                                onTapped: root.picking = screenSection.choosing ? "" : screenSection.modelData.name
                            }
                        }
                    }

                    // The kinds there are, while one is being added.
                    Flow {
                        visible: screenSection.choosing
                        width: parent.width
                        spacing: 6 * root.factor

                        Repeater {
                            model: Object.keys(Organisms.names)

                            delegate: Item {
                                id: kind

                                required property string modelData

                                width: kindName.implicitWidth + 22 * root.factor
                                height: root.chipHeight

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Metrics.radiusFor(height, root.metrics)
                                    antialiasing: true
                                    color: "transparent"
                                    border.width: Metrics.rim(Screen.devicePixelRatio)
                                    border.color: kindHover.hovered ? Theme.primary : Theme.line
                                }

                                Text {
                                    id: kindName
                                    anchors.centerIn: parent
                                    text: Organisms.names[kind.modelData].toUpperCase()
                                    color: kindHover.hovered ? Theme.primary : Theme.text
                                    font: root.chipFont
                                }

                                HoverHandler { id: kindHover }

                                TapHandler {
                                    onTapped: root.add(kind.modelData, screenSection.modelData)
                                }
                            }
                        }
                    }

                    // The options of the organism whose chip is lit.
                    OptionRow {
                        visible: screenSection.open >= 0
                        label: "SIZE"

                        Segmented {
                            metrics: root.metrics
                            fontSize: root.metrics.fontMeta
                            buttonPadding: 10 * root.factor
                            options: [
                                { "key": "", "label": "Membranes" },
                                { "key": "compact", "label": "Compact" },
                                { "key": "normal", "label": "Normal" },
                                { "key": "comfortable", "label": "Comfortable" }
                            ]
                            current: screenSection.open >= 0 ? (root.organisms[screenSection.open].size || "") : ""
                            onChose: key => root.setOption(screenSection.open, "size", key.length > 0 ? key : null)
                        }
                    }

                    OptionRow {
                        visible: screenSection.open >= 0 && root.organisms[screenSection.open].type === "media"
                        label: "VISUALISER"

                        Switch {
                            factor: root.factor
                            on: screenSection.open >= 0 && root.organisms[screenSection.open].band !== false
                            onToggled: value => root.setOption(screenSection.open, "band", value ? null : false)
                        }
                    }

                    OptionRow {
                        visible: screenSection.open >= 0 && root.organisms[screenSection.open].type === "vitals"
                        label: "LAYOUT"

                        Segmented {
                            metrics: root.metrics
                            fontSize: root.metrics.fontMeta
                            buttonPadding: 10 * root.factor
                            options: [
                                { "key": "row", "label": "Row" },
                                { "key": "square", "label": "Square" }
                            ]
                            current: screenSection.open >= 0 && root.organisms[screenSection.open].layout === "square"
                                     ? "square" : "row"
                            onChose: key => root.setOption(screenSection.open, "layout", key === "square" ? key : null)
                        }
                    }

                    OptionRow {
                        visible: screenSection.open >= 0 && root.organisms[screenSection.open].type === "note"
                        label: "HEIGHT"

                        Segmented {
                            metrics: root.metrics
                            fontSize: root.metrics.fontMeta
                            buttonPadding: 10 * root.factor
                            options: [
                                { "key": "short", "label": "Short" },
                                { "key": "medium", "label": "Medium" },
                                { "key": "tall", "label": "Tall" }
                            ]
                            current: screenSection.open >= 0 ? (root.organisms[screenSection.open].height || "medium") : "medium"
                            onChose: key => root.setOption(screenSection.open, "height", key === "medium" ? null : key)
                        }
                    }

                    // A note's file: the path, typed or chosen, and why it
                    // cannot be read when it cannot.
                    Column {
                        id: noteFile

                        readonly property bool shown: screenSection.open >= 0
                                                      && root.organisms[screenSection.open].type === "note"
                        readonly property string path: noteFile.shown ? (root.organisms[screenSection.open].file || "") : ""

                        visible: noteFile.shown
                        width: parent.width
                        spacing: 8 * root.factor

                        // Whether it can be read, asked the way the organism asks.
                        property bool readable: false
                        FileView {
                            path: noteFile.shown ? root.expanded(noteFile.path) : ""
                            printErrors: false
                            watchChanges: true
                            onLoaded: noteFile.readable = true
                            onLoadFailed: noteFile.readable = false
                            onFileChanged: reload()
                        }
                        onPathChanged: noteFile.readable = false

                        readonly property bool wrong: noteFile.path.length > 0 && !noteFile.readable

                        Item {
                            width: parent.width
                            height: 34 * root.factor

                            Text {
                                id: fileLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "FILE"
                                color: Theme.textFaint
                                font: root.chipFont
                            }

                            Rectangle {
                                anchors.left: fileLabel.right
                                anchors.leftMargin: 14 * root.factor
                                anchors.right: choose.left
                                anchors.rightMargin: 8 * root.factor
                                height: parent.height
                                radius: Metrics.radiusFor(height, root.metrics)
                                antialiasing: true
                                color: "transparent"
                                border.width: Metrics.rim(Screen.devicePixelRatio)
                                border.color: noteFile.wrong ? Theme.alert
                                            : fileField.activeFocus ? Theme.primary : Theme.line

                                TextInput {
                                    id: fileField

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
                                    text: noteFile.path

                                    onActiveFocusChanged: if (root.cell && activeFocus) root.cell.fieldEngaged = true
                                    onAccepted: {
                                        root.setFile(screenSection.open, text);
                                        focus = false;
                                    }
                                    Keys.onEscapePressed: {
                                        text = noteFile.path;
                                        focus = false;
                                    }

                                    Text {
                                        visible: fileField.text.length === 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "A Markdown file"
                                        color: Theme.textFaint
                                        font: fileField.font
                                    }
                                }
                            }

                            Choice {
                                id: choose
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                metrics: root.metrics
                                label: "Choose"
                                onActivated: root.chooseFile(screenSection.open)
                            }
                        }

                        Row {
                            visible: noteFile.wrong || Arranging.pickerError.length > 0
                            spacing: 8 * root.factor

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14 * root.factor
                                height: width
                                name: "error"
                                colour: Theme.alert
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Arranging.pickerError.length > 0 ? Arranging.pickerError
                                      : "This file cannot be read, so the note is not shown."
                                color: Theme.alert
                                font.family: Typography.expressive
                                font.pixelSize: root.metrics.fontSecondary
                            }
                        }
                    }

                    Line {
                        text: screenSection.here.length === 0
                              ? "Nothing stands on this desktop. The dashed chip adds an organism here."
                              : screenSection.open >= 0
                                ? "Its size follows the membranes unless it is given its own."
                                : "Press an organism for its options, or its cross to take it away."
                    }
                }
            }

            // ---- Placing --------------------------------------------------------------

            Section {
                label: "ARRANGE"

                trailing: Choice {
                    anchors.verticalCenter: parent.verticalCenter
                    metrics: root.metrics
                    kind: "primary"
                    label: "Arrange"
                    onActivated: root.arrange()
                }

                Line {
                    text: "Lifts the organisms above the windows, to be dragged into place on any screen. Done, or Escape, puts them back."
                }
            }

            // ---- The weather's place ----------------------------------------------------

            Section {
                id: weather

                label: "WEATHER"

                readonly property bool wrong: Weather.problem.length > 0 && Weather.city.length > 0

                Item {
                    width: parent.width
                    height: 34 * root.factor

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        antialiasing: true
                        color: "transparent"
                        border.width: Metrics.rim(Screen.devicePixelRatio)
                        border.color: weather.wrong ? Theme.alert
                                    : cityField.activeFocus ? Theme.primary : Theme.line
                    }

                    TextInput {
                        id: cityField

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

                        // Not cleared when the city is not found: making
                        // someone type it again is a punishment, not
                        // information.
                        text: Weather.city

                        onActiveFocusChanged: if (root.cell && activeFocus) root.cell.fieldEngaged = true
                        onAccepted: {
                            Config.set("weather.city", text.trim());
                            focus = false;
                        }
                        Keys.onEscapePressed: {
                            text = Weather.city;
                            focus = false;
                        }

                        Text {
                            visible: cityField.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "A city"
                            color: Theme.textFaint
                            font: cityField.font
                        }
                    }
                }

                // The reason, where it happened.
                Row {
                    visible: weather.wrong
                    width: parent.width
                    spacing: 8 * root.factor

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14 * root.factor
                        height: width
                        name: "error"
                        colour: Theme.alert
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.problem
                        color: Theme.alert
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }
                }

                Line {
                    text: Weather.city.length === 0
                          ? "The weather organism reads the weather for this city. Enter keeps it."
                          : Weather.located
                            ? `Read for ${Weather.place}, every ${Config.get("weather.minutes", 30)} minutes, from Open-Meteo.`
                            : "Looking for it…"
                }
            }
        }
    }
}
