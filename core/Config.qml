pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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
        root.values = root.merge(base, override);
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
        const next = JSON.parse(JSON.stringify(root.overrideValues || {}));

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

        // The merged values follow when the file lands, but a control has to
        // answer the press it just received: the write is asynchronous and a
        // segmented pill that waits for the disk reads as a control that did
        // not take.
        root.overrideValues = next;
        root.values = root.merge(root.values, root.expandPath(path, value));

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
