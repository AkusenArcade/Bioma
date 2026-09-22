import QtQuick
import Quickshell
import qs.core

// The temporal grammar, in one place. Every cell owns one of these.
//
//   always       never hidden, never takes keyboard focus
//   conditional  appears when a condition becomes true, never takes focus
//                (except an expansion that needs a text field — see PRD §5.2)
//   invoked      appears on a shortcut, takes keyboard focus, closes on the
//                same shortcut, Escape, or a click outside
//
// The types combine: the same cell may be conditional and invocable.
//
// No per-cell logic. Three parameters on the condition, and they are
// asymmetric on purpose — appear promptly, leave slowly.
QtObject {
    id: root

    property string type: "always"          // "always" | "conditional" | "invoked"
    property bool invocable: type === "invoked"

    // The raw measurement the condition watches, and its two thresholds.
    // Distinct enter and exit values apply to every boundary, not only the
    // critical one, so the state cannot flicker around it.
    property real value: 0
    property real enterThreshold: 0
    property real exitThreshold: 0

    // How long the condition must hold before the cell appears.
    property int confirmDelay: 300
    // How long the cell remains after the condition lapses.
    property int dwellTime: 2000

    // Set by the cell while the pointer is on it. Interaction suspends
    // disappearance: a cell does not vanish under the user's hands.
    property bool interacting: false

    property bool invoked: false
    property bool conditionMet: false
    // Asked for is asked for, whatever the type says. A conditional cell that
    // is not currently on the membrane — connectivity with nothing connected —
    // still answers a shortcut, because the person pressing it is asking to
    // see the thing, not to be told that its condition is false.
    property bool shown: type === "always" || (invoked && invocable) || conditionMet

    onValueChanged: root.evaluate()

    function evaluate() {
        if (type !== "conditional")
            return;

        if (!conditionMet && value >= enterThreshold) {
            dwell.stop();
            if (!confirm.running)
                confirm.restart();
        } else if (conditionMet && value < exitThreshold) {
            confirm.stop();
            if (!interacting && !dwell.running)
                dwell.restart();
        } else if (!conditionMet && value < enterThreshold) {
            confirm.stop();
        } else if (conditionMet && value >= exitThreshold) {
            dwell.stop();
            root.remaining = 0;
        }
    }

    // On pointer exit the dwell timer resumes where it stopped rather than
    // restarting — otherwise a stray hover would keep the cell alive
    // indefinitely.
    property int remaining: 0
    property real pausedAt: 0

    onInteractingChanged: {
        if (interacting && dwell.running) {
            root.remaining = Math.max(0, dwell.interval - (Date.now() - root.pausedAt));
            dwell.stop();
        } else if (!interacting && root.remaining > 0) {
            dwell.interval = root.remaining;
            root.remaining = 0;
            dwell.restart();
        } else if (!interacting) {
            // The condition may have lapsed *while* the pointer was on the
            // cell, in which case no timer was ever started and there is
            // nothing to resume — the cell would simply stay for ever. The
            // recording cell is where this showed: stop and save with the
            // pointer still on it, and the counter stood frozen on the
            // membrane afterwards.
            root.evaluate();
        }
    }

    function toggle() {
        if (type === "invoked" || root.invocable)
            root.invoked = !root.invoked;
    }

    property Timer confirm: Timer {
        interval: root.confirmDelay
        onTriggered: root.conditionMet = true
    }

    property Timer dwell: Timer {
        interval: root.dwellTime
        onRunningChanged: if (running) root.pausedAt = Date.now()
        onTriggered: {
            root.conditionMet = false;
            interval = root.dwellTime;
        }
    }
}
