pragma Singleton

import QtQuick
import Quickshell

// Saved layouts: the whole composition of the desktop — every membrane, every
// floating tissue, every organism, on every monitor — under a name, to be put
// back in one press.
//
// **Vocabulary, not presets** (PRD §3.7) is about what Bioma ships: the system
// offers rules and the user composes. These are not that. Nothing here is
// shipped; a preset is a composition the user made and kept, and the list
// starts empty.
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
        || root.saved.some(preset => root.signature(preset) === root.currentKey)

    readonly property bool empty: root.keys.every(key => (root.current[key] || []).length === 0)

    function find(name) {
        return root.saved.find(preset => preset.name === name) || null;
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
        if (name.length === 0)
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
        if (!root.find(name))
            return false;
        console.info(`Bioma: removing the layout preset "${name}"`);
        const pairs = [["presets.saved", root.saved.filter(entry => entry.name !== name)]];
        if (root.active === name)
            pairs.push(["presets.active", ""]);
        Config.setMany(pairs);
        return true;
    }
}
