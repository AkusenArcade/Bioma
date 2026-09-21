import QtQuick
import Qt5Compat.GraphicalEffects
import qs.core

// The audio band: small vertical capsules, mirrored from the centre.
//
// The mark's own shape, put in a row. Two things are symmetrical here and they
// are not the same symmetry.
//
// A bar grows from the middle **line**, up and down, rather than from the
// floor: filling from the bottom already means something else in this shell —
// it is how memory is drawn — and sound has no floor, it is a displacement
// either side of nothing.
//
// And the row itself is mirrored about its **middle**: the left half is the
// left channel and the right half the right one, with the low frequencies
// meeting at the centre and the high ones at the outside. It is the shape
// Sinestesia draws, and it means the picture is the stereo image — a sound that
// sits on one side lights one wing.
//
// The gradient is defined over the height of the **band**, not of a single bar:
// a short bar samples the middle of it, a tall one runs its whole length. That
// is the only way to keep one light source on something that changes shape
// thirty times a second, and it is why the bars are a mask over one gradient
// rather than a row of separately filled rectangles.
Item {
    id: root

    // One spectrum per channel, 0 to 1, lowest frequency first. Shorter than
    // half the count is allowed: the rest rest.
    //
    // Not `left` and `right`: an Item declares those final — they are its own
    // anchor lines — and shadowing them costs the component.
    property var leftChannel: []
    property var rightChannel: []

    // Bars in the whole row, both wings together. An odd one would have no
    // middle to mirror about.
    property int count: 14
    readonly property int half: Math.floor(count / 2)
    property real barWidth: 3
    property real pitch: 6
    property color base: Theme.primary

    // A bar with nothing in it is a dot, not a gap: the row is the instrument,
    // and an instrument with missing teeth reads as broken rather than as
    // quiet.
    readonly property real minimum: barWidth

    implicitWidth: count * barWidth + (count - 1) * (pitch - barWidth)
    implicitHeight: 22

    // Which band a bar is showing. Counting outwards from the middle in both
    // directions: the bar against the centre is the lowest frequency of its
    // channel, the one at the edge is the highest.
    function valueAt(index) {
        const mirrored = index < root.half;
        const list = mirrored ? root.leftChannel : root.rightChannel;
        const place = mirrored ? root.half - 1 - index : index - root.half;
        return place < list.length ? list[place] : 0;
    }

    function heightAt(index) {
        return Math.max(root.minimum, root.valueAt(index) * root.height);
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
