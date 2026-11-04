import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.organisms
import qs.services

// The time, large, the clock cell's face beside it, and the date in words
// under them.
//
// The face is the cell's own: the hour filling and starting again empty — or,
// while a timer runs, what is left of it — and round the rim the disc that is
// where the second hand is. Without it the organism read as unfinished
// (Akusen, 2026-10-04), and it is the same live value the cell shows, not a
// motion chosen to look alive.
//
// 12 or 24 hours as the clock cell was told, so the desktop does not answer
// the same question two ways.
//
// See docs/design/ORGANISMS.md §01.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})

    readonly property real factor: root.metrics.factor

    readonly property bool twentyFourHour: Organisms.cellOption("clock", "format", "24h") === "24h"

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // The second hand, continuous: see components/MinuteHand.qml.
    MinuteHand {
        id: hand
    }

    readonly property string figures: {
        const hours = clock.hours;
        const minutes = String(clock.minutes).padStart(2, "0");
        if (root.twentyFourHour)
            return `${String(hours).padStart(2, "0")}:${minutes}`;
        return `${hours % 12 || 12}:${minutes}`;
    }

    // In English and spelled out, whatever the system locale: every string the
    // shell shows is English, and the names are the clock cell's own.
    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                                     "Saturday"]
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
                                       "August", "September", "October", "November", "December"]

    readonly property string date: {
        const day = clock.date;
        return `${root.dayNames[day.getDay()]} ${day.getDate()} ${root.monthNames[day.getMonth()]}`;
    }

    // Two units by one (`Organisms.templates`), the figures centred in it.
    Column {
        id: column

        anchors.centerIn: parent
        spacing: 4 * root.factor

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16 * root.factor

            LitText {
                id: time
                text: root.figures
                font: Typography.tabular(Qt.font({
                    "family": Typography.expressive,
                    "pixelSize": Math.round(72 * root.factor),
                    "weight": Font.Medium
                }))
            }

            Text {
                visible: !root.twentyFourHour
                anchors.baseline: time.baseline
                text: clock.hours >= 12 ? "PM" : "AM"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
                })
            }

            // The size of the vitals organism's rings, so the clock's face
            // and the graphics card's satellite are one size on the desktop
            // too.
            Dial {
                anchors.verticalCenter: time.verticalCenter
                width: 62 * root.factor
                height: width
                fraction: Time.running ? Time.fractionLeft
                                       : (clock.minutes * 60 + clock.seconds) / 3600
                orbit: hand.value
                orbitEased: false
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.date
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: Math.round(19 * root.factor)
        }
    }
}
