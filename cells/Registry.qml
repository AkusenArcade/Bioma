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
        "media": "media/MediaCell.qml",
        "audio": "audio/AudioCell.qml",
        "connectivity": "connectivity/Connectivity.qml",
        "system": "system/SystemCell.qml",
        "dock": "dock/Dock.qml",
        "notifications": "notifications/NotificationCell.qml",
        "launcher": "launcher/Launcher.qml",
        "settings": "settings/SettingsCell.qml",
        "tray": "tray/TrayCell.qml",
        "clipboard": "clipboard/ClipboardCell.qml",
        "keyboard": "keyboard/KeyboardCell.qml",
        "privacy": "privacy/PrivacyCell.qml",
        "timer": "timer/TimerCell.qml"
    })

    // What a cell is called when it is spoken about rather than drawn — the
    // settings cell lists them, and `window_title` is not a name.
    readonly property var names: ({
        "clock": "Clock",
        "window_title": "Window title",
        "workspaces": "Workspaces",
        "vitals": "Vitals",
        "media": "Media",
        "audio": "Audio",
        "utility": "Utility",
        "theme": "Theme",
        "system": "System",
        "dock": "Dock",
        "notifications": "Notifications",
        "connectivity": "Connectivity",
        "launcher": "Launcher",
        "settings": "Settings",
        "tray": "Tray",
        "clipboard": "Clipboard",
        "keyboard": "Keyboard",
        "privacy": "Privacy",
        "timer": "Timer"
    })

    // When each cell is there by itself, said the way the settings cell's
    // Cells page explains it. What the condition *is* lives in the cell; this
    // is the sentence about it, and it is kept beside the name so a new cell
    // brings both in the same line of work.
    readonly property var conditions: ({
        "clock": "When the hour strikes, for that minute.",
        "window_title": "While a window has the focus. With none, there is no title to show.",
        "workspaces": "For five seconds after the workspace changes.",
        "vitals": "While the processor, the memory, the graphics card or the battery is past its alert level, and three seconds after it comes back.",
        "media": "While sound is playing, and four seconds after it stops.",
        "audio": "For five seconds after the volume changes or the sound is muted.",
        "utility": "For five seconds after a screenshot, and for as long as a recording runs and waits to be kept.",
        "theme": "For five seconds after the palette changes.",
        "system": "While a restart is due: the kernel was updated and the one running is no longer installed.",
        "dock": "While the desktop is showing — no windows on this monitor's workspace — and it has something to hold.",
        "notifications": "When a notification arrives, and while many arrive at once.",
        "connectivity": "For five seconds after something connects: the wire, a Wi-Fi network, a Bluetooth device, a VPN, or a print starting.",
        "launcher": "Never by itself: it comes when its keybind asks for it.",
        "settings": "Never by itself: it comes when its keybind asks for it.",
        "tray": "From the moment an application's icon changes state until the pointer has been over it, then five seconds.",
        "clipboard": "For five seconds after something is copied.",
        "keyboard": "For five seconds after the keyboard layout changes.",
        "privacy": "While the microphone, a camera or the screen is being taken, and two seconds after.",
        "timer": "While a timer runs, or waits, paused, to be resumed."
    })

    function conditionOf(type) {
        type = root.canonical(type);
        return root.conditions[type] || "";
    }

    // Old names for cells that were renamed. A block that still says the old
    // one works; the settings cell writes the new one whenever it writes a
    // list. `session` became `system` on 2026-09-23, when the account and the
    // ways to leave were joined by the machine's own description.
    // `sinestesia` became `media` on 2026-10-07, so the cell says what it is
    // about: Sinestesia is the standalone visualiser its band comes from.
    readonly property var aliases: ({ "session": "system", "sinestesia": "media" })

    function canonical(type) {
        return root.aliases[type] || type;
    }

    // Cells that were folded into another and no longer exist on their own.
    // A block that still names one is passed over without a word — the
    // configuration that has it is not wrong, only older — and the settings
    // cell drops it whenever it writes a list. `recording` joined `utility` on
    // 2026-09-27: a layout without it had no way to stop a recording.
    readonly property var retired: ["recording"]

    function isRetired(type) {
        return root.retired.indexOf(type) >= 0;
    }

    // A membrane or floating list with every old name replaced and every
    // retired cell dropped, for the pages that write the layout back.
    function renamed(list) {
        const walk = cells => {
            for (const entry of (cells || []))
                if (entry && entry.type)
                    entry.type = root.canonical(entry.type);
            return (cells || []).filter(entry => !(entry && root.isRetired(entry.type)));
        };
        for (const block of (list || [])) {
            if (block.cells)
                block.cells = walk(block.cells);
            for (const tissue of (block.tissues || []))
                if (tissue.cells)
                    tissue.cells = walk(tissue.cells);
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
    // say, and a sound that is not playing is not a cell.
    //
    // The settings cell shows the ones a cell cannot have dimmed rather than
    // hidden: seeing that the window title is only ever conditional teaches
    // how the shell is built.
    readonly property var visibilities: ({
        "clock": ["always", "conditional"],
        "window_title": ["conditional"],
        "workspaces": ["always", "conditional"],
        "vitals": ["always", "conditional"],
        "media": ["conditional"],
        "audio": ["always", "conditional", "invoked"],
        "utility": ["always", "conditional"],
        "theme": ["always", "conditional"],
        "system": ["always", "conditional"],
        "dock": ["always", "conditional"],
        "notifications": ["always", "conditional"],
        "connectivity": ["always", "conditional"],
        "launcher": ["always", "invoked"],
        "settings": ["always", "invoked"],
        "tray": ["conditional", "always"],
        "clipboard": ["always", "conditional"],
        "keyboard": ["always", "conditional"],
        "privacy": ["conditional"],
        "timer": ["conditional"]
    })

    // A cell whose form changes when it floats, and whose visibility changes
    // with it. The launcher on a membrane is a button, and may be always
    // there; floating it *is* the panel, field and results, and a panel always
    // open would hold the keyboard for good. So floating it is invoked, and
    // its block's word is not asked.
    readonly property var floatingVisibility: ({
        "launcher": "invoked"
    })

    function fixedWhenFloating(type) {
        return root.floatingVisibility[root.canonical(type)] || "";
    }

    function allowsIn(type, kind, floating) {
        const fixed = floating ? root.fixedWhenFloating(type) : "";
        return fixed.length > 0 ? kind === fixed : root.allows(type, kind);
    }

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
        "media": 81,
        "audio": 40,
        "utility": 40,
        "theme": 120,
        "system": 40,
        "dock": 52,
        "notifications": 220,
        "connectivity": 64,
        "launcher": 40,
        "settings": 40,
        "tray": 40,
        "clipboard": 40,
        "keyboard": 76,
        "privacy": 64,
        "timer": 40
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
            if (!entry || entry.enabled === false || root.isRetired(entry.type))
                continue;
            const declared = entry.min_width && entry.min_width.value !== undefined
                           ? entry.min_width.value : root.minimumOf(entry.type);
            wanted.push(declared);
        }
        return Metrics.roomFor(wanted, metrics);
    }

    // The temporal grammar a domain's condition means when its block does not
    // say. A conditional cell is not conditional in the abstract: a window
    // title goes when the focus does, the system cell the moment a restart is
    // no longer due, a
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
        "media": { "enter": 0.02, "exit": 0.005, "confirm": 200, "dwell": 4000 },
        "connectivity": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        "dock": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 400 },
        "notifications": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 400 },
        "tray": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        // For a moment after a copy, as the sign that it was kept.
        "clipboard": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        // For five seconds after the layout changes, saying which it is now.
        "keyboard": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 5000 },
        // While something is taken, and a moment after: a call that drops
        // and rejoins is one call.
        "privacy": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 2000 },
        // Gone when it ends: the notification and the sound say so.
        "timer": { "enter": 1, "exit": 1, "confirm": 0, "dwell": 0 }
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
        if (!file && root.isRetired(type))
            return null;
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
