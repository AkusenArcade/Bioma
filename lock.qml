import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.core
import qs.components
import qs.services
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
    property string active: scenery.focusedOutput

    property string password: ""
    property bool checking: false
    // The password was right and the lock is on its way out: the surfaces
    // play their departure, and the session unlocks when it is over.
    property bool leaving: false
    property bool failed: false
    property string reason: ""

    // ---- What it shows ---------------------------------------------------------

    // Who is logged in, for the threshold.
    readonly property string fullName: Session.fullName
    readonly property url avatar: Session.avatar
    readonly property bool hasAvatar: Session.hasAvatar
    function avatarFailed() { Session.avatarFailed(); }

    // The wallpaper, its mode, the density and the clock's format, read from
    // where the shell left them.
    GateScenery {
        id: scenery
    }

    readonly property string wallpaperMode: scenery.wallpaperMode
    function wallpaperFor(screenName) { return scenery.wallpaperFor(screenName); }
    readonly property string density: scenery.density
    readonly property bool twentyFourHour: scenery.twentyFourHour

    // ---- The desktop, as it was -------------------------------------------------
    //
    // The lock does not cut to itself. A moment before it takes the screens,
    // each one is photographed, and the first frame of the lock is that
    // photograph: the desktop as it was, which then blurs and dissolves into
    // the wallpaper behind the composition. Leaving, it goes back the same way
    // and the session unlocks onto the picture it came from — so the eye sees
    // one movement in and one out, never a cut.
    //
    // `grim`, a process, rather than a live capture inside the lock: a
    // screencopy view held by a surface that goes away has crashed Quickshell
    // before, and a lock screen is the one place that must not. Without grim
    // the lock starts from the wallpaper, sharp, which is the next best thing.
    //
    // The photographs are the screen's contents, so they live in the runtime
    // directory — memory, readable only by the user — and are removed when
    // the lock ends, and again when the next one starts.
    readonly property string captureDirectory:
        `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/bioma-lock`

    function captureFor(screenName) {
        return `${root.captureDirectory}/${screenName}.png`;
    }

    Process {
        running: true
        command: ["sh", "-c",
            'umask 077; d="$1"; shift; rm -rf "$d"; mkdir -p "$d"; '
            + 'command -v grim >/dev/null || exit 0; '
            + 'for o in "$@"; do grim -l 0 -o "$o" "$d/$o.png" & done; wait',
            "capture", root.captureDirectory,
            ...Quickshell.screens.map(screen => screen.name)]
        onExited: root.begin()
    }

    // Never later than this, however long the photographs take: a lock that
    // waits on a screenshot is a lock that is late.
    Timer {
        id: captureGuard
        running: true
        interval: Timing.open
        onTriggered: root.begin()
    }

    function begin() {
        captureGuard.stop();
        if (!lock.locked && !root.leaving)
            lock.locked = true;
    }

    // ---- The lock -------------------------------------------------------------

    WlSessionLock {
        id: lock

        locked: false

        // Everything is on screen and the compositor says so: the session is
        // locked in the sense logind means, and whoever is waiting on it —
        // `scripts/lock`, the shell holding up a suspend — can go on.
        onSecureChanged: if (secure) root.hint(true)

        // Only when the compositor ends the lock on its own: since Quickshell
        // 0.3.2 the signal no longer fires for `locked = false` set from
        // here, so `departure` finishes directly.
        onLockedChanged: {
            if (!locked)
                root.finish();
        }

        LockSurface {
            lockState: root
        }
    }

    // The composition goes quickly, then the picture clears back to the
    // desktop; the session unlocks once both have.
    Timer {
        id: departure
        interval: Timing.close + Timing.open
        onTriggered: {
            lock.locked = false;
            root.finish();
        }
    }

    // Once, whichever way the lock ended. A process left behind after an
    // unlock is a lock that `scripts/lock` believes is still up, and every
    // later lock would stop there.
    property bool finished: false

    function finish() {
        if (root.finished)
            return;
        root.finished = true;
        root.hint(false);
        Quickshell.execDetached(["rm", "-rf", root.captureDirectory]);
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
                root.leaving = true;
                departure.start();
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
}
