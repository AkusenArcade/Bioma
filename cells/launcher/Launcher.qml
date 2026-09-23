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

    // The panel's own measures, stated rather than measured: its content
    // arrives through a loader, and a shape measured while that loader was
    // still empty stayed too small for what came.
    panelWidth: 480 * metrics.factor
    panelHeight: root.asPanel ? -1 : root.bodyExtent
    readonly property real fieldHeight: 44 * metrics.factor
    readonly property real resultHeight: 52 * metrics.factor
    readonly property int shownRows: 6

    readonly property real inset: 10 * metrics.factor

    // Two forms, one cell.
    //
    // Asked for by name it has no place of its own, so it *is* the panel: it
    // arrives in the middle of the screen already itself, which is the form
    // CELLS §13 describes. Put on a membrane by somebody who would rather
    // have a button to aim at, it is a button, and the same body hangs off it
    // the way every other expansion hangs off its cell. What changes is where
    // it is born; what it is does not. Akusen asked for the anchored one and
    // drew its glyph, 2026-09-22.
    readonly property bool asPanel: root.floating

    readonly property real listGap: 6 * metrics.factor
    readonly property real glyphSize: 20 * metrics.factor

    // The height is **fixed** in both forms. A panel that grew and shrank
    // with the number of results re-centred its tissue on every letter typed,
    // and the blur region chased a shape that had already moved: the field
    // jumped under the fingers and the glass tore. The design says it in as
    // many words — with nothing found, the field stays where it is and the
    // panel does not collapse under your fingers — so six rows is what it
    // always holds, full or not.
    readonly property real bodyExtent: inset * 2 + fieldHeight + listGap
                                     + shownRows * resultHeight

    contentWidth: root.asPanel ? panelWidth - inset * 2 : glyphSize
    bodyHeight: root.asPanel ? bodyExtent : metrics.cellHeight

    paddingLeading: root.asPanel ? inset : (metrics.cellHeight - glyphSize) / 2
    paddingTrailing: root.asPanel ? inset : paddingLeading

    // The panel form is only ever there because it was asked for and holds
    // the keyboard throughout; the button form holds it while it is open,
    // which is when there is a field to type into.
    wantsKeyboard: root.asPanel ? true : root.open

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

        Apps.run(result.entry, Proxy.environment);
        root.dismiss();
    }

    function dismiss() {
        root.query = "";
        if (root.asPanel)
            root.visibility.invoked = false;
        else
            root.open = false;
    }

    function move(delta) {
        if (root.results.length === 0)
            return;
        root.chosen = (root.chosen + delta + root.results.length) % root.results.length;
    }

    // The field takes the caret the moment there is one, because nobody asks
    // for a launcher in order to click on it first.
    //
    // As a panel that is when the cell is *placed*, not when it opens: that
    // form never opens, it is the panel. As a button it is when the panel is.
    onPlacedChanged: {
        if (root.asPanel && root.placed)
            root.caret();
        else if (!root.placed)
            root.query = "";
    }

    onOpenChanged: {
        if (!root.asPanel && root.open)
            root.caret();
        else if (!root.open)
            root.query = "";
    }

    function caret() {
        if (panelLoader.item)
            panelLoader.item.takeCaret();
    }

    Component.onCompleted: if (root.asPanel && root.placed) root.caret()

    // ---- The two wrappers ----------------------------------------------------

    // As a panel: the body is the cell's own content, and it waits for the
    // shape the way a panel's content does.
    Loader {
        id: panelLoader

        active: root.asPanel
        visible: root.asPanel

        width: root.contentWidth
        height: root.bodyExtent - root.inset * 2
        opacity: root.grown ? 1 : 0

        // The source is a binding and nothing else. `setSource` was tried and
        // it loads the file whether the loader is active or not — which built
        // the panel form's body inside the button form too, twenty pixels
        // wide, hanging its rows down the screen under the button.
        source: root.asPanel ? Qt.resolvedUrl("LauncherBody.qml") : ""

        onLoaded: {
            item.cell = root;
            item.metrics = Qt.binding(() => root.metrics);
            if (root.placed)
                item.takeCaret();
        }

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
    }

    // As a button: the glyph, and the body hanging off it.
    Icon {
        anchors.centerIn: parent
        visible: !root.asPanel
        width: root.glyphSize
        height: width
        name: "launcher"
        gradient: true
    }

    panel: root.asPanel ? null : hung

    Component {
        id: hung

        Loader {
            id: hungLoader

            width: root.panelWidth - root.inset * 2
            height: root.bodyExtent - root.inset * 2

            source: Qt.resolvedUrl("LauncherBody.qml")

            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
                item.takeCaret();
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
