pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import qs.core

// The session's authentication agent: what asks for the password when
// something the user started needs permission — mounting a disk, changing a
// system service, `pkexec`.
//
// Quickshell carries the agent itself; this is the one place that holds it.
// When polkit asks, the polkit cell is summoned into the middle of the screen
// the keyboard is pointed at, with the field, the message polkit was given
// and the icon of the action; when the request ends, however it ends, the
// cell goes. Closing the cell — Escape, a press outside — is cancelling.
//
// One agent per session is polkit's rule, so this one registers only when
// `polkit.agent` is on (the default), and a session that already runs
// another — polkit-gnome started by niri, say — keeps whichever registered
// first. `registered` says which it was. When the other one is taken away —
// Setup → System does it, where it is started — `retry` registers again
// without restarting the shell.
Singleton {
    id: root

    readonly property bool wanted: Config.get("polkit.agent", true)

    // Off for a moment while `retry` lets go of a refused registration.
    property bool resting: false

    LazyLoader {
        id: loader
        active: root.wanted && !root.resting

        PolkitAgent {}
    }

    readonly property var agent: loader.item
    readonly property bool registered: root.agent ? root.agent.isRegistered : false
    readonly property var flow: root.agent ? root.agent.flow : null
    readonly property bool asking: root.agent ? root.agent.isActive : false

    // Said once, because a second agent in the session is not a failure of
    // Bioma's — but it does mean this one will never ask.
    onRegisteredChanged: {
        if (root.registered)
            console.info("Bioma: polkit agent registered");
    }

    Timer {
        running: root.wanted && !root.registered
        interval: 5000
        onTriggered: if (!root.registered)
            console.info("Bioma: another polkit agent holds this session; Bioma's will not ask");
    }

    // Where the cell was summoned, so it is taken away from the same screen
    // even if the keyboard has moved on meanwhile.
    property string output: ""

    onAskingChanged: {
        if (root.asking) {
            root.output = Niri.focusedOutput;
            if (!root.shown)
                Focus.invoke("polkit", root.output);
        } else {
            Focus.retire("polkit", root.output);
        }
    }

    // Set by the cell while it is on screen, so a second request arriving
    // while the first is still leaving does not toggle it away.
    property bool shown: false

    // polkit learns the other agent is gone when its process is, a moment
    // after the signal: a few tries, a second apart, until one holds.
    function retry() {
        if (!root.wanted || root.registered)
            return;
        again.tries = 5;
        again.restart();
    }

    Timer {
        id: again
        property int tries: 0
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.registered || again.tries <= 0) {
                again.stop();
                return;
            }
            again.tries--;
            root.resting = true;
            Qt.callLater(() => root.resting = false);
        }
    }

    function submit(password) {
        if (root.flow && root.flow.isResponseRequired)
            root.flow.submit(password);
    }

    // Closing the cell is the answer "no": whatever was waiting is told so,
    // rather than left to time out.
    function cancel() {
        if (root.flow && !root.flow.isCompleted)
            root.flow.cancelAuthenticationRequest();
    }
}
