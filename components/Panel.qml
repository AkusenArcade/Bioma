import QtQuick
import QtQuick.Effects
import qs.core

// A rectangular surface for an expanded cell: glass, the lit rim, radius 20,
// and the shadow that only invoked and expanded cells carry.
//
// It is **born from its point** — the node of the thread that ties it to the
// cell it came out of. Growth animates width and height from that node, never a
// scale: scaling deforms the rim, distorts the radius and stretches the text.
//
// Content enters only once the shape is at size, and it enters the way it
// leaves: growing from its own centre. STYLE_GUIDE §6 asks for opacity plus a
// 4 px rise instead; on the machine that reads as the content dropping in from
// above, and a shell where things arrive one way and leave another has two
// gestures where it needs one. Akusen's call, 2026-09-21.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    // Where the shape ends up, in the coordinates of whatever holds it.
    property real anchorX: 0
    property real anchorY: 0

    // The node it grows out of, in the same coordinates.
    property real nodeX: 0
    property real nodeY: 0

    // 0 contracted, 1 at size.
    property real growth: 0

    // Content enters after the shape, and leaves before it.
    property bool contentReady: false

    property real padding: 10 * metrics.factor
    property real radius: metrics.radiusPanel

    // A panel is as wide as its job: the content declares the size, the panel
    // adds its padding. Symmetry is not a reason to narrow one.
    default property alias content: contentSlot.data

    // A panel is as wide as its job, and usually its content knows that job.
    // Content that arrives through a Loader does not know it yet at the
    // moment it is measured — a loader has no size until it has loaded — so
    // whoever owns the panel may state the measure instead.
    property real fixedWidth: -1
    property real fixedHeight: -1

    // The shell's own content this panel lies over, on the same surface, when
    // it lies over any — a dropdown's list over the capsules around it. The
    // compositor's blur is of what is behind the surface, so it cannot reach
    // this: the panel draws a blurred copy of it under its glass itself, and
    // takes the pointer away from it — hovered through the list, the controls
    // under it lit up as if nothing covered them (Akusen, 2026-10-01). Under
    // a translucent glass the sharp original still shows through the copy, so
    // whoever holds both cuts this panel's shape out of `over`
    // (cells/theme/ThemeExpansion.qml does, with an inverted mask).
    property Item over: null

    property real targetWidth: fixedWidth > 0 ? fixedWidth
                                              : contentSlot.childrenRect.width + padding * 2
    property real targetHeight: fixedHeight > 0 ? fixedHeight
                                                : contentSlot.childrenRect.height + padding * 2

    x: nodeX + (anchorX - nodeX) * growth
    y: nodeY + (anchorY - nodeY) * growth
    width: targetWidth * growth
    height: targetHeight * growth
    visible: growth > 0

    // Only invoked and expanded cells carry a shadow; a contracted cell never
    // does.
    // Outside the shape only, as the design's box-shadow is: under the
    // translucent fill it darkened what the blur showed through.
    OuterShadow {
        anchors.fill: parent
        radius: root.radius
        blur: 28
        spread: 0
        offsetY: 14
        color: Theme.shadow
        opacity: Timing.shadowFor(root.growth)
    }

    // The glass over shell content: a copy of what lies under the shape, taken
    // a blur's width wider on every side so the blur does not darken towards
    // the edges, blurred at the glass radius and cut to the shape.
    readonly property bool overShown: root.over !== null && root.visible
    readonly property real overBleed: root.overShown ? Math.ceil(root.metrics.blurRadius) : 0

    ShaderEffectSource {
        id: overCopy
        visible: false
        sourceItem: root.overShown ? root.over : null
        hideSource: false
        live: true
        sourceRect: {
            if (!root.overShown || root.width <= 0 || root.height <= 0)
                return Qt.rect(0, 0, 0, 0);
            // A mapping is not a binding: the panel moves while it grows, and
            // it has to say so.
            root.x;
            root.y;
            const at = root.over.mapFromItem(root, -root.overBleed, -root.overBleed);
            return Qt.rect(at.x, at.y, root.width + root.overBleed * 2, root.height + root.overBleed * 2);
        }
    }

    Item {
        id: overShape
        width: root.width + root.overBleed * 2
        height: root.height + root.overBleed * 2
        visible: false
        layer.enabled: root.overShown

        Rectangle {
            x: root.overBleed
            y: root.overBleed
            width: root.width
            height: root.height
            radius: root.radius
            antialiasing: true
        }
    }

    MultiEffect {
        id: overEffect
        x: -root.overBleed
        y: -root.overBleed
        width: root.width + root.overBleed * 2
        height: root.height + root.overBleed * 2
        visible: root.overShown && root.width > 0 && root.height > 0
        source: overCopy
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: Math.round(root.metrics.blurRadius)
        maskEnabled: true
        maskSource: overShape
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Theme.cell, Config.get("cell.opacity", 0.72))
        antialiasing: true
    }

    Rim {
        anchors.fill: parent
        radius: root.radius
    }

    // Nothing under the shape hears the pointer: not a hover, not a press,
    // not a wheel. Under the content, so the content hears it first.
    //
    // An item that accepts a press is not enough in Qt 6: the press still goes
    // on to the handlers of every item below, and a TapHandler there taps — a
    // row chosen in the list would have switched the app chip under it. The
    // press has to be grabbed exclusively, which is what a TapHandler holding
    // to its bounds does; the handlers below only held it passively, and lose
    // it.
    MouseArea {
        anchors.fill: parent
        enabled: root.over !== null
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    TapHandler {
        enabled: root.over !== null
        gesturePolicy: TapHandler.WithinBounds
        acceptedButtons: Qt.AllButtons
    }

    HoverHandler {
        enabled: root.over !== null
        blocking: true
    }

    // The content sits inside the padding and is centred in what is left: a
    // pill with its content against the top edge reads as a mistake, and every
    // pod in the shell is a pill.
    //
    // Its size is the shape's **target** size, not the size the shape is at.
    // Bound to the animated one, the slot narrows on every frame of a growth
    // and whatever is centred in it re-centres with it: at rest nothing shows,
    // and on the way out the content shoots sideways while the capsule retracts
    // under it. At full size the two are the same figure, so this changes
    // nothing that is ever still.
    //
    // Content is the one thing in the shell that scales. Shapes never do — a
    // scaled shape deforms its rim and its radii — but content has neither, and
    // growing and shrinking about its own centre is what reads as arriving in
    // the shape and being put back into it.
    //
    // It still arrives only once the shape is at size, and it still leaves
    // before the shape does: `contentFade` against the shape's `close`.
    //
    // And while the shape is not at size, the content is held inside it. The
    // closing curve is quick from its first frame, so the shape is most of the
    // way back to its node while the content is still fading, and content
    // wider than the shape it is shrinking into — a list of left-aligned rows
    // — hung out past the capsule the shape came from: the list seemed to
    // leave towards nobody (Akusen, 2026-10-01). At size nothing is clipped,
    // so what may overhang a panel at rest still does.
    Item {
        anchors.fill: parent
        clip: root.growth < 0.999

        Item {
            id: contentSlot

            readonly property real inner: Math.max(0, root.targetWidth - root.padding * 2)
            readonly property real innerHeight: Math.max(0, root.targetHeight - root.padding * 2)

            width: contentSlot.inner
            height: contentSlot.innerHeight

            x: (root.width - width) / 2
            y: (root.height - height) / 2

            opacity: root.contentReady ? 1 : 0
            scale: root.contentReady ? 1 : 0.88
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
            Behavior on scale { NumberAnimation { duration: Timing.contentFade; easing.type: Easing.OutQuad } }
        }
    }
}
