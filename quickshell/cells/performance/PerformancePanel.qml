pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The performance cell, opened: whether the mode is on and why, the switch,
// and what it has quietened.
//
// What it quietens is chosen on the Settings page; here it is only said, one
// row a lever, so whoever turned it on with a key can see what that did.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real inset: 14 * factor

    readonly property font labelFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontSecondary,
        "letterSpacing": Typography.tracking(root.metrics.fontSecondary, Typography.labelTracking)
    })

    readonly property font metaFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontMeta,
        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
    })

    // One row a lever, said as what it does to the shell.
    readonly property var levers: [
        { "key": "motion", "words": "LIVE INDICATORS STILL" },
        { "key": "organisms", "words": "ORGANISMS PUT AWAY" },
        { "key": "wallpaper", "words": "ONE PICTURE KEPT" },
        { "key": "blur", "words": "NO BLUR, NO SHADOWS" },
        { "key": "transitions", "words": "INSTANT TRANSITIONS" },
        { "key": "polling", "words": `VITALS EVERY ${Math.round(Performance.vitalsInterval / 1000)} S` }
    ]

    readonly property var quietened: root.levers.filter(lever => Config.get(`performance.suspend.${lever.key}`, true) !== false)

    implicitWidth: 340 * factor
    implicitHeight: column.implicitHeight + root.inset * 2
    width: implicitWidth
    height: implicitHeight

    Well {
        metrics: root.metrics
        anchors.fill: parent

        Column {
            id: column

            x: root.inset
            y: root.inset
            width: parent.width - root.inset * 2
            spacing: 10 * root.factor

            Item {
                width: parent.width
                height: 28 * root.factor

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PERFORMANCE MODE"
                    color: Theme.text
                    font: root.labelFont
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    factor: root.factor
                    on: Performance.active
                    onToggled: value => value ? Performance.on() : Performance.off()
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
                lineHeight: 1.15
                text: Performance.manual
                      ? "On by hand. It stays on, across a restart too, until it is turned off."
                      : Performance.active
                      ? `On ${Performance.reason}. It goes off by itself when that ends.`
                      : Performance.refused
                      ? "Off by hand while a trigger holds it. It comes back with the next one."
                      : "Off. The shell runs in full."
            }

            Column {
                width: parent.width
                spacing: 4 * root.factor
                visible: root.quietened.length > 0

                Repeater {
                    model: root.quietened

                    delegate: Text {
                        required property var modelData
                        width: parent.width
                        text: modelData.words
                        elide: Text.ElideRight
                        color: Performance.active ? Theme.textMuted : Theme.textFaint
                        font: root.metaFont
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontMeta
                text: "What it quietens, and what turns it on by itself, is chosen in Settings, under Performance."
            }
        }
    }
}
