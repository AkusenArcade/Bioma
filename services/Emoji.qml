pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Emoji: the set, the search over it, and putting one into the window that
// has the focus.
//
// The set is Unicode's own — every fully-qualified emoji in the order a picker
// shows them, its name, CLDR's English search words, and the five skin tones
// where it has them — generated once by `tools/emoji-data` into
// `assets/emoji/emoji.json`. It is read the first time the cell asks for it
// and kept: two thousand rows are smaller than one wallpaper thumbnail.
//
// The pick is pasted, not typed, by `scripts/paste`, the same way dictation
// puts its text in (see that script for why `wtype` cannot): onto the
// clipboard, a Ctrl+V from a keyboard of its own, then the clipboard put back.
// The keyboard is made when the cell opens rather than when the emoji is
// chosen — niri takes a moment to follow a new input device, and that moment
// is spent while the user searches.
Singleton {
    id: root

    // ---- The set ------------------------------------------------------------

    // Read on first use: asked for by the cell, never by the shell starting.
    property bool wanted: false

    property bool loaded: false
    property var groups: []
    // [{ "character", "name", "keywords", "group", "tones", "words" }], in
    // CLDR order. `words` is everything searched, name first.
    property var all: []
    // Base character → its row, for the recent list.
    property var byCharacter: ({})

    FileView {
        path: root.wanted ? Quickshell.shellPath("assets/emoji/emoji.json") : ""
        onLoaded: root.take(text())
    }

    function take(raw) {
        let data = null;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            console.warn("Emoji: the set does not parse —", e);
            return;
        }
        const rows = [];
        const index = {};
        for (const row of data.emoji) {
            const name = row[1];
            const entry = {
                "character": row[0],
                "name": name,
                "group": row[3],
                "tones": row.length > 4 ? row[4] : null,
                "nameWords": name.toLowerCase().split(/[^a-z0-9\u00c0-\u024f'+#*-]+/).filter(w => w.length > 0),
                "keyWords": row[2].length > 0 ? row[2].split(" ") : []
            };
            index[entry.character] = rows.length;
            rows.push(entry);
        }
        root.groups = data.groups;
        root.all = rows;
        root.byCharacter = index;
        root.loaded = true;
        console.info(`Emoji: ${rows.length} emoji, Unicode ${data.version}`);
    }

    // ---- What the user chose before -----------------------------------------

    // One skin tone for everything that has one: 0 is none (the yellow of the
    // standard), 1–5 light to dark. Chosen in the cell and kept.
    readonly property int tone: Math.max(0, Math.min(5, Config.get("emoji.tone", 0)))

    function setTone(value) {
        Config.set("emoji.tone", Math.max(0, Math.min(5, value)));
    }

    // The emoji as it is sent, in the tone chosen.
    function shown(entry) {
        return root.tone > 0 && entry.tones ? entry.tones[root.tone - 1] : entry.character;
    }

    // The last ones sent, newest first, kept as their base character so a new
    // tone reaches them too.
    readonly property int recentCount: Config.get("emoji.recent_count", 20)
    readonly property var recent: Config.get("emoji.recent", [])

    // Every write to the configuration hands back a new list, even when this
    // one did not change — choosing a tone is a write — and a new list would
    // rebuild the grid under the pointer and scroll it to the top. The
    // characters joined are a string, and a string that is the same is not
    // a change.
    readonly property string recentKey: root.recent.join("\n")

    readonly property var recentEntries: {
        const out = [];
        for (const character of root.recentKey.split("\n")) {
            const at = root.byCharacter[character];
            if (at !== undefined)
                out.push(root.all[at]);
        }
        return out;
    }

    function remember(entry) {
        const next = [entry.character].concat(root.recent.filter(c => c !== entry.character));
        Config.set("emoji.recent", next.slice(0, root.recentCount));
    }

    // ---- Finding ------------------------------------------------------------

    // Every word typed has to begin a word the emoji is known by — its name,
    // or one of CLDR's words for it. A whole word is worth more than its
    // beginning, and a search word said whole more than a word of the name
    // merely begun: "lol" is the face with tears of joy before the lollipop.
    // A shorter name is more nearly the thing asked for — "cat" is the cat
    // before the cat with wry smile — and what was sent lately comes first
    // among equals: the set has no notion of which heart people mean, and the
    // recent list does.
    function search(query) {
        const terms = query.toLowerCase().split(/\s+/).filter(t => t.length > 0);
        if (terms.length === 0)
            return [];

        const lately = {};
        root.recentKey.split("\n").forEach((character, at) => lately[character] = 3 * (1 - at / root.recentCount));

        const found = [];
        for (let i = 0; i < root.all.length; i++) {
            const entry = root.all[i];
            let score = 0;
            let missed = false;

            for (const term of terms) {
                let best = 0;
                for (const word of entry.nameWords) {
                    if (word === term) { best = 8; break; }
                    if (best < 4 && word.startsWith(term)) best = 4;
                }
                if (best < 5) {
                    for (const word of entry.keyWords) {
                        if (word === term) { best = 5; break; }
                        if (best < 2 && word.startsWith(term)) best = 2;
                    }
                }
                if (best === 0) {
                    missed = true;
                    break;
                }
                score += best;
            }
            if (missed)
                continue;

            score -= Math.max(0, entry.nameWords.length - terms.length) * 0.5;
            score += lately[entry.character] ?? 0;
            found.push({ "entry": entry, "score": score, "order": i });
        }

        found.sort((a, b) => b.score - a.score || a.order - b.order);
        return found.map(f => f.entry);
    }

    // ---- Sending ------------------------------------------------------------

    // The cell holds the keyboard ready while it is open.
    property bool ready: false
    // A pick on its way: put onto the clipboard and pasted once the panel has
    // given the keys back to the window.
    property string pending: ""
    // Handed to the script and not yet answered — pasted, or left on the
    // clipboard. The script lives until then, whatever the cell does.
    property bool inFlight: false
    // Handed over to be pasted, which is what quiets the clipboard cell.
    property bool pasting: false

    readonly property bool sending: root.pending.length > 0 || root.inFlight

    function send(entry) {
        if (!entry)
            return;
        root.remember(entry);
        root.pending = root.shown(entry);
        handBack.restart();
    }

    // The window has the keys again only once the panel has let go of them,
    // and the panel lets go as it closes.
    Timer {
        id: handBack
        interval: Timing.close
        onTriggered: {
            const text = root.pending;
            if (text.length === 0)
                return;
            const copyOnly = !Niri.focusedWindow || !paster.canPaste;
            // In flight before the pick is let go of: the script is kept
            // alive by one or the other, and never by neither in between.
            root.inFlight = true;
            root.pending = "";
            root.pasting = !copyOnly;
            paster.write(JSON.stringify({
                "text": text,
                "terminal": Dictation.isTerminal(Niri.focusedAppId),
                "copyOnly": copyOnly
            }) + "\n");
        }
    }

    // The paste goes through the clipboard twice, the emoji and then the
    // restore. Neither is the user copying, so the clipboard cell stays quiet
    // — except when there is no window to paste into: then the emoji is left
    // on the clipboard, and the cell's "copied" is how the user learns it.
    Binding {
        target: Clipboard
        property: "quiet"
        value: true
        when: root.pasting || hushTail.running
    }

    Timer {
        id: hushTail
        interval: Timing.hush
    }

    Process {
        id: paster

        property bool canPaste: false

        running: root.ready || root.sending
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", Quickshell.shellPath("scripts/paste")]

        onStarted: paster.canPaste = false

        stdout: SplitParser {
            onRead: line => {
                if (line === "ready") {
                    paster.canPaste = true;
                } else if (line === "no-uinput") {
                    paster.canPaste = false;
                    console.warn("Emoji: /dev/uinput is not writable; the emoji will be left on the clipboard");
                } else if (line === "pasted" || line === "copied") {
                    if (root.pasting)
                        hushTail.restart();
                    root.pasting = false;
                    root.inFlight = false;
                }
            }
        }

        onExited: {
            root.pasting = false;
            root.inFlight = false;
        }
    }
}
