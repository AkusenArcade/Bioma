pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// VPN profiles, as NetworkManager keeps them.
//
// Quickshell's networking module knows devices and wireless networks, not VPN
// connections, so this reads NetworkManager through `nmcli`: the profiles and
// which are active, read again whenever `nmcli monitor` — one process for the
// life of the shell — says something changed. Nothing polls.
//
// A profile is added from the settings a provider hands out, an `.ovpn` file:
// `nmcli connection import` makes the profile, and `scripts/vpn` gives it the
// user name and the password — the password on stdin, never on a command line,
// where any process could read it. NetworkManager stores it with the profile,
// so a toggle is all it takes from then on.
Singleton {
    id: root

    // [{ "name", "uuid", "type", "state" }], state being NetworkManager's word
    // for an active one ("activated", "activating", …) or "" when it is down.
    property var profiles: []

    readonly property var active: root.profiles.filter(p => p.state === "activated")
    readonly property bool anyActive: root.active.length > 0

    // The last thing NetworkManager refused, in its words.
    property string error: ""

    // A profile being brought up or down, by uuid, until NetworkManager says.
    property string working: ""

    readonly property bool busy: root.working.length > 0 || importer.running || keeper.running

    // ---- Reading -----------------------------------------------------------------

    function refresh() {
        if (reader.running) {
            again.restart();
            return;
        }
        reader.running = true;
    }

    // `-t` escapes a colon inside a field as `\:`; split on the others.
    function fields(line) {
        const out = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            if (line[i] === "\\" && i + 1 < line.length) {
                current += line[i + 1];
                i++;
            } else if (line[i] === ":") {
                out.push(current);
                current = "";
            } else {
                current += line[i];
            }
        }
        out.push(current);
        return out;
    }

    Process {
        id: reader

        command: ["bash", "-c",
            "nmcli -t -f NAME,UUID,TYPE connection show; echo '--'; "
            + "nmcli -t -f UUID,STATE connection show --active"]

        stdout: StdioCollector {
            onStreamFinished: {
                const halves = this.text.split("\n--\n");
                const states = {};
                for (const line of (halves[1] || "").split("\n")) {
                    const f = root.fields(line.trim());
                    if (f.length >= 2 && f[0].length > 0)
                        states[f[0]] = f[1];
                }
                const out = [];
                for (const line of halves[0].split("\n")) {
                    const f = root.fields(line.trim());
                    if (f.length < 3)
                        continue;
                    if (f[2] !== "vpn" && f[2] !== "wireguard")
                        continue;
                    out.push({ "name": f[0], "uuid": f[1], "type": f[2], "state": states[f[1]] || "" });
                }
                out.sort((a, b) => a.name.localeCompare(b.name));
                root.profiles = out;
                if (root.working.length > 0) {
                    const pending = out.find(p => p.uuid === root.working);
                    if (!pending || pending.state === "activated" || pending.state === "")
                        root.working = "";
                }
            }
        }
    }

    Timer {
        id: again
        interval: Timing.debounce
        onTriggered: root.refresh()
    }

    // NetworkManager says when anything changes; a burst of lines is one change.
    Process {
        id: monitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: again.restart()
        }
        onExited: restart.start()
    }

    // If NetworkManager restarts, so does the watch — a little later.
    Timer {
        id: restart
        interval: 5000
        onTriggered: monitor.running = true
    }

    Component.onCompleted: root.refresh()

    // ---- Acting ------------------------------------------------------------------

    function toggle(profile, on) {
        if (!profile || root.working.length > 0)
            return;
        root.error = "";
        root.working = profile.uuid;
        switcher.command = ["nmcli", "connection", on ? "up" : "down", "uuid", profile.uuid];
        switcher.running = true;
    }

    Process {
        id: switcher
        stderr: StdioCollector { id: switchComplaint }
        onExited: code => {
            if (code !== 0) {
                root.error = root.reason(switchComplaint.text);
                root.working = "";
            }
            root.refresh();
        }
    }

    function remove(profile) {
        if (!profile)
            return;
        root.error = "";
        remover.command = ["nmcli", "connection", "delete", "uuid", profile.uuid];
        remover.running = true;
    }

    Process {
        id: remover
        stderr: StdioCollector { id: removeComplaint }
        onExited: code => {
            if (code !== 0)
                root.error = root.reason(removeComplaint.text);
            root.refresh();
        }
    }

    // ---- Adding -----------------------------------------------------------------

    property string pendingUser: ""
    property string pendingPassword: ""

    // Emitted when a profile has been added and given its credentials.
    signal imported(string name)

    function importProfile(file, user, password) {
        if (importer.running || keeper.running)
            return;
        root.error = "";
        root.pendingUser = user;
        root.pendingPassword = password;
        const path = String(file).replace(/^file:\/\//, "");
        importer.command = ["nmcli", "connection", "import", "type", "openvpn", "file", decodeURIComponent(path)];
        importer.running = true;
    }

    Process {
        id: importer
        stdout: StdioCollector { id: importAnswer }
        stderr: StdioCollector { id: importComplaint }
        onExited: code => {
            const found = /Connection '(.*)' \(([0-9a-f-]{36})\)/.exec(importAnswer.text);
            if (code !== 0 || !found) {
                root.error = root.reason(importComplaint.text || importAnswer.text);
                root.pendingPassword = "";
                return;
            }
            keeper.name = found[1];
            if (root.pendingUser.length === 0 && root.pendingPassword.length === 0) {
                root.imported(found[1]);
                root.refresh();
                return;
            }
            keeper.command = [Quickshell.shellPath("scripts/vpn"), "credentials", found[2]];
            keeper.running = true;
        }
    }

    Process {
        id: keeper

        property string name: ""

        stdinEnabled: true
        stderr: StdioCollector { id: keepComplaint }

        onStarted: {
            keeper.write(root.pendingUser + "\n" + root.pendingPassword + "\n");
            keeper.stdinEnabled = false;
            // The password has gone where it is kept; it is not held here.
            root.pendingPassword = "";
        }

        onExited: code => {
            if (code !== 0)
                root.error = root.reason(keepComplaint.text);
            else
                root.imported(keeper.name);
            keeper.stdinEnabled = true;
            root.refresh();
        }
    }

    // nmcli prefixes its complaint with `Error: ` and follows it with a hint
    // about the journal; the complaint is the reason.
    function reason(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l.length > 0);
        const complaint = lines.find(l => l.startsWith("Error:")) || lines[0] || "";
        return complaint.replace(/^Error:\s*/, "") || "NetworkManager refused it.";
    }
}
