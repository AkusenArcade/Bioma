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

    // A cell that can be asked for by name says so, and stops saying it when
    // it goes. The register is what a shortcut reaches; see `core/Focus.qml`.
    Component.onCompleted: if (visibility.invocable) Focus.offer(root)
    Component.onDestruction: Focus.withdraw(root)

    // Set by the tissue when there is no room left for this cell inside the
    // percentage its membrane granted. A cell has no position and no width of
    // its own — it takes what the tissue grants — and what a tissue cannot
    // grant it does not draw: a cell half outside its band, or off the screen
    // altogether, is worse than a cell that waits its turn.
    property bool crowded: false

    readonly property bool placed: shown && !crowded

    // Who keeps their place when the tissue runs short. A cell is here because
    // it has something to say, and some of them have more: one that appeared
    // because something is happening — a recording running, a device that just
    // connected — outranks one that is simply always there, and an open cell
    // outranks both, because it is the one being looked at.
    //
    // This is what stops the arithmetic from throwing away the cell that
    // matters: the recording cell doubles in width to ask whether to save, and
    // on a narrow membrane that question was the first thing to be dropped —
    // the one cell in the shell that must be answerable.
    readonly property int precedence: open ? 2
                                     : visibility.type === "conditional" ? 1 : 0

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
    // rest. A cell with an expansion becomes the title of it: the contracted
    // content goes and the glyph of the domain arrives with the cell's name, in
    // the technical voice.
    //
    // Built here rather than by each cell, because every one of them wears the
    // same face — and because the rule for what happens when there is no room
    // for the name has to be the same everywhere. On a narrow membrane a tissue
    // can grant less than the name needs, and a name that runs out of its own
    // pill is worse than no name at all: below that width the cell shows the
    // glyph alone, centred in what it was given.
    // Whether opening this cell means it has the user's attention. One cell
    // is open at a time, and that rule is about attention rather than about
    // surfaces — a body that appears under the pointer is not attention.
    property bool claimsFocus: true

    property Component headerMark: null
    property string headerTitle: ""
    property real headerMarkSize: 20 * metrics.factor
    readonly property real headerGap: 12 * metrics.factor

    // Or it can simply stop speaking, with nothing in its place.
    property bool replacesContent: false

    // ---- Hover -------------------------------------------------------------
    //
    // A cell that answers the pointer says so before it is pressed, and says it
    // in the shell's own vocabulary — the light. The glass lifts a step and the
    // rim catches more of it.
    //
    // Nothing moves, and nothing is said. Two louder answers were built and
    // taken out again on 2026-09-22: the dock's hover label, a pill with the
    // name beside the row — which needed the surface to keep room for it and
    // was still a second thing to read — and the cell opening its own header
    // under the pointer, which reflowed the whole tissue on the way past. The
    // light is what a cell can do without moving anything.
    //
    // A cell that does nothing when pressed does not light up: the light is a
    // promise, and a cell with no expansion and no action has nothing to
    // promise. One that acts without opening anything says so itself.
    property bool interactive: hasPanel
    readonly property bool lit: interactive && hovered && !open

    // Whether the expansion needs the keyboard — a field to type in, a list to
    // drive with the arrows. It costs more than it looks: the membrane can only
    // ask for keys by declaring itself focusable, and a focusable surface is
    // one the compositor may move the focus to on hover. A cell that only
    // wants presses leaves this alone.
    property bool wantsKeyboard: false

    readonly property bool showsHeader: open && (headerMark !== null || headerTitle.length > 0)

    TextMetrics {
        id: headerMetrics
        text: root.headerTitle
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontLabel,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.metrics.fontLabel, Typography.labelTracking)
        })
    }

    readonly property real headerMarkRoom: headerMark !== null ? headerMarkSize + headerGap : 0
    readonly property real headerWidth: headerMarkRoom + headerMetrics.width

    // What the cell was actually given for its content, against what the header
    // would like. The ask always includes the name — a cell that asked for less
    // would never be granted more — and only the drawing gives it up.
    // A header is a different composition from the contracted content, and it
    // keeps its own margins. A cell built around a 30 px avatar leads with
    // five pixels so the avatar is concentric with the cap; the same five in
    // front of a 20 px glyph leave the glyph adrift against the edge. So the
    // leading margin follows whichever mark is actually there, and the name on
    // the other side keeps the full margin. Akusen saw it on the session cell,
    // 2026-09-22 — and it was the same arithmetic in four cells, each doing it
    // by hand with `open ? … : …`.
    readonly property real headerLeading: (metrics.cellHeight - headerMarkSize) / 2
    readonly property real headerTrailing: 16 * metrics.factor

    readonly property real leadingInset: showsHeader ? headerLeading : paddingLeading
    readonly property real trailingInset: showsHeader ? headerTrailing : paddingTrailing

    readonly property real contentRoom: width - leadingInset - trailingInset
    readonly property bool headerNamed: root.contentRoom >= root.headerWidth - 0.5

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

    // Open with a header, the cell is as wide as that header; otherwise as wide
    // as whatever it shows at rest.
    readonly property real askedWidth: showsHeader ? headerWidth : contentWidth

    // Nearly every cell is a pill of one height, because a membrane is a row
    // of them. A cell that is born from a shortcut and never sits on a
    // membrane is not: the launcher is a field and six rows, and it has no
    // pill at all. So a cell may say how tall it is, and the tissue makes
    // room for the tallest it holds.
    property real bodyHeight: metrics.cellHeight

    readonly property real contractedHeight: bodyHeight
    readonly property real contractedWidth: {
        const natural = Math.max(minWidth, askedWidth + leadingInset + trailingInset);
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
    visible: placed || appearance.running
    opacity: placed ? 1 : 0

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
        color: Qt.alpha(root.lit ? Theme.lift(Theme.cell, 0.05) : Theme.cell, root.cellOpacity)
        antialiasing: true

        Behavior on color { ColorAnimation { duration: Timing.transition } }
    }

    Rim {
        anchors.fill: parent
        radius: root.radius
        topColour: root.lit ? Theme.lift(Theme.rim, 0.10) : Theme.rim
        bottomColour: root.lit ? Theme.lift(Theme.line, 0.06) : Theme.line

        Behavior on topColour { ColorAnimation { duration: Timing.transition } }
        Behavior on bottomColour { ColorAnimation { duration: Timing.transition } }
    }

    // A state that belongs to the whole cell, said on its edge: urgency is an
    // outline and never a fill, because a coloured surface makes the text
    // unreadable and the shell look broken.
    //
    // It is drawn here rather than by the cell that wants it, for the same
    // reason the tap is: anything a cell declares lands in the content slot,
    // which is inset by the cell's own padding — so an outline drawn there is
    // a smaller pill inside the real one, which is exactly how it looked.
    property color outline: "transparent"

    Rectangle {
        anchors.fill: parent
        visible: root.outline.a > 0
        radius: root.radius
        color: "transparent"
        border.width: Metrics.crisp(1.5 * root.metrics.factor, Screen.devicePixelRatio)
        border.color: root.outline
        antialiasing: true

        Behavior on border.color { ColorAnimation { duration: Timing.transition } }
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
    Item {
        id: headerSlot

        anchors.fill: parent
        opacity: root.showsHeader ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: Timing.stagger * 2 }
                NumberAnimation { duration: Timing.contentFade }
            }
        }

        Loader {
            active: root.headerMark !== null && headerSlot.visible
            sourceComponent: root.headerMark

            anchors.verticalCenter: parent.verticalCenter
            width: root.headerMarkSize
            height: root.headerMarkSize

            // Against the leading cap when the name is beside it, and in the
            // middle of the cell when it is alone.
            x: root.headerNamed ? root.leadingInset
                                : Math.max(0, (root.width - width) / 2)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: root.leadingInset + root.headerMarkRoom
            visible: root.headerNamed
            text: root.headerTitle
            color: Theme.text
            font: headerMetrics.font
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

    // Open, or still on its way back. The membrane offers a surface the size of
    // the screen for as long as something is expanded on it, and "expanded" has
    // to include the closing: a surface that shrinks the instant the cell is no
    // longer open clips the retraction away, and what the eye sees is a panel
    // that vanished rather than one that closed.
    readonly property bool expanded: open || panelGrowth > 0 || threadProgress > 0

    // How far the open composition reaches past the cell, on the side it opens
    // — the thread's gap plus whatever hangs off the end of it. A tissue that
    // has to place the *whole* of a cell rather than its pill needs this: a
    // floating cell in the middle of the screen is centred on everything it
    // draws, not on the shape it grew from. Zero while it is shut, so a
    // contracted cell is placed by its pill as always.
    readonly property real reach: {
        if (!expanded)
            return 0;
        const body = expansion !== null
            ? (expansionSlot.item ? expansionSlot.item.height : 0)
            : (panel !== null ? panelShape.targetHeight : 0);
        return body > 0 ? gap + body : 0;
    }

    readonly property real reachWidth: {
        if (!expanded)
            return width;
        const body = expansion !== null
            ? (expansionSlot.item ? expansionSlot.item.width : 0)
            : (panel !== null ? panelShape.targetWidth : 0);
        return Math.max(width, body);
    }

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
        if (open) {
            // A cell that opened because the pointer brushed it has not been
            // asked for: the notification's body arrives on hover, and it
            // must not close the panel somebody is actually using. Only a
            // deliberate opening claims the shell's attention.
            if (claimsFocus)
                Focus.opened(root);
        } else {
            Focus.released(root);

            // A cell that exists only while it is asked for goes when it is
            // closed, however it was closed — the press outside that shut it
            // is also the answer to "do you still want this?".
            if (visibility.type === "invoked")
                visibility.invoked = false;
        }

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

    // The whole pill opens the cell, caps included. It cannot live with the
    // content: anything a cell declares goes into `contractedSlot`, which is
    // inset by the cell's own padding — so a handler declared there answers
    // over the icons and nowhere else, which on a 40 px square cell is the icon
    // and a two-pixel frame around it.
    property bool opensOnTap: hasPanel

    TapHandler {
        enabled: root.opensOnTap
        onTapped: root.open = !root.open
    }

    // The other two gestures a pill can answer, here for the same reason the
    // tap is: a cell that wants them wants them over its whole shape. A cell
    // says it takes them and receives the gesture; what it means is the cell's
    // own business.
    property bool acceptsWheel: false
    signal wheeled(int steps)

    WheelHandler {
        enabled: root.acceptsWheel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y > 0)
                root.wheeled(1);
            else if (event.angleDelta.y < 0)
                root.wheeled(-1);
        }
    }

    property bool acceptsMiddle: false
    signal middleTapped

    TapHandler {
        enabled: root.acceptsMiddle
        acceptedButtons: Qt.MiddleButton
        onTapped: root.middleTapped()
    }

    HoverHandler {
        id: hover
        // Interaction suspends disappearance (PRD §5.2). Mandatory for
        // notifications, where the actions live in the hover state.
        onHoveredChanged: root.engage()
    }

    readonly property bool hovered: hover.hovered

    // Whether there is anything to interact with. The rule protects what
    // somebody is reading; a cell whose content has just gone has nothing to
    // protect, and holding it there leaves an empty pill under the pointer
    // until the pointer moves — which is what dismissing a notification with
    // the pointer still on it looked like. A cell that empties says so.
    property bool engaging: true

    function engage() {
        root.visibility.interacting = root.hovered && root.engaging;
    }

    onEngagingChanged: root.engage()

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
