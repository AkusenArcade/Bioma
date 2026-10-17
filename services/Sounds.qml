pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Bioma's sound effects: the desktop appearing after login, a notification,
// a cell opening and closing, a measured value turning red.
//
// The sounds are Bioma's own, synthesised by tools/sounds into assets/sounds
// and committed. Each is played by a detached `pw-play`, which costs nothing
// between sounds — no audio library loaded into the shell, no stream held
// open — and starts in about twenty milliseconds, under the first frame of a
// cell growing. pw-play is already a dependency, for the alarm.
//
// One switch per kind of event, on the Sounds page of Settings
// (`sounds.login`, `.notifications`, `.cells`, `.alerts`), and one volume for
// all of them, under the system's. Akusen asked for the system and chose its
// shape, 2026-10-17: original sounds, a toggle per event, and a notification
// that brings a sound of its own keeps it — the Bioma sound is for the ones
// that do not, so an application stays recognisable by ear.
Singleton {
    id: root

    readonly property real volume: Math.max(0, Math.min(1, Config.get("sounds.volume", 0.6)))

    function enabled(kind) {
        return Config.get(`sounds.${kind}`, true) === true;
    }

    // ---- Playing -------------------------------------------------------------

    // When each sound last started.
    property var last: ({})

    function since(name) {
        return Date.now() - (root.last[name] ?? 0);
    }

    // Bioma's sounds are signal leaving the machine like any other, so the
    // media cell, which appears on any, appears for them too. Left so on
    // purpose until it has been heard (Akusen, 2026-10-17).
    function file(path) {
        Quickshell.execDetached(["pw-play", "--media-role", "Notification",
                                 "--volume", String(root.volume),
                                 "-P", "{ application.name = \"Bioma\" }",
                                 path]);
    }

    function play(name) {
        if (root.volume <= 0)
            return;
        // The same sound twice inside a breath is one sound.
        if (root.since(name) < 60)
            return;
        const stamps = Object.assign({}, root.last);
        stamps[name] = Date.now();
        root.last = stamps;
        root.file(Quickshell.shellPath(`assets/sounds/${name}.wav`));
    }

    // A cell's panel opening or closing (structure/Cell.qml).
    //
    // Two cells trading places would play both: opening one closes the other,
    // and a press on a second cell can shut the first a moment before it opens
    // itself. The opening is what was asked for, so a close waits a breath
    // and is dropped if an opening comes inside it, before or after.
    function cell(open) {
        if (!root.enabled("cells"))
            return;
        if (open) {
            closing.stop();
            root.play("open");
        } else if (root.since("open") > closing.interval) {
            closing.restart();
        }
    }

    Timer {
        id: closing
        interval: 90
        onTriggered: root.play("close")
    }

    // ---- Login -----------------------------------------------------------------
    //
    // Once per session, when the desktop first appears: the shell restarts far
    // more often than anybody logs in, so the session remembers it was greeted
    // in a mark in its runtime directory, which goes when the session ends.
    // Asked for by shell.qml alone — the lock screen and the greeter are
    // processes of their own and never greet.

    property bool greeting: false

    function greet() {
        root.greeting = true;
        root.tryGreeting();
    }

    function tryGreeting() {
        if (!root.greeting || !Config.ready || !Config.overrideRead)
            return;
        root.greeting = false;
        greeted.running = true;
    }

    Connections {
        target: Config
        function onReloaded() { root.tryGreeting(); }
        function onOverrideReadChanged() { root.tryGreeting(); }
    }

    Process {
        id: greeted
        command: ["sh", "-c", "m=\"${XDG_RUNTIME_DIR:-/tmp}/bioma-greeted\"; [ -e \"$m\" ] && exit 1; : > \"$m\""]
        onExited: code => {
            if (code === 0 && root.enabled("login"))
                root.play("login");
        }
    }

    // ---- Notifications --------------------------------------------------------
    //
    // Called when a notification appears (services/Notifications.qml): not for
    // one that only went into the history while quiet or past the cap, which
    // made no entrance to sound.
    //
    // The freedesktop hints decide whose sound it is. `suppress-sound` means
    // the sender plays its own, or wants none; `sound-file` and `sound-name`
    // are the sender's own sound, which the server plays — the specification
    // gives that job to whoever shows the notification. Only a notification
    // with none of them gets Bioma's.
    function notification(notification) {
        if (!root.enabled("notifications") || root.volume <= 0)
            return;
        const hints = notification?.hints ?? ({});
        if (hints["suppress-sound"] === true)
            return;

        const path = String(hints["sound-file"] ?? "").replace(/^file:\/\//, "");
        if (path.length > 0) {
            root.file(path);
            return;
        }

        const name = String(hints["sound-name"] ?? "");
        if (/^[A-Za-z0-9._-]+$/.test(name)) {
            root.named(name);
            return;
        }

        root.play("notification");
    }

    // A sound named from the freedesktop sound theme, looked for where the
    // theme specification says it lives. Nothing found is silence: the sender
    // asked for its own sound, and Bioma's in its place would be a stranger's.
    function named(name) {
        const home = Quickshell.env("XDG_DATA_HOME") || `${Quickshell.env("HOME")}/.local/share`;
        const dirs = [home].concat((Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":"));
        const candidates = [];
        for (const dir of dirs)
            for (const extension of ["oga", "ogg", "wav"])
                candidates.push(`${dir}/sounds/freedesktop/stereo/${name}.${extension}`);
        Quickshell.execDetached(["sh", "-c",
            "v=$1; shift; for f; do [ -f \"$f\" ] && exec pw-play --media-role Notification --volume \"$v\" -P '{ application.name = \"Bioma\" }' \"$f\"; done",
            "sound", String(root.volume)].concat(candidates));
    }

    // ---- Values turning red ---------------------------------------------------
    //
    // A measured value crossing into the alert colour — the load at which a
    // vitals ring turns red (Theme.thresholdAlert), and a battery that far gone
    // while it runs on itself. It sounds on the way in, once: a value that
    // stays red is not news, and one that falls back has to rest under the
    // threshold for `sounds.alert_gap` seconds before it can sound again,
    // because a compile crossing 80% every few seconds is one event, not forty.
    // Watched here rather than in the cells, so two vitals cells do not sound
    // twice and a value goes on being watched with no cell showing it.

    readonly property int alertGap: Math.max(0, Config.get("sounds.alert_gap", 300)) * 1000

    readonly property bool cpuRed: SystemMonitor.cpuPercent / 100 >= Theme.thresholdAlert
    readonly property bool ramRed: SystemMonitor.ramPercent / 100 >= Theme.thresholdAlert
    readonly property bool gpuRed: SystemMonitor.gpuPresent
                                   && SystemMonitor.gpuPercent / 100 >= Theme.thresholdAlert
    readonly property bool batteryRed: SystemMonitor.hasBattery && SystemMonitor.discharging
                                       && 1 - SystemMonitor.batteryLevel >= Theme.thresholdAlert

    onCpuRedChanged: root.redden("cpu", root.cpuRed)
    onRamRedChanged: root.redden("ram", root.ramRed)
    onGpuRedChanged: root.redden("gpu", root.gpuRed)
    onBatteryRedChanged: root.redden("battery", root.batteryRed)

    // Nothing sounds while the session is starting: the first samples are
    // the shell loading itself, and a login that begins with an alarm is a
    // poor welcome.
    property bool armed: false

    Timer {
        interval: 15000
        running: true
        onTriggered: root.armed = true
    }

    // When each value last left the red.
    property var cooled: ({})

    function redden(key, red) {
        if (!red) {
            const next = Object.assign({}, root.cooled);
            next[key] = Date.now();
            root.cooled = next;
            return;
        }
        if (!root.armed || !root.enabled("alerts"))
            return;
        if (key in root.cooled && Date.now() - root.cooled[key] < root.alertGap)
            return;
        // Two values turning red together are one alarm.
        if (root.since("alert") < 1500)
            return;
        root.play("alert");
    }
}
