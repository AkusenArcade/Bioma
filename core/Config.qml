pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.cells

// Layered configuration.
//
//   1. config/default.json  — base layer, hand-written, lives in the repository
//   2. override file        — written by the settings UI, loaded last, wins
//
// Both layers exist from the start on purpose: adding the override layer later
// would mean redoing all loading. Consumers read `Config.values`, never a file.
Singleton {
    id: root

    readonly property string basePath: Qt.resolvedUrl("../config/default.json").toString().replace("file://", "")
    readonly property string overridePath: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/bioma/override.json`

    // The merged result. Every consumer reads from here.
    property var values: ({})

    // The override layer as a document, kept beside the merged values: two
    // settings changed in the same breath both have to land, and a second write
    // that re-read the file would read what was on disk before the first one
    // arrived and drop it.
    property var overrideValues: ({})

    // True once the base layer has been parsed at least once.
    property bool ready: false

    signal reloaded()

    function get(path, fallback) {
        let node = values;
        for (const key of path.split(".")) {
            if (node === undefined || node === null || !(key in node))
                return fallback;
            node = node[key];
        }
        return node === undefined ? fallback : node;
    }

    // Objects merge key by key; arrays and scalars are replaced wholesale.
    // An override that declares a tissue list means that list, not an append.
    function merge(base, override) {
        if (override === undefined)
            return base;
        if (base === null || typeof base !== "object" || Array.isArray(base))
            return override;
        if (override === null || typeof override !== "object" || Array.isArray(override))
            return override;

        const out = Object.assign({}, base);
        for (const key in override)
            out[key] = merge(base[key], override[key]);
        return out;
    }

    // The layout as the shell reads it today: old names replaced and retired
    // cells dropped, so no page ever shows a cell that cannot exist. Copied
    // rather than edited in place, because the override document shares its
    // arrays with the merged values and is left as it was written.
    function current(merged) {
        for (const key of ["membranes", "floating"])
            if (Array.isArray(merged[key]))
                merged[key] = Registry.renamed(JSON.parse(JSON.stringify(merged[key])));
        return merged;
    }

    function parse(text, label) {
        if (!text)
            return undefined;
        try {
            return JSON.parse(text);
        } catch (error) {
            console.warn(`Bioma: ${label} is not valid JSON — ${error.message}`);
            return undefined;
        }
    }

    function rebuild() {
        const base = parse(baseFile.text(), "config/default.json");
        if (base === undefined)
            return;

        const override = parse(overrideFile.text(), "override.json");
        root.overrideValues = override || ({});
        root.values = root.current(root.merge(base, override));
        root.ready = true;
        root.reloaded();
    }

    // ---- Writing back ------------------------------------------------------
    //
    // A cell that changes a setting writes it into the override layer, never
    // into the base: `config/default.json` is the repository's hand-written
    // floor and stays the same on every machine. What is written is the
    // override document itself with one key changed, never the merged values,
    // so a key this session never touched — a membrane list, a font — survives
    // untouched, and so do the comments-as-keys a human left in it.
    function set(path, value) {
        root.setMany([[path, value]]);
    }

    // Several keys in one write. A tissue moved from a band to a floating
    // place changes two lists, and written one after the other the shell
    // would build the layout in between — the tissue in both places, or in
    // neither — for the length of one reload.
    function setMany(pairs) {
        const next = JSON.parse(JSON.stringify(root.overrideValues || {}));
        let merged = root.values;

        for (const pair of pairs) {
            const path = pair[0];
            const value = pair[1];
            const keys = path.split(".");
            let node = next;
            for (let i = 0; i < keys.length - 1; i++) {
                const key = keys[i];
                if (node[key] === undefined || node[key] === null
                    || typeof node[key] !== "object" || Array.isArray(node[key]))
                    node[key] = {};
                node = node[key];
            }
            node[keys[keys.length - 1]] = value;
            merged = root.merge(merged, root.expandPath(path, value));
        }

        // The merged values follow when the file lands, but a control has to
        // answer the press it just received: the write is asynchronous and a
        // segmented pill that waits for the disk reads as a control that did
        // not take.
        root.overrideValues = next;
        root.values = merged;

        // And said out loud. Most of the shell reads `Config.get` through a
        // binding and follows `values` on its own, but what is built *from*
        // the configuration rather than bound to it — the membranes and the
        // floating tissues in `shell.qml` — waits for this signal. The file
        // watcher cannot be relied on to give it: the write is ours and
        // atomic, and a watcher that does not report our own replacement left
        // a membrane added from the settings cell unbuilt until the next
        // start.
        root.reloaded();

        // Kept for the retry, in case the config directory has to be made
        // first: the write that failed is the one to redo, not a fresh one.
        mkdir.pending = JSON.stringify(next, null, 2) + "\n";
        overrideFile.setText(mkdir.pending);
    }

    // `{ "theme": { "source": "manual" } }` from `theme.source` and `manual`.
    function expandPath(path, value) {
        const keys = path.split(".");
        let out = value;
        for (let i = keys.length - 1; i >= 0; i--) {
            const level = {};
            level[keys[i]] = out;
            out = level;
        }
        return out;
    }

    FileView {
        id: baseFile
        path: root.basePath
        watchChanges: true
        blockLoading: true
        onLoaded: root.rebuild()
        onFileChanged: reload()
    }

    FileView {
        id: overrideFile
        path: root.overridePath
        watchChanges: true
        atomicWrites: true
        // Absent until the settings UI writes it for the first time, which is
        // the normal case and not worth a warning on every start.
        printErrors: false
        onLoaded: root.rebuild()
        onLoadFailed: root.rebuild()
        onFileChanged: reload()

        // The config directory may not exist on a first run. Create it once,
        // on the first failure, rather than spawning anything at startup.
        onSaveFailed: {
            if (mkdir.running || mkdir.attempted)
                return;
            mkdir.attempted = true;
            mkdir.running = true;
        }
    }

    Process {
        id: mkdir
        property bool attempted: false
        property string pending: ""
        command: ["mkdir", "-p", root.overridePath.slice(0, root.overridePath.lastIndexOf("/"))]
        running: false
        onExited: code => { if (code === 0 && mkdir.pending.length > 0) overrideFile.setText(mkdir.pending); }
    }
}
