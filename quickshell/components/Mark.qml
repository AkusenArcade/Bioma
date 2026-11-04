import QtQuick
import QtQuick.Shapes
import qs.core

// Bioma's mark, drawn: a vertical pill with a thread through its middle and a
// node at each end of the thread — a cell on a membrane.
//
// Rebuilt from the full logotype (docs/media/logo.png), whose proportions it
// takes, in units of the pill's outer height. `assets/icons/mark.svg` is the
// same sign as a line icon; this is the sign as a solid, lit shape.
//
// The light falls straight down, not at the shell's 165°: the mark is
// symmetric, and a slanted light would lean it. The top half is the light
// tone and the bottom half the deep one, and the change happens across the
// thread — as the drawing has it. Both tones come from `base`, so the mark
// retints with the palette.
Item {
    id: root

    property color base: Theme.primary

    readonly property real unit: height
    readonly property real ringWidth: 0.608 * unit
    readonly property real stroke: 0.075 * unit
    readonly property real nodeRadius: 0.065 * unit
    // From the middle to the centre of either node.
    readonly property real reach: 0.4715 * unit

    // One gradient, over the whole mark, for both paths.
    readonly property LinearGradient light: LinearGradient {
        x1: 0; y1: 0
        x2: 0; y2: root.height

        GradientStop { position: 0; color: Theme.gradientTop(root.base) }
        GradientStop { position: 0.42; color: Theme.gradientTop(root.base) }
        GradientStop { position: 0.58; color: Theme.gradientBottom(root.base) }
        GradientStop { position: 1; color: Theme.gradientBottom(root.base) }
    }

    implicitHeight: 64
    implicitWidth: (reach + nodeRadius) * 2

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // The pill, as an outer and an inner outline: a stroke cannot carry a
        // gradient.
        ShapePath {
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1
            fillGradient: root.light

            PathRectangle {
                x: (root.width - root.ringWidth) / 2
                y: 0
                width: root.ringWidth
                height: root.height
                radius: root.ringWidth / 2
            }
            PathRectangle {
                x: (root.width - root.ringWidth) / 2 + root.stroke
                y: root.stroke
                width: root.ringWidth - root.stroke * 2
                height: root.height - root.stroke * 2
                radius: root.ringWidth / 2 - root.stroke
            }
        }

        // The thread and its nodes, one filled shape: they overlap, and a
        // winding fill makes the overlap one surface.
        ShapePath {
            fillRule: ShapePath.WindingFill
            strokeWidth: -1
            fillGradient: root.light

            PathRectangle {
                x: root.width / 2 - root.reach
                y: (root.height - root.stroke) / 2
                width: root.reach * 2
                height: root.stroke
            }
            PathRectangle {
                x: root.width / 2 - root.reach - root.nodeRadius
                y: root.height / 2 - root.nodeRadius
                width: root.nodeRadius * 2
                height: width
                radius: root.nodeRadius
            }
            PathRectangle {
                x: root.width / 2 + root.reach - root.nodeRadius
                y: root.height / 2 - root.nodeRadius
                width: root.nodeRadius * 2
                height: width
                radius: root.nodeRadius
            }
        }
    }
}
