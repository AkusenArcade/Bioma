import QtQuick
import Quickshell
import qs.core
import qs.structure
import qs.components

// The time. One of the two things the shell says at rest — a clock that only
// appears on hover is not a clock — and human language, so it is set in the
// expressive face rather than the technical one.
//
// The minute dial beside it is the only movement: it fills over the minute and
// starts again empty, which is a live value and not decoration.
Cell {
    id: root

    domain: "clock"

    // The dial is round and sits against the trailing cap, so it keeps less
    // padding than the leading text.
    paddingLeading: 16
    paddingTrailing: 12

    readonly property bool twentyFourHour: option("format", "24h") === "24h"
    readonly property real timeSize: 19 * metrics.factor

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property string reading: {
        const hours = root.twentyFourHour
                      ? clock.hours
                      : (clock.hours % 12 === 0 ? 12 : clock.hours % 12);
        return `${root.twentyFourHour ? String(hours).padStart(2, "0") : hours}:${String(clock.minutes).padStart(2, "0")}`;
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * root.metrics.factor

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.reading
            color: Theme.text
            // Tabular figures, or the cell's width dances every minute and the
            // tissue reflows for nothing.
            font: Typography.tabular(Qt.font({
                "family": Typography.expressive,
                "pixelSize": root.timeSize,
                "weight": Typography.weightValue
            }))
        }

        Dial {
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.metrics.factor
            height: 17 * root.metrics.factor
            // The minute, filling and starting again empty.
            fraction: clock.seconds / 60
        }
    }
}
