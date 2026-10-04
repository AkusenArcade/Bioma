import QtQuick
import Quickshell
import qs.core
import qs.components

// This month, on the wall.
//
// The clock cell's month, alone and read-only: no arrows, no navigation — a
// calendar on the wall, not a planner. Today is the only lit day, and the
// only thing that ever changes, at midnight.
//
// Six weeks always, as in the cell: every month fits, and the panel never
// changes height from one month to the next — an organism that grew a row
// would move on the desktop by itself.
//
// See docs/design/ORGANISMS.md §04.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})

    readonly property real factor: root.metrics.factor

    SystemClock {
        id: now
        precision: SystemClock.Minutes
    }

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
                                       "August", "September", "October", "November", "December"]

    // Six weeks from the Monday on or before the first.
    readonly property var days: {
        const date = now.date;
        const year = date.getFullYear();
        const month = date.getMonth();
        const first = new Date(year, month, 1);
        const lead = (first.getDay() + 6) % 7;
        const out = [];
        for (let i = 0; i < 42; i++) {
            const day = new Date(year, month, 1 - lead + i);
            out.push({
                "day": day.getDate(),
                "inMonth": day.getMonth() === month,
                "today": day.getMonth() === month && day.getDate() === date.getDate()
            });
        }
        return out;
    }

    readonly property real cellWidth: 37 * root.factor
    readonly property real cellHeight: 34 * root.factor

    implicitWidth: root.cellWidth * 7
    implicitHeight: column.implicitHeight

    function technical(size, weight) {
        return Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": size,
            "weight": weight === undefined ? Typography.weightSecondary : weight
        }));
    }

    Column {
        id: column

        width: parent.width
        spacing: 10 * root.factor

        // The month's name is language; the year is a figure.
        Row {
            spacing: 10 * root.factor

            Text {
                id: name
                text: root.monthNames[now.date.getMonth()]
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: Math.round(19 * root.factor)
                font.weight: Font.Bold
            }

            Text {
                anchors.baseline: name.baseline
                text: now.date.getFullYear()
                color: Theme.textMuted
                font: root.technical(root.metrics.fontSecondary)
            }
        }

        Grid {
            columns: 7

            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                delegate: Text {
                    required property string modelData
                    width: root.cellWidth
                    height: 22 * root.factor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: Theme.textFaint
                    font: root.technical(root.metrics.fontMeta)
                }
            }

            Repeater {
                model: root.days

                delegate: Item {
                    id: day

                    required property var modelData

                    width: root.cellWidth
                    height: root.cellHeight

                    // Today is lit the way a chosen control is: the disc with
                    // the light gradient, the figure dark on it.
                    Disc {
                        anchors.centerIn: parent
                        visible: day.modelData.today
                        width: 28 * root.factor
                        height: width
                    }

                    Text {
                        anchors.centerIn: parent
                        text: day.modelData.day
                        color: day.modelData.today ? Theme.background
                             : day.modelData.inMonth ? Theme.text : Theme.textFaint
                        font: root.technical(root.metrics.fontSecondary,
                                             day.modelData.today ? Typography.weightTitle
                                                                 : Typography.weightSecondary)
                    }
                }
            }
        }
    }
}
