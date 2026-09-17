import QtQuick
import Quickshell
import "root:/core"

// A positioned container. Owns anchor, margins, orientation, monitor, max width
// and the ordered list of its cells. It has no opinion about what a cell shows.
//
// Phase 0 skeleton — see PRD §4.2 and §4.4.
Item {
    id: root

    // Anchored tissues declare a percentage of their membrane's length.
    // Floating tissues sit free on screen and use anchor + margins instead.
    property bool floating: false
    property real percentage: 0            // anchored only, 0..100
    property string orientation: "horizontal"
    property string growth: "inward"       // "inward" for corners, "symmetric" for centre

    property real opacity_: Config.get("tissue.opacity", 0.75)
    property int padding: Math.max(2, Math.min(12, Config.get("tissue.padding", 6)))

    property list<Item> cells: []

    readonly property bool horizontal: orientation === "horizontal"

    // The cell's radius is the tissue's minus the padding, so concentric corners
    // are automatic at every value. Clamped so it can never go below zero, and
    // never exceeds half the smaller dimension.
    readonly property real radiusPercent: Config.get("appearance.radius", 60)
    readonly property real radius: Math.min(radiusPercent / 100 * Math.min(width, height) / 2,
                                            Math.min(width, height) / 2)
    readonly property real cellRadius: Math.max(0, radius - padding)

    // The tissue background is a surface, not a border: at a wide margin the
    // band reads as a tray. It is drawn only in the band, punching out the cell
    // areas — otherwise cell blur is seen through two layers and cell opacity
    // stops meaning what it declares. It is never blurred.
    //
    // TODO Phase 0: punch-out mask over the cell rectangles.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.background, root.opacity_)
        radius: root.radius
        z: -1
    }

    // Growth moves away from the anchor: a corner tissue stacks inward so
    // existing cells never shift when a new one appears; a centre tissue
    // redistributes symmetrically. The declared order never changes — only the
    // position does. A cell appearing reflows the whole tissue, always-visible
    // cells included, so the tissue always behaves the same way.
    //
    // TODO Phase 0: elastic cells take the remaining space; with several,
    // equal share capped by each one's limit, remainder redistributed. Keep the
    // width field an object, not a bare number, so a per-cell weight stays
    // possible later. Reflow transitions use Timing.reflow.
}
