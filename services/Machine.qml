pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// What this machine is: its name, what it runs, what it is made of.
//
// Identity, not load — the load is the vitals cell's, and moves; this stands
// still and is read. So it is read once, the first time somebody asks, from the
// kernel's own files where there are some and from a program where there are
// not (`lspci` for the graphics, `df` for the disk, niri for itself). The only
// thing that changes is the uptime, read again each minute while somebody is
// looking — see `watching`.
Singleton {
    id: root

    property bool asked: false

    // Set while the panel that shows this is open.
    property bool watching: false

    function ask() {
        if (root.asked)
            return;
        root.asked = true;
        programs.running = true;
    }

    // ---- The kernel's own files ------------------------------------------------

    // Read into properties when each file arrives: a binding on `text()` is a
    // binding on a function, and it is not told when the file loads.
    property string host: ""
    property string kernel: ""
    property string os: ""
    property string cpu: ""
    property string memory: ""

    FileView {
        path: root.asked ? "/proc/sys/kernel/hostname" : ""
        onLoaded: root.host = text().trim()
    }

    FileView {
        path: root.asked ? "/proc/sys/kernel/osrelease" : ""
        onLoaded: root.kernel = text().trim()
    }

    FileView {
        path: root.asked ? "/etc/os-release" : ""
        onLoaded: {
            const found = /^PRETTY_NAME="?([^"\n]*)"?$/m.exec(text());
            root.os = found ? found[1] : "Linux";
        }
    }

    FileView {
        path: root.asked ? "/proc/cpuinfo" : ""
        onLoaded: {
            const all = text();
            const model = /^model name\s*:\s*(.*)$/m.exec(all);
            const threads = (all.match(/^processor\s*:/gm) || []).length;
            if (!model)
                return;
            const name = model[1].replace(/\(R\)|\(TM\)/g, "").replace(/\s+\d+-Core Processor/, "")
                .replace(/\s+/g, " ").trim();
            root.cpu = threads > 0 ? `${name} · ${threads} threads` : name;
        }
    }

    FileView {
        path: root.asked ? "/proc/meminfo" : ""
        onLoaded: {
            const found = /^MemTotal:\s*(\d+)\s*kB/m.exec(text());
            root.memory = found ? `${Math.round(parseInt(found[1], 10) / 1048576)} GB` : "";
        }
    }

    FileView {
        id: uptimeFile
        path: root.asked ? "/proc/uptime" : ""
        onLoaded: root.uptimeSeconds = parseFloat(text()) || 0
    }

    property real uptimeSeconds: 0

    function readUptime() {
        uptimeFile.reload();
    }

    Timer {
        interval: 60 * 1000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readUptime()
    }

    readonly property string uptime: {
        const minutes = Math.floor(root.uptimeSeconds / 60);
        const days = Math.floor(minutes / 1440);
        const hours = Math.floor((minutes % 1440) / 60);
        const rest = minutes % 60;
        if (days > 0)
            return `${days} d ${hours} h`;
        if (hours > 0)
            return `${hours} h ${rest} min`;
        return `${rest} min`;
    }

    // ---- What needs a program ----------------------------------------------------

    property var gpus: []
    property string disk: ""
    property string niri: ""

    Process {
        id: programs

        command: ["bash", "-c",
            "lspci -mm 2>/dev/null | grep -Ei '\"(VGA compatible controller|3D controller|Display controller)\"'; "
            + "echo '--'; df -h --output=used,size / | tail -1; "
            + "echo '--'; niri --version 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("\n--\n");
                const out = [];
                for (const line of (parts[0] || "").split("\n")) {
                    const quoted = line.match(/"[^"]*"/g) || [];
                    if (quoted.length < 3)
                        continue;
                    // The device's own name, with the marketing in brackets
                    // kept: "Navi 48 [Radeon RX 9070/9070 XT/9070 GRE]" says
                    // which card it is only through the bracket.
                    const device = quoted[2].slice(1, -1);
                    const bracket = /\[([^\]]+)\]/.exec(device);
                    out.push(bracket ? bracket[1] : device);
                }
                root.gpus = out;
                const disk = (parts[1] || "").trim().split(/\s+/);
                root.disk = disk.length === 2 ? `${disk[0]} of ${disk[1]}` : "";
                const niri = /niri\s+(\S+)/.exec(parts[2] || "");
                root.niri = niri ? niri[1] : "";
            }
        }
    }

    // The rows the panel draws, in the order a person reads a machine: what it
    // is called, what it runs, what it is made of, how long it has been up.
    readonly property var rows: {
        const out = [
            { "label": "HOST", "value": root.host, "human": true },
            { "label": "SYSTEM", "value": root.os, "human": true },
            { "label": "KERNEL", "value": root.kernel, "human": false },
            { "label": "NIRI", "value": root.niri, "human": false },
            { "label": "CPU", "value": root.cpu, "human": true }
        ];
        for (const gpu of root.gpus)
            out.push({ "label": "GPU", "value": gpu, "human": true });
        out.push({ "label": "MEMORY", "value": root.memory, "human": false });
        out.push({ "label": "DISK", "value": root.disk, "human": false });
        out.push({ "label": "UP", "value": root.uptime, "human": false });
        return out.filter(row => row.value && row.value.length > 0);
    }
}
