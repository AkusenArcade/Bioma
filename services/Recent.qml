pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The files used lately, as the desktop records them.
//
// `recently-used.xbel` is freedesktop's list: GTK applications, the file
// chooser portal and the file manager add to it whenever a file is opened or
// saved through them. It is read as it is written — watched, never polled —
// and only while something holds the service: the sediment organism.
//
// What is kept is files: folders are places rather than work, and a file that
// is no longer there is not shown as though it were. The list records both,
// so it is filtered: folders by their type, the missing by asking the disk
// once whenever the list changes.
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

    // The most recent first: [{ "path", "name", "mime", "at" }], `at` in
    // milliseconds — the latest of when it was added, modified or visited.
    property var files: []
    property bool loaded: false

    readonly property int kept: 60

    readonly property string path: `${Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"}/recently-used.xbel`

    FileView {
        id: list

        path: root.active ? root.path : ""
        watchChanges: true
        printErrors: false
        onFileChanged: list.reload()
        onLoaded: root.read(list.text())
        onLoadFailed: {
            root.files = [];
            root.loaded = true;
        }
    }

    function entities(text) {
        return text.replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&lt;/g, "<")
                   .replace(/&gt;/g, ">").replace(/&amp;/g, "&");
    }

    // Enough of the format to read it: each bookmark's address and times, and
    // the type inside it. Not a general XML reader, and it need not be — the
    // file is written by one library, always the same way.
    function read(text) {
        const found = [];
        const bookmarks = text.split("<bookmark ").slice(1);
        for (const chunk of bookmarks) {
            const href = /href="([^"]*)"/.exec(chunk);
            if (!href || !href[1].startsWith("file://"))
                continue;
            const mime = /mime-type type="([^"]*)"/.exec(chunk);
            const type = mime ? mime[1] : "";
            if (type === "inode/directory")
                continue;
            let at = 0;
            for (const key of ["added", "modified", "visited"]) {
                const stamp = new RegExp(`${key}="([^"]*)"`).exec(chunk.slice(0, chunk.indexOf(">")));
                if (stamp)
                    at = Math.max(at, Date.parse(stamp[1]) || 0);
            }
            let path = root.entities(href[1]).slice("file://".length);
            try {
                path = decodeURIComponent(path);
            } catch (e) {
                continue;
            }
            found.push({ "path": path, "name": path.slice(path.lastIndexOf("/") + 1), "mime": type, "at": at });
        }
        found.sort((a, b) => b.at - a.at);
        root.check(found.slice(0, root.kept));
    }

    // Which of them are still there: one process, asked once per change of
    // the list, answering with the paths that exist.
    property var pending: []
    property var queued: null

    function check(candidates) {
        // A list that changed again while the last one was being checked
        // is checked when that answer is in.
        if (checker.running) {
            root.queued = candidates;
            return;
        }
        if (candidates.length === 0) {
            root.files = [];
            root.loaded = true;
            return;
        }
        root.pending = candidates;
        checker.command = ["sh", "-c", "for f; do [ -e \"$f\" ] && printf '%s\\n' \"$f\"; done", "check"]
                          .concat(candidates.map(c => c.path));
        checker.running = true;
    }

    Process {
        id: checker

        stdout: StdioCollector {
            onStreamFinished: {
                const there = new Set(this.text.split("\n").filter(line => line.length > 0));
                root.files = root.pending.filter(c => there.has(c.path));
                root.pending = [];
                root.loaded = true;
                if (root.queued !== null) {
                    const next = root.queued;
                    root.queued = null;
                    root.check(next);
                }
            }
        }
    }
}
