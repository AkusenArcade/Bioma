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
// it cannot help.
//
// So there are two backends and a capability check.
//
//   backlight   /sys/class/backlight via brightnessctl — laptops, and any panel
//               the kernel drives directly. Fast, reliable, one device.
//   ddc         DDC/CI over I²C via ddcutil — external monitors. Slow, per
//               display, and not always permitted.
//
// With neither available the service reports `available: false` and every
// control is a no-op. Nothing above it should be visible in that case: a
// brightness control that cannot change brightness is exactly the kind of
// element that exists without having anything to say.
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
        if (root.ddcDisplays.length > 0 && root.ddcAllowed)
            return "ddc";
        return "none";
    }

    readonly property bool available: backend === "backlight" || backend === "ddc"
    readonly property bool probing: backlightProbe.running || ddcProbe.running

    // 0..1, the brightness of whatever the backend considers current.
    property real brightness: 0

    property string lastError: ""

    // ── Backlight ────────────────────────────────────────────────────────

    property bool hasBacklight: false
    property int backlightValue: 0
    property int backlightMax: 0

    // `brightnessctl -l` lists LEDs as well as backlights, and its bare `get`
    // falls back to whatever it finds first. Asking specifically for the
    // backlight class is what separates a panel from a caps-lock light.
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
        // driver alongside `acpi_video0`, which is the generic fallback and the
        // worse of the two. Taking whichever the glob returned last would pick
        // by alphabet, which is arbitrary and would differ between machines.
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
            root.brightness = chosen.value / chosen.max;
        }
    }

    property string backlightDevice: ""

    function setBacklight(fraction) {
        const percent = Math.max(1, Math.min(100, Math.round(fraction * 100)));
        writer.command = root.backlightDevice.length > 0
            ? ["brightnessctl", "--class=backlight", "--device", root.backlightDevice,
               "set", percent + "%"]
            : ["brightnessctl", "--class=backlight", "set", percent + "%"];
        writer.running = false;
        writer.running = true;
    }

    // ── DDC/CI ───────────────────────────────────────────────────────────
    //
    // Every call is a round trip over I²C and takes a good fraction of a
    // second, so this is never polled. The value is read once per display at
    // startup, and after that the service's own writes are the only thing that
    // changes it — anything else adjusting the monitor (its own buttons) will
    // not be noticed, which is the correct trade for not hammering the bus.
    //
    // VCP feature 10h is luminance, the one every monitor implements.

    // [{ index, name, brightness, max }]
    property var ddcDisplays: []

    readonly property int ddcSelected: Config.get("brightness.display", 1)

    function ddcDisplayFor(index) {
        return root.ddcDisplays.find(display => display.index === index) ?? null;
    }

    Process {
        id: ddcProbe
        property var found: []
        command: ["sh", "-c",
                  "command -v ddcutil >/dev/null 2>&1 || exit 0; "
                  + "ddcutil detect --brief 2>/dev/null "
                  + "| awk '/^Display/ {d=$2} /Model:/ {$1=\"\"; print d\"\\t\"substr($0,2)}'"]
        running: false

        onRunningChanged: if (running) ddcProbe.found = []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split("\t");
                const index = parseInt(parts[0], 10);
                if (isNaN(index))
                    return;
                ddcProbe.found.push({
                    index: index,
                    name: (parts[1] ?? "").trim() || `Display ${index}`,
                    brightness: -1,
                    max: 100
                });
            }
        }

        onExited: {
            root.ddcDisplays = ddcProbe.found.slice();
            if (root.ddcDisplays.length > 0 && !root.hasBacklight)
                root.readDdc(root.ddcSelected);
        }
    }

    Process {
        id: ddcRead
        property int index: -1
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

                const updated = root.ddcDisplays.map(display =>
                    display.index === ddcRead.index
                        ? Object.assign({}, display, { brightness: current, max: max })
                        : display);
                root.ddcDisplays = updated;
                if (ddcRead.index === root.ddcSelected)
                    root.brightness = current / max;
            }
        }
    }

    function readDdc(index) {
        ddcRead.index = index;
        ddcRead.command = ["ddcutil", "--display", String(index), "getvcp", "10", "--brief"];
        ddcRead.running = false;
        ddcRead.running = true;
    }

    function setDdc(index, fraction) {
        const display = root.ddcDisplayFor(index);
        const max = display?.max > 0 ? display.max : 100;
        const value = Math.max(0, Math.min(max, Math.round(fraction * max)));
        writer.command = ["ddcutil", "--display", String(index), "setvcp", "10", String(value)];
        writer.running = false;
        writer.running = true;
    }

    // ── Control ──────────────────────────────────────────────────────────
    //
    // The displayed value moves immediately and the hardware follows. A DDC
    // write takes long enough that waiting for it would make a slider feel
    // broken, and a backlight write is fast enough that it makes no difference.
    // The write itself is debounced: dragging a slider must not queue fifty
    // I²C round trips.

    function set(fraction) {
        if (!root.available)
            return;
        root.brightness = Math.max(0, Math.min(1, fraction));
        writeDebounce.restart();
    }

    function step(delta) {
        root.set(root.brightness + delta);
    }

    Timer {
        id: writeDebounce
        interval: root.backend === "ddc" ? 120 : 0
        onTriggered: {
            if (root.backend === "backlight")
                root.setBacklight(root.brightness);
            else if (root.backend === "ddc")
                root.setDdc(root.ddcSelected, root.brightness);
        }
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
            if (code === 0) {
                root.lastError = "";
                if (root.backend === "backlight")
                    root.restartBacklightProbe();
            } else if (root.lastError.length > 0) {
                console.warn("Brightness:", root.lastError);
            }
        }
    }

    function restartBacklightProbe() {
        backlightProbe.running = false;
        backlightProbe.running = true;
    }

    Component.onCompleted: {
        if (root.configuredBackend === "off")
            return;
        if (root.backlightAllowed) {
            backlightProbe.running = true;
        }
        if (root.ddcAllowed) {
            ddcProbe.running = true;
        }
    }
}
