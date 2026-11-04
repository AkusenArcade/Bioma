import QtQuick
import Qt5Compat.GraphicalEffects
import qs.core

// Text filled with the light, not coloured by it.
//
// Value digits take the gradient (STYLE_GUIDE §4), and IMPLEMENTATION.md says
// how: a text fill, not a colour property. A Text can only be one colour, so
// the gradient is drawn as a box and the glyphs reveal it — the same way the
// audio band's bars reveal one light over the whole band.
Item {
    id: root

    property alias text: glyphs.text
    property alias font: glyphs.font
    property color base: Theme.primary

    implicitWidth: glyphs.implicitWidth
    implicitHeight: glyphs.implicitHeight
    baselineOffset: glyphs.baselineOffset

    // The light, over the whole text box: one source, so a short figure and a
    // long one are lit the same way.
    Rectangle {
        id: light
        anchors.fill: parent
        opacity: 0
        layer.enabled: true

        gradient: Gradient {
            GradientStop { position: 0; color: Theme.gradientTop(root.base) }
            GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
        }
    }

    Text {
        id: glyphs
        anchors.fill: parent
        opacity: 0
        layer.enabled: true
        color: "white"
    }

    OpacityMask {
        anchors.fill: parent
        source: light
        maskSource: glyphs
    }
}
