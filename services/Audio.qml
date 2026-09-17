pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.core

// Audio: devices, streams, and the signal itself.
//
// Prisma stopped at the volume and mute of the default sink, which is the easy
// tenth of this. The rest — choosing an output or input device, and a volume per
// application — means following PipeWire nodes as they appear and disappear, and
// that is what the expanded volume cell is almost entirely made of.
//
// PwObjectTracker is not optional bookkeeping. A node that nothing tracks stays
// unpopulated: its `audio` is null and its volume reads zero, which looks
// exactly like a muted application rather than like a node nobody asked for.
Singleton {
    id: root

    // ── Defaults ─────────────────────────────────────────────────────────

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // PipeWire allows volumes above 100%, and refusing to show that would make
    // the indicator lie about the state of the system.
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volumePercent: Math.round(volume * 100)

    readonly property real inputVolume: source?.audio?.volume ?? 0
    readonly property bool inputMuted: source?.audio?.muted ?? false

    readonly property real maxVolume: 1.5

    function setVolume(value) {
        if (root.sink?.audio)
            root.sink.audio.volume = Math.max(0, Math.min(root.maxVolume, value));
    }

    function stepVolume(delta) {
        root.setVolume(root.volume + delta);
    }

    function toggleMute() {
        if (root.sink?.audio)
            root.sink.audio.muted = !root.muted;
    }

    function setInputVolume(value) {
        if (root.source?.audio)
            root.source.audio.volume = Math.max(0, Math.min(root.maxVolume, value));
    }

    function toggleInputMute() {
        if (root.source?.audio)
            root.source.audio.muted = !root.inputMuted;
    }

    // ── Devices ──────────────────────────────────────────────────────────

    readonly property var allNodes: Pipewire.nodes?.values ?? []

    // Filtering by `isSink` and `isStream` alone is not enough, and fails in a
    // way that looks plausible: PipeWire's graph also holds its own driver
    // nodes, MIDI bridges and every webcam, and all of them answer false to
    // both. A list of microphones offering "Freewheel-Driver" and two webcams
    // is the result.
    //
    // The node type is a flag set — Audio 1, Video 2, Stream 4, Source 8,
    // Sink 16 — so AudioSource is 9 and VideoSource is 10, and masking
    // separates them where a boolean cannot.
    function isType(node, flags) {
        return (node.type & flags) === flags;
    }

    readonly property var outputs: allNodes.filter(
        node => root.isType(node, PwNodeType.AudioSink) && !node.isStream)

    readonly property var inputs: allNodes.filter(
        node => root.isType(node, PwNodeType.AudioSource) && !node.isStream)

    // Note that the `.monitor` source every sink publishes does not appear here
    // at all: Quickshell does not surface them as nodes, though `pactl` lists
    // them. Nothing needs filtering out, and the visualiser will have to reach
    // a monitor some other way when it comes to that.

    // A device's own words for itself, in descending order of how much thought
    // went into them. `name` is the ALSA path and is never shown to anyone.
    function describe(node) {
        if (!node)
            return "";
        return node.nickname || node.description || node.name || "";
    }

    // Changing the default is a preference, not a command: PipeWire applies it
    // and reports back through `defaultAudioSink`, so nothing here assumes it
    // took effect.
    function setDefaultOutput(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultInput(node) {
        if (node)
            Pipewire.preferredDefaultAudioSource = node;
    }

    function isDefaultOutput(node) { return node === root.sink; }
    function isDefaultInput(node) { return node === root.source; }

    // ── Streams — per-application volume ─────────────────────────────────
    //
    // The expensive part, and the reason this service has to track objects
    // rather than read a couple of properties. Streams come and go constantly:
    // a notification sound is a node that exists for a second and a half.

    // An application playing audio is an AudioOutStream — a stream that is a
    // sink from the graph's point of view, because sound flows into it.
    // Something recording is an AudioInStream.
    readonly property var streams: allNodes.filter(
        node => root.isType(node, PwNodeType.AudioOutStream))
    readonly property var recordingStreams: allNodes.filter(
        node => root.isType(node, PwNodeType.AudioInStream))

    readonly property int streamCount: streams.length
    readonly property bool anyoneRecording: recordingStreams.length > 0

    // What to call a stream in the list. An application publishes its name in
    // its properties; `media.name` is usually the track or the page title, which
    // is more informative and also changes under the user's hand, so the
    // application's own name comes first.
    function describeStream(node) {
        if (!node)
            return "";
        const properties = node.properties ?? ({});
        return properties["application.name"]
            || node.description
            || properties["media.name"]
            || node.name
            || "";
    }

    // For resolving an icon: the desktop entry if the application published one,
    // otherwise its declared icon name.
    function streamIcon(node) {
        const properties = node?.properties ?? ({});
        return properties["application.icon-name"]
            || properties["application.process.binary"]
            || "";
    }

    function setStreamVolume(node, value) {
        if (node?.audio)
            node.audio.volume = Math.max(0, Math.min(root.maxVolume, value));
    }

    function toggleStreamMute(node) {
        if (node?.audio)
            node.audio.muted = !node.audio.muted;
    }

    // Everything exposed above is bound here, or its `audio` is never populated
    // and every volume in the list reads zero.
    PwObjectTracker {
        objects: [root.sink, root.source]
            .concat(root.outputs)
            .concat(root.inputs)
            .concat(root.streams)
            .concat(root.recordingStreams)
            .filter(node => node !== null && node !== undefined)
    }

    // ── The signal ───────────────────────────────────────────────────────
    //
    // Sinestesia's condition is the audio signal leaving the machine, not MPRIS
    // playback — a game or a browser tab with no metadata must still raise the
    // cell. This is that signal, read from the default sink.
    //
    // It is deliberately not the visualiser. The visualiser needs bands, which
    // means capture and an FFT living in their own process; this is one number,
    // and one number is all a visibility condition needs.
    readonly property bool monitoring: Config.get("audio.monitor_signal", true)

    readonly property real peak: peakMonitor.peak
    readonly property bool signalPresent: peak > 0

    PwNodePeakMonitor {
        id: peakMonitor
        node: root.sink
        enabled: root.monitoring && root.sink !== null
    }
}
