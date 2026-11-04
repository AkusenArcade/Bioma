import QtQuick
import qs.core
import qs.components
import qs.services

// The setup's fourth step: the login screen, as a choice.
//
// Installing the package used to make Bioma the login screen by itself. With
// strangers installing it, the login screen is the one thing it must not
// change without asking (Akusen, 2026-10-13): KEEP is what is there, and NEXT
// without touching anything keeps it. Choosing Bioma runs
// `scripts/greeter-setup enable` through pkexec, and the password is asked by
// the session's polkit agent, never by Bioma. Nothing is restarted —
// restarting greetd from inside a session ends that session — so it takes
// effect at the next boot.
//
// See docs/design/SETUP.md, step 4.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // What a press asked for, while pkexec runs: the row it pressed shows the
    // wait, not the other one.
    property bool asked: false

    readonly property bool noAgent: !Setup.polkitAgent || Setup.loginError.indexOf("Nothing could ask") === 0

    readonly property string outcome: !Setup.greeterRead ? ""
        : Setup.biomaGreeter ? "Bioma's login screen"
        : `Kept ${Setup.managerName === "TEXT LOGIN" ? "the text login" : Setup.managerName}`
    onOutcomeChanged: if (root.outcome.length > 0) Setup.note("login", root.outcome)
    Component.onCompleted: if (root.outcome.length > 0) Setup.note("login", root.outcome)

    function choose(bioma) {
        root.asked = bioma;
        Setup.setGreeter(bioma);
    }

    Column {
        anchors.fill: parent
        spacing: 10 * root.factor

        SetupSection {
            metrics: root.metrics
            label: "WHO GREETS YOU"

            SetupOption {
                metrics: root.metrics
                label: "BIOMA'S LOGIN SCREEN"
                line: "Your wallpaper, your palette and your picture, before anyone is logged in."
                chosen: Setup.biomaGreeter
                busy: Setup.loginBusy && root.asked
                onActivated: root.choose(true)
            }

            SetupOption {
                metrics: root.metrics
                label: Setup.biomaGreeter && Setup.manager === "greetd.service"
                       ? "THE ONE BEFORE BIOMA"
                       : `KEEP ${Setup.managerName}`
                line: Setup.manager === "none" || Setup.manager.length === 0
                      ? "A text login on the console, as now."
                      : "The login screen this machine has now, unchanged."
                chosen: !Setup.biomaGreeter
                busy: Setup.loginBusy && !root.asked
                onActivated: root.choose(false)
            }

            SetupLine {
                metrics: root.metrics
                visible: Setup.loginError.length > 0
                color: Theme.alert
                text: Setup.loginError
            }

            SetupLine {
                metrics: root.metrics
                text: Setup.biomaGreeter
                      ? "From the next boot. greetd's old configuration is kept as config.toml.before-bioma, and removing Bioma puts it back."
                      : "Choosing Bioma asks for your password, and takes effect from the next boot."
            }
        }

        // When nothing can ask for the password, the same thing as a command.
        SetupSection {
            metrics: root.metrics
            label: "FROM A TERMINAL"
            visible: root.noAgent

            SetupLine {
                metrics: root.metrics
                text: "No polkit agent is running, so nothing here can ask for your password. The same change, from a terminal:"
            }

            SetupCommand {
                metrics: root.metrics
                command: Setup.loginCommand(!Setup.biomaGreeter)
            }
        }
    }
}
