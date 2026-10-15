pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Removable drives: what is attached, what is mounted, and whether it is
// being written to.
//
// `scripts/drives` asks udisks — woken by `udisksctl monitor`, so nothing
// polls for drives — and, while a removable filesystem is mounted, reads the
// kernel's own count of what has been written to it once a second. That count
// is what makes "safe to remove" knowable: a copy that has finished for the
// program that made it can still sit in the page cache, and the stick goes on
// being written to after the file manager has said it is done.
//
// Opening mounts first when it has to; ejecting unmounts every filesystem on
// the drive — which waits for whatever is still being written — and then
// powers it off, so the light on the stick goes out and it is gone from the
// list. Both go through `udisksctl`, so the polkit rules are udisks' own.
//
// It runs while something holds it — a drives cell.
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

    // [{ "id", "name", "device", "power_off", "rate", "volumes": [{ "device",
    // "label", "type", "size", "mounts" }] }]
    property var drives: []
    readonly property bool attached: root.drives.length > 0
    readonly property real rate: root.drives.reduce((sum, drive) => sum + drive.rate, 0)

    // A loop device the user set up counts as a drive: the cell can then be
    // tried without a stick in the machine (`udisksctl loop-setup -f image`).
    readonly property bool loops: Config.get("drives.include_loop", false)

    Process {
        id: watch
        command: ["setpriv", "--pdeathsig", "TERM", Quickshell.shellPath("scripts/drives")]
                 .concat(root.loops ? ["--loop"] : [])
        running: root.active
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.drives = JSON.parse(line).drives;
                } catch (e) {}
            }
        }
        onExited: {
            root.drives = [];
            if (root.active)
                rewatch.start();
        }
    }

    Timer {
        id: rewatch
        interval: 5000
        onTriggered: watch.running = root.active
    }

    // ---- What a drive is doing -----------------------------------------------

    // Writing, by the kernel's count: anything above a trickle. The journal of
    // a mounted filesystem writes a few bytes now and then, and those are not
    // a copy still landing.
    function writing(drive) {
        return drive && drive.rate >= 4096;
    }

    function mounted(drive) {
        return drive ? drive.volumes.some(volume => volume.mounts.length > 0) : false;
    }

    function size(drive) {
        return drive ? drive.volumes.reduce((sum, volume) => sum + volume.size, 0) : 0;
    }

    // What is being done to which drive, and what went wrong the last time —
    // by drive id. A drive that leaves takes both with it.
    property var busy: ({})
    property var errors: ({})

    onDrivesChanged: {
        const here = new Set(root.drives.map(drive => drive.id));
        const keep = map => {
            const out = {};
            for (const id in map)
                if (here.has(id))
                    out[id] = map[id];
            return out;
        };
        root.busy = keep(root.busy);
        root.errors = keep(root.errors);
    }

    function mark(id, doing, error) {
        const busy = Object.assign({}, root.busy);
        const errors = Object.assign({}, root.errors);
        if (doing)
            busy[id] = doing;
        else
            delete busy[id];
        if (error)
            errors[id] = error;
        else
            delete errors[id];
        root.busy = busy;
        root.errors = errors;
    }

    // ---- Doing it ------------------------------------------------------------

    // Mounted where udisks puts it, then opened by whatever opens a folder.
    function open(drive, environment) {
        if (!drive || root.busy[drive.id])
            return;
        const volume = drive.volumes[0];
        root.mark(drive.id, "opening", "");
        root.run(drive.id, ["sh", "-c",
            'dev="$1"; launch="$2"; '
            + 'at=$(findmnt -n -o TARGET --source "$dev" | head -n 1); '
            + 'if [ -z "$at" ]; then udisksctl mount -b "$dev" >/dev/null || exit 1; '
            + 'at=$(findmnt -n -o TARGET --source "$dev" | head -n 1); fi; '
            + '[ -n "$at" ] && exec "$launch" --id xdg-open -- xdg-open "$at"',
            "open", volume.device, Quickshell.shellPath("scripts/launch")], environment);
    }

    // Every filesystem unmounted — which is the wait for the last write — and
    // then the power. A loop device has no power to cut: it is let go of
    // instead, which is what pulling it out would have been.
    function eject(drive) {
        if (!drive || root.busy[drive.id])
            return;
        const mounted = drive.volumes.filter(volume => volume.mounts.length > 0)
                                     .map(volume => volume.device);
        const loop = drive.device.startsWith("/dev/loop");
        root.mark(drive.id, "ejecting", "");
        root.run(drive.id, ["sh", "-c",
            'disk="$1"; power="$2"; shift 2; '
            + 'for dev in "$@"; do udisksctl unmount -b "$dev" >/dev/null || exit 1; done; '
            + 'case "$power" in '
            + 'loop) exec udisksctl loop-delete -b "$disk" ;; '
            + 'yes) exec udisksctl power-off -b "$disk" ;; esac',
            "eject", drive.device, loop ? "loop" : drive.power_off ? "yes" : "no"]
            .concat(mounted));
    }

    function run(id, command, environment) {
        const process = action.createObject(root, {
            "drive": id,
            "command": command,
            "environment": environment || ({})
        });
        process.running = true;
    }

    Component {
        id: action

        Process {
            id: call

            property string drive: ""

            stderr: StdioCollector { id: complaint }

            onExited: code => {
                root.mark(call.drive, "", code === 0 ? "" : root.reason(complaint.text));
                call.destroy();
            }
        }
    }

    // What udisks says, in the shell's own words: the one that matters is a
    // file still open on the drive, because that is the one the user can do
    // something about.
    function reason(text) {
        const said = (text || "").toLowerCase();
        if (said.indexOf("busy") >= 0)
            return "In use — close what has a file open on it";
        if (said.indexOf("not authorized") >= 0 || said.indexOf("dismissed") >= 0)
            return "Not allowed";
        const line = (text || "").trim().split("\n").pop();
        return line.length > 0 ? line.replace(/^Error [^:]*:\s*/, "") : "It did not answer";
    }

    // 64 GB, 512 MB — a measurement, in the technical voice.
    function bytes(value) {
        if (value >= 1000 * 1000 * 1000)
            return `${(value / 1000 / 1000 / 1000).toFixed(value >= 10e9 ? 0 : 1)} GB`;
        if (value >= 1000 * 1000)
            return `${Math.round(value / 1000 / 1000)} MB`;
        if (value >= 1000)
            return `${Math.round(value / 1000)} KB`;
        return `${Math.round(value)} B`;
    }
}
