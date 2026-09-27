import QtQuick
import Quickshell
import qs.core
import qs.components

// When the session locks by itself.
//
// Two rows, both writing straight into the override layer, which
// services/Locker.qml is bound to: a choice here is the lock's behaviour
// changing, not a preview of it. Locking on request is not here, because it
// is not a setting — the key and the System cell's LOCK always lock.
//
// The idle time is a handful of stops rather than a slider: nobody means
// thirteen minutes, and a figure that travels under the finger is a figure
// that has to be read. Akusen asked for it to be set from here, 2026-09-23.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real rowHeight: 44 * factor
    readonly property real labelWidth: 124 * factor

    readonly property font labelFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontSecondary,
        "letterSpacing": Typography.tracking(root.metrics.fontSecondary, Typography.labelTracking)
    })

    Column {
        anchors.fill: parent
        spacing: 0

        // Minutes without input before the session locks. `0` is never.
        Item {
            width: parent.width
            height: root.rowHeight

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelWidth
                text: "LOCK AFTER"
                color: Theme.textMuted
                font: root.labelFont
            }

            Segmented {
                anchors.left: parent.left
                anchors.leftMargin: root.labelWidth + 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                options: [
                    { "key": "0", "label": "Never" },
                    { "key": "5", "label": "5 min" },
                    { "key": "10", "label": "10 min" },
                    { "key": "15", "label": "15 min" },
                    { "key": "30", "label": "30 min" }
                ]
                current: String(Config.get("lock.idle_minutes", 10))
                onChose: key => Config.set("lock.idle_minutes", parseInt(key, 10))
            }
        }

        // Before a suspend, so the machine never wakes on the desktop it went
        // to sleep with.
        Item {
            width: parent.width
            height: root.rowHeight

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelWidth
                text: "BEFORE SLEEP"
                color: Theme.textMuted
                font: root.labelFont
            }

            Switch {
                anchors.left: parent.left
                anchors.leftMargin: root.labelWidth + 12 * root.factor
                anchors.verticalCenter: parent.verticalCenter
                factor: root.factor
                on: Config.get("lock.before_sleep", true)
                onToggled: value => Config.set("lock.before_sleep", value)
            }
        }
    }
}
