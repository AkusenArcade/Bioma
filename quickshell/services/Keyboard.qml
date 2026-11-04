pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The keyboard's layouts: which ones there are, which one is on, and changing
// either.
//
// niri owns the keymap. What it has loaded and which one is active arrive on
// its event stream (`Niri.layoutNames`, `Niri.keyboardLayout`), by their
// xkeyboard-config names — "English (US, alt. intl.)" — which is also how they
// are matched back to their codes in the catalogue (`scripts/xkb list`).
//
// **Switching** is niri's action. **Which layouts there are** is written by
// Bioma: the list lives in `keyboard.layouts`, and `scripts/niri-include
// keyboard` puts it in niri's own `bioma-keyboard.kdl`, included last, so it
// overrides the layout and variant and leaves every other keyboard setting —
// numlock, repeat, options — where somebody set it. Until the list is first
// changed from the shell nothing is written: the layouts are whatever the
// system and niri's configuration already say.
Singleton {
    id: root

    // ---- What niri has -------------------------------------------------------

    readonly property var loaded: Niri.layoutNames
    readonly property string current: Niri.keyboardLayout
    readonly property int currentIndex: root.loaded.indexOf(root.current)

    // Emitted when the layout changes while the shell is running — not when
    // the first one is reported — for the cell's condition.
    signal switched

    property string lastSeen: ""

    onCurrentChanged: {
        if (root.lastSeen.length > 0 && root.current.length > 0 && root.current !== root.lastSeen)
            root.switched();
        if (root.current.length > 0)
            root.lastSeen = root.current;
    }

    // ---- The catalogue ---------------------------------------------------------

    // [{ "layout", "variant", "name" }], every layout and variant this machine
    // has. Read once, at the first binding: it is six hundred rows that never
    // change while the shell runs.
    property var catalogue: []

    Process {
        running: true
        command: [Quickshell.shellPath("scripts/xkb"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.catalogue = JSON.parse(this.text);
                } catch (e) {}
            }
        }
    }

    function entryNamed(name) {
        return root.catalogue.find(e => e.name === name) || null;
    }

    // What is loaded, with its codes where the catalogue knows the name.
    readonly property var layouts: root.loaded.map(name => {
        const known = root.entryNamed(name);
        return {
            "name": name,
            "layout": known ? known.layout : "",
            "variant": known ? known.variant : ""
        };
    })

    // The short form the membrane shows: the layout's code, which is what
    // anybody who switches layouts already calls it — IT, US, DE.
    function codeOf(entry) {
        if (!entry)
            return "";
        if (entry.layout && entry.layout.length > 0)
            return entry.layout.toUpperCase();
        return String(entry.name || "").slice(0, 2).toUpperCase();
    }

    readonly property string currentCode: root.codeOf(root.layouts[root.currentIndex] || null)

    // ---- Switching ---------------------------------------------------------------

    function switchTo(index) {
        if (index < 0 || index >= root.loaded.length || index === root.currentIndex)
            return;
        Quickshell.execDetached(["niri", "msg", "action", "switch-layout", String(index)]);
    }

    function next() {
        Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"]);
    }

    // ---- Which layouts there are ------------------------------------------------

    // The last thing niri refused, in its words.
    property string error: ""

    function add(entry) {
        if (!entry)
            return;
        const list = root.codes();
        if (list.some(e => e.layout === entry.layout && e.variant === entry.variant))
            return;
        root.write(list.concat([{ "layout": entry.layout, "variant": entry.variant || "" }]));
    }

    function remove(index) {
        const list = root.codes();
        if (list.length <= 1 || index < 0 || index >= list.length)
            return;
        list.splice(index, 1);
        root.write(list);
    }

    // What is loaded now, as codes — the list a change starts from. A name the
    // catalogue does not know cannot be written back, so it is left out rather
    // than written as nonsense.
    function codes() {
        return root.layouts.filter(e => e.layout.length > 0)
                           .map(e => ({ "layout": e.layout, "variant": e.variant }));
    }

    function kdl(list) {
        const quote = value => `"${String(value).replace(/["\\]/g, "")}"`;
        const layouts = list.map(e => e.layout).join(",");
        const variants = list.map(e => e.variant || "").join(",");
        return "// Written by Bioma's keyboard cell. Changing layouts there rewrites it.\n"
             + "input {\n    keyboard {\n        xkb {\n"
             + `            layout ${quote(layouts)}\n`
             + `            variant ${quote(variants)}\n`
             + "        }\n    }\n}";
    }

    function write(list) {
        if (list.length === 0)
            return;
        Config.set("keyboard.layouts", list);
        root.error = "";
        writer.body = root.kdl(list);
        if (writer.running)
            writer.again = true;
        else
            writer.running = true;
    }

    Process {
        id: writer

        property string body: ""
        property bool again: false

        command: [Quickshell.shellPath("scripts/niri-include"), "keyboard"]
        stdinEnabled: true

        onStarted: {
            writer.write(writer.body);
            writer.stdinEnabled = false;
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const reason = this.text.trim();
                if (reason.length > 0)
                    root.error = "niri refused it: " + reason;
            }
        }

        onExited: {
            writer.stdinEnabled = true;
            if (writer.again) {
                writer.again = false;
                writer.running = true;
            }
        }
    }
}
