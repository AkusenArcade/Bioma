pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Time beyond the one on the clock: other places, a timer, an alarm.
//
// The clock cell shows the time here; opened, it shows the time elsewhere and
// keeps a timer and an alarm, and those have to outlive the panel — a timer
// that stopped when the panel closed would be a timer nobody could use. So
// they live here, and the cell only draws them.
//
// **Other places.** QML has no time zones, so the offset of each place is
// asked of the system (`TZ=… date +%z`) when the list changes, and again every
// half hour so a change of summer time is caught the same day. The time in a
// place is then the machine's clock moved by that offset — nothing polls to
// draw it.
//
// **The timer and the alarm** end in a critical notification, which stays until
// it is closed, and the freedesktop alarm sound.
Singleton {
    id: root

    // ---- Other places ----------------------------------------------------------

    readonly property var zones: Config.get("clock.zones", [])

    // Minutes east of UTC, by zone.
    property var offsets: ({})

    function refreshOffsets() {
        if (root.zones.length === 0) {
            root.offsets = ({});
            return;
        }
        offsetAsker.command = ["bash", "-c",
            "for z in \"$@\"; do printf '%s %s\\n' \"$z\" \"$(TZ=\"$z\" date +%z)\"; done",
            "offsets"].concat(root.zones);
        offsetAsker.running = true;
    }

    onZonesChanged: root.refreshOffsets()
    Component.onCompleted: root.refreshOffsets()

    Timer {
        interval: 30 * 60 * 1000
        running: root.zones.length > 0
        repeat: true
        onTriggered: root.refreshOffsets()
    }

    Process {
        id: offsetAsker

        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const line of this.text.split("\n")) {
                    const match = /^(\S+) ([+-])(\d\d)(\d\d)$/.exec(line.trim());
                    if (!match)
                        continue;
                    const minutes = parseInt(match[3], 10) * 60 + parseInt(match[4], 10);
                    out[match[1]] = match[2] === "-" ? -minutes : minutes;
                }
                root.offsets = out;
            }
        }
    }

    // The wall-clock fields of `now` in a zone: a Date whose local fields read
    // as that zone's time.
    function inZone(zone, now) {
        const offset = root.offsets[zone];
        if (offset === undefined)
            return null;
        return new Date(now.getTime() + (offset + now.getTimezoneOffset()) * 60000);
    }

    // `Europe/Rome` → `Rome`, `America/Argentina/Buenos_Aires` → `Buenos Aires`.
    function cityOf(zone) {
        return String(zone).split("/").pop().replace(/_/g, " ");
    }

    function utcLabel(zone) {
        const offset = root.offsets[zone];
        if (offset === undefined)
            return "";
        const sign = offset < 0 ? "−" : "+";
        const hours = Math.floor(Math.abs(offset) / 60);
        const minutes = Math.abs(offset) % 60;
        return offset === 0 ? "UTC" : `UTC${sign}${hours}${minutes ? ":" + String(minutes).padStart(2, "0") : ""}`;
    }

    function addZone(zone) {
        if (root.zones.indexOf(zone) >= 0)
            return;
        Config.set("clock.zones", root.zones.concat([zone]));
    }

    function removeZone(zone) {
        Config.set("clock.zones", root.zones.filter(z => z !== zone));
    }

    // Every zone the system knows, asked once, for the field that adds one.
    property var known: []
    property bool knownAsked: false

    function askKnown() {
        if (root.knownAsked)
            return;
        root.knownAsked = true;
        knownAsker.running = true;
    }

    Process {
        id: knownAsker
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: root.known = this.text.split("\n").filter(line => line.trim().length > 0)
        }
    }

    // ---- The timer -------------------------------------------------------------

    // How long it runs, in seconds, and what is left of it.
    property int length: Config.get("clock.timer", 25 * 60)
    property int left: root.length
    property bool running: false
    readonly property bool paused: !root.running && root.left < root.length && root.left > 0

    // Where it ends, as a moment: counting down by ticks would drift, and a
    // machine that slept through the end has to know it ended.
    property real endsAt: 0

    // How much of it is left, for the dial on the clock.
    readonly property real fractionLeft: root.length > 0 ? root.left / root.length : 0

    function setLength(seconds) {
        if (root.running)
            return;
        root.length = Math.max(60, Math.min(24 * 3600, Math.round(seconds)));
        root.left = root.length;
        Config.set("clock.timer", root.length);
    }

    function start() {
        if (root.running || root.left <= 0)
            return;
        root.endsAt = Date.now() + root.left * 1000;
        root.running = true;
        root.tick();
    }

    function pause() {
        if (!root.running)
            return;
        root.tick();
        root.running = false;
    }

    function reset() {
        root.running = false;
        root.left = root.length;
    }

    function tick() {
        const remaining = Math.max(0, Math.round((root.endsAt - Date.now()) / 1000));
        root.left = remaining;
        if (remaining === 0 && root.running) {
            root.running = false;
            root.ring("Timer", `${root.describe(root.length)} are up.`);
            root.left = root.length;
        }
    }

    Timer {
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: root.tick()
    }

    function describe(seconds) {
        const minutes = Math.round(seconds / 60);
        if (minutes < 60)
            return minutes === 1 ? "One minute" : `${minutes} minutes`;
        const hours = Math.floor(minutes / 60);
        const rest = minutes % 60;
        return `${hours} h${rest ? " " + rest + " min" : ""}`;
    }

    // ---- The alarm -------------------------------------------------------------

    readonly property var alarm: Config.get("clock.alarm", ({ "hour": 7, "minute": 30, "on": false }))

    function setAlarm(hour, minute, on) {
        Config.set("clock.alarm", {
            "hour": ((hour % 24) + 24) % 24,
            "minute": ((minute % 60) + 60) % 60,
            "on": on
        });
    }

    SystemClock {
        id: minuteClock
        precision: SystemClock.Minutes
        onMinutesChanged: {
            const alarm = root.alarm;
            if (alarm && alarm.on && minuteClock.hours === alarm.hour && minuteClock.minutes === alarm.minute)
                root.ring("Alarm", `It is ${String(alarm.hour).padStart(2, "0")}:${String(alarm.minute).padStart(2, "0")}.`);
        }
    }

    // ---- Ringing ---------------------------------------------------------------

    function ring(title, body) {
        ringer.command = ["notify-send", "-u", "critical", "-a", "Bioma", "-i", "alarm-symbolic",
                          title, body];
        ringer.running = true;
        sound.running = true;
    }

    Process { id: ringer }

    Process {
        id: sound
        command: ["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]
    }
}
