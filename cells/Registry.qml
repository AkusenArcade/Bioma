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
        "session": "session/SessionCell.qml",
        "dock": "dock/Dock.qml",
        "notifications": "notifications/NotificationCell.qml",
        "launcher": "launcher/Launcher.qml",
        "settings": "settings/SettingsCell.qml"
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
        "session": "Session",
        "dock": "Dock",
        "notifications": "Notifications",
        "connectivity": "Connectivity",
        "recording": "Recording",
        "launcher": "Launcher",
        "settings": "Settings"
    })

    function nameOf(type) {
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
        "clock": ["always", "invoked"],
        "window_title": ["conditional"],
        "workspaces": ["always", "invoked"],
        "vitals": ["always", "invoked"],
        "sinestesia": ["conditional"],
        "audio": ["always", "conditional", "invoked"],
        "utility": ["always", "invoked"],
        "theme": ["always", "invoked"],
        "session": ["always", "invoked"],
        "dock": ["always", "conditional"],
        "notifications": ["conditional"],
        "connectivity": ["always", "conditional"],
        "recording": ["conditional"],
        "launcher": ["always", "invoked"],
        "settings": ["always", "invoked"]
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
        "session": 40,
        "dock": 52,
        "notifications": 220,
        "connectivity": 64,
        "recording": 40,
        "launcher": 40,
        "settings": 40
    })

    function minimumOf(type) {
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

    function allows(type, kind) {
        const list = root.visibilities[type];
        return list === undefined || list.indexOf(kind) >= 0;
    }

    property var cache: ({})

    function component(type) {
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
