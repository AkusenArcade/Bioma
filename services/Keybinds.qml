pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "niri-config.js" as NiriKdl

// The keys, as niri has them.
//
// Keybinds are the compositor's, not the shell's: niri holds the keys and
// reads them from its own configuration, spread over whatever files that
// configuration includes. This lists every bind in the order niri reads them
// and writes an edit back **into the file the bind lives in**, touching only
// the span of text that bind occupies. Comments, blank lines and everything
// outside the `binds` block stay exactly as their author left them. The files
// themselves, and the rule that nothing niri would refuse is written, are
// `NiriConfig`'s.
//
// One file per bind, but one niri: the same key in two files is allowed, and
// the one read later wins. A bind that has been overridden that way is still
// listed, marked `shadowed`, because it is still written down somewhere.
Singleton {
    id: root

    readonly property string main: NiriConfig.main
    readonly property bool ready: NiriConfig.ready
    readonly property bool busy: NiriConfig.busy
    readonly property string error: NiriConfig.error

    // Every bind, in the order niri reads them.
    readonly property var binds: {
        const found = [];
        for (const item of NiriConfig.items) {
            if (item.kind !== "bind")
                continue;
            const text = NiriConfig.textOf(item.file) || "";
            found.push({
                // What a row is known by: where it is and what it is bound
                // to, so an edit makes it a new row and the list around it
                // stays where it was.
                "id": item.file + "#" + item.start + "#" + item.key,
                "file": item.file,
                "key": item.key,
                "keyRaw": text.slice(item.keyStart, item.keyEnd),
                "keyStart": item.keyStart,
                "keyEnd": item.keyEnd,
                "start": item.start,
                "end": item.end,
                "props": item.props,
                "action": item.action,
                "label": NiriKdl.describe(item),
                "caps": NiriKdl.keycaps(item.key),
                "norm": NiriKdl.normalize(item.key),
                "shadowed": false
            });
        }

        const last = {};
        for (let i = 0; i < found.length; i++)
            last[found[i].norm] = i;
        for (let i = 0; i < found.length; i++)
            found[i].shadowed = last[found[i].norm] !== i;
        return found;
    }

    readonly property int count: root.binds.length

    // The bind that answers a combination, leaving one out — the one being
    // edited, which is allowed to keep its own key.
    function owner(key, except) {
        const norm = NiriKdl.normalize(key);
        for (let i = root.binds.length - 1; i >= 0; i--) {
            const bind = root.binds[i];
            if (bind.norm === norm && bind.id !== except)
                return bind;
        }
        return null;
    }

    function keycaps(key) {
        return NiriKdl.keycaps(key);
    }

    // ---- Writing -------------------------------------------------------------

    // The text a bind was read from must still be there: an edit made against
    // a file somebody else has changed since would land in the wrong place.
    function current(bind) {
        const text = NiriConfig.textOf(bind.file);
        if (text === null || text.slice(bind.keyStart, bind.keyEnd) !== bind.keyRaw) {
            NiriConfig.error = "The file changed under this bind. Try again.";
            return null;
        }
        return text;
    }

    function commit(file, text) {
        NiriConfig.write(file, text, NiriKdl.blockOf(text));
    }

    function rekey(bind, key) {
        const text = root.current(bind);
        if (text !== null)
            root.commit(bind.file, NiriKdl.withKey(text, bind, key));
    }

    function remove(bind) {
        const text = root.current(bind);
        if (text !== null)
            root.commit(bind.file, NiriKdl.without(text, bind));
    }

    // A new bind goes into niri's own file, at the end of its block — the
    // one file here nothing else rewrites.
    function add(key, action, title) {
        const text = NiriConfig.textOf(root.main);
        if (text === null) {
            NiriConfig.error = "niri's configuration could not be read.";
            return;
        }
        const scanned = NiriKdl.scan(text);
        const binds = scanned.items.filter(item => item.kind === "bind");
        const entry = NiriKdl.line(key, action, title);
        root.commit(root.main, NiriKdl.withAdded(text, scanned.block, entry,
                                                 binds.length > 0 ? binds[binds.length - 1] : null));
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
        return NiriKdl.describe({ "props": {}, "action": { "name": name, "args": [] }, "key": "" });
    }
}
