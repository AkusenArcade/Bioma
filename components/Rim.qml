import QtQuick
import QtQuick.Shapes
import qs.core

// The lit border. One light source, from above, on every surface in the shell.
//
// It is a **shape on the edge**, not a border colour: it runs from the rim
// colour at the top to the line colour at mid-height, and stays there below. A
// `Rectangle` cannot do that — `border.color` is flat — and a gradient
// rectangle behind a translucent fill would show through the glass. So the rim
// is a ring: two rounded rectangles in one path with an odd-even fill, which
// leaves the inside untouched.
//
// It is never clipped. Any `clip: true` on a cell eats it, which is exactly
// what made the outline vanish in the first window title.
Shape {
    id: root

    // Set by the surface it outlines.
    property real radius: 0
    property color topColour: Theme.rim
    property color bottomColour: Theme.line

    // A hairline is a critical dimension: rounded to the physical pixel or it
    // smears and disappears under fractional scaling.
    readonly property real thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)

    // The curve renderer antialiases the ring properly at this width; the
    // geometry renderer leaves it ragged on the caps.
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillRule: ShapePath.OddEvenFill
        strokeWidth: -1

        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            // The light reaches the line colour at mid-height and stays there:
            // the gradient pads below its last stop.
            y2: Math.max(1, root.height / 2)

            GradientStop { position: 0; color: root.topColour }
            GradientStop { position: 1; color: root.bottomColour }
        }

        PathRectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }

        PathRectangle {
            x: root.thickness
            y: root.thickness
            width: Math.max(0, root.width - root.thickness * 2)
            height: Math.max(0, root.height - root.thickness * 2)
            // Concentric: the inner radius is the outer minus the inset, and
            // never below zero.
            radius: Metrics.innerRadius(root.radius, root.thickness)
        }
    }
}
