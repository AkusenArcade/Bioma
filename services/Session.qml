pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Who is logged in, and the five ways to leave.
//
// The smallest service in the shell and the one with the sharpest edges: three
// of its five commands close programs. None of them is run from here without
// being asked for twice — the asking belongs to the cell, and this file only
// carries out what it is told.
//
// Every command is a configuration key, because none of them is universal. A
// lock screen is a choice the machine's owner has already made; `systemctl` is
// not the only init there is; and leaving the session means asking the
// compositor to quit, which is a different sentence on every compositor. The
// defaults are what this machine runs — systemd and niri — and nothing here
// pretends they are the only answer.
Singleton {
    id: root

    // ── Who ──────────────────────────────────────────────────────────────

    readonly property string login: Quickshell.env("USER") ?? ""
    readonly property string home: Quickshell.env("HOME") ?? ""

    // The full name, from the GECOS field of the passwd entry — the first
    // comma-separated part of it, because the rest is an office number and a
    // pair of phone numbers nobody has filled in since 1979.
    property string fullName: ""

    // `/etc/passwd` is the one place this is readable without a bus call, and
    // it is read once: a user's own name does not change while they are logged
    // in. NSS users — LDAP, systemd-homed — are not in the file, and there the
    // name is simply the login, which is true rather than wrong.
    FileView {
        id: passwd
        path: "/etc/passwd"
        onLoaded: {
            const lines = passwd.text().split("\n");
            for (const line of lines) {
                const parts = line.split(":");
                if (parts[0] !== root.login)
                    continue;
                const gecos = (parts[4] ?? "").split(",")[0].trim();
                root.fullName = gecos.length > 0 ? gecos : root.login;
                return;
            }
            root.fullName = root.login;
        }
        onLoadFailed: root.fullName = root.login
    }

    // AccountsService keeps the picture, and it is the one the login screen
    // shows, so it is the one the shell shows. `~/.face` is the older
    // convention and still common. Neither may exist, and a missing avatar is
    // a silhouette — never an initial in a coloured circle, which is a label
    // pretending to be a portrait.
    readonly property var avatarCandidates: [
        `/var/lib/AccountsService/icons/${root.login}`,
        `${root.home}/.face`,
        `${root.home}/.face.icon`
    ]

    // Which candidate is being tried. Nothing here opens the file: the one
    // thing that can say whether an image is readable is the thing that reads
    // images, so whoever draws it reports a failure and the next candidate is
    // tried. Reading a PNG as text to find out that it exists is a file read
    // for an answer the loader already has.
    property int avatarIndex: 0

    readonly property bool hasAvatar: root.avatarIndex < root.avatarCandidates.length
    readonly property string avatar: root.hasAvatar
        ? `file://${root.avatarCandidates[root.avatarIndex]}` : ""

    function avatarFailed() {
        if (root.avatarIndex < root.avatarCandidates.length)
            root.avatarIndex = root.avatarIndex + 1;
    }

    // Writing a new one is an AccountsService call over DBus and not a file
    // copy, which the PRD marks optional (§9.8). Reading is all this does.

    // ── The five ─────────────────────────────────────────────────────────
    //
    // In the order of gravity the design lists them in: what undoes itself
    // first, what closes programs last.

    readonly property var lockCommand: Config.get("session.lock", ["loginctl", "lock-session"])
    readonly property var suspendCommand: Config.get("session.suspend", ["systemctl", "suspend"])
    readonly property var restartCommand: Config.get("session.restart", ["systemctl", "reboot"])
    readonly property var shutdownCommand: Config.get("session.shutdown", ["systemctl", "poweroff"])
    readonly property var logoutCommand: Config.get("session.logout",
                                                    ["niri", "msg", "action", "quit", "-s"])

    // What was last asked for, so a cell can say which row is waiting and the
    // service can be driven from one place. "" means nothing is pending.
    property string pending: ""

    readonly property var commands: ({
        "lock": root.lockCommand,
        "suspend": root.suspendCommand,
        "restart": root.restartCommand,
        "shutdown": root.shutdownCommand,
        "logout": root.logoutCommand
    })

    // The three that close programs. The other two undo themselves with a
    // movement of the mouse, and asking about those is noise.
    function confirms(action) {
        return action === "restart" || action === "shutdown" || action === "logout";
    }

    function run(action) {
        const command = root.commands[action];
        if (!command || command.length === 0) {
            console.warn(`Bioma: session action "${action}" has no command configured`);
            return;
        }
        root.pending = "";
        Quickshell.execDetached(command);
    }

    // Asked for, and not yet confirmed. A second call with the same action
    // carries it out; with a different one it moves the question.
    function ask(action) {
        if (!root.confirms(action)) {
            root.run(action);
            return;
        }
        root.pending = root.pending === action ? "" : action;
    }

    function confirm() {
        if (root.pending.length > 0)
            root.run(root.pending);
    }

    function cancel() {
        root.pending = "";
    }
}
