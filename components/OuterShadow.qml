import QtQuick
import QtQuick.Effects
import qs.core

// A shadow drawn only outside its shape, the way the design draws it.
//
// The design pages give every raised surface a CSS `box-shadow`, and CSS
// draws an outer shadow only outside the border box: through a translucent
// fill it is never seen. `RectangularShadow` is a filled, blurred shape, so
// under a panel whose fill is translucent it darkened the inside too — black
// at 45 % under an opened panel, 60 % under a floating one — and what the
// blur showed through the surface was about half what the opacity promised.
// Akusen found the panels showed less of the desktop than niri's windows
// (2026-09-29). Here the shape is taken back out of the shadow.
//
// The item is the shape's own rectangle, so it can fill it and the parent's
// childrenRect does not grow; what is drawn reaches past it by the blur and
// the offset.
Item {
    id: root

    property real radius: 0
    property real blur: 28
    property real spread: 0
    property real offsetY: 14
    property color color: Theme.shadow

    // How far inside the shape the hole starts. Cut exactly along the edge,
    // the hole and the rim both only half-cover the pixels on a curve, and in
    // what neither covers the unshaded desktop shows: a bright thread outside
    // the rim, round every corner, plain on a light wallpaper (Akusen,
    // 2026-09-29). Every shadowed surface draws a rim, and the rim is opaque,
    // so the shadow runs on under it and is hidden there — only the glass
    // inside stays unshaded.
    property real inset: Metrics.rim(Screen.devicePixelRatio)

    readonly property real reach: Math.ceil(root.blur + root.spread + Math.abs(root.offsetY)) + 2

    // The shadow as RectangularShadow draws it, on a canvas large enough to
    // hold its whole reach.
    Item {
        id: canvas

        x: -root.reach
        y: -root.reach
        width: root.width + root.reach * 2
        height: root.height + root.reach * 2
        visible: false
        layer.enabled: true

        RectangularShadow {
            x: root.reach
            y: root.reach
            width: root.width
            height: root.height
            radius: root.radius
            blur: root.blur
            spread: root.spread
            offset.y: root.offsetY
            color: root.color
        }
    }

    // The shape, on the same canvas, to be taken out.
    Item {
        id: shape

        x: -root.reach
        y: -root.reach
        width: canvas.width
        height: canvas.height
        visible: false
        layer.enabled: true

        Rectangle {
            x: root.reach + root.inset
            y: root.reach + root.inset
            width: Math.max(0, root.width - root.inset * 2)
            height: Math.max(0, root.height - root.inset * 2)
            radius: Metrics.innerRadius(root.radius, root.inset)
            antialiasing: true
            color: "white"
        }
    }

    MultiEffect {
        x: -root.reach
        y: -root.reach
        width: canvas.width
        height: canvas.height
        source: canvas
        maskEnabled: true
        maskInverted: true
        maskSource: shape
    }
}
