import QtQuick
import qs.core
import qs.components
import qs.services

// The setup's system step: `bioma-install --check`, drawn.
//
// It exists only when something is missing. Packages are named by what they
// are for, with the one command that installs them all: Bioma never runs a
// package manager. Services that are installed but off are enabled in place,
// through pkexec. Dictation is optional, and its size is said plainly.
// Another polkit agent started with the session is named, with where it is
// started, and handed over to Bioma's in one press — or kept, which switches
// Bioma's off: polkit allows one, and two only race.
//
// See docs/design/SETUP.md, step 6.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property string outcome: {
        const parts = [];
        if (Setup.missing.length > 0)
            parts.push(Setup.missing.length === 1 ? "One to install" : `${Setup.missing.length} to install`);
        if (Setup.disabled.length > 0)
            parts.push(Setup.disabled.length === 1 ? "one service off" : `${Setup.disabled.length} services off`);
        if (Setup.polkitRival.length > 0)
            parts.push(parts.length > 0 ? "another polkit agent" : "Another polkit agent");
        return parts.length > 0 ? parts.join(", ") : "Nothing missing";
    }
    onOutcomeChanged: Setup.note("system", root.outcome)
    Component.onCompleted: Setup.note("system", root.outcome)

    Flickable {
        id: page

        anchors.fill: parent
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: parent.width
            spacing: 10 * root.factor

            SetupSection {
                metrics: root.metrics
                label: "TO INSTALL"
                visible: Setup.missing.length > 0

                Repeater {
                    model: Setup.missing

                    delegate: SetupFact {
                        required property var modelData
                        metrics: root.metrics
                        label: modelData.name.toUpperCase()
                        detail: modelData.what
                        state: "active"
                    }
                }

                SetupCommand {
                    metrics: root.metrics
                    visible: Setup.installCommand.length > 0
                    command: Setup.installCommand
                }
            }

            SetupSection {
                metrics: root.metrics
                label: "TO SWITCH ON"
                visible: Setup.disabled.length > 0

                Repeater {
                    model: Setup.disabled

                    delegate: SetupFact {
                        id: service

                        required property string modelData

                        readonly property bool busy: Setup.enabling[service.modelData] === true
                        readonly property string error: Setup.enableErrors[service.modelData] || ""

                        metrics: root.metrics
                        label: service.modelData.replace(/\.(service|socket)$/, "").toUpperCase()
                        detail: service.error === "not given" ? "The password was not given."
                              : service.error === "no agent" ? "Nothing could ask for the password."
                              : service.error === "failed" ? "systemd refused it."
                              : "Installed, and off: the cells that read it stay empty."
                        state: service.error.length > 0 ? "alert" : "active"

                        trailing: Choice {
                            metrics: root.metrics
                            label: service.busy ? "ENABLING" : "ENABLE"
                            dimmed: service.busy || !Setup.polkitAgent
                            onActivated: Setup.enableService(service.modelData)
                        }
                    }
                }

                SetupCommand {
                    metrics: root.metrics
                    visible: !Setup.polkitAgent
                    command: `sudo systemctl enable --now ${Setup.disabled.join(" ")}`
                }
            }

            SetupSection {
                id: rival

                metrics: root.metrics
                label: "PASSWORDS"
                visible: Setup.polkitRival.length > 0

                readonly property var places: {
                    const said = { "niri": "niri's configuration", "unit": "a systemd unit",
                                   "autostart": "the session's autostart", "running": "" };
                    const out = [];
                    for (const source of Setup.polkitSources)
                        if (said[source.kind].length > 0 && out.indexOf(said[source.kind]) < 0)
                            out.push(said[source.kind]);
                    return out;
                }

                SetupLine {
                    metrics: root.metrics
                    text: `${Setup.polkitRival} asks for passwords in this session`
                          + (rival.places.length > 0 ? `, started by ${rival.places.join(" and ")}. ` : ". ")
                          + "Bioma has its own agent, with the lock screen's field, and polkit allows only one. "
                          + "Switching turns the other off where it starts — commented out, disabled or hidden, never deleted."
                }

                SetupFact {
                    metrics: root.metrics
                    visible: Setup.handOverError.length > 0
                    label: "NOT SWITCHED"
                    detail: Setup.handOverError
                    state: "alert"
                }

                Row {
                    spacing: 8 * root.factor

                    Choice {
                        metrics: root.metrics
                        label: Setup.handingOver ? "Switching" : "Use Bioma's agent"
                        kind: "primary"
                        dimmed: Setup.handingOver
                        onActivated: Setup.useBiomaAgent()
                    }

                    Choice {
                        metrics: root.metrics
                        label: `Keep ${Setup.polkitRival}`
                        dimmed: Setup.handingOver
                        onActivated: Setup.keepOtherAgent()
                    }
                }
            }

            SetupSection {
                metrics: root.metrics
                label: "PASSWORDS"
                visible: !Setup.polkitAgent && Setup.polkitRival.length === 0

                SetupLine {
                    metrics: root.metrics
                    text: Polkit.wanted
                          ? "No polkit agent is running, so nothing in Bioma that needs your password can ask for it. Bioma's own could not register with polkit; the shell's log says why."
                          : "No polkit agent is running, so nothing in Bioma that needs your password can ask for it. Bioma has its own, and it is switched off: turn it back on, or install another and start it with niri — polkit-gnome is the usual choice."
                }

                Choice {
                    metrics: root.metrics
                    visible: !Polkit.wanted
                    label: "Use Bioma's agent"
                    kind: "primary"
                    onActivated: Config.set("polkit.agent", true)
                }
            }

            DashedRule {
                width: parent.width
                visible: Setup.dictationMissing
            }

            SetupSection {
                metrics: root.metrics
                label: "OPTIONAL · DICTATION"
                visible: Setup.dictationMissing

                SetupLine {
                    metrics: root.metrics
                    text: "Speech typed into any window, with Mod+Alt+D. About half a gigabyte, for one key."
                }

                SetupCommand {
                    metrics: root.metrics
                    command: Setup.dictationCommand
                }
            }
        }
    }

    Glide {
        flick: page
    }
}
