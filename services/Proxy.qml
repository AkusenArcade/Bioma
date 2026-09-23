pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Which proxy is on, and making it so.
//
// A proxy is a profile — a name, HTTP or SOCKS5, a host and a port, the hosts
// that go around it, and what turns it on by itself: a VPN coming up, a Wi-Fi
// network by name, the wire. Akusen's design, 2026-09-23: several profiles,
// each with its own triggers, and a switch that overrides them.
//
// **Which one is on** is `mode`: `auto` — the first profile one of whose
// triggers matches what is connected now — or a profile forced on by its id, or
// `off`. The switch on a row forces; the AUTO pill gives the choice back.
//
// **Where it applies**, since "system-wide" means two things on this desktop:
// - the desktop's own proxy setting, `org.gnome.system.proxy`, which browsers
//   and GTK programs read live;
// - the environment of the programs the shell starts — `http_proxy` and the
//   rest — through `Apps.run`. Terminals already open and programs niri starts
//   do not see it.
Singleton {
    id: root

    readonly property var profiles: Config.get("proxy.profiles", [])
    readonly property string mode: Config.get("proxy.mode", "auto")

    function profileFor(id) {
        return root.profiles.find(p => p.id === id) || null;
    }

    // ---- What is connected -------------------------------------------------------

    function matches(trigger) {
        if (!trigger)
            return false;
        if (trigger.kind === "vpn")
            return Vpn.active.some(p => p.uuid === trigger.uuid);
        if (trigger.kind === "wifi")
            return Network.wifiConnected && Network.ssid === trigger.ssid;
        if (trigger.kind === "wired")
            return Network.wiredConnected;
        return false;
    }

    function triggered(profile) {
        return (profile.triggers || []).some(t => root.matches(t));
    }

    readonly property var current: {
        if (root.mode === "off")
            return null;
        if (root.mode !== "auto")
            return root.profileFor(root.mode);
        for (const profile of root.profiles)
            if (root.triggered(profile))
                return profile;
        return null;
    }

    readonly property bool on: root.current !== null

    // ---- The environment of what the shell starts --------------------------------

    function urlOf(profile) {
        const scheme = profile.type === "socks5" ? "socks5h" : "http";
        return `${scheme}://${profile.host}:${profile.port}`;
    }

    readonly property string exceptions: root.current
        ? (root.current.noProxy || "localhost,127.0.0.1,::1") : ""

    readonly property var environment: {
        if (!root.current)
            return ({});
        const url = root.urlOf(root.current);
        const out = {
            "http_proxy": url, "HTTP_PROXY": url,
            "https_proxy": url, "HTTPS_PROXY": url,
            "no_proxy": root.exceptions, "NO_PROXY": root.exceptions
        };
        if (root.current.type === "socks5") {
            out.all_proxy = url;
            out.ALL_PROXY = url;
        }
        return out;
    }

    // ---- The desktop's setting --------------------------------------------------
    //
    // Written when what is on changes — and not while the shell is starting:
    // the networks fill in a moment after start, and writing "none" for that
    // moment would drop a proxy somebody's browser is using.

    readonly property string signature: root.current
        ? JSON.stringify([root.current.type, root.current.host, root.current.port, root.exceptions])
        : "none"

    onSignatureChanged: if (root.settled) root.apply()

    property bool settled: false

    Timer {
        interval: Timing.settle
        running: true
        onTriggered: {
            root.settled = true;
            root.apply();
        }
    }

    // With no profiles the shell manages no proxy, and the desktop's setting is
    // somebody else's to leave alone — unless the shell set it and then lost
    // its last profile, in which case it undoes what it did, once.
    property bool touched: false

    onProfilesChanged: if (root.settled && root.profiles.length === 0 && root.touched) root.apply()

    function apply() {
        const empty = root.profiles.length === 0;
        if (empty && !root.touched)
            return;
        root.touched = !empty;
        const schema = "org.gnome.system.proxy";
        const set = (key, value) => `gsettings set ${key} ${value}`;
        const lines = [];
        // Read with the list, not after it: the handler that removed the last
        // profile runs before `current` has heard.
        const profile = empty ? null : root.current;
        if (!profile) {
            lines.push(set(schema, "mode none"));
        } else {
            // Quoted twice: once for bash, once for GVariant — gsettings
            // wants `'proxy.example'`, a string, not a bare word.
            const host = `"'${String(profile.host).replace(/['"\\$`]/g, "")}'"`;
            const port = Math.max(0, parseInt(profile.port, 10) || 0);
            const ignored = root.exceptions.split(",").map(h => h.trim()).filter(h => h.length > 0)
                .map(h => `'${h.replace(/['"\\$`]/g, "")}'`).join(", ");
            lines.push(set(schema, `ignore-hosts "[${ignored}]"`));
            if (profile.type === "socks5") {
                lines.push(set(schema + ".socks", `host ${host}`), set(schema + ".socks", `port ${port}`));
                lines.push(set(schema + ".http", `host "''"`), set(schema + ".https", `host "''"`));
            } else {
                lines.push(set(schema + ".http", `host ${host}`), set(schema + ".http", `port ${port}`));
                lines.push(set(schema + ".https", `host ${host}`), set(schema + ".https", `port ${port}`));
                lines.push(set(schema + ".socks", `host "''"`));
            }
            lines.push(set(schema, "mode manual"));
        }
        writer.command = ["bash", "-c", lines.join(" && ")];
        writer.running = true;
    }

    Process {
        id: writer
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim().length > 0)
                console.warn("Bioma: the proxy setting was not written —", this.text.trim())
        }
    }

    // ---- Changing profiles ------------------------------------------------------

    function setMode(mode) {
        Config.set("proxy.mode", mode);
    }

    function save(profile) {
        const list = JSON.parse(JSON.stringify(root.profiles));
        const index = list.findIndex(p => p.id === profile.id);
        if (index >= 0)
            list[index] = profile;
        else
            list.push(profile);
        Config.set("proxy.profiles", list);
    }

    function remove(id) {
        Config.set("proxy.profiles", root.profiles.filter(p => p.id !== id));
        if (root.mode === id)
            root.setMode("auto");
    }

    function newId() {
        return "p" + Date.now().toString(36);
    }

    // A trigger in words, for the row under the profile's name.
    function describe(trigger) {
        if (trigger.kind === "vpn")
            return trigger.name || "VPN";
        if (trigger.kind === "wifi")
            return trigger.ssid;
        if (trigger.kind === "wired")
            return "Wired";
        return "";
    }
}
