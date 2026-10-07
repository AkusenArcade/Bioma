pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// What the browsers are downloading, and how fast.
//
// `scripts/downloads` watches the downloads folder with inotify and reports
// the partial files that are growing — Firefox's `.part`, Chromium's
// `.crdownload` — with the bytes so far and the bytes a second. Neither
// browser writes the total anywhere outside itself, so there is no fraction:
// how much has come and how fast it is coming are what can be known.
//
// It runs while something holds it — a download cell.
Singleton {
    id: root

    property var holders: []
    readonly property bool active: root.holders.length > 0

    function hold(owner, wanted) {
        const held = root.holders.indexOf(owner) >= 0;
        if (wanted && !held)
            root.holders = root.holders.concat([owner]);
        else if (!wanted && held)
            root.holders = root.holders.filter(h => h !== owner);
    }

    // [{ "path", "name", "size", "rate" }], bytes and bytes a second.
    property var files: []
    readonly property bool downloading: root.files.length > 0
    readonly property real rate: root.files.reduce((sum, file) => sum + file.rate, 0)

    Process {
        id: watch
        command: ["setpriv", "--pdeathsig", "TERM", Quickshell.shellPath("scripts/downloads")]
        running: root.active
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.files = JSON.parse(line);
                } catch (e) {}
            }
        }
        onExited: {
            root.files = [];
            if (root.active)
                rewatch.start();
        }
    }

    Timer {
        id: rewatch
        interval: 5000
        onTriggered: watch.running = root.active
    }

    // 2.4 MB/s, 812 KB/s, 40 B/s — a measurement, in the technical voice.
    function bytes(value) {
        if (value >= 1024 * 1024 * 1024)
            return `${(value / 1024 / 1024 / 1024).toFixed(1)} GB`;
        if (value >= 1024 * 1024)
            return `${(value / 1024 / 1024).toFixed(value >= 10 * 1024 * 1024 ? 0 : 1)} MB`;
        if (value >= 1024)
            return `${Math.round(value / 1024)} KB`;
        return `${Math.round(value)} B`;
    }
}
