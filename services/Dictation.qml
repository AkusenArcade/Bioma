pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Dictation: speech to text, into the window that has the focus.
//
// PRD §9.6. One take is three processes in a row, each started when it is
// needed and gone when it is done: `scripts/listen` while the user speaks,
// `whisper-cli` on what was said, and `scripts/paste` to put the text where
// the keyboard is pointed. Nothing stays resident between takes. The model is
// read from the page cache in a fraction of a second, and that is the price of
// not holding it in memory all day.
//
// The text is pasted, not typed: see `scripts/paste` for why `wtype` cannot
// do it.
//
// Every process runs under `setpriv --pdeathsig`: a shell that dies must not
// leave a microphone open behind it.
Singleton {
    id: root

    // ---- Configuration ------------------------------------------------------

    readonly property string model: Config.get("capture.dictation.model",
        "/usr/share/whisper.cpp-model-large-v3-turbo-q5_0/ggml-large-v3-turbo-q5_0.bin")
    readonly property string language: Config.get("capture.dictation.language", "auto")
    readonly property int maxSeconds: Config.get("capture.dictation.max_seconds", 120)
    readonly property var terminals: Config.get("capture.dictation.terminals", [])

    // ---- State --------------------------------------------------------------

    // "idle" | "listening" | "transcribing"
    property string state: "idle"
    readonly property bool listening: root.state === "listening"
    readonly property bool transcribing: root.state === "transcribing"
    readonly property bool active: root.state !== "idle"

    // Seconds spoken so far, counted while listening.
    property int elapsed: 0

    // The microphone's level while listening, 0–1 on a decibel scale: speech
    // sits far below full scale, and a linear peak would barely move. The
    // peak comes from the recorder itself (see `scripts/listen` for why not
    // from a PipeWire peak monitor).
    property real peak: 0
    readonly property real level: {
        if (!root.listening || root.peak <= 0)
            return 0;
        const db = 20 * Math.log10(root.peak);
        return Math.max(0, Math.min(1, (db + 50) / 50));
    }

    // Whether the engine and the model are there. Checked at start and again
    // whenever the model's path changes; without them the panel draws
    // dictation as unavailable rather than offering it and failing.
    property bool available: false

    // The paste goes through the clipboard twice, the text and then the
    // restore of what was there. Neither is the user copying, so the
    // clipboard cell is kept quiet from the paste until the restore has
    // reached the history.
    Binding {
        target: Clipboard
        property: "quiet"
        value: root.transcribing || hushTail.running
    }

    Timer {
        id: hushTail
        interval: Timing.hush
    }

    readonly property string temporaryDirectory:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bioma-dictation"
    property string take: ""

    onModelChanged: probe.running = true
    Component.onCompleted: probe.running = true

    Process {
        id: probe
        command: ["sh", "-c", 'command -v whisper-cli >/dev/null && [ -r "$1" ]', "probe", root.model]
        running: false
        onExited: code => root.available = code === 0
    }

    // ---- Taking -------------------------------------------------------------

    function toggle() {
        if (root.listening)
            root.stop();
        else if (!root.active)
            root.start();
    }

    // Capture's recorder and this one are one capture at a time: the cell has
    // one contracted form to speak with.
    readonly property bool blocked: Capture.recording || Capture.pendingVideo.length > 0

    function start() {
        if (root.active || root.blocked)
            return;
        if (!root.available) {
            root.tell("Dictation is not available",
                      "whisper-cli or its model is missing.");
            return;
        }
        root.elapsed = 0;
        root.peak = 0;
        root.take = `${root.temporaryDirectory}/take-${Date.now()}.wav`;
        root.state = "listening";
        paster.running = true;
        recorder.running = true;
        console.info("Dictation: listening");
    }

    // Stopping is what transcribes. The recorder closes the file properly on
    // SIGINT; killed outright it would leave a header that says zero samples.
    function stop() {
        if (!root.listening)
            return;
        root.state = "transcribing";
        recorder.signal(2);
    }

    // Nothing transcribed, nothing typed, nothing kept.
    function cancel() {
        if (!root.active)
            return;
        console.info("Dictation: cancelled");
        root.cancelling = true;
        recorder.running = false;
        engine.running = false;
        root.finish();
    }

    property bool cancelling: false

    function finish() {
        if (root.transcribing)
            hushTail.restart();
        paster.running = false;
        if (root.take.length > 0)
            Quickshell.execDetached(["rm", "-f", root.take]);
        root.take = "";
        root.state = "idle";
        root.cancelling = false;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.listening
        onTriggered: root.elapsed++
    }

    // A forgotten toggle does not keep the microphone open.
    Timer {
        interval: root.maxSeconds * 1000
        running: root.listening
        onTriggered: {
            console.info(`Dictation: stopped at the ${root.maxSeconds} s ceiling`);
            root.stop();
        }
    }

    Process {
        id: recorder
        running: false
        command: ["setpriv", "--pdeathsig", "TERM",
                  Quickshell.shellPath("scripts/listen"), root.take]

        stdout: SplitParser {
            onRead: line => root.peak = parseFloat(line) || 0
        }

        onExited: code => {
            if (root.cancelling || root.state !== "transcribing")
                return;
            engine.text = "";
            engine.running = true;
        }
    }

    // ---- Transcribing -------------------------------------------------------

    Process {
        id: engine

        property string text: ""

        running: false
        command: ["setpriv", "--pdeathsig", "TERM",
                  "whisper-cli", "--model", root.model, "--language", root.language,
                  "--no-timestamps", "--no-prints", "--file", root.take]

        stdout: SplitParser {
            onRead: line => engine.text += line + "\n"
        }

        onExited: code => {
            if (root.cancelling)
                return;
            if (code !== 0) {
                root.tell("Dictation failed", `whisper-cli exited with ${code}.`);
                root.finish();
                return;
            }
            root.deliver(root.clean(engine.text));
        }
    }

    // Whisper marks what is not speech in brackets — [BLANK_AUDIO], (music) —
    // and a line of nothing but that is not something the user said.
    function clean(raw) {
        return raw.split("\n")
            .map(line => line.trim())
            .filter(line => line.length > 0 && !/^[\[(].*[\])]$/.test(line))
            .join(" ")
            .replace(/\s+/g, " ")
            .trim();
    }

    // ---- Delivering ---------------------------------------------------------

    function isTerminal(appId) {
        const id = (appId || "").toLowerCase();
        return root.terminals.some(t => String(t).toLowerCase() === id);
    }

    function deliver(text) {
        // Nothing said is nothing typed, and nothing to report either.
        if (text.length === 0) {
            console.info("Dictation: nothing heard");
            root.finish();
            return;
        }
        // No window to paste into: the text stays on the clipboard rather
        // than be pasted into nothing and then taken back by the restore.
        paster.write(JSON.stringify({
            "text": text,
            "terminal": root.isTerminal(Niri.focusedAppId),
            "copyOnly": !Niri.focusedWindow || !paster.canPaste
        }) + "\n");
    }

    Process {
        id: paster

        property bool canPaste: false

        running: false
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", Quickshell.shellPath("scripts/paste")]

        onStarted: paster.canPaste = false

        stdout: SplitParser {
            onRead: line => {
                if (line === "ready") {
                    paster.canPaste = true;
                } else if (line === "no-uinput") {
                    paster.canPaste = false;
                    console.warn("Dictation: /dev/uinput is not writable; the text will be left on the clipboard");
                } else if (line === "pasted") {
                    console.info("Dictation: pasted");
                    root.finish();
                } else if (line === "copied") {
                    root.tell("Dictation is on the clipboard", "Paste it with Ctrl+V.");
                    root.finish();
                }
            }
        }
    }

    // ---- Saying so ----------------------------------------------------------
    //
    // Only what the cell can no longer say: by the time a take fails or ends
    // on the clipboard, the cell has gone quiet.

    function tell(summary, body) {
        console.warn("Dictation:", summary, body);
        Quickshell.execDetached(["notify-send", "--app-name=Bioma",
                                 "--icon=audio-input-microphone", summary, body]);
    }
}
