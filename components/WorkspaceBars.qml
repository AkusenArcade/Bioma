import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// The workspaces mark: two stacked bars that shift one step when the workspace
// changes.
//
// It does not count workspaces. How many there are is what the list is for, and
// an indicator repeating in miniature something already legible elsewhere is
// noise. What it says is narrower and more useful: *the command arrived* — which
// matters exactly when the change came from the keyboard and the eye was not on
// the membrane.
//
// Four bars are drawn on a pitch of 9.5 in the 24 grid and clipped to it, so a
// shift of one pitch lands on an identical arrangement: the mark moves, and
// stays itself. The clip is on this item, never on the cell around it.
Item {
    id: root

    // Set to -1 or 1 to shift by one step; it returns to rest on its own.
    property int direction: 0
    property color base: Theme.primary

    implicitWidth: 16
    implicitHeight: 16

    // The design grid the geometry is written in.
    readonly property real grid: 24
    readonly property real unit: Math.min(width, height) / grid
    readonly property real pitch: 9.5 * unit
    // A 1.4 stroke in the 24 grid is under a pixel once the mark is drawn at
    // 16, so it is rounded to the physical pixel like every other hairline.
    readonly property real stroke: Metrics.crisp(1.4 * unit, Screen.devicePixelRatio)

    // Grid 24, live area 20: the two pixels of margin per side are what hold
    // the neighbouring bars out of sight until the mark shifts. Clipping the
    // whole grid instead leaves a sliver of each of them on show at rest.
    readonly property real margin: 2 * unit

    // The bars are a few pixels across, so their edges must land on whole
    // physical pixels or a one-pixel stroke is spread over two and the mark
    // reads as a smudge. Only the static geometry is snapped: the shift stays
    // fluid, or it would step.
    function snap(value) {
        return Metrics.snap(value, Screen.devicePixelRatio);
    }

    readonly property real barX: snap(4 * unit)
    readonly property real barWidth: snap(16 * unit)
    readonly property real barHeight: snap(7.5 * unit)
    readonly property real barRadius: snap(3 * unit)

    // The bars slide by one pitch and are then placed back without animation:
    // the pattern repeats, so the return is invisible.
    property real offset: 0

    function shift(steps) {
        if (steps === 0)
            return;
        slide.stop();
        root.offset = 0;
        slide.to = -steps * root.pitch;
        slide.start();
    }

    NumberAnimation {
        id: slide
        target: root
        property: "offset"
        duration: Timing.transition
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpen
        onFinished: root.offset = 0
    }

    Item {
        anchors.fill: parent
        anchors.margins: root.margin
        // The one clip the shell allows, and it is on an icon, never on a cell:
        // it is what makes the next bar arrive from outside and the last leave.
        clip: true

        Shape {
            x: -root.margin
            y: -root.margin
            width: root.width
            height: root.height
            preferredRendererType: Shape.CurveRenderer

            // One path for the four bars, and one gradient across the whole
            // mark rather than one per bar: a single light source on an element
            // that changes shape.
            ShapePath {
                fillRule: ShapePath.OddEvenFill
                strokeWidth: -1
                fillGradient: LightGradient {
                    base: root.base
                    boxWidth: root.width
                    boxHeight: root.height
                }

                // Outer and inner rectangle per bar: the design strokes these
                // bars rather than filling them, and a stroke cannot carry a
                // gradient.

                PathRectangle {
                    x: root.barX
                    y: root.snap(-6 * root.unit) + root.offset
                    width: root.barWidth
                    height: root.barHeight
                    radius: root.barRadius
                }
                PathRectangle {
                    x: root.barX + root.stroke
                    y: root.snap(-6 * root.unit) + root.offset + root.stroke
                    width: root.barWidth - root.stroke * 2
                    height: root.barHeight - root.stroke * 2
                    radius: Metrics.innerRadius(root.barRadius, root.stroke)
                }

                PathRectangle {
                    x: root.barX
                    y: root.snap(3.5 * root.unit) + root.offset
                    width: root.barWidth
                    height: root.barHeight
                    radius: root.barRadius
                }
                PathRectangle {
                    x: root.barX + root.stroke
                    y: root.snap(3.5 * root.unit) + root.offset + root.stroke
                    width: root.barWidth - root.stroke * 2
                    height: root.barHeight - root.stroke * 2
                    radius: Metrics.innerRadius(root.barRadius, root.stroke)
                }

                PathRectangle {
                    x: root.barX
                    y: root.snap(13 * root.unit) + root.offset
                    width: root.barWidth
                    height: root.barHeight
                    radius: root.barRadius
                }
                PathRectangle {
                    x: root.barX + root.stroke
                    y: root.snap(13 * root.unit) + root.offset + root.stroke
                    width: root.barWidth - root.stroke * 2
                    height: root.barHeight - root.stroke * 2
                    radius: Metrics.innerRadius(root.barRadius, root.stroke)
                }

                PathRectangle {
                    x: root.barX
                    y: root.snap(22.5 * root.unit) + root.offset
                    width: root.barWidth
                    height: root.barHeight
                    radius: root.barRadius
                }
                PathRectangle {
                    x: root.barX + root.stroke
                    y: root.snap(22.5 * root.unit) + root.offset + root.stroke
                    width: root.barWidth - root.stroke * 2
                    height: root.barHeight - root.stroke * 2
                    radius: Metrics.innerRadius(root.barRadius, root.stroke)
                }
            }
        }
    }
}
