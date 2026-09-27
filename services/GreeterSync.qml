pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Keeps the greeter's copy of the desktop current.
//
// The greeter runs as another user before anyone is logged in, from a copy in
// /var/lib/bioma-greeter (see scripts/greeter-sync). This watches what that copy
// is made of — the configuration, the wallpaper's state, the palette, the
// user's niri outputs, keyboard and cursor, their picture — and runs the sync a
// moment after any of it changes, and once when the shell starts, so a new
// version of Bioma reaches the greeter too.
//
// Without the directory there is no greeter to keep: the sync finds nowhere to
// write and stops there, and `synced` stays false. The directory is created
// once, by hand, with sudo, when the greeter is installed (README).
Singleton {
    id: root

    readonly property string directory: Quickshell.env("BIOMA_GREETER_DIR")
        || Config.get("greeter.directory", "/var/lib/bioma-greeter")
    readonly property string script: Qt.resolvedUrl("../scripts/greeter-sync").toString().replace("file://", "")

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"

    readonly property var watched: [
        `${root.configHome}/bioma/override.json`,
        `${root.configHome}/bioma/wallpaper.json`,
        `${root.configHome}/bioma/generated/palette.json`,
        `${root.configHome}/niri/outputs.kdl`,
        `${root.configHome}/niri/bioma-keyboard.kdl`,
        `${root.configHome}/niri/bioma-cursor.kdl`,
        `/var/lib/AccountsService/icons/${Quickshell.env("USER")}`
    ]

    // Whether the last sync went through. False with the directory missing,
    // which is the ordinary state of a machine without Bioma's greeter.
    property bool synced: false

    Instantiator {
        model: root.watched

        delegate: FileView {
            required property string modelData
            path: modelData
            watchChanges: true
            printErrors: false
            onFileChanged: {
                reload();
                root.schedule();
            }
        }
    }

    function schedule() {
        settle.restart();
    }

    // Changes come in bursts — a new wallpaper rewrites its state and then the
    // palette — and one copy after the last of them is enough.
    Timer {
        id: settle
        interval: Timing.settle
        running: true
        onTriggered: {
            if (sync.running) {
                settle.restart();
                return;
            }
            sync.running = true;
        }
    }

    Process {
        id: sync
        command: [root.script, root.directory]
        onExited: code => root.synced = code === 0
    }
}
