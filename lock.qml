import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.core
import qs.lock

// Bioma's lock screen — a second entry point, and a process of its own.
//
// Not a part of the shell, on purpose. A lock screen that fails shuts its owner
// out of their own session, and the shell is the larger program: every cell,
// every service, every poller. Here there is the lock, the password and the
// picture behind them. If the shell falls over, the screen stays locked; if
// this falls over, niri keeps the outputs locked and `scripts/lock`, which
// started it, starts hyprlock in its place.
//
// It is started by `scripts/lock` and by nothing else, and it ends by
// unlocking: there is no way to put it away without the password.
//
// Akusen decided on 2026-09-23 that Bioma has a lock screen of its own, against
// PRD §2. What it shows was his choice too: the wallpaper blurred, the time and
// the date, who is logged in, and the field. Nothing else — at rest the
// interface does not speak, and a locked desktop is the most at rest it gets.
ShellRoot {
    id: root

    // The screen the keyboard is on. niri hands the keys to the lock surface
    // of the focused output, so that is where the field has to be; asked
    // once, at start, and moved by a press on another screen.
    property string active: ""

    property string password: ""
    property bool checking: false
    property bool failed: false
    property string reason: ""

    // ---- What it shows ---------------------------------------------------------

    // The wallpaper as the shell last left it, read from the shell's own
    // state file. Read, never written, and without the wallpaper service: that
    // one scans the library and makes thumbnails, which is no work for a lock
    // screen to be doing.
    FileView {
        id: wallpaperState
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/bioma/wallpaper.json`
        blockLoading: true
        printErrors: false
    }

    readonly property var wallpaper: {
        try {
            return JSON.parse(wallpaperState.text()) || {};
        } catch (error) {
            return {};
        }
    }

    readonly property string wallpaperMode: root.wallpaper.mode || "fill"

    function wallpaperFor(screenName) {
        const perMonitor = root.wallpaper.perMonitorPaths || {};
        let path = root.wallpaperMode === "per_monitor" && perMonitor[screenName]
                 ? perMonitor[screenName] : (root.wallpaper.path || "");
        if (path.startsWith("~/"))
            path = Quickshell.env("HOME") + path.slice(1);
        return path;
    }

    // The clock says the time the way the clock cell does, wherever that cell
    // is placed.
    readonly property bool twentyFourHour: {
        const lists = [Config.get("membranes", []), Config.get("floating", [])];
        for (const list of lists)
            for (const block of list)
                for (const group of (block.tissues || [block]))
                    for (const cell of (group.cells || []))
                        if (cell.type === "clock" && cell.options && cell.options.format)
                            return cell.options.format === "24h";
        return true;
    }

    // ---- The lock -------------------------------------------------------------

    WlSessionLock {
        id: lock

        locked: true

        // Everything is on screen and the compositor says so: the session is
        // locked in the sense logind means, and whoever is waiting on it —
        // `scripts/lock`, the shell holding up a suspend — can go on.
        onSecureChanged: if (secure) root.hint(true)

        onLockedChanged: {
            if (!locked)
                root.finish();
        }

        LockSurface {
            lockState: root
        }
    }

    function finish() {
        root.hint(false);
        // A beat for the compositor to take the surfaces down before the
        // process that owns them goes.
        quitLater.start();
    }

    Timer {
        id: quitLater
        interval: Timing.close
        onTriggered: Qt.quit()
    }

    // ---- Checking the password -------------------------------------------------

    // Bioma's own PAM file, beside the repository rather than in /etc: see
    // assets/pam/bioma-lock for why it is not `login`.
    PamContext {
        id: pam

        configDirectory: Qt.resolvedUrl("assets/pam").toString().replace("file://", "")
        config: "bioma-lock"

        onResponseRequiredChanged: {
            if (responseRequired)
                respond(root.password);
        }

        onCompleted: result => {
            root.checking = false;
            if (result === PamResult.Success) {
                root.failed = false;
                lock.locked = false;
                return;
            }
            root.failed = true;
            root.reason = result === PamResult.MaxTries ? "Too many attempts"
                        : "That is not the password";
        }

        onError: error => {
            root.checking = false;
            root.failed = true;
            root.reason = "The password could not be checked";
            console.warn(`Bioma lock: PAM error — ${PamError.toString(error)}`);
        }
    }

    function submit() {
        if (root.checking || root.password.length === 0)
            return;
        root.checking = true;
        root.failed = false;
        if (!pam.start()) {
            root.checking = false;
            root.failed = true;
            root.reason = "The password could not be checked";
        }
    }

    // ---- What the lock tells the rest of the machine ----------------------------

    // logind's own flag for "this session is locked". `scripts/lock` waits for
    // it before deciding the lock took; the shell waits for it before letting
    // a suspend go ahead.
    function hint(locked) {
        Quickshell.execDetached(["sh", "-c",
            "s=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 "
            + "org.freedesktop.login1.Manager GetSession s auto | cut -d'\"' -f2) && "
            + "busctl call org.freedesktop.login1 \"$s\" org.freedesktop.login1.Session "
            + `SetLockedHint b ${locked}`]);
    }

    // ---- Where the keyboard is ------------------------------------------------

    Process {
        running: true
        command: ["niri", "msg", "--json", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const output = JSON.parse(text);
                    if (output && output.name)
                        root.active = output.name;
                } catch (error) {
                    // Not niri, or not answering: the first screen will do.
                }
                if (root.active.length === 0 && Quickshell.screens.length > 0)
                    root.active = Quickshell.screens[0].name;
            }
        }
    }
}
