import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Search and launch.
//
// The only cell with **no contracted state**: it sits on no membrane, hangs
// from nothing, and when it appears it is already itself, in the middle of the
// screen. That is also why it has no thread — everything else in the shell
// grows out of something, and this arrives from the keyboard and leaves.
//
// It is built last on purpose. By the time a launcher exists the mechanism it
// needs has to work already: a cell asked for by name, given somewhere to be,
// holding the keyboard and giving it back. There is nothing here that is not
// one of those.
//
// See docs/design/CELLS.md §13, PRD §9.13.
Cell {
    id: root

    domain: "launcher"

    readonly property real panelWidth: 480 * metrics.factor
    readonly property real fieldHeight: 44 * metrics.factor
    readonly property real resultHeight: 52 * metrics.factor
    readonly property int shownRows: 6

    readonly property real inset: 10 * metrics.factor

    paddingLeading: inset
    paddingTrailing: inset

    // A cell that is a panel rather than a pill: its own height, and the
    // tissue makes room for it.
    //
    // The height is **fixed**, and that is the whole of it. A panel that grew
    // and shrank with the number of results re-centred its tissue on every
    // letter typed, and the blur region chased a shape that had already
    // moved: the field jumped under the fingers and the glass tore. The
    // design says it in as many words — with nothing found, the field stays
    // where it is and the panel does not collapse under your fingers — and
    // six rows is what it always holds, full or not.
    readonly property real listGap: 6 * metrics.factor

    contentWidth: panelWidth - inset * 2
    bodyHeight: inset * 2 + fieldHeight + listGap + shownRows * resultHeight

    // It is only ever there because it was asked for, and it takes the
    // keyboard for as long as it is.
    wantsKeyboard: true

    // ---- What it knows -------------------------------------------------------

    property string query: ""
    property int chosen: 0

    // How often each one has been launched from here. With an empty field the
    // launcher shows the most used rather than the first alphabetically: an
    // alphabetical list is an archive, and the most used are an answer.
    readonly property var uses: Config.get("launcher.uses", ({}))

    readonly property var entries: DesktopEntries.applications?.values ?? []

    function usesOf(entry) {
        const count = root.uses[entry.id];
        return count === undefined ? 0 : count;
    }

    // A subsequence match, and it says **where** it matched: the letters the
    // search found are coloured in the result, which is the one place in this
    // shell where colour enters a word. It earns it — it shows the reasoning,
    // so when the answer is wrong it is visibly wrong rather than broken.
    function match(name, wanted) {
        if (wanted.length === 0)
            return { "hit": true, "at": [], "score": 0 };

        const lowered = name.toLowerCase();
        const at = [];
        let index = 0;
        let run = 0;
        let score = 0;

        for (const letter of wanted) {
            const found = lowered.indexOf(letter, index);
            if (found < 0)
                return { "hit": false, "at": [], "score": 0 };
            // A run of letters together, and a match at the start of a word,
            // are both worth more than the same letters scattered.
            run = found === index ? run + 1 : 0;
            score += run * 2 + (found === 0 || lowered[found - 1] === " " ? 3 : 0);
            at.push(found);
            index = found + 1;
        }
        return { "hit": true, "at": at, "score": score };
    }

    readonly property var results: {
        const wanted = root.query.trim().toLowerCase();
        const out = [];

        for (const entry of root.entries) {
            if (entry.noDisplay)
                continue;
            const name = entry.name || entry.id || "";
            const found = root.match(name, wanted);
            if (!found.hit)
                continue;
            out.push({
                "entry": entry,
                "name": name,
                "at": found.at,
                "score": found.score,
                "used": root.usesOf(entry)
            });
        }

        out.sort((a, b) => {
            if (wanted.length === 0)
                return b.used - a.used || a.name.localeCompare(b.name);
            return b.score - a.score || b.used - a.used || a.name.localeCompare(b.name);
        });

        return wanted.length === 0 ? out.slice(0, root.shownRows * 3) : out.slice(0, 40);
    }

    onQueryChanged: root.chosen = 0
    onResultsChanged: if (root.chosen >= root.results.length) root.chosen = 0

    // ---- Doing it ------------------------------------------------------------

    function launch(index) {
        const result = root.results[index];
        if (!result)
            return;

        const counted = JSON.parse(JSON.stringify(root.uses));
        counted[result.entry.id] = (counted[result.entry.id] ?? 0) + 1;
        Config.set("launcher.uses", counted);

        result.entry.execute();
        root.dismiss();
    }

    function dismiss() {
        root.query = "";
        root.visibility.invoked = false;
    }

    function move(delta) {
        if (root.results.length === 0)
            return;
        root.chosen = (root.chosen + delta + root.results.length) % root.results.length;
        list.positionViewAtIndex(root.chosen, ListView.Contain);
    }

    // The field takes the caret the moment the cell is there, because nobody
    // asks for a launcher in order to click on it first.
    //
    // On `placed` and not on `open`: this cell never opens. Everything else
    // in the shell has a pill and grows a panel out of it; here the panel is
    // the cell, so being on screen at all is the whole of its arriving.
    onPlacedChanged: {
        if (root.placed)
            field.forceActiveFocus();
        else
            root.query = "";
    }

    Component.onCompleted: if (root.placed) field.forceActiveFocus()

    // ---- The field -----------------------------------------------------------
    //
    // Everything below is inside one item that waits for the shape: a field
    // drawn into a panel that is still growing is a field at the wrong width,
    // and it arrives the way a panel's content arrives everywhere else.

    Item {
        id: body

        anchors.fill: parent
        opacity: root.grown ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }

    Item {
        id: search

        width: root.contentWidth
        height: root.fieldHeight
        y: 0

        Icon {
            id: lens
            anchors.left: parent.left
            anchors.leftMargin: 6 * root.metrics.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.metrics.factor
            height: width
            name: "search"
            gradient: true
        }

        TextInput {
            id: field

            anchors.left: lens.right
            anchors.leftMargin: 12 * root.metrics.factor
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.metrics.factor
            anchors.verticalCenter: parent.verticalCenter

            text: root.query
            onTextChanged: root.query = text

            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: 16 * root.metrics.factor
            selectByMouse: true
            cursorVisible: true

            // Arrows move, Enter launches, Escape closes. The first result is
            // already chosen: two letters and Enter has to be enough.
            Keys.onDownPressed: root.move(1)
            Keys.onUpPressed: root.move(-1)
            Keys.onReturnPressed: root.launch(root.chosen)
            Keys.onEnterPressed: root.launch(root.chosen)
            Keys.onEscapePressed: root.dismiss()

            Text {
                anchors.fill: parent
                visible: field.text.length === 0
                text: "Search"
                color: Theme.textFaint
                font: field.font
            }
        }
    }

    // ---- The results ---------------------------------------------------------

    // Nothing found is one line, and the field does not move: a panel that
    // collapsed under the fingers would take the field with it.
    Text {
        y: search.height + root.listGap
        width: root.contentWidth
        height: root.resultHeight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        visible: root.query.length > 0 && root.results.length === 0
        text: "Nothing answers to that"
        color: Theme.textMuted
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontTitle
    }

    ListView {
        id: list

        y: search.height + root.listGap
        width: root.contentWidth
        height: root.shownRows * root.resultHeight
        visible: root.results.length > 0

        model: root.results
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        delegate: Item {
            id: result

            required property var modelData
            required property int index

            readonly property bool picked: root.chosen === result.index

            width: ListView.view.width
            height: root.resultHeight

            // Selection is a fill and never an outline: the lit outline means
            // "surface" in this shell, and a row wearing one would read as a
            // cell inside a cell.
            Rectangle {
                anchors.fill: parent
                anchors.rightMargin: 2 * root.metrics.factor
                radius: 14 * root.metrics.factor
                color: Qt.alpha(Theme.primary, 0.12)
                visible: result.picked
                antialiasing: true
            }

            Item {
                id: portrait

                anchors.left: parent.left
                anchors.leftMargin: 8 * root.metrics.factor
                anchors.verticalCenter: parent.verticalCenter
                width: 36 * root.metrics.factor
                height: width

                readonly property string source: result.modelData.entry.icon
                    ? Quickshell.iconPath(result.modelData.entry.icon, true) : ""

                Ring {
                    anchors.fill: parent
                    visible: result.picked
                    radius: width / 2
                    thickness: Metrics.crisp(1.5 * root.metrics.factor, Screen.devicePixelRatio)
                    colour: Theme.primary
                }

                Image {
                    anchors.centerIn: parent
                    visible: portrait.source !== ""
                    width: parent.width * 0.7
                    height: width
                    source: portrait.source
                    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: portrait.source === ""
                    width: parent.width * 0.6
                    height: width
                    name: "app-fallback"
                    colour: Theme.textMuted
                }
            }

            // The name, with the letters the search matched lit. A name is
            // human language; the category under it is the system's own word
            // for what the thing is, and takes the other voice.
            Text {
                id: name

                anchors.left: portrait.right
                anchors.leftMargin: 14 * root.metrics.factor
                anchors.right: parent.right
                anchors.rightMargin: 14 * root.metrics.factor
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: category.text.length > 0 ? 0 : -name.height / 2

                text: root.lit(result.modelData.name, result.modelData.at)
                textFormat: Text.StyledText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: 15 * root.metrics.factor
            }

            Text {
                id: category

                anchors.left: name.left
                anchors.right: name.right
                anchors.top: parent.verticalCenter
                anchors.topMargin: 2 * root.metrics.factor
                visible: category.text.length > 0 && name.anchors.bottomMargin === 0

                text: {
                    const list = result.modelData.entry.categories || [];
                    return list.length > 0 ? String(list[0]).toUpperCase() : "";
                }
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.textFaint
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                         Typography.labelTracking)
                })
            }

            HoverHandler {
                onHoveredChanged: if (hovered) root.chosen = result.index
            }

            TapHandler {
                onTapped: root.launch(result.index)
            }
        }
    }

    }

    // The matched letters, in the primary. Built as markup because a Text can
    // colour a run of characters and nothing else can, and the name has to
    // stay one line that elides.
    function lit(name, at) {
        if (!at || at.length === 0)
            return root.safe(name);

        const colour = Theme.primary.toString();
        let out = "";
        let next = 0;
        for (let i = 0; i < name.length; i++) {
            const letter = root.safe(name[i]);
            if (next < at.length && at[next] === i) {
                out += `<font color="${colour}">${letter}</font>`;
                next++;
            } else {
                out += letter;
            }
        }
        return out;
    }

    // Not `escape`: QML refuses a method with the name of a JavaScript
    // global, and refuses it as "illegal method name" rather than as a clash.
    function safe(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
}
