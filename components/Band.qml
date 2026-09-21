import QtQuick
import Qt5Compat.GraphicalEffects
import qs.core

// The audio band: small vertical capsules, symmetrical from the centre.
//
// The mark's own shape, put in a row. They grow from the middle line rather
// than from the floor because filling from the bottom already means something
// else in this shell — it is how memory is drawn — and because sound has no
// floor: it is a displacement either side of nothing.
//
// The gradient is defined over the height of the **band**, not of a single bar:
// a short bar samples the middle of it, a tall one runs its whole length. That
// is the only way to keep one light source on something that changes shape
// thirty times a second, and it is why the bars are a mask over one gradient
// rather than a row of separately filled rectangles.
Item {
    id: root

    // 0 to 1 per bar, lowest frequency first. Shorter than `count` is allowed:
    // the rest rest.
    property var values: []

    property int count: 14
    property real barWidth: 3
    property real pitch: 6
    property color base: Theme.primary

    // A bar with nothing in it is a dot, not a gap: the row is the instrument,
    // and an instrument with missing teeth reads as broken rather than as
    // quiet.
    readonly property real minimum: barWidth

    implicitWidth: count * barWidth + (count - 1) * (pitch - barWidth)
    implicitHeight: 22

    function heightAt(index) {
        const list = root.values;
        const value = index < list.length ? list[index] : 0;
        return Math.max(root.minimum, value * root.height);
    }

    // The light: one gradient over the whole band, which the bars reveal.
    Rectangle {
        id: light
        anchors.fill: parent
        visible: false
        layer.enabled: true

        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradientTop(root.base) }
            GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
        }
    }

    // The shape: the bars themselves, drawn only to be sampled.
    Item {
        id: bars
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Repeater {
            model: root.count

            delegate: Rectangle {
                id: bar

                required property int index

                width: root.barWidth
                height: root.heightAt(bar.index)
                radius: width / 2
                antialiasing: true
                color: "white"

                x: bar.index * root.pitch
                y: (root.height - height) / 2

                // The value is the data; this is the only thing here that is
                // not. A band that snapped between frames would flicker rather
                // than move, and the tool's own smoothing is about the sound,
                // not about the screen.
                Behavior on height {
                    NumberAnimation {
                        duration: Timing.contentFade
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: light
        maskSource: bars
    }
}
