pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The sound leaving the machine, as bands.
//
// The capture and the transform are not here and cannot be: Quickshell has no
// way to read a PipeWire stream, and `docs/design/IMPLEMENTATION.md` requires
// the split anyway — two processes capturing the same audio is an error that
// does not show immediately and is paid for later. So `tools/sinestesia-bands`
// does that work, one process, and this service reads what it emits.
//
// The numbers behind the band — window, binning, dB mapping, attack and decay —
// are Sinestesia's, taken from its own source. The design fixes the form of the
// band and says plainly that the behaviour is defined there.
//
// It runs only while something is looking at it. Whether the cell is on screen
// at all is a different question, and `services/Audio.qml` answers it from the
// peak monitor without any of this running.
Singleton {
    id: root

    // Bound by the cell. Nothing runs until it is true, and the process is shut
    // by closing it: it exits when its stdout does.
    property bool active: false

    readonly property int bandCount: Config.get("sinestesia.bands", 64)
    readonly property int fps: Config.get("sinestesia.fps", 60)
    readonly property real gain: Config.get("sinestesia.gain", 1.0)
    // "output" — what the machine is playing — or "input", a microphone.
    readonly property string source: Config.get("sinestesia.source", "output")

    readonly property string binary:
        `${Quickshell.shellDir}/tools/sinestesia-bands/target/release/sinestesia-bands`

    // One spectrum per channel, `bandCount` values from 0 to 1 each, lowest
    // frequency first. The band is mirrored from the middle — left channel on
    // the left, right channel on the right, the low frequencies meeting at the
    // centre — which is how Sinestesia draws it and why the tool keeps the two
    // apart all the way from the capture.
    property var left: []
    property var right: []

    // The loudest band of the last frame, which is what a cell asks when it
    // wants one number rather than a shape.
    property real level: 0

    // Without the tool built there is no band, and a cell with nothing to say
    // does not appear. The shell does not fall back to something else: half a
    // visualiser is worse than none.
    property bool available: true
    property int failures: 0

    Process {
        id: emitter

        running: root.active && root.available
        command: [root.binary,
                  "--bands", String(root.bandCount),
                  "--fps", String(root.fps),
                  "--gain", String(root.gain),
                  "--source", root.source]

        // One line per frame, two hexadecimal digits per band. Parsed by
        // character rather than split and converted: at sixty frames a second
        // this is the one place in the shell where that difference is real.
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.take(line)
        }

        onExited: code => {
            root.left = [];
            root.right = [];
            root.level = 0;
            if (code === 0)
                return;
            root.failures++;
            if (root.failures > 2) {
                root.available = false;
                console.warn("Sinestesia: no bands — is tools/sinestesia-bands built?");
            }
        }

        onStarted: root.failures = 0
    }

    function take(line) {
        const text = line.trim();
        const half = Math.floor(text.length / 4);
        if (half === 0)
            return;

        const one = new Array(half);
        const other = new Array(half);
        let loudest = 0;

        for (let i = 0; i < half; i++) {
            const l = parseInt(text.substr(i * 2, 2), 16) / 255;
            const r = parseInt(text.substr((half + i) * 2, 2), 16) / 255;
            one[i] = l;
            other[i] = r;
            if (l > loudest) loudest = l;
            if (r > loudest) loudest = r;
        }

        root.left = one;
        root.right = other;
        root.level = loudest;
    }

    // The band the cell draws is coarser than the one that arrives: seven
    // capsules a side contracted, seventeen open, out of sixty-four. Folded by
    // peak rather than by mean, for the same reason the tool takes the peak bin
    // inside a band — a mean turns a snare into a shrug.
    function fold(source, into) {
        if (into <= 0 || !source || source.length === 0)
            return [];
        if (into >= source.length)
            return source;

        const out = new Array(into);
        for (let i = 0; i < into; i++) {
            const from = Math.floor(i * source.length / into);
            const to = Math.max(from + 1, Math.floor((i + 1) * source.length / into));
            let peak = 0;
            for (let b = from; b < to; b++)
                if (source[b] > peak)
                    peak = source[b];
            out[i] = peak;
        }
        return out;
    }
}
