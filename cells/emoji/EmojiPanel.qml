pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The emoji cell, opened: a field with the skin tones beside it, the emoji in a
// grid, and the name of the one chosen.
//
// With nothing typed the grid is the whole set in Unicode's order, under its
// groups' names, with the last ones sent above them all. Typed into, it is
// what answers, best first, with no groups: an answer is not an archive.
//
// The keyboard stays in the field. The arrows move the choice through the
// grid, Enter sends it, Tab changes the tone, Escape empties the field and then
// closes the cell — the hand never has to leave the letters it is typing.
//
// The grid is a list of rows rather than a grid, because a grid cannot carry
// the groups' names between its rows; each row is ten emoji or one name.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property int columns: 10
    readonly property real rowHeight: 42 * factor
    readonly property real labelHeight: 26 * factor
    readonly property int shownRows: 7
    readonly property real glyph: 24 * factor
    readonly property real footHeight: 36 * factor

    implicitWidth: 440 * factor
    implicitHeight: root.metrics.fieldHeight + 10 * factor + listHeight + footHeight
    width: implicitWidth
    height: implicitHeight

    readonly property real listHeight: root.shownRows * root.rowHeight + 12 * factor

    // ---- What is shown ------------------------------------------------------

    readonly property string query: field.text.trim()

    // The emoji in the order they are drawn, and the rows that draw them:
    // `{ "label": "SMILEYS & EMOTION" }` or `{ "from": 120, "count": 10 }`.
    readonly property var layout: {
        const flat = [];
        const rows = [];
        const section = (label, entries) => {
            if (entries.length === 0)
                return;
            if (label.length > 0)
                rows.push({ "label": label, "from": 0, "count": 0 });
            for (let at = 0; at < entries.length; at += root.columns) {
                const count = Math.min(root.columns, entries.length - at);
                rows.push({ "label": "", "from": flat.length, "count": count });
                for (let i = 0; i < count; i++)
                    flat.push(entries[at + i]);
            }
        };

        if (!Emoji.loaded)
            return { "flat": flat, "rows": rows };

        if (root.query.length > 0) {
            section("", Emoji.search(root.query));
        } else {
            section("RECENT", Emoji.recentEntries);
            const byGroup = Emoji.groups.map(() => []);
            for (const entry of Emoji.all)
                byGroup[entry.group].push(entry);
            Emoji.groups.forEach((name, at) => section(name, byGroup[at]));
        }
        return { "flat": flat, "rows": rows };
    }

    readonly property var flat: root.layout.flat
    readonly property var rows: root.layout.rows

    property int chosen: 0
    readonly property var chosenEntry: root.chosen < root.flat.length ? root.flat[root.chosen] : null

    // A new answer starts at its best, at the top.
    onQueryChanged: {
        root.chosen = 0;
        list.positionViewAtBeginning();
    }
    onFlatChanged: if (root.chosen >= root.flat.length) root.chosen = 0

    // ---- Moving the choice --------------------------------------------------

    function rowOf(index) {
        for (let r = 0; r < root.rows.length; r++) {
            const row = root.rows[r];
            if (row.count > 0 && index >= row.from && index < row.from + row.count)
                return r;
        }
        return -1;
    }

    function choose(index) {
        if (root.flat.length === 0)
            return;
        root.chosen = Math.max(0, Math.min(root.flat.length - 1, index));
        const r = root.rowOf(root.chosen);
        // A row just under a group's name brings the name into view with it.
        if (r > 0 && root.rows[r - 1].count === 0)
            list.positionViewAtIndex(r - 1, ListView.Contain);
        list.positionViewAtIndex(r, ListView.Contain);
    }

    // Up and down keep the column, and step over the groups' names.
    function vertical(step, rows) {
        let r = root.rowOf(root.chosen);
        if (r < 0)
            return;
        const column = root.chosen - root.rows[r].from;
        let left = rows;
        let next = r;
        for (let at = r + step; at >= 0 && at < root.rows.length && left > 0; at += step) {
            if (root.rows[at].count === 0)
                continue;
            next = at;
            left--;
        }
        const row = root.rows[next];
        root.choose(row.from + Math.min(column, row.count - 1));
    }

    function send(index) {
        const entry = root.flat[index];
        if (entry && root.cell)
            root.cell.send(entry);
    }

    function takeCaret() {
        field.forceActiveFocus();
    }

    Component.onCompleted: root.takeCaret()
    onCellChanged: root.takeCaret()

    // ---- The field, and the tones beside it ----------------------------------

    Item {
        id: head

        width: parent.width
        height: root.metrics.fieldHeight

        TapHandler {
            onTapped: field.forceActiveFocus()
        }

        readonly property bool navigable: !field.activeFocus

        function activate() {
            Focus.type(field);
        }

        KeyMark {
            factor: root.factor
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
            id: field

            anchors.left: lens.right
            anchors.leftMargin: 10 * root.factor
            anchors.right: tones.left
            anchors.rightMargin: 12 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
            clip: true

            Keys.onEscapePressed: {
                if (field.text.length > 0) {
                    field.text = "";
                    return;
                }
                if (root.cell) {
                    root.cell.open = false;
                    root.cell.visibility.invoked = false;
                }
            }
            Keys.onLeftPressed: root.choose(root.chosen - 1)
            Keys.onRightPressed: root.choose(root.chosen + 1)
            Keys.onUpPressed: root.vertical(-1, 1)
            Keys.onDownPressed: root.vertical(1, 1)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageDown) {
                    root.vertical(1, root.shownRows - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.vertical(-1, root.shownRows - 1);
                    event.accepted = true;
                }
            }
            Keys.onTabPressed: Emoji.setTone((Emoji.tone + 1) % 6)
            Keys.onBacktabPressed: Emoji.setTone((Emoji.tone + 5) % 6)
            onAccepted: root.send(root.chosen)

            Text {
                anchors.fill: parent
                visible: field.text === ""
                text: "Search emoji"
                color: Theme.textMuted
                font: field.font
            }
        }

        // The six tones as the raised hand wears them: none — the standard's
        // yellow — then light to dark. The one in use wears the selection's
        // fill.
        Row {
            id: tones

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.factor

            Repeater {
                model: ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"]

                delegate: Item {
                    id: tone

                    required property string modelData
                    required property int index

                    width: 26 * root.factor
                    height: width

                    readonly property bool navigable: true

                    function activate() {
                        Emoji.setTone(tone.index);
                    }

                    KeyMark {
                        factor: root.factor
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        antialiasing: true
                        color: Emoji.tone === tone.index ? Qt.alpha(Theme.primary, 0.16)
                             : toneHover.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: tone.modelData
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 15 * root.factor
                        opacity: Emoji.tone === tone.index || toneHover.hovered ? 1 : 0.55
                    }

                    HoverHandler { id: toneHover }
                    TapHandler { onTapped: Emoji.setTone(tone.index) }
                }
            }
        }
    }

    // ---- The emoji ----------------------------------------------------------

    Well {
        id: well

        metrics: root.metrics
        y: head.height + 10 * root.factor
        width: parent.width
        height: root.listHeight

        Text {
            anchors.centerIn: parent
            visible: Emoji.loaded && root.flat.length === 0
            text: "Nothing answers to that"
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: 6 * root.factor
            anchors.rightMargin: 12 * root.factor
            model: root.rows
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Rows are cheap and many: a little kept beyond the edge so a fast
            // wheel does not show them arriving.
            cacheBuffer: root.rowHeight * 4

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                width: ListView.view.width
                height: row.modelData.count > 0 ? root.rowHeight : root.labelHeight

                // A group's name: the system's word for what follows, in
                // the other voice.
                Text {
                    visible: row.modelData.count === 0
                    anchors.fill: parent
                    leftPadding: 6 * root.factor
                    bottomPadding: 4 * root.factor
                    verticalAlignment: Text.AlignBottom
                    text: row.modelData.label
                    color: Theme.textFaint
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "weight": Typography.weightLabel,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }

                Repeater {
                    model: row.modelData.count

                    delegate: Item {
                        id: slot

                        required property int index

                        readonly property int at: row.modelData.from + slot.index
                        readonly property var entry: root.flat[slot.at]
                        readonly property bool picked: root.chosen === slot.at

                        x: slot.index * width
                        width: row.width / root.columns
                        height: row.height

                        // Selection is a fill, as in the launcher: the lit
                        // outline means "surface", and an emoji wearing one
                        // would read as a cell inside a cell.
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 2 * root.factor
                            height: width
                            radius: Metrics.shaped(10 * root.factor)
                            antialiasing: true
                            color: Qt.alpha(Theme.primary, 0.14)
                            visible: slot.picked
                        }

                        Text {
                            anchors.centerIn: parent
                            text: slot.entry ? Emoji.shown(slot.entry) : ""
                            font.family: "Noto Color Emoji"
                            font.pixelSize: root.glyph
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered) root.chosen = slot.at
                        }

                        TapHandler {
                            onTapped: root.send(slot.at)
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
    }

    // ---- Its name -----------------------------------------------------------

    // The one chosen, larger, and what it is called: an emoji is read as a
    // picture, and the name is how to tell the two hearts that look alike
    // apart. A name is human language, so it takes Spectral.
    Item {
        y: well.y + well.height
        width: parent.width
        height: root.footHeight

        Text {
            id: big
            anchors.left: parent.left
            anchors.leftMargin: 8 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: root.chosenEntry ? Emoji.shown(root.chosenEntry) : ""
            font.family: "Noto Color Emoji"
            font.pixelSize: 20 * root.factor
        }

        Text {
            anchors.left: big.right
            anchors.leftMargin: 10 * root.factor
            anchors.right: parent.right
            anchors.rightMargin: 8 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: root.chosenEntry ? root.chosenEntry.name : ""
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }
}
