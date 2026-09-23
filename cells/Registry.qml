pragma Singleton

import QtQuick
import Quickshell
import qs.core

// Which file is which cell.
//
// Adding a cell costs one config block and one line here — never a structural
// change anywhere else. A type the registry does not know is a warning and a
// cell that does not appear, not a broken membrane.
Singleton {
    id: root

    readonly property var files: ({
        "clock": "clock/Clock.qml",
        "window_title": "window_title/WindowTitle.qml",
        "workspaces": "workspaces/Workspaces.qml",
        "vitals": "vitals/Vitals.qml",
        "theme": "theme/ThemeCell.qml",
        "utility": "utility/Utility.qml",
        "recording": "recording/Recording.qml",
        "sinestesia": "sinestesia/Sinestesia.qml",
        "audio": "audio/AudioCell.qml",
        "connectivity": "connectivity/Connectivity.qml",
        "system": "system/SystemCell.qml",
        "dock": "dock/Dock.qml",
        "notifications": "notifications/NotificationCell.qml",
        "launcher": "launcher/Launcher.qml",
        "settings": "settings/SettingsCell.qml",
        "tray": "tray/TrayCell.qml",
        "clipboard": "clipboard/ClipboardCell.qml",
        "keyboard": "keyboard/KeyboardCell.qml"
    })

    // What a cell is called when it is spoken about rather than drawn — the
    // settings cell lists them, and `window_title` is not a name.
    readonly property var names: ({
        "clock": "Clock",
        "window_title": "Window title",
        "workspaces": "Workspaces",
        "vitals": "Vitals",
        "sinestesia": "Sinestesia",
        "audio": "Audio",
        "utility": "Utility",
        "theme": "Theme",
        "system": "System",
        "dock": "Dock",
        "notifications": "Notifications",
        "connectivity": "Connectivity",
        "recording": "Recording",
        "launcher": "Launcher",
        "settings": "Settings",
        "tray": "Tray",
        "clipboard": "Clipboard",
        "keyboard": "Keyboard"
    })

    // Old names for cells that were renamed. A block that still says the old
    // one works; the settings cell writes the new one whenever it writes a
    // list. `session` became `system` on 2026-09-23, when the account and the
    // ways to leave were joined by the machine's own description.
    readonly property var aliases: ({ "session": "system" })

    function canonical(type) {
        return root.aliases[type] || type;
    }

    // A membrane or floating list with every old name replaced, for the pages
    // that write the layout back.
    function renamed(list) {
        const walk = cells => {
            for (const entry of (cells || []))
                if (entry && entry.type)
                    entry.type = root.canonical(entry.type);
        };
        for (const block of (list || [])) {
            walk(block.cells);
            for (const tissue of (block.tissues || []))
                walk(tissue.cells);
        }
        return list;
    }

    function nameOf(type) {
        type = root.canonical(type);
        return root.names[type] || type;
    }

    // Which visibilities a cell can actually wear. Every cell can be invoked —
    // a shortcut opens it whatever it is — so this is about whether it exists
    // *without* being invoked: a window title with no window has nothing to
    // say, and a recording that is not running is not a cell.
    //
    // The settings cell shows the ones a cell cannot have dimmed rather than
    // hidden: seeing that the window title is only ever conditional teaches
    // how the shell is built.
    readonly property var visibilities: ({
        "clock": ["always", "conditional"],
        "window_title": ["conditional"],
        "workspaces": ["always", "conditional"],
        "vitals": ["always", "conditional"],
        "sinestesia": ["conditional"],
        "audio": ["always", "conditional", "invoked"],
        "utility": ["always", "conditional"],
        "theme": ["always", "conditional"],
        "system": ["always", "conditional"],
        "dock": ["always", "conditional"],
        "notifications": ["conditional"],
        "connectivity": ["always", "conditional"],
        "recording": ["conditional"],
        "launcher": ["always", "invoked"],
        "settings": ["always", "invoked"],
        "tray": ["conditional", "always"],
        "clipboard": ["always", "conditional"],
        "keyboard": ["always", "conditional"]
    })

    // The narrowest a cell can be and still be itself, in logical units at
    // the normal step. A block may raise it with `min_width`; nothing lowers
    // it below what the cell needs to be read.
    //
    // It is here rather than in the cells because the settings cell has to
    // answer "does this fit?" **before** the cell exists — a structure page
    // that let somebody add a seventh cell to a band that holds six, and then
    // showed them a membrane with cells missing from it, would be a page that
    // breaks the shell politely.
    readonly property var minimums: ({
        "clock": 72,
        "window_title": 0,
        "workspaces": 96,
        "vitals": 90,
        "sinestesia": 81,
        "audio": 40,
        "utility": 40,
        "theme": 120,
        "system": 40,
        "dock": 52,
        "notifications": 220,
        "connectivity": 64,
        "recording": 40,
        "launcher": 40,
        "settings": 40,
        "tray": 40,
        "clipboard": 40,
        "keyboard": 48
    })

    function minimumOf(type) {
        type = root.canonical(type);
        const value = root.minimums[type];
        return value === undefined ? 24 : value;
    }

    // What a band would have to grant to hold these cells at their narrowest.
    // `cells` is a list of configuration blocks, the way a membrane declares
    // them, so a page can ask about a list it has not built yet.
    function roomFor(cells, metrics) {
        const wanted = [];
        for (const entry of (cells || [])) {
            if (!entry || entry.enabled === false)
                continue;
            const declared = entry.min_width && entry.min_width.value !== undefined
                           ? entry.min_width.value : root.minimumOf(entry.type);
            wanted.push(declared);
        }
        return Metrics.roomFor(wanted, metrics);
    }

    // The temporal grammar a domain's condition means when its block does not
    // say. A conditional cell is not conditional in the abstract: a window
    // title goes when the focus does, a recording goes the moment it stops, a
    // sound level needs a fraction of a second to be believed and four to be
    // forgotten. Leaving them all at one generic figure made the window title
    // sit there for two seconds with nothing to name — Akusen, 2026-09-22.
    //
    // These are the figures `config/default.json` ships; a block that names
    // its own still wins.
    // Akusen's conditions, 2026-09-23: the clock on the hour, for its minute;
    // the workspaces, audio and connectivity for five seconds after something
    // changed; vitals while an indicator is critical; the tray from a change
    // of state until the pointer has been over it, then five seconds.
    readonly property var grammar: ({
        "clock": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 0 },
        "workspaces": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        // Critical is the alert threshold every indicator is coloured by, with
        // hysteresis under it and a second to be believed: a spike that comes
        // and goes is not the machine being in trouble.
        "vitals": { "enter": 0.8, "exit": 0.75, "confirm": 1000, "dwell": 3000 },
        "audio": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        // Proposed on the same day and kept: the theme after the palette
        // changes, the utility after a screenshot, the system while a restart
        // is due, the dock while the desktop is showing.
        "theme": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        "utility": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        "system": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 0 },
        "window_title": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 200 },
        "sinestesia": { "enter": 0.02, "exit": 0.005, "confirm": 200, "dwell": 4000 },
        "recording": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 0 },
        "connectivity": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        "dock": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 400 },
        "notifications": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 400 },
        "tray": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        // For a moment after a copy, as the sign that it was kept.
        "clipboard": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        // For five seconds after the layout changes, saying which it is now.
        "keyboard": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 }
    })

    // Boolean, appearing promptly and leaving slowly, for a domain with
    // nothing more particular to say.
    readonly property var defaultGrammar: ({ "enter": 1, "exit": 1, "confirm": 0, "dwell": 2000 })

    function grammarOf(type) {
        type = root.canonical(type);
        const own = root.grammar[type];
        return own === undefined ? root.defaultGrammar : own;
    }

    function allows(type, kind) {
        type = root.canonical(type);
        const list = root.visibilities[type];
        return list === undefined || list.indexOf(kind) >= 0;
    }

    property var cache: ({})

    function component(type) {
        type = root.canonical(type);
        const file = root.files[type];
        if (!file) {
            console.info(`Bioma: cell "${type}" is declared in the configuration but not implemented yet`);
            return null;
        }

        if (!root.cache[type]) {
            const created = Qt.createComponent(Qt.resolvedUrl(file), Component.PreferSynchronous);
            if (created.status === Component.Error) {
                console.warn(`Bioma: cell "${type}" failed to compile — ${created.errorString()}`);
                return null;
            }
            root.cache[type] = created;
        }
        return root.cache[type];
    }
}
