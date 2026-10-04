import QtQuick
import qs.core
import qs.components
import qs.services

// The weather where the user is: now, and the next five hours.
//
// The temperature measures the weather, not the machine, so it is primary and
// never takes a state colour — the same reason a timezone dial never changes
// colour. It is there while there is a reading young enough to trust: no city
// set, a city nobody could find, or two hours without the network, and it
// leaves rather than say something old as though it were now.
//
// See docs/design/ORGANISMS.md §05.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    // The service asks only while an organism holds it — one placed on this
    // screen, not the copy every other screen keeps of it.
    readonly property bool wanted: root.organism === null || root.organism.here
    onWantedChanged: Weather.hold(root, root.wanted)
    Component.onCompleted: Weather.hold(root, root.wanted)
    Component.onDestruction: Weather.hold(root, false)

    readonly property bool present: Weather.fresh
    readonly property var now: Weather.current

    implicitWidth: 300 * root.factor
    implicitHeight: 156 * root.factor

    function degrees(value) {
        return value === undefined || value === null ? "" : `${Math.round(value)}°`;
    }

    function technical(size, weight) {
        return Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": size,
            "weight": weight === undefined ? Typography.weightSecondary : weight
        }));
    }

    // The place's name is language.
    Text {
        id: city
        width: parent.width
        text: Weather.place
        elide: Text.ElideRight
        maximumLineCount: 1
        color: Theme.text
        font.family: Typography.expressive
        font.pixelSize: Math.round(15 * root.factor)
        font.weight: Font.Bold
    }

    Row {
        id: current

        y: city.height + 6 * root.factor
        spacing: 14 * root.factor

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 44 * root.factor
            height: width
            name: root.now ? Weather.glyphFor(root.now.code, root.now.day) : "weather-cloudy"
            gradient: true
        }

        LitText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.now ? root.degrees(root.now.temperature) : ""
            font: root.technical(Math.round(40 * root.factor), Typography.weightValue)
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.factor

            Text {
                text: root.now ? Weather.wordsFor(root.now.code) : ""
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: Math.round(15 * root.factor)
            }

            Text {
                text: root.now ? `${root.degrees(root.now.high)} · ${root.degrees(root.now.low)}` : ""
                color: Theme.textMuted
                font: root.technical(root.metrics.fontSecondary)
            }
        }
    }

    // The next hours, in a well: the hour, what it will be like, how warm.
    Well {
        metrics: root.metrics
        // Radius 10, as every well in a panel: the concentric rule taken
        // against the panel's own padding would leave it square.
        inset: 10 * root.factor
        anchors.bottom: parent.bottom
        width: parent.width
        height: 64 * root.factor

        Row {
            anchors.centerIn: parent

            Repeater {
                model: Weather.hours

                delegate: Column {
                    id: hour

                    required property var modelData

                    width: (root.width) / 5
                    spacing: 2 * root.factor

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(hour.modelData.hour).padStart(2, "0")
                        color: Theme.textFaint
                        font: root.technical(root.metrics.fontMeta)
                    }

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 20 * root.factor
                        height: width
                        name: Weather.glyphFor(hour.modelData.code, hour.modelData.day)
                        gradient: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.degrees(hour.modelData.temperature)
                        color: Theme.text
                        font: root.technical(root.metrics.fontSecondary)
                    }
                }
            }
        }
    }
}
