pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.cells
import qs.services

// The keys: added, edited and removed.
//
// Every bind niri reads, one row each, in the order niri reads them — which is
// the order they are written across the configuration's files. A row is what
// the bind does and the keys that do it, as keycaps.
//
// **A combination is recorded by pressing it, not by typing it.** The pencil
// turns the keycaps into a field that listens; the next key pressed with its
// modifiers is the new combination, and it is written as soon as it is
// pressed. While the field listens niri's own shortcuts are inhibited, or
// pressing a combination that is already taken would do what it is taken for
// instead of being recorded. A taken combination is refused where it was
// pressed, saying by what; Escape leaves the bind as it was, and the cross
// that replaces the pencil removes it.
//
// A new shortcut starts from what it does: the dashed chip opens a picker on
// a thread — the cells first, then niri's own actions — and what is chosen
// arrives at the end of the list already listening for its keys.
//
// The binds are niri's, so they are written where niri keeps them, each into
// the file it came from; see services/Keybinds.qml.
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real listRow: 38 * factor
    readonly property real pickerRow: 36 * factor
    readonly property real pickerWidth: 220 * factor
    readonly property real threadLength: metrics.gap
    readonly property real fieldHeight: 30 * factor
    readonly property real fieldWidth: 230 * factor
    readonly property real chipHeight: 26 * factor
    readonly property real footerHeight: 44 * factor
    readonly property real slotWidth: 28 * factor

    // ---- What is being done ------------------------------------------------

    // The bind whose keys are being recorded, by id; or `"new"` for the one
    // being added, whose action is in `adding`.
    property string recording: ""
    property var adding: null

    // What the field has heard so far: the modifiers held down now, and the
    // last combination refused, with what it belongs to.
    property var held: []
    property string refused: ""
    property string refusedBy: ""

    property bool picking: false

    readonly property bool listening: root.recording.length > 0

    // The rows, with the one being added at the end while it waits for keys.
    // What the search asks for. Words that are all names of keys are a
    // combination, and find the binds that use every one of those keys —
    // "super v" is Clipboard Manager, not every action with a v in its name.
    // Anything else is looked for in what the bind does, any key named along
    // the way still counting as a key: "super workspace".
    readonly property var words: search.text.toLowerCase().split(/[\s+]+/)
        .filter(w => w.length > 0)
        .map(w => w === "mod" || w === "win" || w === "meta" ? "super" : w === "control" ? "ctrl" : w)

    readonly property var capNames: {
        const seen = {};
        for (const bind of Keybinds.binds)
            for (const cap of bind.caps)
                seen[cap.toLowerCase()] = true;
        return seen;
    }

    readonly property bool combination: root.words.length > 0
                                        && root.words.every(word => root.capNames[word] === true)

    function matches(bind) {
        if (root.words.length === 0)
            return true;
        const caps = bind.caps.map(cap => cap.toLowerCase());
        if (root.combination)
            return root.words.every(word => caps.includes(word));
        const label = bind.label.toLowerCase();
        return root.words.every(word => caps.includes(word) || label.includes(word));
    }

    readonly property var found: Keybinds.binds.filter(bind => root.matches(bind))

    readonly property var rows: {
        const out = root.found.slice();
        if (root.adding)
            out.push({
                "id": "new",
                "label": root.adding.label,
                "caps": [],
                "file": Keybinds.main,
                "shadowed": false
            });
        return out;
    }

    // The keyboard is the page's for as long as it listens or filters —
    // not only while the pointer is over the panel: a hand reaching for a
    // modifier moves the mouse as often as not.
    onListeningChanged: if (root.cell) root.cell.holdsKeys = root.listening || root.picking
    onPickingChanged: if (root.cell) root.cell.holdsKeys = root.listening || root.picking
    Component.onDestruction: if (root.cell) {
        root.cell.holdsKeys = false;
        root.cell.fieldEngaged = false;
    }

    function edit(bind) {
        root.picking = false;
        root.adding = null;
        root.listen(bind.id);
    }

    function listen(id) {
        root.recording = id;
        root.held = [];
        root.refused = "";
        root.refusedBy = "";
        recorder.forceActiveFocus();
    }

    function stop() {
        root.recording = "";
        root.adding = null;
        root.held = [];
        root.refused = "";
        root.refusedBy = "";
        recorder.focus = false;
    }

    function bindOf(id) {
        return Keybinds.binds.find(bind => bind.id === id) || null;
    }

    function drop(id) {
        const bind = root.bindOf(id);
        root.stop();
        if (bind)
            Keybinds.remove(bind);
    }

    // A combination heard in full. Refused if it is taken — by anything but
    // the bind being edited — and written otherwise.
    function heard(combination) {
        const editing = root.recording === "new" ? "" : root.recording;
        const taken = Keybinds.owner(combination, editing);
        if (taken) {
            root.refused = combination;
            root.refusedBy = taken.label;
            root.held = [];
            return;
        }

        if (root.recording === "new") {
            Keybinds.add(combination, root.adding.action, root.adding.title);
        } else {
            const bind = root.bindOf(root.recording);
            if (bind)
                Keybinds.rekey(bind, combination);
        }
        root.stop();
    }

    // ---- From a key event to niri's name for it -----------------------------
    //
    // niri names keys by their xkb keysym at the first level — the one with no
    // Shift applied — so `Mod+Shift+1`, never `Mod+Shift+exclam`. Qt reports
    // the shifted symbol for everything but letters, so the punctuation and
    // the digit row are read by position instead, from the scan code, which
    // Wayland hands over as the xkb keycode. Letters and named keys come from
    // Qt, which already knows the layout.

    readonly property var byPosition: ({
        "10": "1", "11": "2", "12": "3", "13": "4", "14": "5",
        "15": "6", "16": "7", "17": "8", "18": "9", "19": "0",
        "20": "Minus", "21": "Equal", "34": "BracketLeft", "35": "BracketRight",
        "47": "Semicolon", "48": "Apostrophe", "49": "Grave", "51": "Backslash",
        "59": "Comma", "60": "Period", "61": "Slash", "94": "Less"
    })

    function named(key) {
        switch (key) {
        case Qt.Key_Space: return "Space";
        case Qt.Key_Return: return "Return";
        case Qt.Key_Enter: return "KP_Enter";
        case Qt.Key_Escape: return "Escape";
        case Qt.Key_Tab: case Qt.Key_Backtab: return "Tab";
        case Qt.Key_Backspace: return "BackSpace";
        case Qt.Key_Delete: return "Delete";
        case Qt.Key_Insert: return "Insert";
        case Qt.Key_Home: return "Home";
        case Qt.Key_End: return "End";
        case Qt.Key_PageUp: return "Page_Up";
        case Qt.Key_PageDown: return "Page_Down";
        case Qt.Key_Up: return "Up";
        case Qt.Key_Down: return "Down";
        case Qt.Key_Left: return "Left";
        case Qt.Key_Right: return "Right";
        case Qt.Key_Print: return "Print";
        case Qt.Key_Pause: return "Pause";
        case Qt.Key_Menu: return "Menu";
        case Qt.Key_VolumeUp: return "XF86AudioRaiseVolume";
        case Qt.Key_VolumeDown: return "XF86AudioLowerVolume";
        case Qt.Key_VolumeMute: return "XF86AudioMute";
        case Qt.Key_MicMute: return "XF86AudioMicMute";
        case Qt.Key_MediaPlay: case Qt.Key_MediaTogglePlayPause: return "XF86AudioPlay";
        case Qt.Key_MediaPause: return "XF86AudioPause";
        case Qt.Key_MediaStop: return "XF86AudioStop";
        case Qt.Key_MediaNext: return "XF86AudioNext";
        case Qt.Key_MediaPrevious: return "XF86AudioPrev";
        case Qt.Key_MonBrightnessUp: return "XF86MonBrightnessUp";
        case Qt.Key_MonBrightnessDown: return "XF86MonBrightnessDown";
        }
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35)
            return "F" + (key - Qt.Key_F1 + 1);
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            return String.fromCharCode(key);
        return "";
    }

    function isModifier(key) {
        return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
            || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R
            || key === Qt.Key_AltGr || key === Qt.Key_Hyper_L || key === Qt.Key_Hyper_R;
    }

    function modifiersOf(event) {
        const out = [];
        if (event.modifiers & Qt.MetaModifier) out.push("Mod");
        if (event.modifiers & Qt.ControlModifier) out.push("Ctrl");
        if (event.modifiers & Qt.AltModifier) out.push("Alt");
        if (event.modifiers & Qt.ShiftModifier) out.push("Shift");
        return out;
    }

    // The modifier a key is, when it is one — its own flag is not yet in the
    // event's modifiers on the press that sets it.
    function modifierOf(key) {
        if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "Mod";
        if (key === Qt.Key_Control) return "Ctrl";
        if (key === Qt.Key_Alt) return "Alt";
        if (key === Qt.Key_Shift) return "Shift";
        return "";
    }

    Item {
        id: recorder

        focus: false

        Keys.onPressed: event => {
            event.accepted = true;
            const mods = root.modifiersOf(event);

            if (root.isModifier(event.key)) {
                const own = root.modifierOf(event.key);
                if (own.length > 0 && !mods.includes(own))
                    mods.push(own);
                root.held = Keybinds.keycaps(mods.concat([""]).join("+")).slice(0, -1);
                return;
            }

            if (event.key === Qt.Key_Escape && mods.length === 0) {
                root.stop();
                return;
            }

            const key = root.byPosition[String(event.nativeScanCode)] || root.named(event.key);
            if (key.length === 0)
                return;

            root.heard(mods.concat([key]).join("+"));
        }

        Keys.onReleased: event => {
            event.accepted = true;
            if (!root.isModifier(event.key))
                return;
            const own = root.modifierOf(event.key);
            const mods = root.modifiersOf(event).filter(m => m !== own);
            root.held = mods.length > 0 ? Keybinds.keycaps(mods.concat([""]).join("+")).slice(0, -1) : [];
        }
    }

    // niri answers its own shortcuts before any surface hears them. While
    // the field listens, they are asked to stand aside for this one.
    readonly property var window: QsWindow.window

    ShortcutInhibitor {
        window: root.window
        enabled: root.listening
    }

    // ---- The list ----------------------------------------------------------

    // ---- The search --------------------------------------------------------
    //
    // The vitals search, the same object: a lens in the primary, no well of its
    // own, and the count said in words on the other side. Pressing the field
    // keeps the keyboard after the pointer has wandered off the panel; Escape
    // empties it first and gives the keyboard back second.

    Item {
        id: searchRow

        width: parent.width
        height: root.metrics.fieldHeight

        TapHandler {
            onTapped: {
                if (root.cell)
                    root.cell.fieldEngaged = true;
                search.forceActiveFocus();
            }
        }

        Icon {
            id: lens
            anchors.left: parent.left
            anchors.leftMargin: 6 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            width: 16 * root.factor
            height: width
            gradient: true
        }

        TextInput {
            id: search

            anchors.left: lens.right
            anchors.leftMargin: 10 * root.factor
            anchors.right: count.left
            anchors.rightMargin: 12 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
            selectByMouse: true
            clip: true

            Keys.onEscapePressed: {
                if (search.text.length > 0) {
                    search.text = "";
                    return;
                }
                search.focus = false;
                if (root.cell)
                    root.cell.fieldEngaged = false;
            }

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: "Search shortcuts"
                color: Theme.textMuted
                font: search.font
            }
        }

        Text {
            id: count
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: root.words.length === 0 ? Keybinds.count + " shortcuts"
                                          : root.found.length + " of " + Keybinds.count
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }

    Well {
        id: well

        metrics: root.metrics
        inset: 6 * root.factor
        y: searchRow.height + 10 * root.factor
        width: parent.width
        height: parent.height - root.footerHeight - y

        // Picking is about the picker; the list stays where it was, quieter.
        opacity: root.picking ? 0.35 : 1

        Behavior on opacity {
            NumberAnimation { duration: Timing.transition }
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: 6 * root.factor
            anchors.rightMargin: 12 * root.factor
            // Changed in place rather than replaced: a list handed a new
            // array starts again from the top, and every edit is a new array.
            model: ScriptModel {
                values: root.rows
                objectProp: "id"
            }
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            interactive: !root.picking

            // The row being added is at the end, and it has to be seen to be
            // pressed for.
            onCountChanged: if (root.adding) positionViewAtEnd()

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property bool live: root.recording === row.modelData.id
                readonly property bool isNew: row.modelData.id === "new"

                width: ListView.view.width
                height: root.listRow

                HoverHandler {
                    id: rowHover
                    onHoveredChanged: {
                        if (hovered)
                            root.hoveredFile = row.modelData.file;
                        else if (root.hoveredFile === row.modelData.file)
                            root.hoveredFile = "";
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10 * root.factor
                    anchors.right: row.live ? field.left : caps.left
                    anchors.rightMargin: 12 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label
                    elide: Text.ElideRight
                    // Overridden by a bind read later, so written down but
                    // not what the key does: there, and faint.
                    color: row.modelData.shadowed ? Theme.textFaint : Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: 14 * root.factor
                }

                // The keys, as keycaps.
                Row {
                    id: caps

                    visible: !row.live
                    anchors.right: slot.left
                    anchors.rightMargin: 6 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.factor

                    Repeater {
                        model: row.modelData.caps

                        delegate: Keycap {
                            required property string modelData
                            metrics: root.metrics
                            label: modelData
                            faint: row.modelData.shadowed
                        }
                    }
                }

                // Listening: the keycaps become a field.
                Item {
                    id: field

                    visible: row.live
                    anchors.right: slot.left
                    anchors.rightMargin: 6 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.fieldWidth
                    height: root.fieldHeight

                    readonly property bool refusing: root.refused.length > 0 && root.held.length === 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        color: "transparent"
                        border.width: Metrics.crisp(1.5, Screen.devicePixelRatio)
                        border.color: field.refusing ? Theme.alert : Theme.primary
                        antialiasing: true

                        Behavior on border.color { ColorAnimation { duration: Timing.transition } }
                    }

                    // What is held down so far, as it is held.
                    Row {
                        id: heldCaps

                        visible: root.held.length > 0
                        anchors.left: parent.left
                        anchors.leftMargin: 4 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4 * root.factor

                        Repeater {
                            model: root.held
                            delegate: Keycap {
                                required property string modelData
                                metrics: root.metrics
                                label: modelData
                                height: root.fieldHeight - 8 * root.factor
                            }
                        }
                    }

                    Text {
                        id: prompt

                        visible: root.held.length === 0
                        anchors.left: parent.left
                        anchors.leftMargin: 14 * root.factor
                        anchors.right: parent.right
                        anchors.rightMargin: 14 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: field.refusing
                              ? Keybinds.keycaps(root.refused).join(" ") + " is already " + root.refusedBy
                              : "Press a combination…"
                        elide: Text.ElideRight
                        color: field.refusing ? Theme.alert : Theme.textMuted
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }

                    // The caret: the field is listening. It does not blink —
                    // a blink is a rate with nothing behind it.
                    Rectangle {
                        visible: root.held.length === 0 && !field.refusing
                        x: prompt.x + prompt.contentWidth + 3 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        width: Metrics.crisp(1, Screen.devicePixelRatio)
                        height: root.metrics.fontSecondary + 2 * root.factor
                        color: Theme.primary
                    }
                }

                // The pencil, or — listening — the cross that removes it.
                Item {
                    id: slot

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.slotWidth
                    height: parent.height

                    Icon {
                        anchors.centerIn: parent
                        width: (row.live ? 10 : 13) * root.factor
                        height: width
                        name: row.live ? "close" : "edit"
                        colour: slotHover.hovered ? Theme.text
                              : row.live ? Theme.textMuted : Theme.textFaint
                    }

                    HoverHandler { id: slotHover }

                    TapHandler {
                        enabled: !root.picking && !Keybinds.busy
                        onTapped: {
                            if (!row.live)
                                root.edit(row.modelData);
                            else if (row.isNew)
                                root.stop();
                            else
                                root.drop(row.modelData.id);
                        }
                    }
                }
            }
        }

        Scroller {
            flick: list
            factor: root.factor
            x: well.width - width - 4 * root.factor
        }

        Text {
            anchors.centerIn: parent
            visible: root.rows.length === 0
            text: root.words.length > 0 ? "Nothing bound to that" : "Reading niri's configuration…"
            color: Theme.textFaint
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }

    // ---- The foot of the page ---------------------------------------------

    property string hoveredFile: ""

    // Where a path is, said the short way.
    function shortPath(path) {
        const home = Quickshell.env("HOME") ?? "";
        return home.length > 0 && path.startsWith(home) ? "~" + path.slice(home.length) : path;
    }

    Item {
        id: adder

        anchors.left: parent.left
        anchors.verticalCenter: foot.verticalCenter
        width: adderLabel.implicitWidth + 28 * root.factor
        height: root.chipHeight

        DashedSlot {
            anchors.fill: parent
            radius: Metrics.radiusFor(parent.height, root.metrics)
            colour: root.picking ? Theme.primary : Qt.alpha(Theme.line, 0.7)
        }

        Text {
            id: adderLabel
            anchors.centerIn: parent
            text: "+ Shortcut"
            color: root.picking ? Theme.primary : Theme.textMuted
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                     Typography.labelTracking)
            })
        }

        TapHandler {
            enabled: !Keybinds.busy
            onTapped: root.pick(!root.picking)
        }
    }

    Item {
        id: foot

        anchors.left: adder.right
        anchors.leftMargin: 12 * root.factor
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.footerHeight

        // What is true right now, in one line: what niri refused, how to get
        // out of the field, which file the row under the pointer lives in,
        // or — with nothing else to say — where all of this is written.
        Text {
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: Keybinds.error.length > 0 ? Keybinds.error
                : root.listening ? "Esc leaves it as it was"
                : root.picking ? "Enter takes the first"
                : root.hoveredFile.length > 0 ? root.shortPath(root.hoveredFile)
                : "reads and rewrites niri's binds, where they are written"
            color: Keybinds.error.length > 0 ? Theme.alert : Theme.textFaint
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontMeta
        }
    }

    // ---- The picker ----------------------------------------------------------
    //
    // It hangs off the add chip on a thread and grows up from it, over the
    // list: the cells first, as the shell's own, then niri's actions — every
    // one this niri knows that needs no argument. Every cell is on it: a key
    // opens a cell where it is placed on the monitor, and in the middle of it
    // when it is placed nowhere.

    readonly property var choices: {
        const out = [];
        const wanted = filter.text.trim().toLowerCase();
        const keep = label => wanted.length === 0 || label.toLowerCase().includes(wanted);

        for (const type of Object.keys(Registry.names)) {
            // The recording cell is made by the capture, not summoned.
            if (type === "recording")
                continue;
            const label = Registry.nameOf(type);
            if (!keep(label))
                continue;
            out.push({
                "group": "CELLS",
                "label": label,
                "cell": type,
                "title": "Bioma: " + label.toLowerCase(),
                "action": {
                    "name": "spawn",
                    "args": ["qs", "-p", Quickshell.shellPath("shell.qml"),
                             "ipc", "call", "cell", "toggle", type]
                }
            });
        }

        for (const name of Keybinds.actions) {
            const label = Keybinds.humanize(name);
            if (!keep(label))
                continue;
            out.push({
                "group": "NIRI",
                "label": label,
                "cell": "",
                "title": "",
                "action": { "name": name, "args": [] }
            });
        }
        return out;
    }

    readonly property real headerRow: 26 * factor

    // How many headings the picker draws, for its height.
    readonly property int groups: {
        const seen = [];
        for (const choice of root.choices)
            if (!seen.includes(choice.group))
                seen.push(choice.group);
        return seen.length;
    }

    function pick(on) {
        root.stop();
        root.picking = on;
        if (!on)
            return;
        Keybinds.askActions();
        filter.text = "";
        filter.forceActiveFocus();
    }

    function choose(choice) {
        root.picking = false;
        root.adding = choice;
        root.listen("new");
    }

    Thread {
        id: pickerLink

        visible: root.picking
        vertical: false
        progress: root.picking ? 1 : 0
        width: root.threadLength
        height: implicitHeight
        x: adder.x + adder.width
        y: adder.y + adder.height / 2 - height / 2
    }

    Well {
        id: picker

        visible: root.picking
        metrics: root.metrics
        inset: 6 * root.factor
        width: root.pickerWidth
        x: adder.x + adder.width + root.threadLength
        // It grows up from the chip it hangs from, as far as the page goes.
        height: Math.min(adder.y + adder.height,
                         filterRow.height + Math.max(1, root.choices.length) * root.pickerRow
                         + root.groups * root.headerRow + 20 * root.factor)
        y: adder.y + adder.height - height

        Item {
            id: filterRow

            x: 6 * root.factor
            y: 6 * root.factor
            width: parent.width - 12 * root.factor
            height: 34 * root.factor

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusFor(height, root.metrics)
                color: "transparent"
                border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                border.color: filter.activeFocus ? Theme.primary : Theme.line
                antialiasing: true
            }

            TextInput {
                id: filter

                anchors.left: parent.left
                anchors.leftMargin: 14 * root.factor
                anchors.right: parent.right
                anchors.rightMargin: 14 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
                clip: true

                Keys.onEscapePressed: root.picking = false
                onAccepted: {
                    const first = root.choices.length > 0 ? root.choices[0] : null;
                    if (first)
                        root.choose(first);
                }

                Text {
                    visible: filter.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "What should it do?"
                    color: Theme.textFaint
                    font: filter.font
                }
            }
        }

        ListView {
            id: options

            anchors.fill: parent
            anchors.topMargin: filterRow.y + filterRow.height + 4 * root.factor
            anchors.margins: 6 * root.factor
            model: root.choices
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            section.property: "group"
            section.delegate: Item {
                required property string section

                width: ListView.view.width
                height: root.headerRow

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8 * root.factor
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4 * root.factor
                    text: parent.section
                    color: Theme.textFaint
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }
            }

            delegate: Item {
                id: option

                required property var modelData

                width: ListView.view.width
                height: root.pickerRow

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8 * root.factor
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.modelData.label
                    elide: Text.ElideRight
                    color: optionHover.hovered ? Theme.primary : Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: 14 * root.factor
                }

                HoverHandler { id: optionHover }

                TapHandler {
                    onTapped: root.choose(option.modelData)
                }
            }
        }

        Scroller {
            flick: options
            factor: root.factor
            x: picker.width - width - 4 * root.factor
        }
    }

    // ---- A key, drawn --------------------------------------------------------

    component Keycap: Item {
        id: cap

        property string label: ""
        property bool faint: false
        property var metrics: Metrics.step("normal")

        readonly property real factor: cap.metrics.factor

        height: 24 * cap.factor
        width: Math.max(height, capText.implicitWidth + 16 * cap.factor)

        Rectangle {
            anchors.fill: parent
            radius: 6 * cap.factor
            color: "transparent"
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: cap.faint ? Qt.alpha(Theme.line, 0.5) : Theme.line
            antialiasing: true
        }

        Text {
            id: capText
            anchors.centerIn: parent
            text: cap.label
            color: cap.faint ? Theme.textFaint : Theme.text
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": cap.metrics.fontMeta,
                "letterSpacing": Typography.tracking(cap.metrics.fontMeta,
                                                     Typography.labelTracking)
            })
        }
    }
}
