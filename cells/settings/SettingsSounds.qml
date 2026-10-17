import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Bioma's sound effects: one switch for each kind of event, and one volume
// for all of them (services/Sounds.qml).
//
// Akusen asked for a page of its own with a toggle per event, 2026-10-17.
// Laid out as the Session page is, in wells with a line in Spectral saying
// what the current choice does. A sound switched on plays once, and the
// volume plays the notification when the hand stops: a sound is chosen by
// hearing it, not by reading its name.
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

    readonly property real volume: Sounds.volume

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
            color: Theme.text
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

    // One kind of event: its switch, and what it means on and off.
    component Event: Section {
        id: event

        property string kind: ""
        property string sound: ""
        property string whenOn: ""
        property string whenOff: ""

        readonly property bool on: Config.get(`sounds.${event.kind}`, true) === true

        trailing: Switch {
            anchors.verticalCenter: parent.verticalCenter
            factor: root.factor
            on: event.on
            onToggled: value => {
                Config.set(`sounds.${event.kind}`, value);
                if (value)
                    Sounds.play(event.sound);
            }
        }

        Line {
            text: event.on ? event.whenOn : event.whenOff
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

    // The panel is one height for every category; the wells scroll if a scale
    // or a font ever makes them taller than it.
    Scroller {
        flick: page
        factor: root.factor
        x: root.width - width
    }

    Flickable {
        id: page

        anchors.fill: parent
        anchors.rightMargin: 8 * root.factor
        contentHeight: column.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column

            width: page.width
            spacing: root.gap

            Section {
                label: "VOLUME"

                Slider {
                    width: parent.width
                    factor: root.factor
                    value: root.volume
                    onMoved: fraction => {
                        Config.set("sounds.volume", Math.round(fraction * 20) / 20);
                        preview.restart();
                    }
                }

                Line {
                    text: root.volume <= 0
                          ? "Silent: no sound plays, whatever is switched on below."
                          : `The effects play at ${Math.round(root.volume * 100)}% of the system volume.`
                }

                // Heard when the hand stops, not at every step of the way.
                Timer {
                    id: preview
                    interval: 250
                    onTriggered: Sounds.play("notification")
                }
            }

            Event {
                label: "LOGIN"
                kind: "login"
                sound: "login"
                whenOn: "A chord when the desktop first appears after logging in. Restarting the shell does not play it again."
                whenOff: "The desktop appears in silence."
            }

            Event {
                label: "NOTIFICATIONS"
                kind: "notifications"
                sound: "notification"
                whenOn: "Two droplets when a notification appears. One that brings its own sound plays that instead, so the application stays recognisable."
                whenOff: "Notifications appear in silence, their own sounds included."
            }

            Event {
                label: "CELLS"
                kind: "cells"
                sound: "open"
                whenOn: "A bubble rising when a cell opens, and falling when it closes."
                whenOff: "Cells open and close in silence."
            }

            Event {
                label: "ALERTS"
                kind: "alerts"
                sound: "alert"
                readonly property int past: Math.round(Theme.thresholdAlert * 100)
                readonly property int rest: Math.round(Sounds.alertGap / 60000)
                whenOn: `A low note when a value turns red: the processor, memory or graphics card past ${past}%, `
                        + `or the battery under ${100 - past}% while it runs on itself. `
                        + (rest > 0 ? `Once, until it has rested ${rest} ${rest === 1 ? "minute" : "minutes"}.` : "Every time.")
                whenOff: "Values turn red in silence."
            }
        }
    }
}
