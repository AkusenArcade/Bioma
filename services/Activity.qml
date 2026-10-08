pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core

// How long somebody was at this machine, day by day.
//
// Active is neither idle nor locked. Idle is what the compositor says through
// ext-idle-notify — no input for `activity.idle_minutes` — and it respects
// inhibitors, as the lock does: a video playing full screen is somebody
// watching, not somebody gone. The minutes that passed before idle was
// declared were counted as they went, and are taken back when it is.
//
// There is no history to start from: the journal on this machine keeps three
// days (2026-10-06), and boots are not presence anyway. So the record begins
// when it is first asked for, and it is only kept while something holds the
// service — the growth rings organism. A desktop without one writes nothing
// about its user to disk.
//
// One small file, `activity.json` beside `wallpaper.json`: minutes by local
// date, every day recorded — the growth rings span the machine's whole life,
// and a day is a dozen bytes.
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

    readonly property int idleMinutes: Math.max(1, Config.get("activity.idle_minutes", 5))

    // "YYYY-MM-DD" → minutes active that day.
    property var days: ({})
    property bool loaded: false

    // The day it is, turning at midnight.
    SystemClock {
        id: clock
        enabled: root.active
        precision: SystemClock.Minutes
    }

    readonly property date now: clock.date
    readonly property string today: root.dateKey(clock.date)
    readonly property int todayMinutes: root.days[root.today] ?? 0

    function dateKey(date) {
        const pad = n => String(n).padStart(2, "0");
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    // ---- Presence -------------------------------------------------------------------

    IdleMonitor {
        id: idle
        enabled: root.active
        timeout: root.idleMinutes * 60
        respectInhibitors: true

        onIsIdleChanged: {
            if (idle.isIdle) {
                // The quiet minutes before idle was declared were not presence.
                root.add(-Math.min(root.streak, root.idleMinutes));
                root.streak = 0;
            }
        }
    }

    readonly property bool present: root.active && !idle.isIdle && !Locker.locked

    // Minutes counted since presence last began: what idle may take back.
    property int streak: 0

    // When somebody last came back to the machine — the end of idle, an
    // unlock, the shell starting — as ms since the epoch; 0 while nobody is.
    property real presentSince: 0

    onPresentChanged: {
        root.streak = 0;
        root.presentSince = root.present ? Date.now() : 0;
    }

    // Minutes since then, turning with the clock.
    readonly property int sessionMinutes: root.presentSince > 0
        ? Math.max(0, Math.floor((root.now.getTime() - root.presentSince) / 60000)) : 0

    Timer {
        id: minute
        interval: 60000
        repeat: true
        running: root.present && root.loaded

        // A suspend that did not lock stops the timer without telling anyone:
        // a tick that comes much later than a minute was a sleep, and somebody
        // waking the machine is somebody coming back.
        property real last: 0
        onRunningChanged: minute.last = Date.now()

        onTriggered: {
            const now = Date.now();
            const slept = now - minute.last > 2.5 * 60000;
            minute.last = now;
            if (slept) {
                root.streak = 0;
                root.presentSince = now;
                return;
            }
            root.streak++;
            root.add(1);
        }
    }

    function add(minutes) {
        if (minutes === 0)
            return;
        const next = Object.assign({}, root.days);
        next[root.today] = Math.max(0, (next[root.today] ?? 0) + minutes);
        root.days = next;
        root.save();
    }

    // ---- The file --------------------------------------------------------------------

    readonly property string stateDirectory:
        `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/bioma`

    function save() {
        if (!root.loaded)
            return;
        file.setText(JSON.stringify({ "days": root.days }, null, 1));
    }

    function load(text) {
        if (text && text.trim().length > 0) {
            try {
                const saved = JSON.parse(text);
                if (saved.days && typeof saved.days === "object")
                    root.days = saved.days;
            } catch (error) {
                console.warn("Activity: state file is not valid JSON —", error.message);
            }
        }
        root.loaded = true;
    }

    FileView {
        id: file
        path: root.active ? `${root.stateDirectory}/activity.json` : ""
        atomicWrites: true
        printErrors: false

        onLoaded: root.load(text())
        onLoadFailed: root.load("")
    }
}
