pragma Singleton

import QtQuick
import Quickshell
// For `ProcessContext`: `execDetached` takes one only where Quickshell.Io is
// imported, and refuses the plain object otherwise.
import Quickshell.Io

// Which application a name belongs to.
//
// Two callers need this and neither gets a clean answer from the system: a
// compositor reports an `app_id` that may be a class name, and `ps` reports an
// executable truncated to fifteen characters — `xwayland-satell`,
// `steamwebhelp`, `zen-bin`. Quickshell's own lookup is strict and answers most
// of them with nothing.
//
// So: ask it first, then try the obvious variants, then look through the
// desktop files for one that recognises the name. Answers are cached, because
// the process list asks the same sixty questions every few seconds and the
// answer only changes when an application is installed.
Singleton {
    id: root

    // Quickshell's models fill on their **first property binding**, not on
    // first access, and this is the file that reads them — so the list is
    // bound here rather than left to whichever cell happens to ask first.
    //
    // It also settles what to do when it fills late. Answers are cached,
    // misses included, because the process list asks the same sixty questions
    // every few seconds; but a miss recorded while the list was still empty is
    // not an answer, it is the absence of one. So the cache is emptied
    // whenever the set of applications changes — which is also what happens
    // when one is installed.
    readonly property var entries: DesktopEntries.applications?.values ?? []

    onEntriesChanged: root.cache = ({})

    // Start an application, with whatever the shell adds to its environment —
    // the proxy, while one is on. A desktop entry's own `execute()` takes no
    // environment, so the entry is run by its command; one that runs in a
    // terminal is left to the entry, which knows how to find the terminal.
    function run(entry, environment) {
        if (!entry)
            return;
        const extra = environment || ({});
        if (entry.runInTerminal || Object.keys(extra).length === 0 || !entry.command
                || entry.command.length === 0) {
            entry.execute();
            return;
        }
        const context = { "command": entry.command, "environment": extra };
        if (entry.workingDirectory && entry.workingDirectory.length > 0)
            context.workingDirectory = entry.workingDirectory;
        Quickshell.execDetached(context);
    }

    property var cache: ({})

    function normalise(name) {
        return (name || "")
            .toLowerCase()
            // Wrappers and packaging leave these behind.
            .replace(/\.(exe|bin|sh|py)$/, "")
            .replace(/[-_](bin|wrapped|real|desktop|gtk|qt|electron)$/, "");
    }

    function search(name) {
        const wanted = root.normalise(name);
        if (wanted.length < 2)
            return null;

        let direct = DesktopEntries.heuristicLookup(name) || DesktopEntries.heuristicLookup(wanted);
        if (direct)
            return direct;

        // A truncated executable is a prefix of the real thing, so the match
        // has to go both ways — but never on a fragment so short that it would
        // match half the menu.
        for (const entry of root.entries) {
            const id = (entry.id || "").toLowerCase();
            const label = (entry.name || "").toLowerCase();
            const startup = (entry.startupClass || "").toLowerCase();

            if (id === wanted || label === wanted || startup === wanted)
                return entry;
            if (wanted.length >= 4 && (id.indexOf(wanted) >= 0 || startup.indexOf(wanted) >= 0
                                       || label.indexOf(wanted) >= 0 || wanted.indexOf(label) >= 0))
                return entry;
        }
        return null;
    }

    function entryFor(name) {
        if (!name)
            return null;
        if (root.cache[name] === undefined)
            root.cache[name] = root.search(name);
        return root.cache[name];
    }

    // The path to draw, or an empty string when nothing answers — in which case
    // the caller draws the neutral glyph rather than somebody else's logo.
    function iconFor(name) {
        const entry = root.entryFor(name);
        return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "";
    }
}
