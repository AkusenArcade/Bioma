import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.components
import qs.services

// When the session locks by itself.
//
// Two settings, both writing straight into the override layer, which
// services/Locker.qml is bound to: a choice here is the lock's behaviour
// changing, not a preview of it. Locking on request is not here, because it
// is not a setting — the key and the System cell's LOCK always lock.
//
// The idle time is a handful of stops rather than a slider: nobody means
// thirteen minutes, and a figure that travels under the finger is a figure
// that has to be read. Akusen asked for it to be set from here, 2026-09-23.
//
// Laid out in wells, one per thing that decides when the screen is locked,
// each with a line in Spectral saying what the current choice does. Two bare
// rows at the top of a panel of fixed height left three quarters of it empty
// and said nothing a person could check against (Akusen, 2026-09-29). The
// third well is not a setting: it says what takes over if the lock screen
// fails, because that is the part of locking nobody sees until it matters.
//
// The fourth is the power profile following the plug, and it is there only on
// a machine with a battery and a daemon to ask: elsewhere there is no plug to
// follow. It lives here because, like locking, it is the session doing
// something by itself; choosing a profile by hand stays in the System cell.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real inset: 14 * factor
    readonly property real headerHeight: 28 * factor
    readonly property real gap: 10 * factor

    readonly property font labelFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontSecondary,
        "letterSpacing": Typography.tracking(root.metrics.fontSecondary, Typography.labelTracking)
    })

    readonly property int idleMinutes: Config.get("lock.idle_minutes", 10)
    readonly property bool beforeSleep: Config.get("lock.before_sleep", true)

    // What scripts/lock falls back to, asked once when the page opens.
    property string fallback: ""
    property bool fallbackKnown: false

    Process {
        running: true
        command: ["sh", "-c",
                  "command -v hyprlock >/dev/null && echo hyprlock "
                  + "|| { command -v swaylock >/dev/null && echo swaylock; } || echo none"]
        stdout: SplitParser {
            onRead: line => {
                root.fallback = line.trim();
                root.fallbackKnown = true;
            }
        }
    }

    // A well: its label, perhaps its control on the same line, then what it
    // means. Everything under the label is the well's own content.
    component Section: Well {
        id: section

        property string label: ""
        property alias trailing: trailingSlot.data
        default property alias content: body.data

        metrics: root.metrics
        width: parent.width
        height: root.inset * 2 + root.headerHeight + body.childrenRect.height
                + (body.childrenRect.height > 0 ? 6 * root.factor : 0)

        Text {
            x: root.inset
            y: root.inset
            height: root.headerHeight
            verticalAlignment: Text.AlignVCenter
            text: section.label
            color: Theme.textMuted
            font: root.labelFont
        }

        Item {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            y: root.inset
            width: childrenRect.width
            height: root.headerHeight
        }

        Column {
            id: body
            x: root.inset
            y: root.inset + root.headerHeight + 6 * root.factor
            width: section.width - root.inset * 2
            spacing: 10 * root.factor
        }
    }

    // A profile setting's row: what it is for, and the choice beside it.
    component ProfileRow: Item {
        id: profileRow

        property string label: ""
        property string path: ""
        property string value: "keep"

        width: parent.width
        height: profileChoice.implicitHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: profileRow.label
            color: Theme.textFaint
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                     Typography.labelTracking)
            })
        }

        Segmented {
            id: profileChoice
            anchors.right: parent.right
            metrics: root.metrics
            fontSize: root.metrics.fontMeta
            buttonPadding: 10 * root.factor
            options: [
                { "key": "keep", "label": "Keep" },
                { "key": "saver", "label": "Saver" },
                { "key": "balanced", "label": "Balanced" },
                { "key": "performance", "label": "Performance",
                  "dimmed": !Power.performanceAvailable }
            ]
            current: profileRow.value
            onChose: key => Config.set(profileRow.path, key)
        }
    }

    // What a person reads, so the human voice.
    component Line: Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.text
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontSecondary
        lineHeight: 1.15
    }

    Column {
        anchors.fill: parent
        spacing: root.gap

        // Minutes without input before the session locks. `0` is never.
        Section {
            label: "LOCK AFTER"

            Segmented {
                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                options: [
                    { "key": "0", "label": "Never" },
                    { "key": "5", "label": "5 min" },
                    { "key": "10", "label": "10 min" },
                    { "key": "15", "label": "15 min" },
                    { "key": "30", "label": "30 min" }
                ]
                current: String(root.idleMinutes)
                onChose: key => Config.set("lock.idle_minutes", parseInt(key, 10))
            }

            Line {
                text: root.idleMinutes > 0
                      ? `After ${root.idleMinutes} minutes without input, the session locks.`
                      : "The session never locks by itself. The key and the System cell still do."
            }
        }

        // Before a suspend, so the machine never wakes on the desktop it went
        // to sleep with.
        Section {
            label: "BEFORE SLEEP"

            trailing: Switch {
                anchors.verticalCenter: parent.verticalCenter
                factor: root.factor
                on: root.beforeSleep
                onToggled: value => Config.set("lock.before_sleep", value)
            }

            Line {
                text: root.beforeSleep
                      ? "The session locks before the machine suspends, so it wakes locked."
                      : "The machine suspends as it is, and wakes on the open desktop."
            }
        }

        // Not a setting: what scripts/lock hands the screen to if Bioma's own
        // lock screen fails to come up.
        Section {
            label: "IF THE LOCK FAILS"
            visible: root.fallbackKnown

            Line {
                text: root.fallback === "none"
                      ? "Nothing takes over, and only a TTY is left. Install hyprlock or swaylock."
                      : `${root.fallback} takes over, so the session is never left open.`
                // The one sentence here that reports a risk.
                color: root.fallback === "none" ? Theme.alert : Theme.text
            }
        }

        // The profile the machine switches to when the plug changes.
        Section {
            label: "POWER PROFILE"
            visible: Power.present && Power.hasBattery

            ProfileRow {
                label: "ON BATTERY"
                path: "power.on_battery"
                value: Power.onBatteryProfile
            }

            ProfileRow {
                label: "PLUGGED IN"
                path: "power.on_mains"
                value: Power.onMainsProfile
            }

            Line {
                text: {
                    const battery = Power.onBatteryProfile;
                    const mains = Power.onMainsProfile;
                    if (battery === "keep" && mains === "keep")
                        return "The profile is left alone, on battery and plugged in. It is chosen in the System cell.";
                    const unplugged = battery === "keep" ? "On battery the profile is left alone"
                                                         : `On battery the machine switches to ${battery}`;
                    const plugged = mains === "keep" ? "plugged in, it is left alone"
                                                     : `plugged in, to ${mains}`;
                    return `${unplugged}; ${plugged}. A profile chosen by hand holds until the plug next changes.`;
                }
            }
        }
    }
}
