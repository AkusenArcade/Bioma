pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Capture: screenshots, text recognition, video.
//
// Prisma's service was `slurp` into `grim`, plus a `tesseract` pipeline, and
// that is all PRD §9.6 says to keep. The rest of the cell — clipboard, a
// destination folder, video at all — has no predecessor: `wl-copy` appears
// nowhere in Prisma, screenshots land in `/tmp/prisma-shot.png` and stay there,
// and there is no recorder of any kind.
//
// The selection rectangle is not here either, and that is deliberate a second
// time: §9.6 asks for Bioma's own, drawn over a full-screen surface, and a
// service singleton owns no surfaces. `selectRegion()` raises a flag;
// `structure/SelectionSurface.qml` is what draws the rectangle and answers with
// `regionChosen` or `cancelSelection`. The service never learns how the region
// was picked, which is what kept `slurp` swappable for as long as it stood in.
Singleton {
    id: root

    function expand(candidate) {
        const home = Quickshell.env("HOME") ?? "";
        if (candidate.startsWith("~/"))
            return home + candidate.slice(1);
        if (candidate.startsWith("$HOME"))
            return home + candidate.slice(5);
        return candidate;
    }

    readonly property string folder: root.expand(
        Config.get("capture.folder", "$HOME/Pictures/Screenshots"))
    readonly property string videoFolder: root.expand(
        Config.get("capture.video_folder", "$HOME/Videos/Recordings"))

    readonly property bool copyToClipboard: Config.get("capture.clipboard", true)

    // ── Results ──────────────────────────────────────────────────────────

    property string lastPath: ""
    property string lastText: ""
    property string lastError: ""
    property bool busy: false

    signal captured(string path)
    signal recognised(string text)
    signal cancelled
    signal failed(string reason)

    function fail(reason) {
        root.lastError = reason;
        root.busy = false;
        root.failed(reason);
    }

    // Seconds are not fine enough on their own. Two captures inside one second
    // is not a contrived case — a keybind held down does it, and the probe did
    // it by accident — and the second silently overwrote the first, which is a
    // screenshot lost with no error anywhere. The suffix appears only when a
    // second is reused, so ordinary filenames stay readable.
    property string lastStamp: ""
    property int stampSequence: 0

    function timestamp() {
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
        if (stamp === root.lastStamp) {
            root.stampSequence++;
            return `${stamp}-${root.stampSequence}`;
        }
        root.lastStamp = stamp;
        root.stampSequence = 0;
        return stamp;
    }

    function stillPath() {
        return `${root.folder}/screenshot-${root.timestamp()}.png`;
    }

    function videoPath() {
        return `${root.videoFolder}/recording-${root.timestamp()}.mp4`;
    }

    // ── Regions ──────────────────────────────────────────────────────────
    //
    // A region is `x,y WxH` in the compositor's logical coordinates — slurp's
    // format, which grim and wl-screenrec both take.

    // H.264 refuses odd dimensions, and a hand-drawn rectangle produces them
    // half the time. The obvious fix — round the region itself — does not work
    // and was written that way first: the region is logical and the encoder
    // works in physical pixels, and the conversion is not invertible. 101
    // logical at 1.5× is 151.5 physical; rounding that to 152 and dividing back
    // gives 101 again, so the region comes out exactly as odd as it went in.
    //
    // The encode resolution is a separate argument, and it is in physical
    // pixels, so it is the one place where evenness can actually be stated.
    // The region stays as drawn — cropping the user's selection to suit a codec
    // would move the rectangle they drew.
    function encodeResolution(region, scale) {
        const match = region.match(/^\s*(-?\d+),(-?\d+)\s+(\d+)x(\d+)\s*$/);
        if (!match)
            return "";

        const factor = scale > 0 ? scale : 1;

        function even(logical) {
            const physical = Math.round(logical * factor);
            return Math.max(2, physical - (physical % 2));
        }

        return `${even(parseInt(match[3], 10))}x${even(parseInt(match[4], 10))}`;
    }

    function scaleFor(outputName) {
        for (const screen of Quickshell.screens)
            if (screen.name === outputName)
                return screen.devicePixelRatio;
        return 1;
    }

    // The scale that applies to a region is the scale of the output it starts
    // on. A rectangle spanning two outputs of different scales has no single
    // answer, and neither does the encoder — it produces one image.
    function scaleForRegion(region) {
        const match = region.match(/^\s*(-?\d+),(-?\d+)/);
        if (!match)
            return 1;
        const x = parseInt(match[1], 10);
        const y = parseInt(match[2], 10);
        for (const screen of Quickshell.screens)
            if (x >= screen.x && x < screen.x + screen.width
                && y >= screen.y && y < screen.y + screen.height)
                return screen.devicePixelRatio;
        return 1;
    }

    // ── Selection ────────────────────────────────────────────────────────
    //
    // Raising a flag rather than running a program. The surface that draws the
    // rectangle watches this, and hands back a region in the compositor's
    // logical coordinates — the same string `slurp` used to print, so every
    // path below is unchanged.

    property bool selecting: false
    property string pendingAction: ""   // "still" | "text" | "record"

    function selectRegion() {
        root.lastError = "";
        root.selecting = true;
    }

    function regionChosen(region) {
        root.selecting = false;
        if (!region || region.length === 0) {
            root.cancelled();
            return;
        }
        if (root.pendingAction === "text")
            root.recogniseRegion(region);
        else if (root.pendingAction === "record")
            root.recordRegion(region);
        else
            root.captureRegion(region);
    }

    // Escape is a normal way to finish with a screenshot tool, so a cancelled
    // selection is not a failure and nothing reports one.
    function cancelSelection() {
        root.selecting = false;
        root.cancelled();
    }

    // ── Settling ─────────────────────────────────────────────────────────
    //
    // Everything Bioma draws is on the screen being photographed. The cell
    // closes before a capture is asked for and the selection rectangle is taken
    // down before the region is used, but both are animations and neither is
    // finished when the call returns — `grim` run in the same instant catches
    // the panel mid-close, and the recorder catches it in its first frames.
    //
    // So a capture waits for the shell to be gone, once, here: every path goes
    // through it, rather than each caller remembering.
    readonly property int settleTime: Timing.close + 80

    property var pending: null

    function settleThen(action) {
        root.pending = action;
        settle.restart();
    }

    Timer {
        id: settle
        interval: root.settleTime
        onTriggered: {
            const action = root.pending;
            root.pending = null;
            if (action)
                action();
        }
    }

    // ── Stills ───────────────────────────────────────────────────────────

    function captureRegion(region) {
        root.run(["grim", "-g", region, root.stillPath()]);
    }

    function captureOutput(outputName) {
        root.run(outputName && outputName.length > 0
                 ? ["grim", "-o", outputName, root.stillPath()]
                 : ["grim", root.stillPath()]);
    }

    function run(command) {
        root.lastError = "";
        root.busy = true;
        still.target = command[command.length - 1];
        still.command = command;
        root.settleThen(() => {
            still.running = false;
            still.running = true;
        });
    }

    Process {
        id: still
        property string target: ""
        running: false

        onExited: code => {
            if (code !== 0) {
                root.fail(`capture failed (${code})`);
                return;
            }
            root.lastPath = still.target;
            root.busy = false;
            if (root.copyToClipboard)
                root.copyImage(still.target);
            root.captured(still.target);
        }
    }

    // A window is the one shape `grim` cannot take here: it needs the window's
    // rectangle in layout coordinates, and niri reports
    // `tile_pos_in_workspace_view` as null for every window on this version —
    // size, yes, position, no. The compositor does it by window id instead,
    // which is more correct anyway: it captures the window, not the rectangle
    // the window happened to occupy, so nothing in front of it is included.
    //
    // It goes through the clipboard rather than niri's own file. niri's
    // `--write-to-disk` is a boolean, not a path — it writes wherever *niri's*
    // configuration says, which would put Bioma's screenshots in two places
    // depending on which mode was used. Asking for the clipboard and writing
    // the clipboard out keeps the destination Bioma's, and leaves the image on
    // the clipboard where §9.6 wants it.
    //
    // The wait is not decoration. `niri msg` returns when the action has been
    // dispatched, not when the image is on the clipboard, so reading it
    // immediately hands back *the previous clipboard contents* — reproduced
    // deliberately: with a red 101×51 image copied first, the chained read
    // returned that image instead of the window, and reported success.
    //
    // It waits for the contents to *change*, not for them to appear. Clearing
    // first and waiting for something to show up was the first attempt and does
    // not work: a clipboard manager — `wl-paste --watch cliphist store` on this
    // machine, a common enough setup — puts the old selection straight back, so
    // `wl-copy --clear` does not stick and the poll succeeds immediately on
    // stale content. Comparing a checksum is indifferent to who owns the
    // selection.
    //
    // The cost is that capturing the same unchanged window twice waits the full
    // two seconds before writing the correct, identical bytes. That is the
    // rare case; being confidently wrong is not an acceptable common one.
    function captureWindow(windowId) {
        root.lastError = "";
        root.busy = true;
        const path = root.stillPath();
        windowShot.target = path;
        const id = windowId > 0 ? ` --id ${windowId}` : "";
        const quoted = JSON.stringify(path);
        windowShot.command = ["sh", "-c",
            "before=$(wl-paste --type image/png 2>/dev/null | md5sum); "
            + `niri msg action screenshot-window${id} -d false || exit 1; `
            + "i=0; while [ $i -lt 40 ]; do "
            + "now=$(wl-paste --type image/png 2>/dev/null | md5sum); "
            + "[ \"$now\" != \"$before\" ] && break; "
            + "sleep 0.05; i=$((i+1)); done; "
            + `wl-paste --type image/png > ${quoted} 2>/dev/null; `
            + `[ -s ${quoted} ]`];
        windowShot.running = false;
        windowShot.running = true;
    }

    Process {
        id: windowShot
        property string target: ""
        running: false

        onExited: code => {
            if (code !== 0) {
                root.fail(`window capture failed (${code})`);
                return;
            }
            root.lastPath = windowShot.target;
            root.busy = false;
            root.captured(windowShot.target);
        }
    }

    // ── Clipboard ────────────────────────────────────────────────────────
    //
    // A Wayland clipboard is served by whoever owns the selection, so something
    // has to stay alive holding the data. `wl-copy` forks and does that itself
    // unless told `--foreground`, which is why one Process can be reused here:
    // it exits immediately, and the copy it left behind is not killed when the
    // next capture reuses it. Passing `--foreground` would break exactly that.

    function copyImage(path) {
        imageClip.command = ["sh", "-c",
                             `wl-copy --type image/png < ${JSON.stringify(path)}`];
        imageClip.running = false;
        imageClip.running = true;
    }

    function copyText(text) {
        textClip.command = ["wl-copy", "--type", "text/plain", "--", text];
        textClip.running = false;
        textClip.running = true;
    }

    Process { id: imageClip; running: false }
    Process { id: textClip; running: false }

    // ── Text recognition ─────────────────────────────────────────────────
    //
    // Prisma's OCR path ran `slurp` a second time inside its own shell, so the
    // region it recognised was not the region it had just been given. Harmless
    // there, wrong the moment Bioma owns selection — the region arrives as an
    // argument here and is captured once.

    readonly property string language: Config.get("capture.ocr_language", "eng")

    function recogniseRegion(region) {
        root.lastError = "";
        root.busy = true;
        ocr.buffer = "";
        ocr.command = ["sh", "-c",
                       `grim -g ${JSON.stringify(region)} - | `
                       + `tesseract - stdout -l ${root.language} 2>/dev/null`];
        root.settleThen(() => {
            ocr.running = false;
            ocr.running = true;
        });
    }

    Process {
        id: ocr
        property string buffer: ""
        running: false

        onRunningChanged: if (running) ocr.buffer = "";

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => ocr.buffer += line + "\n"
        }

        onExited: code => {
            root.busy = false;
            const text = ocr.buffer.trim();
            if (code !== 0) {
                root.fail(`recognition failed (${code})`);
                return;
            }
            // Nothing recognised is a result, not an error: a region of empty
            // desktop genuinely contains no text.
            root.lastText = text;
            if (text.length > 0 && root.copyToClipboard)
                root.copyText(text);
            root.recognised(text);
        }
    }

    // ── Video ────────────────────────────────────────────────────────────
    //
    // No audio (§9.6), H.264, and the file is written to a temporary directory
    // and only moved into place when the user saves — a discarded recording
    // must not leave anything among their own files.
    //
    // wl-screenrec with VAAPI handles both region and full screen on AMD, which
    // is why one backend is enough here. `wf-recorder` is the fallback on
    // hardware where it is not, and is not written yet.

    readonly property int fps: Config.get("capture.fps", 60)
    readonly property string codec: Config.get("capture.codec", "avc")
    readonly property string bitrate: Config.get("capture.bitrate", "5 MB")

    property bool recording: false
    property string pendingVideo: ""
    property int elapsed: 0

    signal recordingStarted
    signal recordingFinished(string temporaryPath)
    signal recordingSaved(string path)
    signal recordingDiscarded

    // Elapsed seconds, and the reason the recording cell exists at all: a
    // screenshot is instantaneous and has nothing to say afterwards, while a
    // recording has a duration, so a conditional cell stands for as long as it
    // runs. The figure is real — this is a count of seconds, not a decorative
    // animation.
    Timer {
        interval: 1000
        running: root.recording
        repeat: true
        onTriggered: root.elapsed++
    }

    readonly property string temporaryDirectory:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bioma-capture"

    function recordRegion(region) {
        const resolution = root.encodeResolution(region, root.scaleForRegion(region));
        const target = ["-g", region];
        if (resolution.length > 0)
            target.push("--encode-resolution", resolution);
        root.startRecorder(target);
    }

    function recordOutput(outputName) {
        root.startRecorder(outputName && outputName.length > 0
                           ? ["-o", outputName] : []);
    }

    function startRecorder(target) {
        if (root.recording)
            return;
        root.lastError = "";
        root.elapsed = 0;
        root.pendingVideo = `${root.temporaryDirectory}/recording-${root.timestamp()}.mp4`;
        recorder.pending = target;
        root.settleThen(() => {
            prepareTemporary.running = false;
            prepareTemporary.running = true;
        });
    }

    Process {
        id: prepareTemporary
        command: ["mkdir", "-p", root.temporaryDirectory]
        running: false
        onExited: code => {
            if (code !== 0) {
                root.fail("could not create the temporary directory");
                return;
            }
            recorder.command = ["wl-screenrec",
                                "--filename", root.pendingVideo,
                                "--codec", root.codec,
                                "--max-fps", String(root.fps),
                                "--bitrate", root.bitrate,
                                "--no-cursor"].concat(recorder.pending);
            recorder.running = true;
        }
    }

    Process {
        id: recorder
        property var pending: []
        running: false

        onStarted: {
            root.recording = true;
            root.recordingStarted();
        }

        onExited: code => {
            root.recording = false;
            // SIGINT is how a recording ends, so the shell's own stop signal
            // arrives here as 130 rather than 0. Treating that as a failure
            // would discard every successful recording.
            if (code !== 0 && code !== 130 && code !== 2) {
                root.fail(`recording failed (${code})`);
                root.pendingVideo = "";
                return;
            }
            root.recordingFinished(root.pendingVideo);
        }
    }

    // wl-screenrec finalises the container on SIGINT. Killing it outright
    // leaves an unplayable file with no moov atom.
    function stopRecording() {
        if (root.recording)
            recorder.signal(2);  // SIGINT
    }

    function saveRecording() {
        if (root.pendingVideo.length === 0)
            return;
        move.target = `${root.videoFolder}/` + root.pendingVideo.split("/").pop();
        move.command = ["sh", "-c",
                        `mkdir -p ${JSON.stringify(root.videoFolder)} && `
                        + `mv ${JSON.stringify(root.pendingVideo)} ${JSON.stringify(move.target)}`];
        move.running = false;
        move.running = true;
    }

    Process {
        id: move
        property string target: ""
        running: false
        onExited: code => {
            if (code !== 0) {
                root.fail("could not move the recording into place");
                return;
            }
            root.lastPath = move.target;
            root.pendingVideo = "";
            root.recordingSaved(move.target);
        }
    }

    function discardRecording() {
        if (root.pendingVideo.length === 0)
            return;
        discard.command = ["rm", "-f", root.pendingVideo];
        discard.running = false;
        discard.running = true;
    }

    Process {
        id: discard
        running: false
        onExited: {
            root.pendingVideo = "";
            root.recordingDiscarded();
        }
    }

    // ── Destination ──────────────────────────────────────────────────────
    //
    // Made once at startup rather than checked before every capture: `grim`
    // will not create it, and a screenshot that fails because a directory is
    // missing is a screenshot lost at the moment it was wanted.

    Process {
        command: ["mkdir", "-p", root.folder]
        running: true
    }
}
