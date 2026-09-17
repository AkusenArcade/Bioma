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
        root.values = root.merge(base, override);
        root.ready = true;
        root.reloaded();
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
    }
}
