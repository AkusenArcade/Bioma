pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// How full the filesystems are.
//
// One row per device, not per mount point: on btrfs `/`, `/home`, `/var/log`
// and the rest are subvolumes of one pool, and seven figures for one disk
// would be the same thing said seven times. The row is named after the
// shortest path it is mounted on, so the pool is the system's.
//
// A disk fills in days, not seconds, so `df` is read once a minute — and only
// while something holds the service: the adipose organism. A drive plugged in
// or taken out shows up at the next reading.
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

    // [{ device, mount, name, fstype, size, used, fill, system }], the largest
    // first. `fill` is used over what is usable — used and available, as df's
    // own percentage counts it, the blocks reserved for root left out.
    // `system` marks the small partitions the machine boots from, which say
    // nothing anybody can act on and are hidden unless asked for.
    property var disks: []
    property bool loaded: false

    // Filesystems that are not disks: memory, kernel views, sandboxes, and the
    // FUSE mounts that portals and desktops put in front of other things.
    readonly property var virtual: ["tmpfs", "devtmpfs", "efivarfs", "overlay", "squashfs",
                                    "ramfs", "fuse.portal", "fuse.gvfsd-fuse", "nsfs", "proc",
                                    "sysfs", "cgroup2", "autofs"]

    readonly property var systemMounts: ["/boot", "/efi", "/boot/efi"]

    function nameOf(mount) {
        if (mount === "/")
            return "System";
        if (mount === "/home")
            return "Home";
        if (root.systemMounts.indexOf(mount) >= 0)
            return "Boot";
        const last = mount.split("/").filter(part => part.length > 0).pop() || mount;
        return last;
    }

    function parse(text) {
        const byDevice = {};
        for (const line of text.split("\n").slice(1)) {
            const parts = line.trim().split(/\s+/);
            if (parts.length < 6)
                continue;
            const [source, fstype, size, used, avail] = parts;
            const mount = parts.slice(5).join(" ");
            if (root.virtual.indexOf(fstype) >= 0 || !source.startsWith("/"))
                continue;
            const total = parseInt(size, 10);
            if (!(total > 0))
                continue;
            // A btrfs subvolume can carry its path in brackets after the device.
            const device = source.replace(/\[.*\]$/, "");
            const known = byDevice[device];
            if (known && known.mount.length <= mount.length)
                continue;
            const usedBytes = parseInt(used, 10) || 0;
            const usable = usedBytes + (parseInt(avail, 10) || 0);
            byDevice[device] = {
                "device": device,
                "mount": mount,
                "name": root.nameOf(mount),
                "fstype": fstype,
                "size": total,
                "used": usedBytes,
                "fill": usable > 0 ? usedBytes / usable : 0,
                "system": root.systemMounts.indexOf(mount) >= 0
            };
        }
        root.disks = Object.values(byDevice).sort((a, b) => b.size - a.size);
        root.loaded = true;
    }

    Process {
        id: df
        command: ["df", "-B1", "--output=source,fstype,size,used,avail,target"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    Timer {
        interval: 60 * 1000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }

    // "47 GB", "1.2 TB": decimal units, as disks are sold and as df -H says.
    function bytes(value) {
        const units = ["B", "KB", "MB", "GB", "TB", "PB"];
        let unit = 0;
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1000;
            unit++;
        }
        const digits = value < 10 && unit > 0 ? 1 : 0;
        return `${value.toFixed(digits)} ${units[unit]}`;
    }
}
