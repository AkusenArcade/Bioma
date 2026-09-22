pragma Singleton

import QtQuick
import Quickshell

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
