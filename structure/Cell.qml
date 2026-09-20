import QtQuick
import Quickshell
import qs.core
import qs.components

// A unit of content with one domain. It has no position of its own and no max
// width of its own: it takes what the tissue grants.
//
// Cells always have their own background — flat glass, the one blurred surface
// in the shell — a full-pill radius up to the pill ceiling, and the lit rim on
// the top edge. Nothing here clips: clipping eats the rim.
//
// See PRD §4.3, §6.5, §6.7 and docs/design/STYLE_GUIDE.md §5, §7.
Item {
    id: root

    required property string domain

    // Density and type scale, handed down by the membrane through the tissue.
    property var metrics: Metrics.step("normal")

    // The cell's own block from the configuration. Adding a cell has to cost
    // one config block and no structural change, so everything the engine needs
    // from a cell — how wide, how visible, which options — arrives here and is
    // read below rather than wired per cell.
    property var config: ({})

    function option(key, fallback) {
        const options = root.config.options;
        return options && options[key] !== undefined ? options[key] : fallback;
    }

    // Below its minimum a cell prefers not to appear rather than appear
    // illegible; text cells fall back to ellipsis. A generous minimum also
    // stops small content changes from producing motion.
    property real minWidth: config.min_width && config.min_width.value !== undefined
                            ? config.min_width.value : 24

    // Elastic cells take the remaining space in their tissue. `width` is an
    // object rather than a bare number so a per-cell weight stays possible
    // later without a schema change.
    property bool elastic: config.width ? config.width.elastic === true : false
    property real maxWidth: config.width && config.width.max_percent !== undefined
                            ? Screen.width * config.width.max_percent / 100 : -1

    // The temporal grammar, from the same block. Confirm and dwell are
    // asymmetric on purpose: appear promptly, leave slowly.
    // The measurement the cell's visibility condition watches. A boolean
    // condition — a window has focus, a device is connected — is 1 or 0 against
    // a threshold of 1; a continuous one passes its own value.
    property real condition: 0

    property Visibility visibility: Visibility {
        readonly property var rule: root.config.visibility || ({})
        value: root.condition
        type: rule.type || "always"
        invocable: rule.invocable === true || (rule.type === "invoked")
        enterThreshold: rule.enter !== undefined ? rule.enter : 0
        exitThreshold: rule.exit !== undefined ? rule.exit : 0
        confirmDelay: rule.confirm !== undefined ? rule.confirm : 300
        dwellTime: rule.dwell !== undefined ? rule.dwell : 2000
    }

    readonly property bool shown: visibility.shown

    property real cellOpacity: Config.get("cell.opacity", 0.72)
    property bool blur: Config.get("cell.blur", true)

    // Set by the tissue, so corners stay concentric with it at every radius.
    property real radius: metrics.cellHeight / 2

    // The side the cell was born from: an expansion grows away from it, and the
    // node of its first thread sits on it. Inherited from the parent tissue.
    property string origin: "start"        // "start" | "end" | "centre"

    // Contracted and expanded content. The contracted content is entirely
    // replaced by the expanded one — there is no pre-collapse. The outgoing and
    // incoming are staggered; a simultaneous crossfade reads as overlap.
    default property alias contracted: contractedSlot.data
    property Component expanded: null
    property bool open: false

    // ---- Size --------------------------------------------------------------

    // Side padding around the contracted content. Symmetrical by default; a
    // cell that leads with a round element — the window title's icon, a dial —
    // sets its own leading value so the element stays concentric with the cap.
    property real paddingLeading: 16
    property real paddingTrailing: 16

    // What the contracted content asks for, unclamped. A cell whose content
    // elides — anything with a title in it — must report the width it *wants*
    // here and elide against the width it is granted, or the two measurements
    // chase each other and the cell settles at its minimum.
    property real contentWidth: contractedSlot.implicitWidth

    readonly property real contractedHeight: metrics.cellHeight
    readonly property real contractedWidth: {
        const natural = Math.max(minWidth, contentWidth + paddingLeading + paddingTrailing);
        return maxWidth > 0 ? Math.min(natural, maxWidth) : natural;
    }

    // What the tissue grants. An elastic cell is told its width; every other
    // cell asks for the width of its content.
    property real grantedWidth: contractedWidth

    readonly property real expandedWidth: expansion.item ? expansion.item.implicitWidth : contractedWidth
    readonly property real expandedHeight: expansion.item ? expansion.item.implicitHeight : contractedHeight

    implicitWidth: contractedWidth
    implicitHeight: contractedHeight

    // Growth animates width and height, never `transform: scale`. Scale is
    // cheaper but deforms everything inside: the rim changes thickness
    // throughout the growth, radii distort, and text is stretched. The rim is
    // the signature of Bioma's surfaces, so scale is disqualified.
    width: open ? expandedWidth : grantedWidth
    height: open ? expandedHeight : contractedHeight

    // A cell that is not shown occupies nothing; the tissue reflows around it.
    visible: shown || appearance.running
    opacity: shown ? 1 : 0

    // Reversible from wherever they are, never queued: a Behavior interrupted
    // mid-flight retargets, which is exactly the required behaviour.
    Behavior on width {
        NumberAnimation {
            duration: root.open ? Timing.open : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.open ? Timing.easeOpenFlat : Timing.easeClose
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: root.open ? Timing.open : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.open ? Timing.easeOpenFlat : Timing.easeClose
        }
    }

    Behavior on opacity {
        NumberAnimation {
            id: appearance
            duration: Timing.reflow
            easing.type: Easing.InOutQuad
        }
    }

    // The tissue sets x; the move between two positions is the reflow, and the
    // PRD calls it a design moment rather than an incidental animation.
    Behavior on x {
        NumberAnimation {
            duration: Timing.reflow
            easing.type: Easing.Bezier
            easing.bezierCurve: Timing.easeOpenFlat
        }
    }

    // ---- Surfaces ----------------------------------------------------------

    // Flat glass. The fill is the cell role at the configured opacity; the blur
    // behind it is declared by the membrane as an `ext-background-effect`
    // region, never as a compositor layer rule, so it follows this exact shape
    // and not the gaps between cells.
    Rectangle {
        id: glass
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Theme.cell, root.cellOpacity)
        antialiasing: true
    }

    Rim {
        anchors.fill: parent
        radius: root.radius
    }

    // ---- Content -----------------------------------------------------------

    Item {
        id: contractedSlot
        anchors.fill: parent
        anchors.leftMargin: root.paddingLeading
        anchors.rightMargin: root.paddingTrailing
        // What the content asks for, so the cell can be as wide as its job.
        implicitWidth: childrenRect.width
        // Never clipped, or the rim goes with it: long text ellipsises itself.
        opacity: root.open ? 0 : 1

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
    }

    // Content enters only once the shape is at size, with opacity plus a 4 px
    // upward translation. Text is never scaled.
    Loader {
        id: expansion
        anchors.fill: parent
        active: root.open || root.height > root.contractedHeight + 1
        sourceComponent: root.expanded
        opacity: root.contentReady ? 1 : 0
        y: root.contentReady ? 0 : 4

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        Behavior on y { NumberAnimation { duration: Timing.contentFade; easing.type: Easing.OutQuad } }
    }

    readonly property bool contentReady: open && Math.abs(width - expandedWidth) < 1 && Math.abs(height - expandedHeight) < 1

    // ---- Interaction -------------------------------------------------------

    HoverHandler {
        id: hover
        // Interaction suspends disappearance (PRD §5.2). Mandatory for
        // notifications, where the actions live in the hover state.
        onHoveredChanged: root.visibility.interacting = hovered
    }

    readonly property bool hovered: hover.hovered

    // What the membrane needs to declare the blur region and the input mask:
    // the shape this cell actually occupies.
    function shape() {
        return { "item": root, "radius": root.radius };
    }

    // TODO Phase 0: `appearance.xray` — blur a static copy of the wallpaper
    // instead of the live content underneath. It is a configuration key, not a
    // fixed choice, and the cheap path is the one this build has not exercised.
    // TODO Phase 2: shadow on invoked and expanded cells only (0 14 28 / 45%),
    // and the thread that ties an expansion back to its origin node.
}
