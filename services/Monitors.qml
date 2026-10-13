pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "niri-config.js" as NiriKdl

// The monitors, as niri lays them out.
//
// Two sources, because neither says everything. niri itself answers where each
// output is and what it is running — `niri msg --json outputs`, asked again
// whenever the configuration or the set of screens changes — and the
// configuration says what was *asked* for: the `output` sections, where they
// are written, and which one is focused at startup.
//
// A monitor is switched off and on through niri's IPC, never the
// configuration: `niri msg output … off` lasts until niri restarts, so every
// monitor comes back on with the machine. The last one on cannot be switched
// off — there would be nothing left to switch it back on from.
//
// Moving a monitor writes `position` into its section; making one primary
// writes niri's only notion of a primary output, `focus-at-startup`, and takes
// it off every other. niri does not merge `output` sections — two naming one
// monitor are both kept — so an edit is made in **every** section that names
// it, and an output nobody has written a section for gets one, beside the
// others. The files, and validation before writing, are `NiriConfig`'s.
Singleton {
    id: root

    readonly property bool busy: NiriConfig.busy || asker.running || switcher.running
    readonly property string error: NiriConfig.error

    // What niri reports, one entry per output that is on.
    property var live: []

    // Connected but switched off: niri lists them with no geometry.
    property var dark: []

    // Where each output last was while it was on, so one switched off stays
    // where it was in the drawing.
    property var seen: ({})

    // The configuration's output sections, in the order niri reads them.
    readonly property var sections: NiriConfig.items.filter(item => item.kind === "output")

    readonly property var outputs: {
        const out = [];
        for (const output of root.live) {
            const named = root.sections.filter(section =>
                NiriKdl.names(section, output.name, output.description));
            out.push(Object.assign({}, output, {
                "on": true,
                "sections": named,
                "primary": named.some(section => section.primary)
            }));
        }
        return out;
    }

    // The ones switched off, placed where they last were, or else where their
    // section puts them, or else beside the others: where niri will put them
    // back when they come on.
    readonly property var off: {
        let right = 0;
        for (const output of root.live)
            right = Math.max(right, output.x + output.width);

        const out = [];
        for (const output of root.dark) {
            const named = root.sections.filter(section =>
                NiriKdl.names(section, output.name, output.description));
            const written = named.find(section => section.position);
            let place = root.seen[output.name];
            if (!place) {
                place = {
                    "x": written ? written.position.x : right,
                    "y": written ? written.position.y : 0,
                    "width": output.modeWidth,
                    "height": output.modeHeight,
                    "scale": 1
                };
                right += output.modeWidth;
            }
            out.push(Object.assign({}, output, place, {
                "on": false,
                "sections": named,
                "primary": named.some(section => section.primary)
            }));
        }
        return out;
    }

    // Outputs that are on.
    readonly property int count: root.outputs.length

    function outputOf(name) {
        return root.outputs.find(output => output.name === name)
            || root.off.find(output => output.name === name) || null;
    }

    // ---- Asking niri ---------------------------------------------------------

    function refresh() {
        if (asker.running) {
            root.again = true;
            return;
        }
        asker.running = true;
    }

    property bool again: false

    Process {
        id: asker

        command: ["niri", "msg", "--json", "outputs"]

        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = {};
                try {
                    parsed = JSON.parse(this.text);
                } catch (e) {
                    return;
                }

                const out = [];
                const dark = [];
                const seen = Object.assign({}, root.seen);
                for (const name of Object.keys(parsed).sort()) {
                    const o = parsed[name];
                    if (!o.logical) {
                        const mode = o.modes.find(m => m.is_preferred) || o.modes[0] || null;
                        if (!mode)
                            continue;
                        dark.push({
                            "name": name,
                            "description": [o.make, o.model, o.serial || "Unknown"].join(" "),
                            "modeWidth": mode.width,
                            "modeHeight": mode.height,
                            "refresh": mode.refresh_rate / 1000
                        });
                        continue;
                    }
                    seen[name] = {
                        "x": o.logical.x,
                        "y": o.logical.y,
                        "width": o.logical.width,
                        "height": o.logical.height,
                        "scale": o.logical.scale
                    };
                    const mode = o.current_mode !== null && o.modes[o.current_mode]
                        ? o.modes[o.current_mode] : null;
                    out.push({
                        "name": name,
                        "description": [o.make, o.model, o.serial || "Unknown"].join(" "),
                        "x": o.logical.x,
                        "y": o.logical.y,
                        "width": o.logical.width,
                        "height": o.logical.height,
                        "scale": o.logical.scale,
                        "modeWidth": mode ? mode.width : o.logical.width,
                        "modeHeight": mode ? mode.height : o.logical.height,
                        "refresh": mode ? mode.refresh_rate / 1000 : 0
                    });
                }
                root.seen = seen;
                root.dark = dark;
                root.live = out;
            }
        }

        onExited: if (root.again) {
            root.again = false;
            root.refresh();
        }
    }

    // niri re-reads its configuration on its own, a moment after the file
    // changes; ask once it has.
    Timer {
        id: settle
        interval: 400
        onTriggered: root.refresh()
    }

    Connections {
        target: NiriConfig
        function onWrittenChanged() { settle.restart(); }
    }

    readonly property int screenCount: Quickshell.screens.length
    onScreenCountChanged: settle.restart()

    Component.onCompleted: root.refresh()

    // ---- Switching on and off ------------------------------------------------

    // False when refused: the last monitor on stays on.
    function power(name, on) {
        const output = root.outputOf(name);
        if (!output || output.on === on || switcher.running)
            return true;
        if (!on && root.count <= 1)
            return false;
        switcher.command = ["niri", "msg", "output", name, on ? "on" : "off"];
        switcher.running = true;
        return true;
    }

    Process {
        id: switcher
        onExited: root.refresh()
    }

    // ---- Writing -------------------------------------------------------------

    // Every section of one output in one file, rewritten by `edit`, one at a
    // time and scanned again after each: an edit moves every offset after it.
    function rewrite(text, output, edit) {
        let index = 0;
        for (;;) {
            const found = NiriKdl.scan(text).items.filter(item =>
                item.kind === "output" && NiriKdl.names(item, output.name, output.description));
            if (index >= found.length)
                return text;
            text = edit(text, found[index]);
            index++;
        }
    }

    // Where a section for an output that has none goes: beside the last
    // section there is, or into niri's own file.
    function homeForNew() {
        return root.sections.length > 0 ? root.sections[root.sections.length - 1].file
                                        : NiriConfig.main;
    }

    // Apply a change to every output that needs it, one write per file.
    //   change(text, output, file) → text
    function apply(change) {
        const files = {};
        const order = [];
        const textFor = file => {
            if (!(file in files)) {
                files[file] = NiriConfig.textOf(file);
                order.push(file);
            }
            return files[file];
        };

        for (const output of root.outputs) {
            const touched = output.sections.length > 0
                ? output.sections.map(section => section.file)
                      .filter((file, i, all) => all.indexOf(file) === i)
                : [root.homeForNew()];

            for (const file of touched) {
                const text = textFor(file);
                if (text === null) {
                    NiriConfig.error = "niri's configuration could not be read.";
                    return;
                }
                files[file] = change(text, output, file);
            }
        }

        for (const file of order)
            if (files[file] !== NiriConfig.textOf(file))
                NiriConfig.write(file, files[file], NiriKdl.outputsText(files[file]));
    }

    // Positions in logical units, `{ "DP-1": { "x": 0, "y": 0 }, … }`. Only
    // the outputs named are written.
    function place(positions) {
        root.apply((text, output) => {
            const wanted = positions[output.name];
            if (!wanted || (wanted.x === output.x && wanted.y === output.y))
                return text;
            if (output.sections.length === 0)
                return NiriKdl.withOutput(text, output.name, wanted.x, wanted.y);
            return root.rewrite(text, output,
                                (t, section) => NiriKdl.withPosition(t, section, wanted.x, wanted.y));
        });
    }

    function makePrimary(name) {
        root.apply((text, output) => {
            const on = output.name === name;
            if (output.sections.length === 0) {
                if (!on)
                    return text;
                const added = NiriKdl.withOutput(text, output.name, output.x, output.y);
                const section = NiriKdl.scan(added).items.filter(item => item.kind === "output").pop();
                return NiriKdl.withFlag(added, section, "focus-at-startup", true);
            }
            return root.rewrite(text, output,
                                (t, section) => NiriKdl.withFlag(t, section, "focus-at-startup", on));
        });
    }
}
