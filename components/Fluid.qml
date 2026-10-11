import QtQuick
import qs.core

// The audio band as a fluid, mirrored from the centre: `plasma` or `vesicles`.
//
// The same instrument as the bars, drawn as the organisms are drawn. Both
// forms keep the bars' two symmetries — the left channel on the left and the
// right one on the right, the low frequencies meeting at the middle — and
// what the bars could not say is which bands sound together: neighbours that
// are loud together melt into one body, and a pure tone stands alone.
//
// - plasma: a drop for every band on the middle line, as large as the band is
//   loud. The row is one body whose outline is the spectrum.
// - vesicles: a drop for every band that divides as the band gets louder —
//   one dot at silence, then two drops mirrored across the middle line, as
//   far from it as the band is loud, as the bars' height is.
//
// It takes the bars' measures — `count`, `barWidth`, `pitch` — so a drop sits
// where a bar would, and silence is the bar's dot. The shader is fluid.frag.
// See docs/design/CELLS.md §04.
Item {
    id: root

    property var leftChannel: []
    property var rightChannel: []

    property int count: 14
    readonly property int half: Math.floor(count / 2)
    property real barWidth: 3
    property real pitch: 6
    property color base: Theme.primary
    property string form: "vesicles"
    readonly property bool plasma: form === "plasma"

    // Where the band is tall enough, a vesicle stands for two neighbouring
    // bands (the louder of them) at twice the pitch: forty-eight across the
    // organism were beads on a string, too small to divide. Plasma keeps one
    // drop per band everywhere — its drops are one body, not separate shapes.
    readonly property int step: plasma ? 1 : Math.max(1, Math.round(height / (pitch * 6)))
    readonly property int drops: Math.floor(count / step)
    readonly property real spacing: pitch * step

    // Silence is the bar's dot. A plasma drop at full scale, with the quarter
    // of a radius a blend can add between two neighbours, stays inside the
    // row's height: loud highs were cut by the band's edge. A vesicle at full
    // scale is a little more than half a spacing, so neighbours at one height
    // touch and melt, and never more than a sixth of the band's height, or its
    // halves would have nowhere to go.
    readonly property real thread: barWidth / 2
    readonly property real drop: plasma
        ? height * 0.38
        : Math.max(thread, Math.min(spacing * 0.6, height * 0.15))
    readonly property real blend: drop * 0.45

    // Where the drops stand. Vesicles where the bars do. Plasma drops are as
    // wide as they are tall, so the row is drawn in from both ends by a full
    // drop and the pitch shared out over what is left: the outermost bands,
    // the highs, are as loud on screen as they are, never cut at the side.
    readonly property real inset: plasma ? drop + 1 : 0
    readonly property real place: plasma && drops > 1
        ? (width - 2 * inset) / (drops - 1)
        : spacing
    readonly property real start: plasma ? inset : barWidth / 2 + (step - 1) * pitch / 2

    function valueAt(index) {
        const mirrored = index < root.half;
        const list = mirrored ? root.leftChannel : root.rightChannel;
        const place = mirrored ? root.half - 1 - index : index - root.half;
        return place < list.length ? list[place] : 0;
    }

    // Where each band is heading, and where it is drawn.
    property var wanted: []
    property var values: []

    function aim() {
        const out = [];
        for (let i = 0; i < root.drops; i++) {
            let v = 0;
            for (let j = 0; j < root.step; j++)
                v = Math.max(v, root.valueAt(i * root.step + j));
            out.push(Math.max(0, Math.min(1, v)));
        }
        root.wanted = out;
        if (root.values.length !== out.length)
            root.values = out.slice();
        follow.running = true;
    }

    onLeftChannelChanged: root.aim()
    onRightChannelChanged: root.aim()
    onDropsChanged: root.aim()

    // The value is the data; the easing towards it is the bars' own, so the
    // two effects follow the sound with the same lag. A drop that snapped
    // between frames would flicker rather than breathe. It runs at the
    // monitor's rate while a drop is still moving, and stops when all are
    // where the sound puts them.
    FrameAnimation {
        id: follow

        onTriggered: {
            const tau = Math.max(Timing.contentFade, 1) / 3000;
            const k = 1 - Math.exp(-Math.min(frameTime, 0.05) / tau);
            const next = root.values.slice();
            let moving = false;
            for (let i = 0; i < next.length; i++) {
                const gap = root.wanted[i] - next[i];
                if (Math.abs(gap) > 0.002) {
                    next[i] += gap * k;
                    moving = true;
                } else {
                    next[i] = root.wanted[i];
                }
            }
            root.values = next;
            if (!moving)
                running = false;
        }
    }

    function packed(slot) {
        const at = i => i < root.values.length ? root.values[i] : 0;
        return Qt.vector4d(at(slot * 4), at(slot * 4 + 1), at(slot * 4 + 2), at(slot * 4 + 3));
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("fluid.frag.qsb")

        readonly property size extent: Qt.size(width, height)
        readonly property real count: Math.min(root.drops, 48)
        readonly property real pitch: root.place
        readonly property real first: root.start
        readonly property real form: root.plasma ? 0 : 1
        readonly property real thread: root.thread
        readonly property real drop: root.drop
        readonly property real blend: root.blend
        readonly property color upper: Theme.gradientTop(root.base)
        readonly property color lower: Theme.gradientBottom(root.base)
        readonly property color core: Theme.text

        readonly property vector4d v0: root.packed(0)
        readonly property vector4d v1: root.packed(1)
        readonly property vector4d v2: root.packed(2)
        readonly property vector4d v3: root.packed(3)
        readonly property vector4d v4: root.packed(4)
        readonly property vector4d v5: root.packed(5)
        readonly property vector4d v6: root.packed(6)
        readonly property vector4d v7: root.packed(7)
        readonly property vector4d v8: root.packed(8)
        readonly property vector4d v9: root.packed(9)
        readonly property vector4d v10: root.packed(10)
        readonly property vector4d v11: root.packed(11)
    }

    Component.onCompleted: root.aim()
}
