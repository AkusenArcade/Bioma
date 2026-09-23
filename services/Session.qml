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

    // ── Whether the machine wants a restart ─────────────────────────────
    //
    // After a kernel update the running kernel's modules are no longer on
    // disk — pacman replaces `/usr/lib/modules/<release>` with the new one —
    // and the next module it needs to load it will not find. So a restart is
    // due exactly when the running release's directory is gone. Watched, not
    // polled: the file is removed and the watcher says so.

    FileView {
        id: releaseFile
        path: "/proc/sys/kernel/osrelease"
        blockLoading: true
    }

    readonly property string release: releaseFile.text().trim()

    property bool modulesPresent: true

    FileView {
        path: root.release.length > 0 ? `/usr/lib/modules/${root.release}/pkgbase` : ""
        watchChanges: true
        printErrors: false
        onLoaded: root.modulesPresent = true
        onLoadFailed: root.modulesPresent = false
        onFileChanged: reload()
    }

    readonly property bool restartDue: root.release.length > 0 && !root.modulesPresent

    // ── Who ──────────────────────────────────────────────────────────────

    readonly property string login: Quickshell.env("USER") ?? ""
    readonly property string home: Quickshell.env("HOME") ?? ""

    // The full name, from the GECOS field of the passwd entry — the first
    // comma-separated part of it, because the rest is an office number and a
    // pair of phone numbers nobody has filled in since 1979.
    property string fullName: ""

    // AccountsService names its user objects by uid, and the passwd line that
    // carries the name carries that too.
    property int uid: -1

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
                root.uid = parseInt(parts[2] ?? "-1", 10);
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

    // A new picture lands at the same path as the old one, so the URL has to
    // change for anything to notice: the fragment does that and is dropped
    // when the path is resolved.
    property int avatarRevision: 0

    readonly property string avatar: root.hasAvatar
        ? `file://${root.avatarCandidates[root.avatarIndex]}`
          + (root.avatarRevision > 0 ? `#${root.avatarRevision}` : "")
        : ""

    function avatarFailed() {
        if (root.avatarIndex < root.avatarCandidates.length)
            root.avatarIndex = root.avatarIndex + 1;
    }

    // ── Changing it ──────────────────────────────────────────────────────
    //
    // The picture is AccountsService's, so it is written over DBus and never
    // by copying a file into place: the daemon takes a path, copies the image
    // itself and tells the login screen. `gdbus` is the whole client — one
    // call, the same shape as every other process this shell runs.
    //
    // Polkit decides whether it is allowed. On a local, active session
    // changing one's own user data usually is; where it is not, the call
    // fails and the service says so rather than leaving the avatar as it was
    // with no explanation.

    property string lastError: ""

    function setAvatar(path) {
        const file = String(path).replace(/^file:\/\//, "");
        if (file.length === 0 || root.uid < 0)
            return;
        root.lastError = "";
        writeAvatar.errorLines = [];
        writeAvatar.path = file;
        writeAvatar.running = false;
        writeAvatar.running = true;
    }

    Process {
        id: writeAvatar

        property string path: ""
        property var errorLines: []

        running: false
        command: ["gdbus", "call", "--system",
                  "--dest", "org.freedesktop.Accounts",
                  "--object-path", `/org/freedesktop/Accounts/User${root.uid}`,
                  "--method", "org.freedesktop.Accounts.User.SetIconFile",
                  writeAvatar.path]

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const message = line.trim();
                if (message.length > 0)
                    writeAvatar.errorLines.push(message);
            }
        }

        onExited: code => {
            if (code === 0) {
                // Back to the first candidate: the picture that was missing a
                // moment ago is the one that has just been written.
                root.avatarIndex = 0;
                root.avatarRevision = root.avatarRevision + 1;
                return;
            }
            root.lastError = writeAvatar.errorLines.join(" ");
            console.warn(`Bioma: the avatar was not changed — ${root.lastError}`);
        }
    }

    // ── The five ─────────────────────────────────────────────────────────
    //
    // In the order of gravity the design lists them in: what undoes itself
    // first, what closes programs last.

    // Empty until a locker is set. Bioma has no lock screen of its own yet, and
    // `loginctl lock-session` with nothing listening locks nothing: a LOCK that
    // does nothing is worse than one that says it is not there (Akusen,
    // 2026-09-23 — until Bioma's own lock screen exists).
    readonly property var lockCommand: Config.get("session.lock", [])
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
    // Whether an action has a command to run at all.
    function available(action) {
        const command = root.commands[action];
        return !!command && command.length > 0;
    }

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
        if (!root.available(action))
            return;
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
