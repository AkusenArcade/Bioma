import QtQuick
import qs.core

// Signal strength: four bars of rising height, and never a state colour.
//
// A weak signal is not "past threshold" — nothing is wrong with a network that
// is far away — so the bars stay primary for their whole range and the ones
// that are not reached are the same colour, faded (STYLE_GUIDE §3). Red here
// would say the machine had found a fault, and it has not.
Item {
    id: root

    // 0 to 4, as the network service counts them.
    property int bars: 0
    property real factor: 1
    property color base: Theme.primary

    readonly property var heights: [5, 8, 11, 14]
    readonly property real barWidth: 3 * factor
    readonly property real pitch: 5 * factor

    implicitWidth: root.heights.length * pitch - (pitch - barWidth)
    implicitHeight: 14 * factor

    Row {
        anchors.bottom: parent.bottom
        spacing: root.pitch - root.barWidth

        Repeater {
            model: root.heights.length

            delegate: Rectangle {
                id: bar

                required property int index

                readonly property bool reached: bar.index < root.bars

                width: root.barWidth
                height: root.heights[bar.index] * root.factor
                radius: width / 2
                antialiasing: true
                anchors.bottom: parent.bottom

                color: bar.reached ? root.base : Qt.alpha(root.base, 0.22)

                Behavior on color { ColorAnimation { duration: Timing.transition } }
            }
        }
    }
}
