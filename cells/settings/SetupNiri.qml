import QtQuick
import qs.core
import qs.components
import qs.services

// The setup's third step: Bioma's keys and files in niri's configuration.
//
// What `bioma-install --autostart` does from a terminal, with the outcome
// drawn instead of printed: the keys file beside config.kdl, the includes, and
// the line that starts Bioma with the session. config.kdl is copied aside
// first and handed to `niri validate`; what niri refuses is put back, and the
// first line it refused is quoted here.
//
// See docs/design/SETUP.md, step 3.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // Starting with the session is on unless it was turned off here.
    property bool autostart: true

    readonly property bool known: Setup.reportRead
    readonly property bool hasConfig: Setup.niriState.config === "ok"
    readonly property bool complete: Setup.niriSet && (!root.autostart || Setup.autostartSet)

    function state(ok) {
        if (Setup.niriError.length > 0 && !ok)
            return "alert";
        return ok ? "calm" : "muted";
    }

    // Said in the step's capsule once there is something to say.
    readonly property string outcome: !root.known ? ""
        : Setup.niriError.length > 0 ? "niri refused it"
        : Setup.niriSet ? (Setup.autostartSet ? "Set up, starts with niri" : "Set up")
        : ""
    onOutcomeChanged: if (root.outcome.length > 0) Setup.note("niri", root.outcome)
    Component.onCompleted: if (root.outcome.length > 0) Setup.note("niri", root.outcome)

    Column {
        anchors.fill: parent
        spacing: 10 * root.factor

        SetupSection {
            metrics: root.metrics
            label: "IN NIRI'S CONFIGURATION"

            SetupFact {
                metrics: root.metrics
                label: "KEYS"
                detail: "bioma-binds.kdl, beside config.kdl: yours to edit"
                state: root.state(Setup.niriState.binds === "ok")
            }

            SetupFact {
                metrics: root.metrics
                label: "INCLUDES"
                detail: "Bioma's niri rules and the keys file"
                state: root.state(Setup.niriState.include === "ok"
                                  && Setup.niriState["include-binds"] === "ok")
            }

            SetupFact {
                metrics: root.metrics
                label: "START WITH NIRI"
                detail: "Bioma comes up when the session does"
                state: root.state(Setup.autostartSet)

                trailing: Switch {
                    factor: root.factor
                    // Once written, the line is there: taking it out is a
                    // terminal's job, not this switch's.
                    on: root.autostart || Setup.autostartSet
                    dimmed: Setup.autostartSet
                    onToggled: value => root.autostart = value
                }
            }

            Item {
                width: parent.width
                height: 26 * root.factor
                visible: root.known && root.hasConfig && !root.complete

                Choice {
                    id: setUp
                    metrics: root.metrics
                    label: Setup.niriBusy ? "WRITING" : "SET UP NIRI"
                    kind: "primary"
                    dimmed: Setup.niriBusy
                    onActivated: Setup.setUpNiri(root.autostart)
                }

                Sweep {
                    anchors.left: setUp.right
                    anchors.leftMargin: 10 * root.factor
                    anchors.verticalCenter: setUp.verticalCenter
                    width: 18 * root.factor
                    height: width
                    running: Setup.niriBusy
                    visible: Setup.niriBusy
                }
            }

            SetupLine {
                metrics: root.metrics
                visible: Setup.niriError.length > 0
                color: Theme.alert
                text: `niri refused the result, so config.kdl was put back as it was: ${Setup.niriError}`
            }

            SetupLine {
                metrics: root.metrics
                text: !root.known ? "Reading niri's configuration…"
                    : !root.hasConfig ? "niri has no configuration file yet. Start niri once, then come back to this step."
                    : root.complete ? "Everything is in place. The keys can be changed in Settings → Keybinds."
                    : "config.kdl is copied aside first, and nothing niri would refuse is kept."
            }
        }

        SetupSection {
            metrics: root.metrics
            label: "THE FILE"
            visible: Setup.niriConfig.length > 0

            SetupLine {
                metrics: root.metrics
                color: Theme.textMuted
                text: Setup.niriConfig.replace(/^\/home\/[^/]+/, "~")
            }
        }
    }
}
