import QtQuick
import QtQuick.Shapes
import qs.core

// A rounded-rectangular ring: a band of one colour between an outer rounded
// rectangle and an inner one, with nothing drawn inside.
//
// This is how a tissue draws its background. A filled rectangle behind the
// cells would sit between the blurred background and the cell glass — the blur
// would be seen through two layers and the cell's opacity would stop meaning
// what it declares — and a band tiled out of plain rectangles cannot follow the
// outer radius, which is what makes it read as a rectangle drawn around the
// cells rather than as the edge of a surface.
Shape {
    id: root

    property real radius: 0
    property real thickness: 2
    // Concentric by default: the inner radius is the outer minus the band.
    property real innerRadius: Metrics.innerRadius(radius, thickness)
    property color colour: Theme.elevated

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillRule: ShapePath.OddEvenFill
        strokeWidth: -1
        fillColor: root.colour

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
            radius: root.innerRadius
        }
    }
}
