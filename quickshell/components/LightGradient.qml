import QtQuick
import QtQuick.Shapes
import qs.core

// The one light source, as a fill.
//
// Fixed direction 165° — from above and slightly from the left — two tones of
// the same hue about 22% apart in luminance, computed from a single base colour
// so an indicator only ever declares *which* colour it is, never its two stops.
//
// It simulates light; it does not decorate. Indicators, value digits, header
// icons and selected controls take it. Fills, threads, thin line icons, glows
// and coloured shadows do not.
LinearGradient {
    id: root

    // The flat value: the mid-colour of the gradient, and what a thin line icon
    // would use on its own.
    property color base: Theme.primary

    // The box the gradient runs across. On a shape that changes size thirty
    // times a second — the audio band — this is the band, never the single bar:
    // one light source over an element that changes shape.
    property real boxWidth: 0
    property real boxHeight: 0

    readonly property real radians: Theme.gradientAngle * Math.PI / 180
    // CSS angles: 0° points up, and they turn clockwise. In item coordinates y
    // grows downward, so the direction vector is (sin, -cos) with the sign of
    // the vertical term already accounted for.
    readonly property real dx: Math.sin(radians)
    readonly property real dy: -Math.cos(radians)
    readonly property real span: Math.abs(boxWidth * dx) + Math.abs(boxHeight * dy)

    x1: boxWidth / 2 - dx * span / 2
    y1: boxHeight / 2 - dy * span / 2
    x2: boxWidth / 2 + dx * span / 2
    y2: boxHeight / 2 + dy * span / 2

    GradientStop { position: 0; color: Theme.gradientTop(root.base) }
    GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
}
