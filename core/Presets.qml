pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// Saved layouts: the whole composition of the desktop — every membrane, every
// floating tissue, every organism, on every monitor — under a name, to be put
// back in one press.
//
// **Vocabulary, not presets** (PRD §3.7) is about what Bioma ships: the system
// offers rules and the user composes. A preset here is a composition the user
// made and kept, and that list starts empty. Beside it stand the three Bioma
// ships as starting points — Complete, Minimal, Empty, amended into §3.7 on
// 2026-10-13 and chosen during setup (docs/design/SETUP.md). They are made of
// the same vocabulary, and once applied the layout is the user's: an update
// that changes one does not reach a desktop that applied it.
//
// A shipped preset is a file in config/presets/, so adding one is adding a
// file. One may borrow lists from the base layer (`from_base`): Complete takes
// the default's membranes and floating tissues rather than a copy of them, so
// the two cannot drift apart, and carries organisms of its own — the base
// layer ships none, because nobody's desktop gains furniture by updating.
//
// They live in the override layer, under `presets`, beside the layout they
// snapshot, because putting one back is a single write: the three lists and
// the name of the one now in use land together, and the shell never builds a
// desktop that is half the old layout and half the new (`Config.setMany`).
// Akusen, 2026-10-09: everything, every monitor, NEW starts empty, and a
// changed layout is kept by SAVE AS rather than saved by itself.
Singleton {
    id: root

    // What a layout is. The order of the keys is the order of the writes.
    readonly property var keys: ["membranes", "floating", "organisms"]

    // `{ name, membranes, floating, organisms }`, in the order they were made.
    readonly property var saved: Config.get("presets.saved", [])

    // The shipped ones, resolved: `{ name, line, shipped: true, membranes,
    // floating, organisms }`, in their files' `order`.
    readonly property var shipped: {
        const base = Config.baseValues || {};
        return root.shippedFiles
            .filter(entry => entry && entry.name)
            .slice()
            .sort((a, b) => (a.order || 0) - (b.order || 0))
            .map(entry => {
                const out = { "name": entry.name, "line": entry.line || "", "shipped": true };
                const borrowed = entry.from_base || [];
                for (const key of root.keys)
                    out[key] = JSON.parse(JSON.stringify(borrowed.indexOf(key) >= 0
                                                         ? (base[key] || []) : (entry[key] || [])));
                return out;
            });
    }

    // Every preset a list offers: the user's first, then Bioma's.
    readonly property var all: root.saved.concat(root.shipped)

    // The one last put back or saved, by name; empty after NEW, or before the
    // first one is saved.
    readonly property string active: Config.get("presets.active", "")

    // The layout as the shell has it now, in the shape a preset keeps.
    readonly property var current: {
        const out = {};
        for (const key of root.keys)
            out[key] = Config.get(key, []);
        return out;
    }

    readonly property string currentKey: root.signature(root.current)

    readonly property var activePreset: root.find(root.active)

    // Something on the page differs from the preset in use — or there is no
    // preset in use and the layout is not empty, so it is kept nowhere yet.
    readonly property bool changed: root.activePreset
        ? root.signature(root.activePreset) !== root.currentKey
        : !root.empty

    // Whether the layout as it stands is kept under some name: switching away
    // from one that is not throws it away, and the page asks first.
    readonly property bool kept: root.empty
        || root.all.some(preset => root.signature(preset) === root.currentKey)

    readonly property bool empty: root.keys.every(key => (root.current[key] || []).length === 0)

    function find(name) {
        return root.saved.find(preset => preset.name === name)
            || root.shipped.find(preset => preset.name === name)
            || null;
    }

    // A shipped name cannot be taken by a preset of the user's, in any case:
    // two rows called Minimal, one of them Bioma's, would be one too many.
    function reserved(name) {
        const wanted = (name || "").trim().toLowerCase();
        return wanted.length > 0 && root.shipped.some(preset => preset.name.toLowerCase() === wanted);
    }

    function isShipped(name) {
        return root.shipped.some(preset => preset.name === name);
    }

    // Two layouts are the same layout when they say the same thing, whatever
    // order their keys were written in: the override is written by hand as
    // well as by the page.
    function signature(layout) {
        const sorted = value => {
            if (Array.isArray(value))
                return value.map(sorted);
            if (value === null || typeof value !== "object")
                return value;
            const out = {};
            for (const key of Object.keys(value).sort())
                out[key] = sorted(value[key]);
            return out;
        };
        const picked = {};
        for (const key of root.keys)
            picked[key] = sorted(layout && layout[key] ? layout[key] : []);
        return JSON.stringify(picked);
    }

    // The layout as it stands, under this name: a new preset at the end of
    // the list, or the one of that name replaced where it was.
    function saveAs(name) {
        name = (name || "").trim();
        if (name.length === 0 || root.reserved(name))
            return false;

        const preset = JSON.parse(JSON.stringify(root.current));
        preset.name = name;

        const next = JSON.parse(JSON.stringify(root.saved));
        const at = next.findIndex(entry => entry.name === name);
        if (at >= 0)
            next[at] = preset;
        else
            next.push(preset);

        console.info(`Bioma: ${at >= 0 ? "replacing" : "saving"} the layout preset "${name}"`);
        Config.setMany([["presets.saved", next], ["presets.active", name]]);
        return true;
    }

    // Putting one back: its three lists and its name, in one write.
    function apply(name) {
        const preset = root.find(name);
        if (!preset)
            return false;
        console.info(`Bioma: applying the layout preset "${name}"`);
        const pairs = root.keys.map(key => [key, JSON.parse(JSON.stringify(preset[key] || []))]);
        pairs.push(["presets.active", name]);
        Config.setMany(pairs);
        return true;
    }

    // NEW: a desktop with nothing on it, to be composed from scratch. Nothing
    // is saved until it is given a name.
    function blank() {
        console.info("Bioma: starting an empty layout");
        const pairs = root.keys.map(key => [key, []]);
        pairs.push(["presets.active", ""]);
        Config.setMany(pairs);
    }

    // Forgetting one changes nothing on the screen: the layout stays as it is,
    // kept under no name if it was the one in use.
    function remove(name) {
        if (!root.saved.some(preset => preset.name === name))
            return false;
        console.info(`Bioma: removing the layout preset "${name}"`);
        const pairs = [["presets.saved", root.saved.filter(entry => entry.name !== name)]];
        if (root.active === name)
            pairs.push(["presets.active", ""]);
        Config.setMany(pairs);
        return true;
    }

    // ---- The shipped files ---------------------------------------------------

    readonly property string directory: Qt.resolvedUrl("../config/presets").toString().replace("file://", "")

    property var shippedFiles: []
    property var shippedByFile: ({})

    function noteShipped(file, text) {
        let entry = null;
        try {
            entry = JSON.parse(text);
        } catch (error) {
            console.warn(`Bioma: config/presets/${file}.json is not valid JSON — ${error.message}`);
        }
        const next = Object.assign({}, root.shippedByFile);
        if (entry)
            next[file] = entry;
        else
            delete next[file];
        root.shippedByFile = next;
        root.shippedFiles = Object.keys(next).map(key => next[key]);
    }

    FolderListModel {
        id: shippedFolder
        folder: `file://${root.directory}`
        nameFilters: ["*.json"]
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    // One reader per file, read once, like the palettes in core/Theme.qml.
    Instantiator {
        model: shippedFolder

        delegate: QtObject {
            id: shippedEntry

            required property string fileBaseName
            required property string filePath

            readonly property FileView view: FileView {
                path: shippedEntry.filePath
                blockLoading: true
                printErrors: false
                onLoaded: root.noteShipped(shippedEntry.fileBaseName, text())
            }
        }
    }
}
