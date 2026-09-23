pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The palette, outside the shell: niri's borders, GTK, Qt, the terminals.
//
// The templates are Noctalia's (config/templates/README.md), and they name
// colours the way matugen does — `primary`, `surface_container`,
// `on_primary_container`, sixteen terminal colours. Bioma's palette has four
// roles and derives the rest, so this is the translation: every name a template
// uses, made from the palette's targets the way the shell makes its own
// surfaces. The same templates therefore serve a matugen palette and a Bioma
// one, and the applications change when the shell does.
//
// `scripts/themes` renders and hooks them. It rewrites a file only when what it
// renders has changed and runs a hook only then — so starting the shell does not
// make every terminal reload — or when a template has just been switched on.
//
// niri's template also carries the shell's corner radius to the windows: 20 px
// at 100 % of the RADIUS slider, and in proportion below it.
Singleton {
    id: root

    // Which templates are on. By default niri, the toolkits and what is
    // installed of the rest is decided the first time the catalogue is read.
    readonly property var enabled: Config.get("theme.templates", ["niri", "gtk3", "gtk4", "qt",
                                                                  "alacritty", "btop", "cava"])

    // [{ "id", "name", "category", "installed" }], asked once.
    property var catalogue: []
    property var failures: ({})

    function isOn(id) {
        return root.enabled.indexOf(id) >= 0;
    }

    function setOn(id, on) {
        if (on === root.isOn(id))
            return;
        if (on) {
            root.forced = root.forced.concat([id]);
            Config.set("theme.templates", root.enabled.concat([id]));
        } else {
            Config.set("theme.templates", root.enabled.filter(t => t !== id));
            undoer.command = [Quickshell.shellPath("scripts/themes"), "undo", id];
            undoer.running = true;
        }
    }

    // ---- The translation ------------------------------------------------------------

    function mix(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, 1);
    }

    function hex(colour) {
        const c = Qt.rgba(colour.r, colour.g, colour.b, 1);
        return c.toString();
    }

    function readableOn(colour, dark, light) {
        return Theme.luminance(colour) > 0.5 ? dark : light;
    }

    function hued(hue, like) {
        return Qt.hsla(hue, Math.max(0.45, like.hslSaturation), Math.min(0.75, Math.max(0.45, like.hslLightness)), 1);
    }

    readonly property var colors: {
        const bg = Theme.backgroundTarget;
        const fg = Theme.textTarget;
        const p = Theme.primaryTarget;
        const s = Theme.secondaryTarget;
        const dark = Theme.targetIsDark;
        const states = dark ? Theme.stateDark : Theme.stateLight;
        const e = Qt.color(states.alert);
        const calm = Qt.color(states.calm);
        const warm = Qt.color(states.active);
        const lift = amount => Theme.liftAway(bg, amount, dark);
        const brighter = colour => Theme.liftAway(colour, 0.08, dark);
        // A grey has no hue (-1); it turns from red like any other.
        const t = Qt.hsla((Math.max(0, s.hslHue) + 0.12) % 1, s.hslSaturation, s.hslLightness, 1);
        const outline = Theme.structuralWith(bg, p, dark ? 0.32 : 0.72);
        const ink = dark ? bg : Qt.color("#101010");
        const paper = dark ? Qt.color("#f4f4f4") : bg;

        const out = {
            "background": bg, "on_background": fg,
            "surface": bg, "on_surface": fg,
            "surface_variant": lift(0.07), "on_surface_variant": root.mix(fg, bg, 0.3),
            "surface_container_lowest": lift(0.01), "surface_container_low": lift(0.03),
            "surface_container": lift(0.045), "surface_container_high": lift(0.07),
            "surface_container_highest": lift(0.095),
            "inverse_surface": fg, "hover": lift(0.06),
            "outline": outline, "outline_variant": root.mix(outline, bg, 0.5),
            "shadow": Qt.color("#000000"),

            "primary": p, "on_primary": root.readableOn(p, ink, paper),
            "primary_container": root.mix(p, bg, 0.72), "on_primary_container": root.mix(p, fg, 0.5),
            "secondary": s, "on_secondary": root.readableOn(s, ink, paper),
            "secondary_container": root.mix(s, bg, 0.72), "on_secondary_container": root.mix(s, fg, 0.5),
            "tertiary": t, "on_tertiary": root.readableOn(t, ink, paper),
            "tertiary_container": root.mix(t, bg, 0.72), "on_tertiary_container": root.mix(t, fg, 0.5),
            "error": e, "on_error": root.readableOn(e, ink, paper),
            "error_container": root.mix(e, bg, 0.72), "on_error_container": root.mix(e, fg, 0.5),

            // The terminal's sixteen: the state colours where a terminal means
            // a state — red is an error, green a success — and the palette's
            // own light for the rest.
            "terminal_background": bg, "terminal_foreground": fg,
            "terminal_cursor": p, "terminal_cursor_text": bg,
            "terminal_selection_bg": root.mix(p, bg, 0.65), "terminal_selection_fg": fg,
            "terminal_normal_black": lift(0.1), "terminal_normal_red": e,
            "terminal_normal_green": calm, "terminal_normal_yellow": warm,
            "terminal_normal_blue": root.hued(0.6, p), "terminal_normal_magenta": root.hued(0.85, p),
            "terminal_normal_cyan": root.hued(0.5, s), "terminal_normal_white": root.mix(fg, bg, 0.15),
            "terminal_bright_black": lift(0.25), "terminal_bright_red": brighter(e),
            "terminal_bright_green": brighter(calm), "terminal_bright_yellow": brighter(warm),
            "terminal_bright_blue": brighter(root.hued(0.6, p)),
            "terminal_bright_magenta": brighter(root.hued(0.85, p)),
            "terminal_bright_cyan": brighter(root.hued(0.5, s)), "terminal_bright_white": fg
        };

        const hexes = {};
        for (const name in out)
            hexes[name] = root.hex(out[name]);
        return hexes;
    }

    readonly property int windowRadius: Math.round(20 * Metrics.radiusPercent / 100)

    // ---- Rendering --------------------------------------------------------------------

    readonly property string signature: JSON.stringify([root.colors, root.enabled, root.windowRadius,
                                                        Theme.targetIsDark])

    property var forced: []

    onSignatureChanged: if (root.settled) debounce.restart()

    // A palette crossing changes the targets once, but a slider dragged across
    // its travel changes the radius many times: the files follow when it rests.
    Timer {
        id: debounce
        interval: 400
        onTriggered: root.render()
    }

    property bool settled: false

    Timer {
        interval: Timing.settle
        running: true
        onTriggered: {
            root.settled = true;
            root.render();
            lister.running = true;
        }
    }

    function render() {
        if (renderer.running) {
            debounce.restart();
            return;
        }
        renderer.request = JSON.stringify({
            "colors": root.colors,
            "mode": Theme.targetIsDark ? "dark" : "light",
            "vars": { "window_radius": root.windowRadius },
            "enabled": root.enabled,
            // A hook that failed ran against a file that is now written, so
            // the file will not change again to run it: it is asked again.
            "force": root.forced.concat(Object.keys(root.failures))
        });
        root.forced = [];
        renderer.running = true;
    }

    Process {
        id: renderer

        property string request: ""

        command: [Quickshell.shellPath("scripts/themes"), "render"]
        stdinEnabled: true

        onStarted: {
            renderer.write(renderer.request);
            renderer.stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let report = [];
                try {
                    report = JSON.parse(this.text);
                } catch (e) {
                    return;
                }
                const failures = {};
                for (const outcome of report) {
                    if (!outcome.ok || outcome.error.length > 0) {
                        failures[outcome.id] = outcome.error;
                        console.warn(`Bioma: the ${outcome.id} template —`, outcome.error);
                    }
                }
                root.failures = failures;
            }
        }

        onExited: renderer.stdinEnabled = true
    }

    Process {
        id: lister
        command: [Quickshell.shellPath("scripts/themes"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.catalogue = JSON.parse(this.text);
                } catch (e) {}
            }
        }
    }

    Process { id: undoer }
}
