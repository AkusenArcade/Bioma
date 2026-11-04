pragma Singleton

import QtQuick
import Quickshell

// Performance mode: the shell stepping back so the machine is the program's.
//
// It is one state, and every lever reads it here: a cell never asks why the
// mode is on, only whether its own part of the shell is to be quiet. What
// turns it on is two things:
//
//   - a hand: the key (`qs ipc call performance toggle`), the cell, the
//     Settings page. Kept in the override, so a machine that wants to be
//     lean all the time stays lean across a restart;
//   - a trigger: a game registered with GameMode, or a window of one of the
//     applications on the list. `services/Workload.qml` watches for them and
//     hands them in here, because nothing under core/ reads a service. A
//     trigger's mode goes when the last trigger does.
//
// Turned off by hand while a trigger holds it, it stays off until every
// trigger has gone: a game that is still running is not a reason to turn it
// back on under the hand that just refused it.
//
// The levers, each switchable on the Settings page (`performance.suspend`):
//
//   motion       the live indicators hold still — the vitals, the clock's
//                second hand ticks once a second, the media band and the
//                download threads stop. Most of the idle CPU: the membranes
//                redraw at every refresh while any of them moves.
//   organisms    the desktop's organisms are put away, surface and all.
//   wallpaper    the overview's blurred backdrop is put away, and the
//                wallpaper keeps only the picture on screen decoded.
//   blur         no blur behind the glass, no shadows under it.
//   transitions  shapes jump to their size instead of growing.
//   polling      the vitals are read every `vitals_interval` instead.
Singleton {
    id: root

    // What holds the mode on besides a hand, from services/Workload.qml:
    // `{ kind: "game" | "app", name }`, one for each.
    property var triggers: []

    readonly property bool manual: Config.get("performance.manual", false) === true
    readonly property bool triggered: root.triggers.length > 0

    // Turned off by hand while a trigger held it. Forgotten when the last
    // trigger goes, so the next game turns it on again.
    property bool refused: false
    onTriggeredChanged: if (!root.triggered) root.refused = false

    readonly property bool active: root.manual || (root.triggered && !root.refused)

    function lever(name) {
        return root.active && Config.get(`performance.suspend.${name}`, true) !== false;
    }

    readonly property bool still: root.lever("motion")
    readonly property bool withoutOrganisms: root.lever("organisms")
    readonly property bool leanWallpaper: root.lever("wallpaper")
    readonly property bool flat: root.lever("blur")
    readonly property bool instant: root.lever("transitions")
    readonly property bool sparse: root.lever("polling")

    readonly property int vitalsInterval: Math.max(2000, Config.get("performance.vitals_interval", 10000))

    function on() {
        root.refused = false;
        if (!root.manual && !root.triggered)
            Config.set("performance.manual", true);
    }

    function off() {
        if (root.manual)
            Config.set("performance.manual", false);
        if (root.triggered)
            root.refused = true;
    }

    function toggle() {
        if (root.active)
            root.off();
        else
            root.on();
    }

    // Who holds it, in words: "by hand", "while a game runs", "while Blender
    // is open". Empty while it is off.
    readonly property string reason: {
        if (!root.active)
            return "";
        if (root.manual)
            return "by hand";
        const games = root.triggers.filter(t => t.kind === "game").length > 0;
        const apps = root.triggers.filter(t => t.kind === "app").map(t => t.name);
        const parts = [];
        if (games)
            parts.push("a game runs");
        if (apps.length > 0)
            parts.push(`${apps.join(", ")} ${apps.length === 1 ? "is" : "are"} open`);
        return parts.length > 0 ? "while " + parts.join(" and ") : "";
    }
}
