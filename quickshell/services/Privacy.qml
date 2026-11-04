pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.core

// What is being taken from the room and the screen: the microphone, a
// camera, the screen itself — and by whom.
//
// Three sources, one for each, because no one of them sees all three:
//
// - **The microphone** is PipeWire's: a link from an audio source — a device,
//   not a sink's monitor — into a capture stream. A sink's monitor feeding a
//   stream is somebody listening to what the machine plays (Bioma's own band
//   among them), not to the room, and is left out.
// - **A camera** is opened directly by most applications, not through
//   PipeWire, so `scripts/cameras` watches the device nodes with inotify and
//   says who holds one; an application that does go through PipeWire is a
//   link from a video source, as the microphone is. An open shorter than
//   `confirm` is an application asking a device what it can do, and is not
//   believed.
// - **The screen** is niri's: its screencasts (services/Niri.qml), with the
//   consumer found through the PipeWire node a cast streams to, or by the pid
//   niri knows for a wlr-screencopy one.
//
// It runs while something holds it — a privacy cell.
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

    // What is in use: [{ "kind": "microphone" | "camera" | "screen",
    // "app", "detail", "key" }], the microphone first, then the camera, then
    // the screen.
    readonly property var uses: root.microphone.concat(root.camera, root.screen)
    readonly property bool inUse: root.uses.length > 0

    // ---- PipeWire -------------------------------------------------------------------

    readonly property var links: root.active ? Pipewire.linkGroups.values : []

    function has(type, flag) {
        return (type & flag) === flag;
    }

    function capturing(link, media) {
        const source = link.source;
        const target = link.target;
        if (!source || !target)
            return false;
        return root.has(source.type, media | PwNodeType.Source) && !root.has(source.type, PwNodeType.Sink)
            && !source.isStream && target.isStream && root.has(target.type, media);
    }

    // The streams on the far side of a capture: their properties say whose
    // they are, and a node's properties are only filled while it is bound.
    readonly property var takers: root.links.filter(link => root.capturing(link, PwNodeType.Audio)
                                                         || root.capturing(link, PwNodeType.Video))
                                             .map(link => link.target)
    PwObjectTracker {
        objects: root.takers.concat(root.casting)
    }

    function appOf(node) {
        const props = node.properties ?? {};
        return props["application.name"] || props["node.description"] || node.description || node.name || "";
    }

    function deviceOf(node) {
        return node.description || node.nickname || node.name || "";
    }

    function fromLinks(media, kind) {
        const out = [];
        const seen = {};
        for (const link of root.links) {
            if (!root.capturing(link, media))
                continue;
            const app = root.appOf(link.target);
            const key = `${kind}:${app}:${link.source.id}`;
            if (seen[key])
                continue;
            seen[key] = true;
            out.push({ "kind": kind, "app": app, "detail": root.deviceOf(link.source), "key": key });
        }
        return out;
    }

    readonly property var microphone: root.fromLinks(PwNodeType.Audio, "microphone")

    // ---- Cameras ----------------------------------------------------------------------

    readonly property int confirm: Config.get("privacy.camera_confirm", 1500)

    // Holders as the watcher last reported them, each with when it was first
    // seen; `believed` is those held for at least `confirm`.
    property var holding: []
    property var since: ({})
    property double now: Date.now()

    readonly property var believed: root.holding.filter(h => root.now - (root.since[`${h.pid}:${h.device}`] ?? root.now) >= root.confirm)

    Process {
        id: cameras
        command: ["setpriv", "--pdeathsig", "TERM", Quickshell.shellPath("scripts/cameras")]
        running: root.active
        stdout: SplitParser {
            onRead: line => root.held(line)
        }
        onExited: if (root.active) rewatch.start()
    }

    Timer {
        id: rewatch
        interval: 5000
        onTriggered: cameras.running = root.active
    }

    function held(line) {
        let list = [];
        try {
            list = JSON.parse(line);
        } catch (e) {
            return;
        }
        const now = Date.now();
        const since = {};
        for (const h of list) {
            const key = `${h.pid}:${h.device}`;
            since[key] = root.since[key] ?? now;
        }
        root.since = since;
        root.holding = list;
        root.now = now;
        if (list.length > 0)
            believe.restart();
    }

    // Looks again once the youngest holder has been held long enough.
    Timer {
        id: believe
        interval: root.confirm + 50
        onTriggered: root.now = Date.now()
    }

    readonly property var camera: {
        const out = root.fromLinks(PwNodeType.Video, "camera");
        const seen = {};
        for (const h of root.believed) {
            const key = `camera:${h.name}:${h.device}`;
            if (seen[key])
                continue;
            seen[key] = true;
            out.push({ "kind": "camera", "app": h.name, "detail": h.label, "key": key });
        }
        return out;
    }

    // ---- The screen -------------------------------------------------------------------

    readonly property var casts: root.active ? Object.values(Niri.casts).filter(c => c.is_active !== false) : []

    // The PipeWire nodes the casts stream from, so their consumers can be
    // named.
    readonly property var casting: {
        const out = [];
        for (const cast of root.casts) {
            if (cast.pw_node_id === null || cast.pw_node_id === undefined)
                continue;
            for (const link of Pipewire.linkGroups.values)
                if (link.source && link.source.id === cast.pw_node_id && link.target)
                    out.push(link.target);
        }
        return out;
    }

    // Names of the processes niri gives a pid for: asked once per change.
    property var names: ({})

    onCastsChanged: {
        const pids = root.casts.map(c => c.pid).filter(p => p !== null && p !== undefined && root.names[p] === undefined);
        if (pids.length === 0)
            return;
        namer.command = ["ps", "-o", "pid=,comm=", "-p", pids.join(",")];
        namer.running = true;
    }

    Process {
        id: namer
        stdout: StdioCollector {
            onStreamFinished: {
                const names = Object.assign({}, root.names);
                for (const line of this.text.split("\n")) {
                    const match = /^\s*(\d+)\s+(.+)$/.exec(line);
                    if (match)
                        names[match[1]] = match[2].trim();
                }
                root.names = names;
            }
        }
    }

    function targetOf(cast) {
        const target = cast.target ?? {};
        if (target.Output)
            return target.Output.name ?? "";
        if (target.Window) {
            const window = Niri.windows[target.Window.id];
            return window ? (window.title || window.appId || "A window") : "A window";
        }
        return "";
    }

    readonly property var screen: root.casts.map(cast => {
        let app = "";
        if (cast.pid !== null && cast.pid !== undefined)
            app = root.names[cast.pid] ?? "";
        if (!app && cast.pw_node_id !== null && cast.pw_node_id !== undefined) {
            const link = Pipewire.linkGroups.values.find(l => l.source && l.source.id === cast.pw_node_id && l.target);
            if (link)
                app = root.appOf(link.target);
        }
        return { "kind": "screen", "app": app || "Screen", "detail": root.targetOf(cast), "key": `screen:${cast.stream_id}` };
    })
}
