pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Printers, as CUPS keeps them.
//
// CUPS says nothing unless it is asked to, so `scripts/printers watch` asks
// once — a subscription with `dbus://` as its recipient, found again on the next
// start rather than made twice — and then relays every signal cupsd emits on the
// system bus. One process for the life of the shell; a burst of signals is one
// change, and a change is one `lpstat` read. Nothing polls.
//
// The network is looked at only when asked: a search is DNS-SD for a few
// seconds, and a printer found is added as a driverless queue (IPP Everywhere),
// which is what every network printer of the last decade speaks.
Singleton {
    id: root

    // Without CUPS there is nothing to show, and the well does not appear.
    property bool available: false

    // [{ "queue", "name", "state", "uri", "isDefault", "jobs" }], state being
    // "idle", "printing" or "stopped".
    property var printers: []

    // [{ "id", "queue" }] — every job not finished yet, anyone's.
    property var jobs: []

    property string defaultQueue: ""

    // The machine is printing: something is being printed or waits its turn
    // on a queue that will get to it. A job left on a stopped queue waits for
    // a hand, not for the printer, and is not printing.
    readonly property var printingQueues: {
        const out = [];
        for (const job of root.jobs) {
            const printer = root.printers.find(p => p.queue === job.queue);
            if (printer && printer.state !== "stopped" && out.indexOf(job.queue) < 0)
                out.push(job.queue);
        }
        return out;
    }
    readonly property bool printing: root.printingQueues.length > 0

    // What a search found that is not a queue already: [{ "uri", "name", "uuid" }].
    property var found: []
    property bool searching: finder.running

    // A queue being added, removed or made the default, until CUPS says.
    property string working: ""

    // The last thing CUPS refused, in its words.
    property string error: ""

    readonly property string script: Quickshell.shellPath("scripts/printers")

    // ---- Reading -------------------------------------------------------------

    function refresh() {
        if (reader.running) {
            again.restart();
            return;
        }
        reader.running = true;
    }

    Process {
        id: reader

        command: [root.script, "state"]

        stdout: StdioCollector {
            onStreamFinished: {
                let fallback = "";
                const printers = [];
                const jobs = [];
                for (const line of this.text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "default" && f.length >= 2)
                        fallback = f[1];
                    else if (f[0] === "printer" && f.length >= 5)
                        printers.push({ "queue": f[1], "state": f[2], "name": f[3] || f[1], "uri": f[4] });
                    else if (f[0] === "job" && f.length >= 3)
                        jobs.push({ "id": f[1], "queue": f[2] });
                }
                for (const printer of printers) {
                    printer.isDefault = printer.queue === fallback;
                    printer.jobs = jobs.filter(j => j.queue === printer.queue).length;
                }
                printers.sort((a, b) => a.name.localeCompare(b.name));
                root.defaultQueue = fallback;
                root.printers = printers;
                root.jobs = jobs;
                root.available = true;
                root.found = root.unknown(root.found);
                root.settleDefault();
            }
        }

        onExited: code => { if (code !== 0) root.available = false; }
    }

    Timer {
        id: again
        interval: Timing.debounce
        onTriggered: root.refresh()
    }

    // cupsd's signals, relayed. Any line is news; the read that follows says
    // what the news was.
    Process {
        id: watch
        command: [root.script, "watch"]
        running: true
        stdout: SplitParser {
            onRead: again.restart()
        }
        onExited: rewatch.start()
    }

    // If CUPS or the bus restarts, so does the watch — a little later.
    Timer {
        id: rewatch
        interval: 5000
        onTriggered: watch.running = true
    }

    Component.onCompleted: root.refresh()

    // ---- The network ---------------------------------------------------------

    // The same printer answers on several addresses and under two schemes; a
    // queue already pointing at it is not news either.
    function where(uri) {
        return String(uri).replace(/^[a-z]+:\/\//, "").replace(/\.?:631\//, "/").toLowerCase();
    }

    function unknown(list) {
        const known = root.printers.map(p => root.where(p.uri));
        return list.filter(f => known.indexOf(root.where(f.uri)) < 0);
    }

    function search() {
        if (finder.running)
            return;
        root.error = "";
        root.found = [];
        finder.running = true;
    }

    function stopSearching() {
        finder.running = false;
    }

    Process {
        id: finder
        command: [root.script, "find", "5"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "found" && f.length >= 3)
                        out.push({ "uri": f[1], "name": f[2] || f[1], "uuid": f[3] || "" });
                }
                root.found = root.unknown(out);
            }
        }
    }

    // ---- Acting --------------------------------------------------------------

    function add(printer) {
        if (!printer || root.working.length > 0)
            return;
        root.error = "";
        root.working = printer.uri;
        actor.command = [root.script, "add", printer.uri, printer.name];
        actor.running = true;
    }

    function remove(printer) {
        if (!printer || root.working.length > 0)
            return;
        root.error = "";
        root.working = printer.queue;
        actor.command = [root.script, "remove", printer.queue];
        actor.running = true;
    }

    function makeDefault(printer) {
        if (!printer || printer.isDefault || root.working.length > 0)
            return;
        root.error = "";
        root.working = printer.queue;
        actor.command = [root.script, "default", printer.queue];
        actor.running = true;
    }

    Process {
        id: actor
        stderr: StdioCollector { id: complaint }
        onExited: code => {
            if (code !== 0)
                root.error = root.reason(complaint.text);
            root.working = "";
            // The default lives in the user's lpoptions, which CUPS does not
            // announce; the rest it does, and reading once more costs nothing.
            root.refresh();
        }
    }

    // With one printer and no default, the one printer is the default: there is
    // no choice to leave open, and without a default `lp` refuses outright.
    // Asked for once per queue, so a refusal is shown rather than repeated.
    property string defaultAsked: ""

    function settleDefault() {
        if (root.printers.length !== 1 || root.defaultQueue.length > 0 || root.working.length > 0)
            return;
        const only = root.printers[0];
        if (root.defaultAsked === only.queue)
            return;
        root.defaultAsked = only.queue;
        root.makeDefault(only);
    }

    // lpadmin says `lpadmin: <reason>`; the reason is the part worth showing.
    function reason(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l.length > 0);
        const line = lines[lines.length - 1] || "";
        return line.replace(/^[a-z]+:\s*/, "") || "CUPS refused it.";
    }
}
