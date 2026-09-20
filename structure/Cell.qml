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
    property real maxWidth: {
        const width = config.width;
        if (!width)
            return -1;
        if (width.max !== undefined)
            return width.max * metrics.factor;
        if (width.max_percent !== undefined)
            return Screen.width * width.max_percent / 100;
        return -1;
    }

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

    // The monitor this cell is on, inherited from the membrane. A cell whose
    // domain is per-screen — workspaces, the dock — answers for this output and
    // no other.
    property string output: ""

    // The edge of the membrane this cell sits on, so an expansion knows which
    // way is away from the screen edge.
    property string edge: "top"

    // Contracted content, and the panel an expansion hangs below it. The cell
    // itself keeps its contracted shape: what grows is the panel, out of the
    // node of the thread that ties it back here.
    default property alias contracted: contractedSlot.data

    // One panel, for a cell whose expansion is a single surface — and, for one
    // that is a composition of several, a free-form expansion that lays out its
    // own shapes and threads. A cell declares one or the other.
    property Component panel: null
    property Component expansion: null
    property bool open: false

    // What the cell shows while it is open, if that is not what it shows at
    // rest. A cell with a header becomes the title of its own expansion: the
    // contracted content goes and the header arrives in its place.
    property Component header: null

    // Or it can simply stop speaking, with nothing in its place.
    property bool replacesContent: false

    readonly property bool showsHeader: open && header !== null

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

    implicitWidth: contractedWidth
    implicitHeight: contractedHeight

    width: grantedWidth
    height: contractedHeight

    // A cell that is not shown occupies nothing; the tissue reflows around it.
    visible: shown || appearance.running
    opacity: shown ? 1 : 0

    // A contracted cell resizes to fit its content, and that is a reflow: it
    // must move at the rate its tissue and its neighbours move at, or the row
    // tears. Expansion no longer touches this — what grows is the panel.
    //
    // Reversible from wherever it is, never queued: a Behavior interrupted
    // mid-flight retargets, which is exactly the required behaviour.
    Behavior on width {
        NumberAnimation {
            duration: Timing.reflow
            easing.type: Easing.Bezier
            easing.bezierCurve: Timing.easeOpenFlat
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
        opacity: root.open && (root.replacesContent || root.showsHeader) ? 0 : 1

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
    }

    // The outgoing and the incoming are staggered rather than crossfaded: two
    // strings dissolving through each other read as overlap, not as a change.
    Loader {
        id: headerSlot
        active: root.header !== null && (root.open || opacity > 0)
        sourceComponent: root.header
        anchors.verticalCenter: parent.verticalCenter
        x: root.paddingLeading
        opacity: root.showsHeader ? 1 : 0

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: Timing.stagger * 2 }
                NumberAnimation { duration: Timing.contentFade }
            }
        }
    }

    // ---- Expansion ---------------------------------------------------------
    //
    // It is born from its point. The panel grows out of the node of the thread
    // that connects it to this cell, animating width and height, and it grows
    // away from the screen edge — over the windows, never into reserved space.
    //
    // The cascade is the one in STYLE_GUIDE §6: the thread draws, the panel
    // grows out of its far node a stagger later, and the content arrives only
    // once the shape is at size. Closing reverses it and is quicker: it opens
    // calmly, it closes quickly.

    readonly property bool hasPanel: panel !== null || expansion !== null

    // How far the panel hangs below the cell: the distance from the cell's
    // outer edge to the line where the compositor begins drawing windows. Set
    // by the tissue, which knows where both are. Every open cell therefore
    // hangs its panel from that same line, whatever its own height.
    property real originGap: metrics.marginEdge + metrics.tissuePadding
    readonly property real gap: originGap

    // A top membrane opens downward, a bottom one upward.
    readonly property bool opensDown: edge !== "bottom"

    property real threadProgress: 0
    property real panelGrowth: 0
    readonly property bool panelVisible: panelGrowth > 0
    readonly property bool panelReady: open && panelGrowth > 0.999

    Thread {
        id: thread
        vertical: true
        visible: root.hasPanel && root.threadProgress > 0
        progress: root.threadProgress
        width: implicitWidth
        height: root.gap
        x: (root.width - width) / 2
        y: root.opensDown ? root.height : -root.gap
    }

    Panel {
        id: panelShape
        metrics: root.metrics
        visible: root.panel !== null && root.panelGrowth > 0
        growth: root.panelGrowth
        contentReady: root.panelReady

        // The node the shape is born from: the far end of the thread.
        nodeX: root.width / 2
        nodeY: root.opensDown ? root.height + root.gap : -root.gap

        // Where it settles. A cell anchored to a corner keeps that edge and
        // the panel opens inward; a centred one opens from both sides.
        anchorX: root.origin === "end" ? root.width - targetWidth
               : root.origin === "centre" ? (root.width - targetWidth) / 2
               : 0
        anchorY: root.opensDown ? root.height + root.gap : -root.gap - targetHeight

        Loader {
            id: panelContent
            active: root.open || root.panelGrowth > 0
            sourceComponent: root.panel
        }
    }

    // A composition places itself: it is given the anchor — the line the
    // windows start on, on the side the cell was born from — and grows its own
    // shapes out of the thread's far node.
    Loader {
        id: expansionSlot
        active: root.expansion !== null && (root.open || root.panelGrowth > 0)
        sourceComponent: root.expansion

        y: root.opensDown ? root.height + root.gap : -root.gap - height
        x: root.origin === "end" ? root.width - width
         : root.origin === "centre" ? (root.width - width) / 2
         : 0
    }

    onOpenChanged: {
        // One cell at a time: opening this one closes whatever was open, and a
        // press anywhere the shell does not claim closes this one.
        if (open)
            Focus.opened(root);
        else
            Focus.released(root);

        if (!hasPanel)
            return;
        closing.stop();
        opening.stop();
        if (open)
            opening.start();
        else
            closing.start();
    }

    // Both run from wherever the values already are, so invoking a cell
    // mid-opening sends it back rather than restarting it.
    ParallelAnimation {
        id: opening

        NumberAnimation {
            target: root
            property: "threadProgress"
            to: 1
            duration: Timing.grow
            easing.type: Easing.Bezier
            easing.bezierCurve: Timing.easeOpenFlat
        }

        SequentialAnimation {
            PauseAnimation { duration: Timing.stagger * 2 }
            NumberAnimation {
                target: root
                property: "panelGrowth"
                to: 1
                duration: Timing.grow
                easing.type: Easing.Bezier
                // A panel is not a small capsule: overshoot here reads as a
                // bounce and conflicts with the register.
                easing.bezierCurve: Timing.easeOpenFlat
            }
        }
    }

    ParallelAnimation {
        id: closing

        NumberAnimation {
            target: root
            property: "panelGrowth"
            to: 0
            duration: Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: Timing.easeClose
        }

        SequentialAnimation {
            PauseAnimation { duration: Timing.stagger * 2 }
            NumberAnimation {
                target: root
                property: "threadProgress"
                to: 0
                duration: Timing.close - Timing.stagger * 2
                easing.type: Easing.Bezier
                easing.bezierCurve: Timing.easeClose
            }
        }
    }

    // ---- Interaction -------------------------------------------------------

    HoverHandler {
        id: hover
        // Interaction suspends disappearance (PRD §5.2). Mandatory for
        // notifications, where the actions live in the hover state.
        onHoveredChanged: root.visibility.interacting = hovered
    }

    readonly property bool hovered: hover.hovered

    // What the membrane needs to declare the blur region and the input mask:
    // every shape this cell actually occupies. The thread is not one of them —
    // it takes no input, and blurring a 1.3 px line would only smear it.
    function shapes() {
        const out = [{ "item": root, "radius": root.radius }];
        if (root.panelVisible && root.panel !== null)
            out.push({ "item": panelShape, "radius": panelShape.radius });
        if (expansionSlot.item && expansionSlot.item.shapes)
            for (const shape of expansionSlot.item.shapes())
                out.push(shape);
        return out;
    }

    // TODO Phase 0: `appearance.xray` — blur a static copy of the wallpaper
    // instead of the live content underneath. It is a configuration key, not a
    // fixed choice, and the cheap path is the one this build has not exercised.
    // TODO Phase 2: a cell that replaces its contracted content with a header
    // form when it opens — the vitals indicators fade and the cell becomes the
    // title of its own expansion.
    // TODO Phase 0: clicking outside closes an open cell, which needs the
    // full-screen input surface of PRD §8; and a panel whose anchor would take
    // it off the screen has to be pushed back inside.
}
