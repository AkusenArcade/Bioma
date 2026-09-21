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
        "sinestesia": "sinestesia/Sinestesia.qml"
    })

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
