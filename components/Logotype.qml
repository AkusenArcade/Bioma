import QtQuick
import qs.core

// Bioma's logotype: the mark, the name in Orbitron and the line under it in
// Spectral — rebuilt from docs/media/logo.png, whose proportions it keeps, in
// units of the mark's height. Akusen drew the composition; this sets it in the
// shell's own faces and colours, so it follows the palette.
//
// The name is set tight to the drawing: its capitals are 0.18 of the mark, the
// line under it is as wide as the name, and the gaps are measured from the
// mark's foot to the capitals and from the name's baseline to the line's.
// 0.72 and 0.66 are Orbitron's and Spectral's capital heights, in em.
//
// The three parts can arrive one after the other: `markShown`, `nameShown`
// and `lineShown` run from 0 to 1, and each part comes in from `travel`
// logical units away — negative from above.
Item {
    id: root

    property real markHeight: 96
    property real markShown: 1
    property real nameShown: 1
    property real lineShown: 1
    property real travel: 0

    readonly property real unit: markHeight

    implicitWidth: Math.max(mark.width, name.width, line.width)
    implicitHeight: line.y + line.height

    Mark {
        id: mark

        anchors.horizontalCenter: parent.horizontalCenter
        height: root.unit
        width: implicitWidth
        opacity: root.markShown
        transform: Translate { y: (1 - root.markShown) * root.travel }
    }

    // The name is not a measurement, but it is the machine's own: the
    // technical voice, as the drawing sets it.
    Text {
        id: name

        readonly property real capital: 0.18 * root.unit
        readonly property int size: Math.round(capital / 0.72)

        anchors.horizontalCenter: parent.horizontalCenter
        // Placed by its capitals, not by its line box: the gap in the drawing
        // is ink to ink.
        y: mark.height + 0.114 * root.unit - (baselineOffset - capital)
        opacity: root.nameShown
        transform: Translate { y: (1 - root.nameShown) * root.travel }

        text: "BIOMA"
        color: Theme.text
        font.family: Typography.technical
        font.weight: Font.Normal
        font.pixelSize: size
        font.letterSpacing: size * 0.02
    }

    Text {
        id: line

        readonly property real capital: 0.094 * root.unit

        anchors.horizontalCenter: parent.horizontalCenter
        y: name.y + name.baselineOffset + 0.102 * root.unit - (baselineOffset - capital)
        opacity: root.lineShown
        transform: Translate { y: (1 - root.lineShown) * root.travel }

        text: "A Living Shell"
        color: Theme.textMuted
        font.family: Typography.expressive
        font.weight: Font.Normal
        font.pixelSize: Math.round(capital / 0.66)
    }
}
