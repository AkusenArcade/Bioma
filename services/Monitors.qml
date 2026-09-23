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
// Moving a monitor writes `position` into its section; making one primary
// writes niri's only notion of a primary output, `focus-at-startup`, and takes
// it off every other. niri does not merge `output` sections — two naming one
// monitor are both kept — so an edit is made in **every** section that names
// it, and an output nobody has written a section for gets one, beside the
// others. The files, and validation before writing, are `NiriConfig`'s.
Singleton {
    id: root

    readonly property bool busy: NiriConfig.busy || asker.running
    readonly property string error: NiriConfig.error

    // What niri reports, one entry per output that is on.
    property var live: []

    // The configuration's output sections, in the order niri reads them.
    readonly property var sections: NiriConfig.items.filter(item => item.kind === "output")

    readonly property var outputs: {
        const out = [];
        for (const output of root.live) {
            const named = root.sections.filter(section =>
                NiriKdl.names(section, output.name, output.description));
            out.push(Object.assign({}, output, {
                "sections": named,
                "primary": named.some(section => section.primary)
            }));
        }
        return out;
    }

    readonly property int count: root.outputs.length

    function outputOf(name) {
        return root.outputs.find(output => output.name === name) || null;
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
                for (const name of Object.keys(parsed).sort()) {
                    const o = parsed[name];
                    if (!o.logical)
                        continue;
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
