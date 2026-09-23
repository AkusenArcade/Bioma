import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// The sound: its level, where it goes, where it comes from and who is making
// it.
//
// Named for its domain rather than for the dial it shows at rest. `VOLUME`
// would be the truer word for a cell that only carried a level, and the wrong
// one for a cell that already chooses the output and the input and holds a
// volume per application — the same reason the utility cell is not called
// `CAPTURE`. Akusen's call, 2026-09-22.
//
// The first **control** in the catalogue rather than an indicator: the wheel
// moves it, so it keeps the primary for its whole run — at a hundred per cent
// it is not in alarm, it is at the top. Everything else in this shell that is
// coloured is coloured by what the machine measured on its own; this one is
// coloured by nothing, because the hand on the wheel is not a measurement.
//
// At rest it is the dial alone. There is no figure: a percentage standing in
// the membrane at all times is the interface speaking when it has nothing to
// say, and the arc already says where the volume is.
//
// See docs/design/CELLS.md §05.
Cell {
    id: root

    domain: "audio"

    // The dial is the whole content, so the padding is what makes the cell
    // square: 26 between two sevens. Open, the cell carries its name as well,
    // and a name keeps the full margin on its side.
    readonly property real dialSize: 26 * metrics.factor

    // Two forms, one cell — the launcher's rule. On a membrane it is the dial,
    // and the capsule hangs from it when it opens. Summoned into the middle
    // of the screen it has no membrane to hang anything from, so it **is** the
    // capsule: dial, figure and slider, with no thread above it and the wells
    // hanging below when pressed. CELLS §05, "Invoked": what changes is where
    // it is born, not what it does.
    readonly property bool asCapsule: root.floating

    readonly property real capsuleWidth: 372 * metrics.factor
    readonly property real capsuleHeight: 88 * metrics.factor

    // The capsule's contents measure themselves; the padding is what is left
    // of the capsule's stated width.
    readonly property real capsuleContent: capsule.item ? capsule.item.contentWidth : 0
    readonly property real capsulePadding: (root.capsuleWidth - root.capsuleContent) / 2

    paddingLeading: root.asCapsule ? root.capsulePadding : 7 * metrics.factor
    paddingTrailing: root.paddingLeading

    contentWidth: root.asCapsule ? root.capsuleContent : dialSize
    bodyHeight: root.asCapsule ? root.capsuleHeight : metrics.cellHeight

    // The tissue hands every cell its own concentric radius; the capsule is
    // drawn the way the expansion draws it on a membrane.
    Component.onCompleted: if (root.asCapsule)
        root.radius = Qt.binding(() => Metrics.radiusFor(root.capsuleHeight, root.metrics))

    // Conditional, it is there for a moment after the level or the mute
    // changes — from the wheel, a key, or another program.
    readonly property real level: Audio.volume
    readonly property bool silenced: Audio.muted
    onLevelChanged: root.pulse()
    onSilencedChanged: root.pulse()
    condition: root.pulsing ? 1 : 0

    readonly property real travel: Math.min(1, Audio.volume)
    readonly property real overflow: Math.max(0, Audio.volume - 1)

    // How far one notch of the wheel moves it. In the configuration because a
    // mouse with a coarse wheel and a touchpad want different answers.
    readonly property real step: Config.get("audio.step", 0.05)

    // ---- Open ---------------------------------------------------------------

    // The cell becomes the title of its own expansion, like every other cell
    // with one — and its glyph is the dial itself, still live, because the
    // wheel keeps working while the panel is open and the mark is where the
    // eye already is.
    headerTitle: root.asCapsule ? "" : "AUDIO"
    headerMarkSize: 20 * metrics.factor
    headerMark: root.asCapsule ? null : dialMark

    Component {
        id: dialMark
        Gauge {
            anchors.fill: parent
            fraction: root.travel
            overflow: root.overflow
            muted: Audio.muted
        }
    }

    // The capsule keeps what it carries when it opens: the wells hang below
    // it, and the dial is still where the wheel is aimed.
    replacesContent: !root.asCapsule

    // Summoned, it arrives as the capsule and the wells wait for a press.
    opensOnArrival: !root.asCapsule

    // Closing the wells does not end the summoning: the capsule is still
    // there because it was asked for, and it keeps the attention so that a
    // press outside is what sends it away. Checked again a moment later,
    // because a press outside closes it *and then* ends the summoning.
    leavesOnClose: !root.asCapsule
    onOpenChanged: if (!root.open && root.asCapsule)
        Qt.callLater(() => {
            if (root.visibility.invoked && !root.open)
                Focus.opened(root);
        })

    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("AudioExpansion.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
    }

    // ---- Interaction --------------------------------------------------------
    //
    // The wheel is the main interaction here, and the only cell where that is
    // true. It answers over the whole pill rather than over the dial, which is
    // why both of these are the cell's own handlers and not handlers declared
    // in the content: on a forty pixel cell the content is the glyph and two
    // pixels around it.

    acceptsWheel: true
    onWheeled: steps => Audio.stepVolume(steps * root.step)

    acceptsMiddle: true
    onMiddleTapped: Audio.toggleMute()

    // ---- Contracted ---------------------------------------------------------

    // A sibling file is reached through a loader here: a cell is built from
    // a `qs:@` address, and the directory is not imported from there.
    Loader {
        id: capsule
        anchors.fill: parent
        active: root.asCapsule
        source: Qt.resolvedUrl("AudioCapsule.qml")
        onLoaded: item.metrics = Qt.binding(() => root.metrics)
    }

    Gauge {
        anchors.centerIn: parent
        visible: !root.asCapsule
        width: root.dialSize
        height: width
        fraction: root.travel
        overflow: root.overflow
        muted: Audio.muted
    }
}
