import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.core
import qs.components
import qs.greeter

// Bioma's greeter — a third entry point, run by greetd before anyone is logged
// in.
//
// It is the lock screen's threshold (components/Gate.qml) with greetd in place
// of PAM: the same wallpaper and mode, the same palette and appearance, the
// same clock, so that logging in and unlocking are one gesture. Akusen asked
// for it on 2026-09-24, with the wallpaper synced as image and as mode (span
// included) and the interactive elements only on the primary monitor.
//
// It runs as the `greeter` user, who cannot read the person's home. So it runs
// from a copy the shell keeps up to date (scripts/greeter-sync): this file and
// what it imports, the configuration under `config/` — XDG_CONFIG_HOME points
// there, so Config, Theme and the gate's scenery read the person's own values
// — the wallpapers, the fonts, and `user.json`, who to greet.
//
// scripts/greeter-session starts it inside a minimal niri, and ends that niri
// when this ends.
ShellRoot {
    id: root

    // Where the copy is. The session script says so; run from the repository
    // for a test, it is the directory above this file.
    readonly property string home: Quickshell.env("BIOMA_GREETER_DIR")
        || Qt.resolvedUrl("..").toString().replace("file://", "").replace(/\/$/, "")

    // ---- Who ------------------------------------------------------------------

    FileView {
        id: userFile
        path: `${root.home}/user.json`
        blockLoading: true
        printErrors: false
    }

    readonly property var user: {
        try {
            return JSON.parse(userFile.text()) || {};
        } catch (error) {
            return {};
        }
    }

    readonly property string login: root.user.login || ""
    readonly property string fullName: root.user.fullName || root.login
    readonly property url avatar: root.user.avatar ? `file://${root.home}/${root.user.avatar}` : ""
    property bool hasAvatar: !!root.user.avatar
    function avatarFailed() { root.hasAvatar = false; }

    // What greetd starts once the password is right: the session the person
    // logs into, as the shell found it.
    readonly property var session: root.user.session || ["niri-session"]

    // ---- What it shows ---------------------------------------------------------

    GateScenery {
        id: scenery
    }

    readonly property string wallpaperMode: scenery.wallpaperMode
    function wallpaperFor(screenName) { return scenery.wallpaperFor(screenName); }
    readonly property string density: scenery.density
    readonly property bool twentyFourHour: scenery.twentyFourHour

    // The primary screen, and it stays there: a greeter has nobody's hand to
    // follow yet.
    readonly property string active: scenery.focusedOutput

    property string password: ""
    property bool checking: false
    property bool failed: false
    property string reason: ""
    property bool leaving: false

    Variants {
        model: Quickshell.screens

        delegate: GreeterSurface {
            required property var modelData
            screen: modelData
            greeterState: root
        }
    }

    // ---- Checking the password -------------------------------------------------

    function submit() {
        if (root.checking || root.leaving || root.password.length === 0)
            return;
        if (!Greetd.available) {
            root.failed = true;
            root.reason = "greetd is not running";
            return;
        }
        root.checking = true;
        root.failed = false;
        Greetd.createSession(root.login);
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired)
                Greetd.respond(root.password);
        }

        function onAuthFailure(message) {
            root.checking = false;
            root.failed = true;
            root.reason = "That is not the password";
        }

        function onError(error) {
            root.checking = false;
            root.failed = true;
            root.reason = "The password could not be checked";
            console.warn(`Bioma greeter: greetd error — ${error}`);
            Greetd.cancelSession();
        }

        // The password was right. The composition goes and the picture clears
        // to the wallpaper, sharp — which is what the session opens on — and
        // only then is the session started.
        function onReadyToLaunch() {
            root.checking = false;
            root.leaving = true;
            departure.start();
        }
    }

    Timer {
        id: departure
        interval: Timing.close + Timing.open
        onTriggered: Greetd.launch(root.session, [], true)
    }
}
