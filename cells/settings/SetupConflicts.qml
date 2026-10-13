import QtQuick
import qs.core
import qs.components
import qs.services

// The setup's conflicts: another shell still starting with niri.
//
// Two things then go wrong without saying why — two bars on one edge, and
// notifications that never reach Bioma, because org.freedesktop.Notifications
// has one owner per session. The step exists only while something is found
// (services/Setup.qml), and each row says what it collides on and where it
// starts from. STOP ends it now and takes it out of startup: a spawn line is
// commented out, never deleted, and only if niri accepts the result; a user
// unit is disabled.
//
// See docs/design/SETUP.md, step 5.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property string outcome: Setup.conflicts.length === 0 ? "Nothing else running"
        : Setup.conflicts.length === 1 ? "One other shell" : `${Setup.conflicts.length} other shells`
    onOutcomeChanged: Setup.note("conflicts", root.outcome)
    Component.onCompleted: Setup.note("conflicts", root.outcome)

    function where(from) {
        if (from.startsWith("niri:"))
            return "started by niri, " + from.slice(5).replace(/^.*\//, "");
        if (from.startsWith("unit:"))
            return "started by systemd, " + from.slice(5);
        return "where it starts from was not found";
    }

    Column {
        anchors.fill: parent
        spacing: 10 * root.factor

        SetupSection {
            metrics: root.metrics
            label: "ALSO DRAWING THIS DESKTOP"

            Repeater {
                model: Setup.conflicts

                delegate: SetupFact {
                    id: fact

                    required property var modelData

                    readonly property bool stopping: Setup.stopping[fact.modelData.pid] === true
                    readonly property string error: Setup.stopErrors[fact.modelData.pid] || ""

                    metrics: root.metrics
                    label: fact.modelData.name.toUpperCase()
                    detail: (fact.modelData.what === "notifications" ? "Owns the notifications; "
                                                                     : "Draws a bar; ")
                            + root.where(fact.modelData.from)
                            + (fact.error.length > 0 ? `. ${fact.error}` : "")
                    state: fact.error.length > 0 ? "alert" : "active"

                    trailing: Choice {
                        metrics: root.metrics
                        label: fact.stopping ? "STOPPING" : "STOP"
                        dimmed: fact.stopping
                        onActivated: Setup.stop(fact.modelData)
                    }
                }
            }

            SetupLine {
                metrics: root.metrics
                visible: Setup.conflicts.length === 0
                text: "Nothing else is drawing this desktop now."
            }

            SetupLine {
                metrics: root.metrics
                visible: Setup.conflicts.some(entry => entry.from === "none")
                color: Theme.textMuted
                text: "Where it starts from could not be found, so STOP only stops it: it will come back at the next login."
            }
        }

        SetupSection {
            metrics: root.metrics
            label: "NOTIFICATIONS"
            visible: Setup.restartAtEnd

            SetupLine {
                metrics: root.metrics
                text: "Bioma takes the notifications over once it starts again, which it does by itself when this setup is done."
            }
        }
    }
}
