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
// With no picture the well stands empty. **Never an initial in a coloured
// circle**: a letter in a disc is a label pretending to be a portrait, and the
// design says so in as many words (CELLS §08). The silhouette the handoff
// draws is not in the icon set yet, and an empty well is the honest shape
// until it is.
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
        visible: root.available && picture.status === Image.Ready
        source: picture
        maskSource: mask
    }
}
