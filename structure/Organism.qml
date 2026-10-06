import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.organisms

// One organism: a read-only surface placed on the desktop.
//
// It is not a cell. A cell speaks when something happens and hangs from a
// membrane; an organism is there because it was put there to be looked at,
// and hangs from nothing. So it has no contracted state, no thread and no
// input — it is a glass panel with the rim, without the shadow that would lift
// it off the wallpaper, born in place by growing from its own centre.
//
// Its size is its template — so many units of the grid across and down
// (`Organisms.template`) — and it sits on the grid at a point written as
// `col` and `row`. What it shows is the organism's own file, found by type in
// `organisms/Organisms.qml`. That file is an Item laid out in whatever room
// the template leaves it and, if its presence is conditional, a `present`
// property: media leaves when nothing
// is loaded, a note when its file cannot be read. Absent, it is still placed:
// while arranging it comes up in its blank form — the body draws itself empty,
// saying why, whenever its `present` is false — so the hand has something to
// take (Akusen, 2026-10-05: a media organism added with nothing playing was
// nowhere to be dragged).
//
// See docs/design/ORGANISMS.md.
Item {
    id: root

    // The block from the configuration: type, monitor, col, row, size and
    // the organism's own options.
    property var entry: ({})

    // Its place in the whole list, which is what a drop writes back to, and
    // the surface that carries it — the one that knows what to snap to.
    property int place: -1
    property var surface: null

    // Being placed: lifted above the windows with the rest, outlined, and
    // free to be dragged.
    property bool arranging: false

    // Whether it belongs on this surface's screen. Every surface keeps one of
    // these for every organism and shows only its own: carried to another
    // screen, an organism leaves this one and arrives on that one, and
    // nothing is destroyed under the hand that let it go.
    property bool here: true

    // The density it is drawn at: its own `size` if it says one, else the
    // membranes'.
    property var baseMetrics: Metrics.step("normal")
    readonly property var metrics: root.entry.size ? Metrics.step(root.entry.size) : root.baseMetrics

    readonly property string type: root.entry.type || ""
    readonly property string source: Organisms.fileFor(root.type)

    readonly property Item body: loader.item
    readonly property bool retiring: Arranging.retiring.indexOf(root.place) >= 0
    readonly property bool present: root.here && !root.retiring && root.body !== null
                                    && (root.arranging || root.body.present === undefined || root.body.present === true)

    // ---- Size and place ---------------------------------------------------------

    // An organism whose content is its surface — the media organism's cover,
    // edge to edge — says `bleeds` and is given no padding; the rim is then
    // drawn over its content rather than under it.
    readonly property bool bleeds: root.body !== null && root.body.bleeds === true
    readonly property real padding: root.bleeds ? 0 : 20 * root.metrics.factor

    // The screen it is on, for content that asks whether the desktop there is
    // showing at all.
    readonly property string output: root.surface && root.surface.screenItem ? root.surface.screenItem.name : ""
    // The template: so many units across and down, a gap between each two.
    readonly property var template: Organisms.template(root.entry)
    readonly property real unit: root.metrics.organismUnit
    readonly property real span: root.metrics.gap
    readonly property real targetWidth: root.body ? root.template[0] * root.unit + (root.template[0] - 1) * root.span : 0
    readonly property real targetHeight: root.body ? root.template[1] * root.unit + (root.template[1] - 1) * root.span : 0

    // What it covers on the grid: the panel and half the grid's gap around
    // it, so two organisms on neighbouring squares stand one gap apart and
    // every edge falls on a line. At the membranes' step that is whole
    // modules; an organism with a SIZE of its own covers what it covers.
    readonly property real gridGap: root.surface ? root.surface.metrics.gap : root.span
    readonly property real coverWidth: root.targetWidth + root.gridGap
    readonly property real coverHeight: root.targetHeight + root.gridGap

    // Its grid point. A block written before the grid — or just added, with
    // no point yet — has its centre as fractions of the free area instead,
    // and goes to the grid point nearest to it until it is next dropped.
    readonly property point gridPoint: {
        const surface = root.surface;
        const entry = root.entry;
        if (!surface)
            return Qt.point(0, 0);
        const p = entry.col !== undefined && entry.row !== undefined
            ? surface.kept(root.coverWidth, root.coverHeight, entry.col, entry.row)
            : surface.point(root.coverWidth, root.coverHeight,
                            surface.free.x + (entry.x ?? 0.5) * surface.free.width - root.coverWidth / 2,
                            surface.free.y + (entry.y ?? 0.5) * surface.free.height - root.coverHeight / 2);
        return Qt.point(p.col, p.row);
    }

    readonly property point restCorner: root.surface ? root.surface.corner(root.gridPoint.x, root.gridPoint.y)
                                                     : Qt.point(0, 0)
    readonly property real restX: root.restCorner.x + root.coverWidth / 2
    readonly property real restY: root.restCorner.y + root.coverHeight / 2

    // While it is held it is where the hand puts it, freely, and the surface
    // shows the squares it would land on; let go, the list is told and it
    // slides from the hand onto them.
    property bool held: false
    property real heldX: 0
    property real heldY: 0

    property real driftX: 0
    property real driftY: 0

    readonly property real centreX: root.held ? root.heldX : root.restX + root.driftX
    readonly property real centreY: root.held ? root.heldY : root.restY + root.driftY

    ParallelAnimation {
        id: settle
        NumberAnimation { target: root; property: "driftX"; to: 0; duration: Timing.reflow; easing.type: Easing.BezierSpline; easing.bezierCurve: Timing.easeOpenFlat }
        NumberAnimation { target: root; property: "driftY"; to: 0; duration: Timing.reflow; easing.type: Easing.BezierSpline; easing.bezierCurve: Timing.easeOpenFlat }
    }

    // ---- Arriving and leaving -----------------------------------------------------

    // It grows when it has something to show and the shape has somewhere to
    // be; it leaves content first, then shape — the shell's one way of going.
    property bool wanted: false
    property real growth: 0

    onPresentChanged: root.decide()
    onTargetWidthChanged: root.decide()

    function decide() {
        if (root.present && root.targetWidth > 0) {
            parting.stop();
            root.wanted = true;
        } else if (root.wanted) {
            // Content out first; the shape follows once it has gone.
            parting.restart();
        }
    }

    Timer {
        id: parting
        interval: Timing.contentFade
        onTriggered: root.wanted = false
    }

    readonly property bool leaving: parting.running

    states: State {
        name: "here"
        when: root.wanted
        PropertyChanges { root.growth: 1 }
    }

    transitions: [
        Transition {
            to: "here"
            NumberAnimation {
                property: "growth"
                duration: Timing.open
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Timing.easeOpenFlat
            }
        },
        Transition {
            from: "here"
            NumberAnimation {
                property: "growth"
                duration: Timing.close
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Timing.easeClose
            }
        }
    ]

    // ---- The surface --------------------------------------------------------------

    Panel {
        id: panel

        metrics: root.metrics
        shadowed: false
        padding: root.padding
        fixedWidth: root.targetWidth
        fixedHeight: root.targetHeight

        anchorX: root.centreX - root.targetWidth / 2
        anchorY: root.centreY - root.targetHeight / 2
        nodeX: root.centreX
        nodeY: root.centreY
        growth: root.growth
        contentReady: root.wanted && !root.leaving && root.growth > 0.999

        Loader {
            id: loader

            // The body is given the room the template leaves, not asked for
            // its size.
            anchors.fill: parent

            // Not loaded on a screen it does not belong to — once it has
            // finished leaving it.
            active: root.here || root.growth > 0
            source: root.source.length > 0 ? Qt.resolvedUrl("../organisms/" + root.source) : ""

            onLoaded: {
                item.metrics = Qt.binding(() => root.metrics);
                item.entry = Qt.binding(() => root.entry);
                if (item.organism !== undefined)
                    item.organism = root;
                root.decide();
            }
        }
    }

    // The rim over content that bleeds: the cover reaches the edge, and the
    // light on the top edge is still the surface's.
    Rim {
        visible: root.bleeds && panel.visible
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        radius: panel.radius
    }

    // ---- Being placed -------------------------------------------------------------------

    // Outlined while the mode lasts, a little outside the panel so the rim
    // stays the rim: dashed, because it marks a thing that can move rather
    // than a surface. Brighter under the pointer and in the hand.
    readonly property real ring: 8 * root.metrics.factor
    readonly property bool lit: grab.containsMouse || root.held

    DashedSlot {
        visible: root.arranging && panel.visible
        x: root.centreX - root.targetWidth / 2 - root.ring
        y: root.centreY - root.targetHeight / 2 - root.ring
        width: root.targetWidth + root.ring * 2
        height: root.targetHeight + root.ring * 2
        radius: panel.radius + root.ring
        colour: root.lit ? Theme.primary : Qt.alpha(Theme.primary, 0.55)
        dash: 8 * root.metrics.factor
        space: 6 * root.metrics.factor
    }

    // Its name and template, and where it is on the grid — column and row in
    // the squares as they are divided now, counted from one; where it would
    // land while it is in the hand. Inside its top-left corner, on a plate of
    // the background: above the panel, as it first was, the label of an
    // organism one unit wide ran into its neighbour's, and the gap of a
    // cluster is narrower than the line (2026-10-07).
    Rectangle {
        id: plate

        readonly property real inset: 10 * root.metrics.factor

        visible: root.arranging && panel.visible
        x: root.centreX - root.targetWidth / 2 + plate.inset
        y: root.centreY - root.targetHeight / 2 + plate.inset
        width: legend.implicitWidth + plate.inset * 2
        height: legend.implicitHeight + plate.inset * 1.4
        radius: Metrics.radiusFor(plate.height, root.metrics)
        color: Qt.alpha(Theme.background, 0.88)

        readonly property font face: Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontMeta,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
        }))

        Column {
            id: legend

            anchors.centerIn: parent
            spacing: 3 * root.metrics.factor

            Text {
                text: `${(Organisms.names[root.type] || root.type).toUpperCase()} · ${root.template[0]} × ${root.template[1]}`
                color: Theme.primary
                font: plate.face
            }

            Text {
                readonly property point at: root.held ? root.landingPoint : root.gridPoint

                function counted(modules) {
                    const squares = Math.round(modules * Arranging.grid * 1000) / 1000;
                    return Number.isInteger(squares) ? String(squares + 1) : (squares + 1).toFixed(1);
                }

                text: `COL ${counted(at.x)} · ROW ${counted(at.y)}`
                color: Theme.textMuted
                font: plate.face
            }
        }
    }

    // The hand. Where the press lands inside the panel is kept, so the panel
    // does not jump to centre itself under the pointer.
    MouseArea {
        id: grab

        enabled: root.arranging && panel.visible
        x: root.centreX - root.targetWidth / 2
        y: root.centreY - root.targetHeight / 2
        width: root.targetWidth
        height: root.targetHeight
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real offsetX: 0
        property real offsetY: 0

        onPressed: mouse => {
            settle.stop();
            grab.offsetX = mouse.x - root.targetWidth / 2;
            grab.offsetY = mouse.y - root.targetHeight / 2;
            root.heldX = root.centreX;
            root.heldY = root.centreY;
            root.driftX = 0;
            root.driftY = 0;
            root.held = true;
            root.land();
        }

        onPositionChanged: mouse => {
            if (!root.held || !root.surface)
                return;
            const at = grab.mapToItem(root, mouse.x, mouse.y);
            root.heldX = at.x - grab.offsetX;
            root.heldY = at.y - grab.offsetY;
            root.land();
        }

        onReleased: mouse => {
            if (!root.held)
                return;
            const at = grab.mapToItem(root, mouse.x, mouse.y);
            root.drop(at.x, at.y);
        }

        onCanceled: root.drop(NaN, NaN)
    }

    // The grid point the hand is over, and the squares it would cover shown
    // on the surface.
    property point landingPoint: Qt.point(0, 0)

    function land() {
        const surface = root.surface;
        if (!surface)
            return;
        // Carried off this screen, it lands on the other one, not here.
        if (root.heldX < 0 || root.heldY < 0 || root.heldX > surface.width || root.heldY > surface.height) {
            surface.landing = Qt.rect(0, 0, 0, 0);
            return;
        }
        const p = surface.point(root.coverWidth, root.coverHeight,
                                root.heldX - root.coverWidth / 2, root.heldY - root.coverHeight / 2);
        root.landingPoint = Qt.point(p.col, p.row);
        const corner = surface.corner(p.col, p.row);
        surface.landing = Qt.rect(corner.x + root.gridGap / 2, corner.y + root.gridGap / 2,
                                  root.targetWidth, root.targetHeight);
        surface.landingRadius = panel.radius;
    }

    // Let go. The screen under the pointer is where it now lives — its own,
    // or another one it was carried to — and it is written as the grid point
    // of that screen nearest to where it was let go, wholly inside its grid.
    function drop(pointerX, pointerY) {
        const surface = root.surface;
        let target = surface;
        let cx = root.heldX;
        let cy = root.heldY;

        if (surface && !isNaN(pointerX)) {
            const screen = surface.screenItem;
            const there = Arranging.surfaceAt(screen.x + pointerX, screen.y + pointerY);
            if (there && there !== surface) {
                target = there;
                cx += screen.x - there.screenItem.x;
                cy += screen.y - there.screenItem.y;
            }
        }

        if (surface)
            surface.landing = Qt.rect(0, 0, 0, 0);
        if (!target) {
            root.held = false;
            return;
        }

        const cover = root.targetWidth + target.metrics.gap;
        const coverDown = root.targetHeight + target.metrics.gap;
        const p = target.point(cover, coverDown, cx - cover / 2, cy - coverDown / 2);
        const place = root.place;
        const monitor = target.screenItem.name;

        // Written once the release has been handled, not inside it. Carried to
        // another screen, the last organism of this one takes its delegate
        // with it, and a MouseArea destroyed inside its own release left the
        // shell deaf to the next drag on any screen (2026-10-04). Held until
        // then, so it does not flick back to where it was for a frame.
        //
        // Carried to another screen, it stays held here: it leaves this one
        // from where it was let go, rather than from where its new place
        // would be on a screen it no longer belongs to.
        //
        // Staying, it slides from where it was let go onto its squares: the
        // distance is taken once the list has its new point, and run out.
        const away = target !== surface;
        Qt.callLater(() => {
            Arranging.place(place, monitor, p.col, p.row);
            if (away)
                return;
            root.driftX = root.heldX - root.restX;
            root.driftY = root.heldY - root.restY;
            root.held = false;
            settle.restart();
        });
    }

    onHereChanged: if (root.here) root.held = false

    // The shape the blur follows: the panel itself, which grows and shrinks
    // with the organism, so the glass is always exactly what is drawn.
    function shapes() {
        return panel.visible ? [{ "item": panel, "radius": panel.radius }] : [];
    }

    readonly property bool visibleShape: panel.visible

    Component.onCompleted: if (root.here && root.source.length === 0 && root.type.length > 0)
        console.warn("Organism: no organism of type", root.type);
}
