pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Display brightness.
//
// Prisma drives `brightnessctl` against the first backlight device and polls it
// every ten seconds. That works on a laptop and does nothing at all here: this
// machine has **no backlight device**, because both monitors are external, and
// `brightnessctl -l` offers only keyboard and network-card LEDs. A service that
// cheerfully reports 50% while controlling nothing is worse than one that says
// it cannot help — from the user's side it is indistinguishable from a broken
// monitor.
//
// So there are two backends and, above all, a capability check.
//
//   backlight   /sys/class/backlight, written through brightnessctl. Laptops
//               and any panel the kernel drives directly. Fast, one device.
//   ddc         DDC/CI over I²C through ddcutil. External monitors, addressed
//               individually.
//
// With neither available the service reports `available: false` and every
// control is a no-op. Nothing above it should be visible in that case: a
// control that cannot change anything is exactly what principle 4 excludes.
Singleton {
    id: root

    // auto | backlight | ddc | off
    readonly property string configuredBackend: Config.get("brightness.backend", "auto")
    readonly property bool ddcAllowed: configuredBackend === "auto" || configuredBackend === "ddc"
    readonly property bool backlightAllowed: configuredBackend === "auto" || configuredBackend === "backlight"

    readonly property string backend: {
        if (root.configuredBackend === "off")
            return "off";
        if (root.hasBacklight && root.backlightAllowed)
            return "backlight";
        if (root.displays.length > 0 && root.ddcAllowed)
            return "ddc";
        return "none";
    }

    readonly property bool available: backend === "backlight" || backend === "ddc"
    readonly property bool probing: backlightProbe.running || ddcDetect.running

    property string lastError: ""

    // ── Backlight ────────────────────────────────────────────────────────

    property bool hasBacklight: false
    property string backlightDevice: ""
    property int backlightValue: 0
    property int backlightMax: 0

    readonly property real backlightBrightness: backlightMax > 0 ? backlightValue / backlightMax : 0

    Process {
        id: backlightProbe
        property var found: []

        command: ["sh", "-c",
                  "for d in /sys/class/backlight/*/; do "
                  + "[ -e \"$d/brightness\" ] || continue; "
                  + "printf '%s %s %s\\n' \"$(basename \"$d\")\" "
                  + "\"$(cat \"$d/brightness\")\" \"$(cat \"$d/max_brightness\")\"; "
                  + "done"]
        running: false

        onRunningChanged: if (running) backlightProbe.found = []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.trim().split(/\s+/);
                if (parts.length < 3)
                    return;
                const value = parseInt(parts[1], 10);
                const max = parseInt(parts[2], 10);
                if (isNaN(value) || !(max > 0))
                    return;
                backlightProbe.found.push({ device: parts[0], value: value, max: max });
            }
        }

        // A machine can expose more than one backlight — typically a native
        // driver alongside `acpi_video0`, the generic fallback and the worse of
        // the two. Taking whichever the glob returned last would pick by
        // alphabet, which is arbitrary and differs between machines.
        onExited: {
            const candidates = backlightProbe.found;
            if (candidates.length === 0) {
                root.hasBacklight = false;
                return;
            }
            const chosen = candidates.find(c => !c.device.startsWith("acpi_video"))
                        ?? candidates[0];
            root.backlightDevice = chosen.device;
            root.backlightValue = chosen.value;
            root.backlightMax = chosen.max;
            root.hasBacklight = true;
        }
    }

    // ── DDC/CI ───────────────────────────────────────────────────────────
    //
    // Measured on this machine, and the numbers decide the design:
    //
    //   ddcutil detect                3.5 s
    //   ddcutil --display N getvcp    3.4 s
    //   ddcutil --bus N getvcp        0.09 – 0.12 s
    //   ddcutil --bus N setvcp        0.33 s
    //
    // Nearly all of `--display`'s cost is the bus scan it redoes on every
    // invocation. Detecting once, keeping each display's I²C bus number and
    // addressing `--bus` from then on is thirty times faster, and it is the
    // difference between a control that responds and one that appears broken.
    //
    // Nothing is polled. Each display is read once after detection; after that
    // the service's own writes are the only thing that moves the value. A
    // monitor adjusted by its own physical buttons goes unnoticed, which is the
    // right trade against holding the I²C bus busy forever.
    //
    // VCP feature 10h is luminance, the one feature every monitor implements.

    // [{ index, bus, connector, model, value, max }]
    property var displays: []

    // Which display the bare `brightness` and `set()` refer to. A connector
    // name — `DP-1`, `HDMI-A-1` — because that is what Wayland calls a monitor
    // and what a membrane is anchored to, whereas ddcutil's display numbers are
    // an artefact of its own enumeration order.
    readonly property string configuredDisplay: Config.get("brightness.display", "")

    readonly property var display: {
        if (root.configuredDisplay.length > 0) {
            const chosen = root.displays.find(d => d.connector === root.configuredDisplay);
            if (chosen)
                return chosen;
        }
        return root.displays[0] ?? null;
    }

    function displayFor(connector) {
        return root.displays.find(d => d.connector === connector) ?? null;
    }

    // A monitor's own words for itself. The EDID model is frequently empty —
    // one of the two here publishes none at all — so the connector is the name
    // that always exists.
    function describe(entry) {
        if (!entry)
            return "";
        return entry.model && entry.model.length > 0
            ? `${entry.model} (${entry.connector})`
            : entry.connector;
    }

    // `detect --brief` is not shaped the way the documentation examples suggest:
    // there is no `Model:` line, the connector key contains a space rather than
    // an underscore, and the monitor is published as `MFG:MODEL:SERIAL` with any
    // field possibly empty. Parsing it wrongly yields an empty display list,
    // which looks exactly like a machine with no DDC monitors at all.
    Process {
        id: ddcDetect
        property var found: []

        command: ["sh", "-c",
                  "command -v ddcutil >/dev/null 2>&1 || exit 0; "
                  + "ddcutil detect --brief 2>/dev/null | awk '"
                  + "/^Display[ \\t]+[0-9]+/ { idx=$2; bus=\"\"; conn=\"\"; model=\"\" } "
                  + "/I2C bus:/ { bus=$3; sub(/^\\/dev\\/i2c-/, \"\", bus) } "
                  + "/DRM connector:/ { conn=$3; sub(/^card[0-9]+-/, \"\", conn) } "
                  + "/Monitor:/ { split($2, m, \":\"); model=m[2] } "
                  + "/^$/ { if (idx != \"\") { print idx \"\\t\" bus \"\\t\" conn \"\\t\" model; idx=\"\" } } "
                  + "END { if (idx != \"\") print idx \"\\t\" bus \"\\t\" conn \"\\t\" model }'"]
        running: false

        onRunningChanged: if (running) ddcDetect.found = []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split("\t");
                const index = parseInt(parts[0], 10);
                const bus = parseInt(parts[1], 10);
                if (isNaN(index) || isNaN(bus))
                    return;
                ddcDetect.found.push({
                    index: index,
                    bus: bus,
                    connector: (parts[2] ?? "").trim() || `display-${index}`,
                    model: (parts[3] ?? "").trim(),
                    value: -1,
                    max: 100
                });
            }
        }

        onExited: {
            root.displays = ddcDetect.found.slice();
            for (const entry of root.displays)
                root.queueRead(entry.connector);
        }
    }

    // Reads are queued rather than fired at once. Two ddcutil processes on
    // different buses are fine in principle, but a burst of them is a good way
    // to make an unrelated monitor blink.
    property var readQueue: []

    function queueRead(connector) {
        root.readQueue = root.readQueue.concat([connector]);
        if (!ddcRead.running)
            root.readNext();
    }

    function readNext() {
        if (root.readQueue.length === 0)
            return;
        const connector = root.readQueue[0];
        root.readQueue = root.readQueue.slice(1);
        const entry = root.displayFor(connector);
        if (!entry) {
            root.readNext();
            return;
        }
        ddcRead.connector = connector;
        ddcRead.command = ["ddcutil", "--bus", String(entry.bus), "getvcp", "10", "--brief"];
        ddcRead.running = false;
        ddcRead.running = true;
    }

    Process {
        id: ddcRead
        property string connector: ""
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                // `getvcp --brief` answers: VCP 10 C <current> <max>
                const parts = line.trim().split(/\s+/);
                if (parts[0] !== "VCP")
                    return;
                const current = parseInt(parts[3], 10);
                const max = parseInt(parts[4], 10);
                if (isNaN(current) || !(max > 0))
                    return;
                root.displays = root.displays.map(entry =>
                    entry.connector === ddcRead.connector
                        ? Object.assign({}, entry, { value: current, max: max })
                        : entry);
            }
        }

        onExited: root.readNext()
    }

    // ── Reading ──────────────────────────────────────────────────────────

    readonly property real brightness: {
        if (root.backend === "backlight")
            return root.backlightBrightness;
        if (root.backend === "ddc" && root.display && root.display.value >= 0)
            return root.display.value / root.display.max;
        return 0;
    }

    // -1 when that display has not answered yet, which is not the same as 0.
    function brightnessFor(connector) {
        const entry = root.displayFor(connector);
        return entry && entry.value >= 0 ? entry.value / entry.max : -1;
    }

    // ── Writing ──────────────────────────────────────────────────────────
    //
    // A write takes a third of a second, so a control being dragged must
    // neither queue every intermediate value nor wait for each one. The latest
    // target per display is held, and the next write starts when the previous
    // finishes — coalescing to the newest value rather than replaying the drag.

    property var pendingTargets: ({})       // connector -> 0..1

    function set(fraction) {
        if (root.backend === "backlight")
            root.setBacklight(fraction);
        else if (root.backend === "ddc" && root.display)
            root.setFor(root.display.connector, fraction);
    }

    function step(delta) {
        root.set(Math.max(0, Math.min(1, root.brightness + delta)));
    }

    function setFor(connector, fraction) {
        if (root.backend !== "ddc")
            return;
        const entry = root.displayFor(connector);
        if (!entry)
            return;

        const clamped = Math.max(0, Math.min(1, fraction));
        const targets = Object.assign({}, root.pendingTargets);
        targets[connector] = clamped;
        root.pendingTargets = targets;

        // The reported value moves at once and the hardware follows. Waiting a
        // third of a second for the write would make the control feel broken.
        root.displays = root.displays.map(candidate =>
            candidate.connector === connector
                ? Object.assign({}, candidate, { value: Math.round(clamped * candidate.max) })
                : candidate);

        if (!writer.running)
            root.writeNext();
    }

    function writeNext() {
        const connectors = Object.keys(root.pendingTargets);
        if (connectors.length === 0)
            return;

        const connector = connectors[0];
        const fraction = root.pendingTargets[connector];
        const targets = Object.assign({}, root.pendingTargets);
        delete targets[connector];
        root.pendingTargets = targets;

        const entry = root.displayFor(connector);
        if (!entry) {
            root.writeNext();
            return;
        }

        const value = Math.max(0, Math.min(entry.max, Math.round(fraction * entry.max)));
        writer.command = ["ddcutil", "--bus", String(entry.bus), "setvcp", "10", String(value)];
        writer.running = false;
        writer.running = true;
    }

    function setBacklight(fraction) {
        const percent = Math.max(1, Math.min(100, Math.round(fraction * 100)));
        root.backlightValue = Math.round(fraction * root.backlightMax);
        writer.command = root.backlightDevice.length > 0
            ? ["brightnessctl", "--class=backlight", "--device", root.backlightDevice,
               "set", percent + "%"]
            : ["brightnessctl", "--class=backlight", "set", percent + "%"];
        writer.running = false;
        writer.running = true;
    }

    Process {
        id: writer
        running: false

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const message = line.trim();
                if (message.length > 0)
                    root.lastError = message;
            }
        }

        onExited: code => {
            if (code !== 0 && root.lastError.length > 0)
                console.warn("Brightness:", root.lastError);
            else if (code === 0)
                root.lastError = "";

            if (root.backend === "ddc")
                root.writeNext();
        }
    }

    // ── Start ────────────────────────────────────────────────────────────

    Component.onCompleted: {
        if (root.configuredBackend === "off")
            return;
        if (root.backlightAllowed)
            backlightProbe.running = true;
        // Detection costs three and a half seconds. It runs in the background
        // and nothing waits on it: until it answers, the backend is `none` and
        // anything above this service simply has nothing to show yet.
        if (root.ddcAllowed)
            ddcDetect.running = true;
    }
}
