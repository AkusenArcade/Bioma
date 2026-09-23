import QtQuick
import Qt5Compat.GraphicalEffects
import qs.core

// A person's picture, in a circle.
//
// The picture belongs to the person, so it is never tinted — the same rule the
// application icons follow. The well it sits in is the shell's: the dark disc
// with the thin outline, which is what makes portraits of every size and
// colour read as one family.
//
// With no picture the well holds a silhouette — head and shoulders in the rim
// colour, cut by the circle, as the design page draws it on a 64 grid. **Never
// an initial in a coloured circle**: a letter in a disc is a label pretending
// to be a portrait, and the design says so in as many words (CELLS §08). It is
// not an interface icon, which is why it is drawn here and not in the set: it
// is filled, and it only ever lives inside this well.
Item {
    id: root

    property url source: ""
    property bool available: false

    signal failed

    implicitWidth: 30
    implicitHeight: 30

    Rectangle {
        id: well
        anchors.fill: parent
        radius: width / 2
        color: Theme.lift(Theme.background, -0.015)
        border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
        border.color: Qt.alpha(Theme.text, 0.5)
        antialiasing: true
    }

    // Drawn into a layer and shown through the round mask: a clip on the item
    // itself would take the outline with it.
    Image {
        id: picture
        anchors.fill: parent
        visible: false
        layer.enabled: true
        source: root.available ? root.source : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        sourceSize.width: Math.round(root.width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.height * Screen.devicePixelRatio)
        onStatusChanged: if (status === Image.Error) root.failed()
    }

    // The silhouette, on the design's 64-unit grid: a head of radius 11 at
    // (32, 25) and shoulders that are the top half of a disc of radius 21
    // standing on y 58. Drawn into a layer and cut by the same mask as the
    // picture, because the shoulders' corners reach past the circle.
    readonly property bool bare: !root.available || picture.status !== Image.Ready
    readonly property real unit: width / 64

    Item {
        id: silhouette
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            x: (32 - 11) * root.unit
            y: (25 - 11) * root.unit
            width: 22 * root.unit
            height: width
            radius: width / 2
            color: Qt.alpha(Theme.rim, 0.55)
            antialiasing: true
        }

        Item {
            x: (32 - 21) * root.unit
            y: (58 - 21) * root.unit
            width: 42 * root.unit
            height: 21 * root.unit
            clip: true

            Rectangle {
                width: parent.width
                height: width
                radius: width / 2
                color: Qt.alpha(Theme.rim, 0.45)
                antialiasing: true
            }
        }
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: width / 2
        color: "white"
        antialiasing: true
    }

    OpacityMask {
        anchors.fill: parent
        visible: root.bare
        source: silhouette
        maskSource: mask
    }

    OpacityMask {
        anchors.fill: parent
        visible: !root.bare
        source: picture
        maskSource: mask
    }
}
