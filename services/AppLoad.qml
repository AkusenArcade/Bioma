pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// What each running application costs: its memory and its processor, summed
// over every process that belongs to it.
//
// "Belongs" is the whole difficulty. A process list names executables, and an
// application is several of them — a browser and its content processes, Steam
// and ten `steamwebhelper`s, a terminal and everything running in it. systemd's
// scopes do not settle it either: a terminal opened from the file manager lands
// in the file manager's scope (seen 2026-10-05), and an X11 window's pid is
// xwayland-satellite's, not the application's. So the process tree decides:
//
//   1. a process belongs to the nearest ancestor that owns a window — niri
//      reports each window's pid — unless that pid is Xwayland's;
//   2. otherwise to its ancestor just below the session — the child of the
//      user's systemd, of niri, or of init — which names a group of its own;
//   3. a group of the second kind that holds a process named after an open
//      window's application joins that application: Steam's helpers, under the
//      shell script that launched them, join the Steam window.
//
// Bioma's own process is a group like any other, and named for what it is.
//
// The sample is one `pgrep` and one `awk` over `/proc/<pid>/stat` for this
// user's processes — no `ps`, whose CPU figure is an average over each
// process's lifetime. Processor is the difference in clock ticks between two
// samples. It runs only while held: nothing samples while no organism shows it.
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

    readonly property int interval: Config.get("vitals.process_interval", 3000)

    // Applications, heaviest first:
    //   { key, name, appId, icon, ram (MiB), cpu (% of one core),
    //     processes: [{ pid, comm, ram, cpu }] heaviest first }
    property var apps: []
    property real totalRam: 0   // MiB, over every group

    // Bound, so that niri's windows are being kept when a sample needs them.
    readonly property var windows: Niri.windows

    onActiveChanged: {
        if (!root.active) {
            root.apps = [];
            root.previous = ({});
        }
    }

    Timer {
        interval: root.interval
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            sampler.running = false;
            sampler.running = true;
        }
    }

    // The shell's own pid comes first, as `self`: the sampler's parent.
    Process {
        id: sampler

        property var rows: []
        property int self: -1

        command: ["sh", "-c",
                  "echo \"self\t$PPID\"; "
                  + "cd /proc && pgrep -u \"$(id -u)\" | sed 's|$|/stat|' "
                  + "| xargs -r awk -v page=\"$(getconf PAGESIZE)\" '"
                  // The name sits between the first '(' and the last ')' and
                  // may hold spaces or parentheses of its own.
                  + "{ o = index($0, \"(\"); c = 0; "
                  + "  for (i = length($0); i > o; i--) if (substr($0, i, 1) == \")\") { c = i; break } "
                  + "  if (!c) next; "
                  + "  comm = substr($0, o + 1, c - o - 1); "
                  + "  n = split(substr($0, c + 2), f, \" \"); "
                  + "  split(FILENAME, p, \"/\"); "
                  + "  printf \"%s\\t%s\\t%s\\t%s\\t%s\\n\", p[1], f[2], f[12] + f[13], f[22] * page, comm }"
                  + "' 2>/dev/null"]
        running: false

        onRunningChanged: if (running) sampler.rows = []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split("\t");
                if (parts[0] === "self") {
                    sampler.self = parseInt(parts[1], 10);
                    return;
                }
                if (parts.length < 5)
                    return;
                sampler.rows.push({
                    "pid": parseInt(parts[0], 10),
                    "ppid": parseInt(parts[1], 10),
                    "ticks": parseInt(parts[2], 10),
                    "bytes": parseInt(parts[3], 10),
                    "comm": parts[4]
                });
            }
        }

        onExited: root.digest(sampler.rows, sampler.self)
    }

    // pid → ticks, and when they were read.
    property var previous: ({})
    property real previousAt: 0

    // Clock ticks per second: 100 on every Linux this runs on.
    readonly property int hertz: 100

    readonly property var xwayland: ["Xwayland", "xwayland-satell"]

    function digest(rows, self) {
        const now = Date.now();
        const elapsed = root.previousAt > 0 ? (now - root.previousAt) / 1000 : 0;

        const procs = {};
        for (const row of rows)
            procs[row.pid] = row;

        // The session's roots: the user's systemd, niri, init.
        const roots = new Set([1]);
        for (const row of rows)
            if (row.comm === "systemd" || row.comm === "niri")
                roots.add(row.pid);

        // Windows by pid, Xwayland's left out: its pid says nothing about
        // which application drew the window.
        const windowAt = {};
        const openApps = [];
        for (const id in root.windows) {
            const w = root.windows[id];
            if (!w.appId)
                continue;
            openApps.push(w.appId);
            const proc = procs[w.pid];
            if (proc && root.xwayland.indexOf(proc.comm) < 0)
                windowAt[w.pid] = w.appId;
        }

        // Each process to its group.
        const groups = {};
        const ticks = {};
        for (const row of rows) {
            ticks[row.pid] = row.ticks;

            let key = null;
            let current = row.pid;
            for (let guard = 0; guard < 64 && procs[current]; guard++) {
                if (windowAt[current] !== undefined) {
                    key = "app:" + windowAt[current];
                    break;
                }
                const parent = procs[current].ppid;
                if (roots.has(parent) || !procs[parent]) {
                    key = current === self ? "self" : "root:" + current;
                    break;
                }
                current = parent;
            }
            if (key === null || roots.has(row.pid))
                continue;

            const before = root.previous[row.pid];
            const cpu = elapsed > 0 && before !== undefined
                ? Math.max(0, (row.ticks - before) / root.hertz / elapsed * 100) : 0;

            if (!groups[key])
                groups[key] = { "key": key, "rootComm": procs[current] ? procs[current].comm : row.comm, "processes": [] };
            groups[key].processes.push({
                "pid": row.pid,
                "comm": row.comm,
                "ram": row.bytes / 1048576,
                "cpu": cpu
            });
        }

        // A windowless group that holds a process named after an open
        // application joins it.
        for (const key in groups) {
            if (key.indexOf("root:") !== 0)
                continue;
            const joined = root.ownerOf(groups[key].processes, openApps);
            if (joined === null)
                continue;
            const target = "app:" + joined;
            if (!groups[target])
                groups[target] = { "key": target, "rootComm": groups[key].rootComm, "processes": [] };
            groups[target].processes = groups[target].processes.concat(groups[key].processes);
            delete groups[key];
        }

        const out = [];
        let total = 0;
        for (const key in groups) {
            const group = groups[key];
            const processes = group.processes.sort((a, b) => b.ram - a.ram);
            const ram = processes.reduce((sum, p) => sum + p.ram, 0);
            const cpu = processes.reduce((sum, p) => sum + p.cpu, 0);
            total += ram;

            const appId = key.indexOf("app:") === 0 ? key.slice(4) : "";
            const lookup = appId.length > 0 ? appId : group.rootComm;
            const entry = Apps.entryFor(lookup);
            const name = key === "self" ? "Bioma"
                       : entry && entry.name ? entry.name
                       : appId.length > 0 ? appId : group.rootComm;

            out.push({
                "key": key,
                "name": name,
                "appId": appId,
                "icon": key === "self" ? "" : Apps.iconFor(lookup),
                "ram": ram,
                "cpu": cpu,
                "processes": processes
            });
        }
        out.sort((a, b) => b.ram - a.ram);

        root.previous = ticks;
        root.previousAt = now;
        root.totalRam = total;
        root.apps = out;
    }

    // The open application a set of processes belongs to, by name: the last
    // part of an app id (`org.telegram.desktop` → `desktop` is useless, so the
    // whole id is tried through the desktop files as well).
    function ownerOf(processes, openApps) {
        for (const appId of openApps) {
            const short = appId.split(".").pop().toLowerCase();
            const entry = Apps.entryFor(appId);
            for (const p of processes) {
                const comm = p.comm.toLowerCase();
                if (comm === appId.toLowerCase() || (short.length >= 4 && comm === short))
                    return appId;
                if (entry && Apps.entryFor(p.comm) === entry)
                    return appId;
            }
        }
        return null;
    }
}
