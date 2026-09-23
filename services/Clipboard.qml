pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// What was copied, kept.
//
// One `wl-paste --watch` for the life of the shell runs `scripts/clip` on every
// change of the clipboard; the script saves what is there — text, or an image —
// as a file in a private directory and says so in one line of JSON, read here.
// The list is kept beside the files, so it survives a restart of the shell; it
// does not survive the shell not running, which is the price of needing
// nothing else installed (Akusen's choice, 2026-09-23).
//
// What a password manager marks sensitive is never saved — the script honours
// wl-clipboard's `CLIPBOARD_STATE` — and copying the same thing again moves it
// to the top rather than keeping it twice.
Singleton {
    id: root

    readonly property string directory:
        `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/bioma/clipboard`
    readonly property string indexPath: root.directory + "/history.json"

    readonly property int keep: Config.get("clipboard.history", 50)

    // Newest first: [{ "file", "mime", "hash", "preview", "time", "bytes" }].
    property var entries: []

    // Emitted for every copy that was kept, for the cell's condition.
    signal copied

    // ---- Watching ----------------------------------------------------------------

    Process {
        id: watcher

        command: ["wl-paste", "--watch", Quickshell.shellPath("scripts/clip"), "store", root.directory]
        running: false

        stdout: SplitParser {
            onRead: line => {
                let entry = null;
                try {
                    entry = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root.take(entry);
            }
        }

        onExited: again.start()
    }

    // If the watcher dies — the compositor restarted, say — it comes back.
    Timer {
        id: again
        interval: 3000
        onTriggered: watcher.running = true
    }

    function take(entry) {
        if (!entry || !entry.file)
            return;
        const doomed = [];
        const kept = [entry];
        for (const old of root.entries) {
            if (old.hash === entry.hash)
                doomed.push(old.file);
            else
                kept.push(old);
        }
        while (kept.length > root.keep)
            doomed.push(kept.pop().file);
        root.entries = kept;
        root.forget(doomed);
        root.save();
        root.copied();
    }

    // ---- Keeping the list ---------------------------------------------------------

    FileView {
        id: index
        path: root.indexPath
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (Array.isArray(saved))
                    root.entries = saved.concat(root.entries.filter(e => !saved.some(s => s.hash === e.hash)));
            } catch (e) {}
            watcher.running = true;
            sweeping.restart();
        }
        onLoadFailed: {
            mkdir.running = true;
        }
    }

    // A first run has no directory; it is made private before anything is in it.
    Process {
        id: mkdir
        command: ["bash", "-c", "mkdir -p \"$1\" && chmod 700 \"$1\"", "mkdir", root.directory]
        onExited: watcher.running = true
    }

    function save() {
        index.setText(JSON.stringify(root.entries));
        sweeping.restart();
    }

    // One copy can reach the watcher twice — wl-paste reports the offer and the
    // selection a millisecond apart — and the second file is never in the list.
    // So what the list does not name is swept, a moment after the list settles:
    // a file of somebody's clipboard that nothing shows is a file nobody can
    // delete.
    Timer {
        id: sweeping
        interval: Timing.debounce
        onTriggered: {
            sweeper.command = ["bash", "-c",
                "cd \"$1\" || exit 0; shift; for f in [0-9]*; do "
                + "[ -e \"$f\" ] || continue; keep=0; "
                + "for k in \"$@\"; do [ \"$k\" = \"$f\" ] && keep=1 && break; done; "
                + "[ $keep = 1 ] || rm -f -- \"$f\"; done",
                "sweep", root.directory].concat(root.entries.map(e => String(e.file).split("/").pop()));
            sweeper.running = true;
        }
    }

    Process { id: sweeper }

    function forget(files) {
        if (files.length === 0)
            return;
        Quickshell.execDetached(["rm", "-f", "--"].concat(files));
    }

    // ---- Acting --------------------------------------------------------------------

    // Put an entry back on the clipboard. The watcher sees it arrive and moves
    // it to the top, which is where something just copied belongs.
    function restore(entry) {
        if (!entry)
            return;
        Quickshell.execDetached(["bash", "-c", "wl-copy --type \"$1\" < \"$2\"", "restore",
                                 entry.mime, entry.file]);
    }

    function remove(entry) {
        root.entries = root.entries.filter(e => e.hash !== entry.hash);
        root.forget([entry.file]);
        root.save();
    }

    function clear() {
        root.forget(root.entries.map(e => e.file));
        root.entries = [];
        root.save();
    }

    function isImage(entry) {
        return entry && String(entry.mime).startsWith("image/");
    }

    // How long ago, said the machine's way.
    function age(entry, now) {
        const seconds = Math.max(0, Math.round((now - entry.time) / 1000));
        if (seconds < 60)
            return "NOW";
        const minutes = Math.round(seconds / 60);
        if (minutes < 60)
            return `${minutes} MIN`;
        const hours = Math.round(minutes / 60);
        if (hours < 24)
            return `${hours} H`;
        return `${Math.round(hours / 24)} D`;
    }
}
