import QtQuick
import Quickshell
import "root:/core"

// A unit of content with one domain. It has no position of its own and no max
// width of its own: it takes what the tissue grants.
//
// Cells always have their own background, with configurable opacity and blur.
// Blur applies to cells only, never to the tissue background, and is declared
// through `ext-background-effect` so it follows exactly the shape declared —
// compositor layer rules would blur the gaps between cells too.
//
// Phase 0 skeleton — see PRD §4.3, §6.7.
Item {
    id: root

    required property string domain

    // Below its minimum a cell prefers not to appear rather than appear
    // illegible; text cells fall back to ellipsis. A generous minimum also
    // stops small content changes from producing motion.
    property real minWidth: 24

    // Elastic cells take the remaining space in their tissue.
    property bool elastic: false
    property real maxWidth: -1

    property Visibility visibility: Visibility {}
    readonly property bool shown: visibility.shown

    property real cellOpacity: Config.get("cell.opacity", 0.85)
    property bool blur: Config.get("cell.blur", true)
    property real radius: 0                  // set by the tissue

    // Contracted and expanded content. The contracted content is entirely
    // replaced by the expanded one — there is no pre-collapse. Stagger the
    // outgoing and incoming slightly; a simultaneous crossfade reads as overlap.
    default property alias contracted: contractedSlot.data
    property Component expanded: null
    property bool open: false

    implicitWidth: Math.max(minWidth, contractedSlot.implicitWidth)

    visible: shown
    opacity: shown ? 1 : 0

    // Growth animates width and height, never `transform: scale`. Scale is
    // cheaper but deforms everything inside: the lit border changes thickness
    // throughout the growth, radii distort, and text is stretched. The lit
    // border is the signature of Bioma's surfaces, so scale is disqualified.
    Behavior on width { NumberAnimation { duration: root.open ? Timing.open : Timing.close } }
    Behavior on height { NumberAnimation { duration: root.open ? Timing.open : Timing.close } }
    Behavior on opacity { NumberAnimation { duration: root.open ? Timing.open : Timing.close } }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Theme.surface, root.cellOpacity)
        border.width: Scale.crisp(1, Screen.devicePixelRatio)
        border.color: Theme.border
    }

    Item {
        id: contractedSlot
        anchors.fill: parent
    }

    HoverHandler {
        // Interaction suspends disappearance (PRD §5.2). Mandatory for
        // notifications, where the actions live in the hover state.
        onHoveredChanged: root.visibility.interacting = hovered
    }

    // TODO Phase 0: expansion grows from the cell's anchor point, over windows
    // and never into reserved space; content enters only once the shape has
    // reached its size, via opacity plus a 4 px upward translation, and text is
    // never scaled. Animations must be reversible from their current state,
    // never queued.
    // TODO Phase 0: declare the blur region through ext-background-effect.
}
