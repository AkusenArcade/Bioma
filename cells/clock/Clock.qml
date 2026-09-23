import QtQuick
import Quickshell
import qs.core
import qs.structure
import qs.components
import qs.services

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

    // Conditional, it is there when the hour strikes, for that minute.
    condition: clock.minutes === 0 ? 1 : 0

    // ---- Open -----------------------------------------------------------------
    //
    // Opened, the month hangs from it, with other places on one side and a
    // timer and an alarm on the other. It keeps the time rather than becoming
    // a header that says CLOCK: the time is its own title.

    // Whether a place is being typed into, which is the one time it needs the
    // keyboard.
    property bool typing: false
    wantsKeyboard: root.open && root.typing
    onOpenChanged: if (!root.open) root.typing = false

    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("ClockExpansion.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
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
            // The minute, filling and starting again empty — or, while a
            // timer runs, what is left of it, emptying.
            fraction: Time.running ? Time.fractionLeft : clock.seconds / 60
        }
    }
}
