pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Files in the home, found by name.
//
// No index of its own and none of the system's: plocate's daily database
// leaves out `/home` wherever it is a subvolume of its own (it is on
// Akusen's), and an index kept here would be memory spent all day for a few
// searches. `fd` walks the home instead, every time — on his 518 GB it answers
// in about 50 ms, because it skips what is hidden and what a `.gitignore`
// excludes: caches, Wine prefixes, build trees, the noise nobody searches
// for. An `.ignore` or `.fdignore` in the home tunes it further, and that is
// fd's to read, not ours (Akusen's choice, 2026-10-04).
//
// One search at a time. A newer query does not wait for the older one: the
// older is stopped and what it had found is thrown away, because each walk
// carries the query it was started for and only the one still wanted lands.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // How many fd may hand back before it stops walking. The best are chosen
    // from these, so it is wider than what is shown — but a query that
    // matches thousands has said too little, and the walk stops at this many.
    readonly property int gathered: 300

    // How many are kept after ranking.
    readonly property int kept: 20

    // Below this many letters a search over a whole home is a list of
    // everything, and the launcher's two letters and Enter belong to
    // applications.
    readonly property int shortest: 3

    // What is being asked for, and what has come back for it.
    property string query: ""
    property string answered: ""

    // [{ "path", "name", "folder", "dir", "at", "icon" }], best first.
    property var results: []

    // True between asking and the answer landing: a launcher that said
    // "nothing" while fd was still walking would be saying it too early.
    readonly property bool searching: root.wanted().length > 0 && root.answered !== root.query

    function wanted() {
        const words = root.query.trim().toLowerCase().split(/\s+/).filter(w => w.length > 0);
        return words.join(" ").length >= root.shortest ? words : [];
    }

    onQueryChanged: {
        if (root.wanted().length === 0) {
            settle.stop();
            root.stopWalking();
            root.results = [];
            root.answered = root.query;
            return;
        }
        settle.restart();
    }

    // A walk per keystroke would start and kill fd six times for one word.
    Timer {
        id: settle
        interval: Timing.search
        onTriggered: root.walk()
    }

    property var walking: null

    function stopWalking() {
        if (root.walking) {
            root.walking.running = false;
            root.walking = null;
        }
    }

    function walk() {
        root.stopWalking();
        const words = root.wanted();
        if (words.length === 0)
            return;

        // The words in the order typed, each where it falls in the name.
        const pattern = words.map(w => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*");
        root.walking = walker.createObject(root, {
            "asked": root.query,
            "command": ["fd", "--color", "never", "--ignore-case", "--absolute-path",
                        "--max-results", String(root.gathered), "--", pattern, root.home]
        });
        root.walking.running = true;
    }

    Component {
        id: walker

        Process {
            id: walk

            property string asked: ""

            stdout: StdioCollector {
                onStreamFinished: root.land(walk.asked, text)
            }

            onExited: walk.destroy()
        }
    }

    function land(asked, text) {
        if (asked !== root.query)
            return;

        const words = root.wanted();
        const found = [];
        for (const line of text.split("\n")) {
            if (line.length === 0)
                continue;
            const entry = root.describe(line, words);
            if (entry)
                found.push(entry);
        }
        found.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));

        root.results = found.slice(0, root.kept);
        root.answered = asked;
        root.walking = null;
    }

    // ---- Ranking -----------------------------------------------------------------

    // fd says only that a name matches, in the order its threads happened to
    // finish. The order here is the one a person expects: the name that
    // starts with what was typed, then the one where a word does, then the
    // nearest to the home — a file two folders down was put there to be found,
    // one nine folders down was put there by a program.
    function describe(line, words) {
        const dir = line.endsWith("/");
        const path = dir ? line.slice(0, -1) : line;
        const cut = path.lastIndexOf("/");
        const name = path.slice(cut + 1);
        const lowered = name.toLowerCase();

        const at = [];
        let from = 0;
        let score = 0;
        for (const word of words) {
            const found = lowered.indexOf(word, from);
            if (found < 0)
                return null;
            for (let i = 0; i < word.length; i++)
                at.push(found + i);
            if (found === 0)
                score += 8;
            else if (/[\s._\-]/.test(lowered[found - 1]))
                score += 4;
            from = found + word.length;
        }

        const stem = dir ? lowered : lowered.replace(/\.[^.]+$/, "");
        if (stem === words.join(" "))
            score += 10;

        const below = path.slice(root.home.length).split("/").length - 2;
        score -= below * 0.75;
        score -= name.length * 0.02;

        const folder = path.slice(0, cut);
        return {
            "path": path,
            "name": name,
            "folder": folder.startsWith(root.home) ? "~" + folder.slice(root.home.length) : folder,
            "dir": dir,
            "at": at,
            "icon": root.iconFor(lowered, dir),
            "score": score
        };
    }

    // The theme's own icon for the kind of file, by the name it ends in. Only
    // the generic names every icon theme carries: a theme that lacks one
    // leaves the row the launcher's neutral glyph.
    readonly property var kinds: ({
        "pdf": "application-pdf",
        "png": "image-x-generic", "jpg": "image-x-generic", "jpeg": "image-x-generic",
        "gif": "image-x-generic", "webp": "image-x-generic", "svg": "image-x-generic",
        "bmp": "image-x-generic", "tif": "image-x-generic", "tiff": "image-x-generic",
        "heic": "image-x-generic", "avif": "image-x-generic", "kra": "image-x-generic",
        "xcf": "image-x-generic", "psd": "image-x-generic",
        "mp3": "audio-x-generic", "flac": "audio-x-generic", "ogg": "audio-x-generic",
        "opus": "audio-x-generic", "wav": "audio-x-generic", "m4a": "audio-x-generic",
        "aac": "audio-x-generic",
        "mp4": "video-x-generic", "mkv": "video-x-generic", "webm": "video-x-generic",
        "mov": "video-x-generic", "avi": "video-x-generic",
        "zip": "package-x-generic", "tar": "package-x-generic", "gz": "package-x-generic",
        "xz": "package-x-generic", "zst": "package-x-generic", "7z": "package-x-generic",
        "rar": "package-x-generic", "bz2": "package-x-generic",
        "odt": "x-office-document", "doc": "x-office-document", "docx": "x-office-document",
        "rtf": "x-office-document",
        "ods": "x-office-spreadsheet", "xls": "x-office-spreadsheet",
        "xlsx": "x-office-spreadsheet", "csv": "x-office-spreadsheet",
        "odp": "x-office-presentation", "ppt": "x-office-presentation",
        "pptx": "x-office-presentation",
        "html": "text-html", "htm": "text-html",
        "sh": "text-x-script", "py": "text-x-script", "fish": "text-x-script"
    })

    function iconFor(lowered, dir) {
        if (dir)
            return "folder";
        const dot = lowered.lastIndexOf(".");
        const kind = dot > 0 ? root.kinds[lowered.slice(dot + 1)] : undefined;
        return kind ?? "text-x-generic";
    }

    // ---- Acting on one -----------------------------------------------------------

    // Opened by whatever the desktop says opens it, started the way the
    // launcher starts an application — as a user service of its own, so it
    // neither inherits the shell's nice nor lives in its cgroup. See
    // `scripts/launch`.
    function open(path, environment) {
        Quickshell.execDetached({
            "command": [Quickshell.shellPath("scripts/launch"), "--id", "xdg-open",
                        "--", "xdg-open", path],
            "environment": environment || ({})
        });
    }

    // Shown where it lives, selected, by whichever file manager answers the
    // freedesktop call; the folder opened plainly when none does.
    //
    // The path travels as a URI inside a GVariant string literal, so a quote
    // in a filename is percent-encoded rather than left to end the literal.
    function reveal(path, environment) {
        const uri = "file://" + encodeURI(path).replace(/'/g, "%27");
        const folder = path.slice(0, path.lastIndexOf("/")) || "/";
        Quickshell.execDetached({
            "command": ["bash", "-c",
                'gdbus call --session --dest org.freedesktop.FileManager1 '
                + '--object-path /org/freedesktop/FileManager1 '
                + '--method org.freedesktop.FileManager1.ShowItems "[\'$1\']" "" >/dev/null 2>&1 '
                + '|| exec "$2" --id xdg-open -- xdg-open "$3"',
                "reveal", uri, Quickshell.shellPath("scripts/launch"), folder],
            "environment": environment || ({})
        });
    }
}
