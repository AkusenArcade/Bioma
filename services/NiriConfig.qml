pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "niri-config.js" as NiriKdl

// niri's configuration, as files.
//
// The configuration belongs to niri and to whoever wrote it, and it is spread
// over whatever files `config.kdl` includes. This service reads every one of
// them, watches them, and lists what they say — binds and output sections — in
// the order niri reads it, each item carrying the file it came from and where
// in that file it sits. What to do with those items is the business of the
// services built on this one: `Keybinds`, `Monitors`.
//
// Writing is here too, and it has one rule: **nothing is written that niri
// would refuse.** A write names the file and its new text, plus the part of it
// niri should look at; that part is handed to `niri validate` on its own first,
// and the file is only written when niri accepts it — so a mistake shows up in
// the settings cell, as a sentence, and not as a configuration error in the
// running compositor. niri watches every included file and reloads by itself.
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

    // Every bind and output section, in the order niri reads them, each with
    // a `file`. See niri-config.js for their shape.
    property var items: []

    // Whether every file the configuration reaches has been read.
    property bool ready: false

    // The last thing niri refused, in its words. Cleared by the next write it
    // accepts.
    property string error: ""

    // Whether a write is on its way through `niri validate`.
    readonly property bool busy: validator.running

    // Bumped after every write that landed, for anybody who has to ask niri
    // what it made of it.
    property int written: 0

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

    // Walk the configuration the way niri does: a file's items in the order
    // they are written, an include expanded where it stands.
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

            for (const item of NiriKdl.scan(text).items) {
                if (item.kind === "include") {
                    walk(NiriKdl.resolve(item.path, NiriKdl.directoryOf(path), root.home));
                    continue;
                }
                item.file = path;
                found.push(item);
            }
        };

        walk(root.main);

        if (missing.length > 0) {
            root.paths = root.paths.concat(missing);
            return;
        }

        root.items = found;
        root.ready = complete;
    }

    function textOf(path) {
        const text = root.texts[path];
        return typeof text === "string" ? text : null;
    }

    // ---- Writing -------------------------------------------------------------
    //
    // One write at a time, and in order: a page that moves two monitors asks
    // for two files, and the second is sent once the first has landed.

    property var queue: []
    property var pending: null

    function write(file, text, checked) {
        root.queue = root.queue.concat([{ "file": file, "text": text, "checked": checked }]);
        root.next();
    }

    function next() {
        if (validator.running || root.queue.length === 0)
            return;
        root.pending = root.queue[0];
        root.queue = root.queue.slice(1);
        validator.command = ["sh", "-c", "printf '%s' \"$1\" | niri validate -c /dev/stdin",
                             "sh", root.pending.checked];
        validator.running = true;
    }

    Process {
        id: validator

        stderr: StdioCollector { id: complaint }
        stdout: StdioCollector {}

        onExited: code => {
            const job = root.pending;
            root.pending = null;

            if (code !== 0) {
                root.error = root.reason(complaint.text);
                // What was queued after a refusal was built on it.
                root.queue = [];
                return;
            }

            const view = root.viewOf(job.file);
            if (!view) {
                root.error = "niri's configuration could not be written.";
                root.queue = [];
                return;
            }

            root.error = "";
            view.setText(job.text);
            // Our own write is not always reported back by the watcher, so
            // what was written is what is read from now on.
            root.took(job.file, job.text);
            root.written++;
            root.next();
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
}
