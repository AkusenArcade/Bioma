pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "niri-binds.js" as NiriBinds

// The keys, as niri has them.
//
// Keybinds are the compositor's, not the shell's: niri holds the keys and
// reads them from its own configuration, spread over whatever files that
// configuration includes. This service reads every one of those files, lists
// every bind in the order niri reads them, and writes an edit back **into the
// file the bind lives in**, touching only the span of text that bind occupies.
// Comments, blank lines and everything outside the `binds` block stay exactly
// as their author left them.
//
// Nothing is written that niri would refuse. The block an edit produces is
// handed to `niri validate` first, on its own, and the file is only written
// when niri accepts it — so a mistake shows up here, as a sentence, instead of
// as a configuration error in the running compositor. niri watches every
// included file and reloads by itself; nothing here asks it to.
//
// One file per bind, but one niri: the same key in two files is allowed, and
// the one read later wins. A bind that has been overridden that way is still
// listed, marked `shadowed`, because it is still written down somewhere.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""

    // Where niri itself would look.
    readonly property string main: Quickshell.env("NIRI_CONFIG")
        || `${Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config"}/niri/config.kdl`

    // Every file found so far. It starts with the main one and grows as the
    // includes are read, because what a file includes is only known once it
    // has been read.
    property var paths: [root.main]

    // What each file says, once read: `null` for one that could not be.
    property var texts: ({})

    // Every bind, in the order niri reads them.
    property var binds: []

    // Whether every file the configuration reaches has been read.
    property bool ready: false

    // The last thing niri refused, in its words. Cleared by the next edit
    // that it accepts.
    property string error: ""

    // Whether an edit is on its way through `niri validate`.
    readonly property bool busy: validator.running

    readonly property int count: root.binds.length

    // ---- Reading -------------------------------------------------------------

    Variants {
        id: views

        model: root.paths

        FileView {
            required property string modelData

            path: modelData
            watchChanges: true
            atomicWrites: true
            printErrors: false

            onLoaded: root.took(modelData, text())
            onLoadFailed: root.took(modelData, null)
            onFileChanged: reload()
        }
    }

    function viewOf(path) {
        for (const view of views.instances)
            if (view && view.path === path)
                return view;
        return null;
    }

    function took(path, text) {
        const next = Object.assign({}, root.texts);
        next[path] = text;
        root.texts = next;
        root.rebuild();
    }

    // Walk the configuration the way niri does: a file's binds and includes
    // in the order they are written, an include expanded where it stands.
    function rebuild() {
        const found = [];
        const missing = [];
        const seen = {};
        let complete = true;

        const walk = (path) => {
            if (seen[path])
                return;
            seen[path] = true;

            if (!(path in root.texts)) {
                complete = false;
                if (!root.paths.includes(path))
                    missing.push(path);
                return;
            }

            const text = root.texts[path];
            if (text === null)
                return;

            const scanned = NiriBinds.scan(text);
            for (const item of scanned.items) {
                if (item.kind === "include") {
                    walk(NiriBinds.resolve(item.path, NiriBinds.directoryOf(path), root.home));
                    continue;
                }
                found.push({
                    // What a row is known by: where it is and what it is
                    // bound to, so an edit makes it a new row and the list
                    // around it stays where it was.
                    "id": path + "#" + item.start + "#" + item.key,
                    "file": path,
                    "key": item.key,
                    "keyRaw": text.slice(item.keyStart, item.keyEnd),
                    "keyStart": item.keyStart,
                    "keyEnd": item.keyEnd,
                    "start": item.start,
                    "end": item.end,
                    "props": item.props,
                    "action": item.action,
                    "label": NiriBinds.describe(item),
                    "caps": NiriBinds.keycaps(item.key),
                    "norm": NiriBinds.normalize(item.key),
                    "shadowed": false
                });
            }
        };

        walk(root.main);

        if (missing.length > 0) {
            root.paths = root.paths.concat(missing);
            return;
        }

        const last = {};
        for (let i = 0; i < found.length; i++)
            last[found[i].norm] = i;
        for (let i = 0; i < found.length; i++)
            found[i].shadowed = last[found[i].norm] !== i;

        root.binds = found;
        root.ready = complete;
    }

    // The bind that answers a combination, leaving one out — the one being
    // edited, which is allowed to keep its own key.
    function owner(key, except) {
        const norm = NiriBinds.normalize(key);
        for (let i = root.binds.length - 1; i >= 0; i--) {
            const bind = root.binds[i];
            if (bind.norm === norm && bind.id !== except)
                return bind;
        }
        return null;
    }

    function keycaps(key) {
        return NiriBinds.keycaps(key);
    }

    // ---- Writing -------------------------------------------------------------

    // The text a bind was read from must still be there: an edit made against
    // a file somebody else has changed since would land in the wrong place.
    function current(bind) {
        const text = root.texts[bind.file];
        if (typeof text !== "string" || text.slice(bind.keyStart, bind.keyEnd) !== bind.keyRaw) {
            root.error = "The file changed under this bind. Try again.";
            return null;
        }
        return text;
    }

    function rekey(bind, key) {
        const text = root.current(bind);
        if (text !== null)
            root.commit(bind.file, NiriBinds.withKey(text, bind, key));
    }

    function remove(bind) {
        const text = root.current(bind);
        if (text !== null)
            root.commit(bind.file, NiriBinds.without(text, bind));
    }

    // A new bind goes into niri's own file, at the end of its block — the
    // one file here nothing else rewrites.
    function add(key, action, title) {
        const text = root.texts[root.main];
        if (typeof text !== "string") {
            root.error = "niri's configuration could not be read.";
            return;
        }
        const scanned = NiriBinds.scan(text);
        const binds = scanned.items.filter(item => item.kind === "bind");
        const entry = NiriBinds.line(key, action, title);
        root.commit(root.main, NiriBinds.withAdded(text, scanned.block, entry,
                                                   binds.length > 0 ? binds[binds.length - 1] : null));
    }

    property string pendingFile: ""
    property string pendingText: ""

    function commit(file, text) {
        if (validator.running)
            return;
        root.pendingFile = file;
        root.pendingText = text;
        validator.command = ["sh", "-c", "printf '%s' \"$1\" | niri validate -c /dev/stdin",
                             "sh", NiriBinds.blockOf(text)];
        validator.running = true;
    }

    Process {
        id: validator

        stderr: StdioCollector { id: complaint }
        stdout: StdioCollector {}

        onExited: code => {
            if (code !== 0) {
                root.error = root.reason(complaint.text);
                return;
            }

            const view = root.viewOf(root.pendingFile);
            if (!view) {
                root.error = "niri's configuration could not be written.";
                return;
            }

            root.error = "";
            view.setText(root.pendingText);
            // Our own write is not always reported back by the watcher, so
            // what was written is what is read from now on.
            root.took(root.pendingFile, root.pendingText);
        }
    }

    // niri explains itself in a boxed diagnostic, coloured, that opens with
    // the same three generic lines every time. What it actually objects to
    // is the last marked line after them — "invalid key: Foo", "duplicate
    // keybind later defined here".
    function reason(output) {
        const generic = ["error loading config", "error parsing", "error parsing KDL"];
        const plain = String(output).replace(/\u001b\[[0-9;]*m/g, "");
        let found = "";
        for (const line of plain.split("\n")) {
            const marked = /(?:×|╰─▶)\s+(.*)$/.exec(line);
            if (marked && !generic.includes(marked[1].trim()))
                found = marked[1].trim();
        }
        return found.length > 0 ? "niri refused it: " + found : "niri refused it.";
    }

    // ---- What a new bind can do ---------------------------------------------
    //
    // niri's own actions, asked of niri, so the list is the one this build
    // knows — minus those that need an argument, which a picker cannot
    // supply. Read once, the first time somebody asks.

    property var actions: []
    property bool actionsAsked: false

    function askActions() {
        if (root.actionsAsked)
            return;
        root.actionsAsked = true;
        lister.running = true;
    }

    Process {
        id: lister

        command: ["bash", "-c",
            "niri msg action --help | awk '/^Actions:/{f=1;next} /^[A-Z]/{f=0} f && /^  [a-z]/{print $1}' "
            + "| while read -r name; do "
            + "  usage=$(niri msg action \"$name\" --help 2>/dev/null | grep -m1 '^Usage:'); "
            + "  case \"$usage\" in *'<'*) ;; *) echo \"$name\";; esac; "
            + "done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    const name = line.trim();
                    if (name.length > 0)
                        out.push(name);
                }
                root.actions = out;
            }
        }
    }

    function humanize(name) {
        return NiriBinds.describe({ "props": {}, "action": { "name": name, "args": [] }, "key": "" });
    }
}
