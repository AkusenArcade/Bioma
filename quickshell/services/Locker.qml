pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core

// When the session locks.
//
// The lock screen itself is not here: it is `lock.qml`, a process of its own,
// started through `scripts/lock`, which also stands guard over it. This service
// only decides *when*, and there are three answers (Akusen, 2026-09-23):
//
//   - when asked. The System cell's LOCK runs `loginctl lock-session`, and so
//     can anything else on the machine; logind turns that into a `Lock`
//     signal on this session, and this is what hears it. Mod+Alt+L runs the
//     script directly, so the key works even with the shell down.
//   - before a suspend. A delay inhibitor holds the suspend back until the
//     lock has covered the screens, so the machine never wakes up showing the
//     desktop it went to sleep on.
//   - after a time idle, `lock.idle_minutes`, set on the Session page of the
//     settings cell.
//
// One connection to logind for the life of the shell — `gdbus monitor`, which
// prints each signal as a line — and nothing polls.
Singleton {
    id: root

    readonly property int idleMinutes: Config.get("lock.idle_minutes", 10)
    readonly property bool beforeSleep: Config.get("lock.before_sleep", true)

    readonly property string script: Qt.resolvedUrl("../scripts/lock").toString().replace("file://", "")

    // Whether the session is locked, as logind has it — set by the lock screen
    // once every screen is covered.
    property bool locked: false

    function lock() {
        Quickshell.execDetached([root.script]);
    }

    // ---- This session --------------------------------------------------------

    // The object path of the session the shell runs in. Signals for every
    // session on the machine come down the same line; only this one's count.
    property string session: ""

    Process {
        running: true
        command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                  "org.freedesktop.login1.Manager", "GetSession", "s", "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.match(/"([^"]+)"/);
                root.session = found ? found[1] : "";
                if (root.session.length === 0)
                    console.warn("Bioma: logind does not know this session — lock on request and before sleep are off");
            }
        }
    }

    // ---- What logind says ------------------------------------------------------

    Process {
        id: monitor

        running: root.session.length > 0
        // Told by the kernel when the shell goes. gdbus would otherwise only
        // notice at the next signal it could not write, and a shell restarted
        // a few times would leave a monitor behind for each.
        command: ["setpriv", "--pdeathsig", "TERM",
                  "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.heard(line)
        }

        // gdbus has no reason to stop, so if it does, it is started again.
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: Timing.settle
        onTriggered: {
            monitor.running = false;
            monitor.running = root.session.length > 0;
        }
    }

    function heard(line) {
        if (line.startsWith(`${root.session}: org.freedesktop.login1.Session.Lock `)) {
            root.lock();
            return;
        }

        if (line.startsWith(`${root.session}: org.freedesktop.DBus.Properties.PropertiesChanged`)
                && line.includes("'LockedHint'")) {
            root.locked = line.includes("'LockedHint': <true>");
            return;
        }

        if (line.startsWith("/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep")) {
            if (line.includes("(true,)"))
                root.goingToSleep();
            else
                root.wokeUp();
        }
    }

    // ---- Before a suspend --------------------------------------------------------

    // Held while nothing is happening, and let go once the lock is up: logind
    // waits for a delay inhibitor to be released — at most its own
    // InhibitDelayMaxSec, five seconds by default — before it suspends.
    property bool holding: true

    // What holds the inhibitor open is `cat` reading the shell's end of a
    // pipe: when the shell goes, however it goes, the pipe closes and so does
    // the inhibitor. With `sleep infinity` in its place one was left behind
    // after every restart, each holding every suspend back.
    Process {
        running: root.beforeSleep && root.holding && root.session.length > 0
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Bioma",
                  "--why=Locking the screen before sleep", "cat"]
    }

    function goingToSleep() {
        if (!root.beforeSleep)
            return;
        if (root.locked) {
            root.holding = false;
            return;
        }
        root.lock();
        sleepGuard.restart();
    }

    function wokeUp() {
        sleepGuard.stop();
        root.holding = true;
    }

    // The lock is up: the suspend may go ahead.
    onLockedChanged: {
        if (root.locked && sleepGuard.running) {
            sleepGuard.stop();
            root.holding = false;
        }
    }

    // And if it never comes up, the suspend is not held for ever — logind
    // would stop waiting anyway, and the guard in `scripts/lock` has put
    // hyprlock on the screens by then.
    Timer {
        id: sleepGuard
        interval: Timing.settle
        onTriggered: root.holding = false
    }

    // ---- After a time idle ----------------------------------------------------------

    // Respecting inhibitors: a video playing full screen is not somebody who
    // walked away.
    IdleMonitor {
        enabled: root.idleMinutes > 0
        timeout: Math.max(1, root.idleMinutes) * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle && !root.locked) root.lock()
    }
}
