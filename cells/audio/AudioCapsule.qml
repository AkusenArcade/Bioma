import QtQuick
import qs.core
import qs.components
import qs.services

// What the capsule carries: the dial, the figure and the main slider.
//
// One object in two places. On a membrane it is the first shape of the
// expansion, hung from the cell; summoned into the middle of the screen it is
// the cell itself, because a cell with no membrane has nothing to hang from
// (CELLS §05, "Invoked"). What changes is where it is born, not what it does.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real dialSize: 56 * factor
    readonly property real figureWidth: 62 * factor
    readonly property real sliderWidth: 168 * factor
    readonly property real gap: 20 * factor

    // The three elements and the two gaps between them: the capsule is drawn
    // from these, not from a padding invented around them.
    readonly property real contentWidth: dialSize + figureWidth + sliderWidth + gap * 2

    implicitWidth: contentWidth
    implicitHeight: dialSize

    Gauge {
        id: dial
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.dialSize
        height: width
        // The capsule's dial is drawn finer than the contracted one: the same
        // figures, at a size where 3 units would be a band.
        trackUnits: 1.5
        nodeUnits: 4
        fraction: Math.min(1, Audio.volume)
        overflow: Math.max(0, Audio.volume - 1)
        muted: Audio.muted
    }

    Text {
        id: reading
        anchors.left: dial.right
        anchors.leftMargin: root.gap
        anchors.verticalCenter: parent.verticalCenter
        width: root.figureWidth
        text: `${Audio.volumePercent}%`
        color: Theme.text
        opacity: Audio.muted ? 0.45 : 1
        font: Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontValue,
            "weight": Typography.weightValue
        }))
    }

    // The travel is the travel: this slider runs to a hundred, and what is
    // above it was asked for deliberately with the wheel and is shown on the
    // dial's outer arc. A bar that silently held a hundred and fifty would make
    // every ordinary setting land in its first two thirds.
    Slider {
        anchors.left: reading.right
        anchors.leftMargin: root.gap
        anchors.verticalCenter: parent.verticalCenter
        width: root.sliderWidth
        factor: root.factor
        value: Math.min(1, Audio.volume)
        dimmed: Audio.muted
        onMoved: value => Audio.setVolume(value)
    }
}
