import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.organisms

// The time, large, and the date in words under it.
//
// Mostly text, and the text is the content: no dial and no seconds. A second
// hand moving at a fixed rate on the desktop is the one clock motion that
// carries nothing the minute does not.
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
        precision: SystemClock.Minutes
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

    // The panel is 340 × 168 at the normal step: its content is that less the
    // padding, or wider when a long date asks for it — never ellipsed.
    implicitWidth: Math.max(300 * root.factor, column.implicitWidth)
    implicitHeight: 128 * root.factor

    Column {
        id: column

        anchors.centerIn: parent
        spacing: 4 * root.factor

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 * root.factor

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
