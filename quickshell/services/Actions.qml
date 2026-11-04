pragma Singleton

import QtQuick
import Quickshell
import qs.core

// Quick actions: macros somebody writes on the Settings page and runs from
// the ring that comes to the pointer (cells/actions), or from a key of their
// own (`qs ipc call actions run <name>`).
//
// A macro is a name, an icon from Bioma's set and a list of steps, run one
// after the other. A step is a `type` and the few values that type needs;
// what each type is — its label, what it holds, what it does — is a block in
// `kinds` below, and adding one costs that block and nothing else. The Settings
// page draws its editor from the same blocks.
//
// Kept in `actions.macros`, in the override layer, beside the presets. Akusen
// asked for it and shaped it, 2026-10-18: a ring of up to eight around the
// pointer, steps for an application, a file, the volume, the brightness, the
// sounds, the appearance, a monitor, a preset and a favourite wallpaper — and
// one that keeps the settings as they are now, captured, to be put back. No
// step places a window on a workspace: niri's window rules already do, and
// whoever uses niri knows them. No step switches every monitor off: a macro
// switches one, and never the last one that is on.
Singleton {
    id: root

    readonly property var macros: {
        const list = Config.get("actions.macros", []);
        return Array.isArray(list) ? list.filter(macro => macro && typeof macro.name === "string") : [];
    }

    // As many as the ring holds, and as many as the page makes: one ring, not
    // pages of them (Akusen, 2026-10-24: "eight are enough"). A longer list
    // written by hand is kept and listed, and the rest run from their key.
    readonly property int ringSize: 8
    readonly property var ring: root.macros.slice(0, root.ringSize)

    function find(name) {
        return root.macros.find(macro => macro.name === name) || null;
    }

    function write(list) {
        Config.set("actions.macros", list);
    }

    // ---- The icons ------------------------------------------------------------
    //
    // Drawn for the actions, in the set's own grammar (docs/design/icons): what
    // a macro is *for*, not what it does — work, play, a stream, music, rest.
    readonly property var icons: [
        { "name": "action-work", "label": "Work" },
        { "name": "action-game", "label": "Game" },
        { "name": "action-stream", "label": "Stream" },
        { "name": "action-music", "label": "Music" },
        { "name": "action-relax", "label": "Relax" },
        { "name": "action-focus", "label": "Focus" },
        { "name": "action-night", "label": "Night" },
        { "name": "action-call", "label": "Call" },
        { "name": "action-code", "label": "Code" },
        { "name": "action-design", "label": "Design" },
        { "name": "action-home", "label": "Home" },
        { "name": "action-travel", "label": "Travel" }
    ]

    readonly property string defaultIcon: "action-work"

    function iconOf(macro) {
        const name = macro && macro.icon;
        return root.icons.some(icon => icon.name === name) ? name : root.defaultIcon;
    }

    // ---- What a settings step may hold ------------------------------------------
    //
    // Two groups, the two pages a person thinks of as "how the desktop looks"
    // and "how it sounds". Left out on purpose: the layout (a preset step does
    // that), the monitors and the keys (they are niri's files), and everything
    // that is somebody's data rather than a choice — the weather's city, the
    // calendars, recent emoji, the dock's pins.
    readonly property var groups: [
        { "key": "appearance", "label": "APPEARANCE",
          "paths": ["appearance.radius", "appearance.edge", "appearance.gap",
                    "tissue.padding", "tissue.opacity", "cell.opacity", "cell.blur",
                    "cell.blurStrength", "scrim.opacity", "timing.speed",
                    "theme.source", "theme.palette", "theme.matugen"] },
        { "key": "sounds", "label": "SOUNDS",
          "paths": ["sounds.volume", "sounds.login", "sounds.notifications",
                    "sounds.cells", "sounds.alerts"] }
    ]

    function groupOf(key) {
        return root.groups.find(group => group.key === key) || null;
    }

    // The values as the shell reads them now — the default and the override
    // together, not what differs from the default: a value equal to the
    // default would otherwise be left out, and putting the snapshot back would
    // not undo a change made to it since.
    function capture(keys) {
        const values = {};
        for (const key of keys) {
            const group = root.groupOf(key);
            if (!group)
                continue;
            for (const path of group.paths) {
                const value = Config.get(path, undefined);
                if (value !== undefined)
                    values[path] = JSON.parse(JSON.stringify(value));
            }
        }
        return values;
    }

    // ---- The kinds of step ------------------------------------------------------
    //
    // `label` is how the page names it, `fresh()` the step a press on it adds,
    // `describe(step)` the line it reads as, `run(step)` what it does. A run
    // answers nothing when it is done, a reason when it could not be, or
    // `{ until, timeout }` when the next step has to wait for something.
    readonly property var kinds: ({
        "launch": {
            "label": "LAUNCH",
            "fresh": () => ({ "type": "launch", "app": "" }),
            "describe": step => {
                const entry = root.entryOf(step.app);
                return entry ? entry.name : (step.app || "No application");
            },
            "run": step => {
                const entry = root.entryOf(step.app);
                if (!entry)
                    return `no application "${step.app || ""}"`;
                Apps.run(entry);
            }
        },
        "open": {
            "label": "OPEN FILE",
            "fresh": () => ({ "type": "open", "path": "" }),
            "describe": step => step.path ? step.path.split("/").pop() : "No file",
            "run": step => {
                if (!step.path)
                    return "no file to open";
                Files.open(root.expand(step.path));
            }
        },
        "volume": {
            "label": "VOLUME",
            "fresh": () => ({ "type": "volume", "percent": 50 }),
            "describe": step => `${Math.round(step.percent ?? 50)}%`,
            "run": step => {
                if (!Audio.sink)
                    return "no output to set";
                Audio.setVolume(Math.max(0, Math.min(100, step.percent ?? 50)) / 100);
            }
        },
        "brightness": {
            "label": "BRIGHTNESS",
            "fresh": () => ({ "type": "brightness", "percent": 70 }),
            "describe": step => `${Math.round(step.percent ?? 70)}%`,
            "run": step => {
                Brightness.set(Math.max(1, Math.min(100, step.percent ?? 70)) / 100);
            }
        },
        "settings": {
            "label": "SETTINGS",
            "fresh": () => ({ "type": "settings", "groups": ["appearance"],
                              "values": root.capture(["appearance"]) }),
            "describe": step => root.summary(step),
            "run": step => {
                const pairs = Object.keys(step.values || {}).map(path => [path, step.values[path]]);
                if (pairs.length === 0)
                    return "nothing captured";
                Config.setMany(pairs);
            }
        },
        "monitor": {
            "label": "MONITOR",
            "fresh": () => ({ "type": "monitor", "output": "", "on": false }),
            "describe": step => `${step.output || "No monitor"} ${step.on ? "on" : "off"}`,
            "run": step => {
                if (!Monitors.outputOf(step.output))
                    return `no monitor "${step.output || ""}"`;
                if (!Monitors.power(step.output, step.on === true))
                    return `${step.output} is the last monitor on`;
                return { "until": () => !Monitors.switching, "timeout": 5000 };
            }
        },
        "preset": {
            "label": "PRESET",
            "fresh": () => ({ "type": "preset", "name": "" }),
            "describe": step => step.name || "No preset",
            "run": step => {
                if (!Presets.apply(step.name))
                    return `no preset "${step.name || ""}"`;
            }
        },
        "wallpaper": {
            "label": "WALLPAPER",
            "fresh": () => ({ "type": "wallpaper", "path": "" }),
            "describe": step => step.path ? step.path.split("/").pop() : "No wallpaper",
            "run": step => {
                if (!step.path)
                    return "no wallpaper chosen";
                Wallpaper.path = step.path;
            }
        },
        "quiet": {
            "label": "DO NOT DISTURB",
            "fresh": () => ({ "type": "quiet", "on": true }),
            "describe": step => step.on ? "On" : "Off",
            "run": step => {
                Notifications.setQuiet(step.on === true);
            }
        },
        "profile": {
            "label": "POWER PROFILE",
            "fresh": () => ({ "type": "profile", "profile": "balanced" }),
            "describe": step => ({ "saver": "Power saver", "balanced": "Balanced",
                                   "performance": "Performance" })[step.profile] || "Balanced",
            "run": step => {
                if (!Power.present)
                    return "no power profiles on this machine";
                Power.set(step.profile || "balanced");
            }
        },
        // The shell's own, not the machine's: the same mode the key and the
        // cell turn on (core/Performance.qml). Off by a step, it stays off
        // while a game holds it, as off by hand does.
        "performance": {
            "label": "PERFORMANCE MODE",
            "fresh": () => ({ "type": "performance", "on": true }),
            "describe": step => step.on ? "On" : "Off",
            "run": step => {
                if (step.on === true)
                    Performance.on();
                else
                    Performance.off();
            }
        },
        "timer": {
            "label": "TIMER",
            "fresh": () => ({ "type": "timer", "minutes": 25 }),
            "describe": step => `${Math.round(step.minutes ?? 25)} min`,
            "run": step => {
                const minutes = Math.max(1, Math.round(step.minutes ?? 25));
                Time.reset();
                Time.setLength(minutes * 60);
                Time.start();
            }
        },
        "wait": {
            "label": "WAIT",
            "fresh": () => ({ "type": "wait", "seconds": 2 }),
            "describe": step => `${step.seconds ?? 2} s`,
            "run": step => {
                const until = Date.now() + Math.max(0, step.seconds ?? 2) * 1000;
                return { "until": () => Date.now() >= until, "timeout": 600000 };
            }
        },
        "command": {
            "label": "COMMAND",
            "fresh": () => ({ "type": "command", "command": "" }),
            "describe": step => step.command || "No command",
            // A user service of its own, like an application: the command
            // neither inherits the shell's nice nor dies with it.
            "run": step => {
                if (!step.command || step.command.trim().length === 0)
                    return "no command";
                Quickshell.execDetached([Quickshell.shellPath("scripts/launch"), "--id", "bioma-action",
                                         "--", "sh", "-c", step.command]);
            }
        }
    })

    // In the order the page offers them.
    readonly property var order: ["launch", "open", "volume", "brightness", "settings", "monitor",
                                  "preset", "wallpaper", "quiet", "profile", "performance", "timer",
                                  "wait",
                                  "command"]

    function kindOf(step) {
        return step && root.kinds[step.type] ? root.kinds[step.type] : null;
    }

    function describe(step) {
        const kind = root.kindOf(step);
        return kind ? kind.describe(step) : `Unknown step "${step ? step.type : ""}"`;
    }

    function labelOf(step) {
        const kind = root.kindOf(step);
        return kind ? kind.label : "UNKNOWN";
    }

    // What a captured step holds, in a line: the palette, and how many other
    // values came with it.
    function summary(step) {
        const values = step.values || {};
        const parts = [];
        if ((step.groups || []).indexOf("appearance") >= 0) {
            // matugen draws the palette from the wallpaper; manual is one of
            // Bioma's own, by name.
            const matugen = values["theme.matugen"] || {};
            const scheme = (matugen.scheme || "").replace(/^scheme-/, "").replace(/-/g, " ");
            parts.push(values["theme.source"] === "matugen"
                       ? `colours from the wallpaper${scheme ? ` (${scheme})` : ""}`
                       : `palette ${values["theme.palette"] || "default"}`);
            if (values["appearance.radius"] !== undefined)
                parts.push(`radius ${values["appearance.radius"]}%`);
            if (values["cell.blur"] !== undefined)
                parts.push(values["cell.blur"] ? "blur on" : "blur off");
        }
        if ((step.groups || []).indexOf("sounds") >= 0) {
            const on = ["login", "notifications", "cells", "alerts"].filter(key => values[`sounds.${key}`] !== false);
            parts.push(values["sounds.volume"] !== undefined
                       ? `sounds at ${Math.round(values["sounds.volume"] * 100)}%, ${on.length} of 4 on`
                       : `${on.length} of 4 sounds on`);
        }
        if (parts.length === 0)
            return "Nothing captured";
        const line = parts.join(", ");
        return line.charAt(0).toUpperCase() + line.slice(1);
    }

    function entryOf(id) {
        if (!id)
            return null;
        return DesktopEntries.byId(id) || Apps.entryFor(id);
    }

    function expand(path) {
        const home = Quickshell.env("HOME") || "";
        return path.replace(/^~(?=\/|$)/, home).replace(/^\$HOME(?=\/|$)/, home);
    }

    // ---- Running ----------------------------------------------------------------

    property string running: ""
    property var queue: []
    property int index: 0
    property var holding: null
    property real deadline: 0

    signal finished(string name)
    signal failed(string name, string reason)

    // A macro asked for while another runs takes its place: the second press
    // is the newer wish.
    function run(name) {
        const macro = root.find(name);
        if (!macro)
            return false;
        console.info(`Bioma: running the quick action "${name}"`);
        ticker.stop();
        root.holding = null;
        root.queue = JSON.parse(JSON.stringify(macro.steps || []));
        root.index = 0;
        root.running = name;
        root.advance();
        return true;
    }

    function advance() {
        if (root.holding) {
            if (!root.holding()) {
                if (Date.now() > root.deadline)
                    root.fail(`step ${root.index} took too long`);
                return;
            }
            root.holding = null;
            ticker.stop();
        }

        while (root.index < root.queue.length) {
            const step = root.queue[root.index++];
            const kind = root.kindOf(step);
            if (!kind) {
                root.fail(`step ${root.index} is of a kind this Bioma does not know`);
                return;
            }
            let answer;
            try {
                answer = kind.run(step);
            } catch (error) {
                answer = error.message;
            }
            if (typeof answer === "string") {
                root.fail(`step ${root.index}: ${answer}`);
                return;
            }
            if (answer && typeof answer.until === "function") {
                root.holding = answer.until;
                root.deadline = Date.now() + (answer.timeout || 10000);
                ticker.start();
                return;
            }
        }

        const name = root.running;
        root.running = "";
        root.queue = [];
        root.finished(name);
    }

    // Only while a step waits — a pause, a monitor being switched.
    Timer {
        id: ticker
        interval: 50
        repeat: true
        onTriggered: root.advance()
    }

    // Said, because a macro that stops halfway looks exactly like one that
    // did all it was asked: the desktop is in some state either way.
    function fail(reason) {
        const name = root.running;
        ticker.stop();
        root.holding = null;
        root.running = "";
        root.queue = [];
        console.warn(`Bioma: the quick action "${name}" stopped — ${reason}`);
        Quickshell.execDetached(["notify-send", "--app-name=Bioma", "--icon=dialog-warning",
                                 `${name} stopped`, reason.charAt(0).toUpperCase() + reason.slice(1)]);
        root.failed(name, reason);
    }
}
