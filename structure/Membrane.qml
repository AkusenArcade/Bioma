import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.cells
import qs.services

// One edge of one monitor. Tissues anchored to it share its length.
//
// `reserve_space`, `auto_hide` and `scale` govern every tissue and cell on this
// membrane, the dock included. Hiding a membrane hides everything on it.
//
// The surface is transparent and covers the whole edge, so its input mask is
// the union of the visible cell shapes and nothing else — otherwise the strip
// would swallow clicks meant for the windows underneath. The same union, minus
// the cells that ask not to be blurred, is what is handed to
// `ext-background-effect`: blur follows the declared shapes exactly, never the
// gaps between them, which is why no compositor layer rule is used.
//
// See PRD §4.1, §4.4, §6.6.
PanelWindow {
    id: root

    // Named for what it is rather than `modelData`: a membrane is instantiated
    // from a Variants over the membrane list, and that delegate's `modelData`
    // is the membrane's own configuration block.
    required property var screenItem
    required property string edge            // "top" | "bottom" | "left" | "right"
    property var tissuesConfig: []

    property bool reserveSpace: false
    property bool autoHide: false
    property string scaleStep: "normal"

    readonly property var metrics: Metrics.step(scaleStep)
    readonly property bool horizontal: edge === "top" || edge === "bottom"

    // Geometric rule, no exceptions: only horizontal edges may reserve.
    readonly property bool reserving: reserveSpace && horizontal && !autoHide

    screen: screenItem
    color: "transparent"

    // Named on the wayland side, so that `niri msg layers` and any compositor
    // rule can tell one Bioma surface from another.
    WlrLayershell.namespace: `bioma-membrane-${edge}`

    anchors {
        top: edge !== "bottom"
        bottom: edge !== "top"
        left: edge !== "right"
        right: edge !== "left"
    }

    // ---- Thickness ---------------------------------------------------------

    readonly property real tissueThickness: metrics.cellHeight + metrics.tissuePadding * 2

    // The strip the membrane actually occupies: the screen edge margin is a
    // frame, not a surface, but it is part of what the windows must not cover.
    readonly property real strip: metrics.marginEdge + tissueThickness

    // Where the compositor actually starts drawing windows, in this surface's
    // coordinates. It is not the edge of the reserved strip: niri insets its
    // windows by `gaps`, and by any `struts`, and an expansion hangs from the
    // line the windows really begin on — otherwise the panel floats a gap above
    // them and the alignment the eye checks is the one that is wrong.
    readonly property real windowInset: Niri.windowGap + Niri.strutFor(edge)
    readonly property real windowLine: {
        if (edge === "top" || edge === "left")
            return strip + windowInset;
        return (horizontal ? height : width) - strip - windowInset;
    }

    // When space is reserved it stays reserved even while a conditional cell
    // inside is invisible — the "slot" model, so windows never reflow. An
    // expansion never changes it either: expansions go over windows.
    exclusiveZone: reserving ? Math.round(strip) : 0

    // An expansion grows out of the strip and over the windows, so the surface
    // has to be large enough to hold it — and it holds that size for the whole
    // session rather than taking it when a cell opens and giving it back when
    // it closes.
    //
    // Resizing a layer surface is not free and it is not atomic: the window's
    // height changes on one frame and the compositor applies the new size on
    // another, and everything positioned from that height — the tissue on a
    // bottom membrane sits at `height - margin - thickness` — is drawn once at
    // the old size and once at the new. What the eye sees is the whole bar
    // appearing twice, one of them near the top of the screen, and every cell
    // losing its glass for that frame. Akusen saw both, 2026-09-22.
    //
    // A surface the size of the output costs a transparent buffer and nothing
    // else: it reserves only its strip, and outside its cells it catches no
    // pointer, because the input mask is built from the cells themselves.
    readonly property bool anyOpen: {
        for (const tissue of root.tissues)
            for (const cell of tissue.cells)
                if (cell.open)
                    return true;
        return false;
    }

    implicitHeight: horizontal ? (screen ? screen.height : strip) : 0
    implicitWidth: horizontal ? 0 : (screen ? screen.width : strip)

    // Keyboard focus is asked for by the cell that needs it, and by no other.
    //
    // A layer surface that declares on-demand keyboard interactivity is one a
    // compositor may focus, and under `focus-follows-mouse` niri focuses it the
    // moment the pointer crosses it — which takes the focus off the window. So
    // a membrane that asked for the keyboard because *something* was open made
    // the focused window flicker away and back as the pointer travelled over
    // its cells, and the window title cell, which exists on that focus, went
    // with it. Akusen saw the title; the rule is the focus.
    readonly property bool anyKeyboard: {
        for (const tissue of root.tissues)
            for (const cell of tissue.cells)
                if (cell.open && cell.wantsKeyboard)
                    return true;
        return false;
    }

    // And exclusively, while a cell is taking the keys rather than asking for
    // them — a combination being recorded has to reach the field, not the
    // window the pointer happens to be over.
    readonly property bool anyTaking: {
        for (const tissue of root.tissues)
            for (const cell of tissue.cells)
                if (cell.open && cell.takesKeyboard)
                    return true;
        return false;
    }

    WlrLayershell.keyboardFocus: anyTaking ? WlrKeyboardFocus.Exclusive
                               : anyKeyboard ? WlrKeyboardFocus.OnDemand
                               : WlrKeyboardFocus.None

    // ---- Auto-hide ---------------------------------------------------------

    // An auto-hidden membrane stays present as a surface: destroying it would
    // leave nothing at the edge to catch the pointer. The reveal zone is inside
    // the surface bounds — a bug Prisma already hit and fixed, and it comes back
    // identical here.
    readonly property int revealZone: 2

    // Not a binding, because it is assigned: the pointer reaching the edge
    // reveals the membrane, and the first such assignment would end a binding
    // on `autoHide` for good. That used to be hidden by the membrane being
    // rebuilt whenever the configuration changed; now that a membrane outlives
    // its configuration, switching auto-hide on has to be answered here or the
    // edge simply stays where it is.
    property bool revealed: !autoHide

    onAutoHideChanged: {
        if (!root.autoHide) {
            hideTimer.stop();
            root.revealed = true;
        } else if (membraneHover.hovered || root.anyOpen) {
            // Under the hand, or holding something open: it goes when the
            // hand leaves, not while it is being used.
            hideTimer.restart();
        } else {
            root.revealed = false;
        }
    }

    Item {
        id: revealStrip

        // Above the sliding content, or the pointer never reaches it: the
        // content fills the surface and is declared after this.
        z: 10

        width: root.horizontal ? root.width : root.revealZone
        height: root.horizontal ? root.revealZone : root.height
        x: root.edge === "right" ? root.width - root.revealZone : 0
        y: root.edge === "bottom" ? root.height - root.revealZone : 0

        HoverHandler {
            onHoveredChanged: if (hovered) root.revealed = true
        }
    }

    // And once it is out, the whole band it occupies is claimed rather than
    // the two pixels that called it. The cells sit a frame margin above the
    // edge, so a pointer travelling from the edge up to them crosses ground
    // that belongs to nobody: the membrane stopped being hovered the instant
    // it appeared, and started hiding again under the hand that asked for it.
    Item {
        id: revealBand

        width: root.horizontal ? root.width : root.strip
        height: root.horizontal ? root.strip : root.height
        x: root.edge === "right" ? root.width - root.strip : 0
        y: root.edge === "bottom" ? root.height - root.strip : 0
    }

    HoverHandler {
        id: membraneHover
        onHoveredChanged: {
            if (hovered)
                hideTimer.stop();
            else if (root.autoHide)
                hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: Timing.autoHide
        onTriggered: if (!root.anyOpen) root.revealed = false
    }

    // A cell opened by its key on a hidden membrane brings the membrane out
    // with it. Left hidden, the panel was drawn — it hangs past the band, over
    // the windows — but the hidden membrane claims only the reveal strip, so
    // every press on the panel went to the window underneath (found
    // 2026-09-28). Closed, it goes again unless the hand is on it.
    onAnyOpenChanged: {
        if (!root.autoHide)
            return;
        if (root.anyOpen) {
            hideTimer.stop();
            root.revealed = true;
        } else if (!membraneHover.hovered) {
            hideTimer.restart();
        }
    }

    // ---- The halo ----------------------------------------------------------
    //
    // A membrane that reserves nothing lies over the windows, and its cells
    // were read against whatever a window drew under them. While it is out,
    // each of its tissues takes the light down around itself: a halo of the
    // palette's background, the tissue's own shape blurred outward, and the
    // window left clean where there is no cell. A veil across the whole edge
    // was tried first and dimmed the window along all of it, cells or not
    // (Akusen, 2026-09-28). The background rather than black, so a light
    // palette gets a light halo, and the animated role, so it retints with
    // the rest. It darkens, it does not glow; it takes no pointer, because the
    // input mask is built from the cells, and it is not blurred, because blur
    // is declared for the cells alone.
    readonly property bool overWindows: !root.reserving
    readonly property real haloOpacity: Math.max(0, Math.min(1, Config.get("scrim.opacity", 0.85)))
    readonly property real haloReach: Math.max(0, Config.get("scrim.reach", 32)) * root.metrics.factor

    // The whole content slides out; nothing on the membrane has a hiding rule
    // of its own.
    Item {
        id: content
        anchors.fill: parent

        readonly property real hiddenOffset: root.strip - root.revealZone
        transform: Translate {
            id: slide

            x: root.horizontal ? 0 : (root.revealed ? 0 : (root.edge === "left" ? -content.hiddenOffset : content.hiddenOffset))
            y: !root.horizontal ? 0 : (root.revealed ? 0 : (root.edge === "top" ? -content.hiddenOffset : content.hiddenOffset))

            Behavior on x { NumberAnimation { duration: Timing.open; easing.type: Easing.InOutQuad } }
            Behavior on y { NumberAnimation { duration: Timing.open; easing.type: Easing.InOutQuad } }

            // A region bound to an item follows the item and not a transform
            // on its ancestors, so the regions read while the content was
            // still sliding kept that offset: on an auto-hiding membrane, an
            // opened cell's panel took no press where it was drawn (found
            // 2026-09-28). Once the slide has come to rest they are read
            // again, from where the shapes really are.
            onXChanged: if (slide.x === 0 && root.revealed) root.refreshRegions(true)
            onYChanged: if (slide.y === 0 && root.revealed) root.refreshRegions(true)
        }

        // Over the tissues' **places**, not over the list: a Repeater given a
        // new array rebuilds every delegate, and a tissue rebuilt is every
        // cell in it rebuilt. Over the count it was only a band appearing or
        // disappearing that cost a rebuild — but every band after it moved
        // into the delegate before it, so removing the left band rebuilt the
        // right one, and the settings cell open in it closed under the press
        // that removed the band (Akusen, 2026-09-28). Each delegate is kept
        // for as long as its place is in the list, and reads its own entry
        // out of the configuration by that place.
        ListModel { id: places }

        // One halo per tissue, under the tissues and beside them rather than
        // inside them: a RectangularShadow among a tissue's own children took
        // the pointer away from every expansion hanging off that membrane —
        // the settings' categories stopped answering (Akusen, 2026-09-28) —
        // even while it drew nothing. Out here it follows each tissue's shape
        // and fades with the reveal rather than sliding with it, so the part
        // that reaches past the band never stays on screen after the band has
        // gone.
        Repeater {
            model: root.overWindows && root.haloOpacity > 0 ? root.tissues : []

            delegate: RectangularShadow {
                required property Item modelData

                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                visible: modelData.visible && opacity > 0
                radius: modelData.radius
                blur: root.haloReach
                spread: root.haloReach * 0.25
                color: Qt.alpha(Theme.background, root.haloOpacity)
                opacity: root.revealed ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: Timing.open; easing.type: Easing.InOutQuad }
                }
            }
        }

        Repeater {
            id: tissueRepeater
            model: places

            delegate: Tissue {
                id: tissue
                required property int index
                required property string place

                readonly property var modelData: root.entryAt(tissue.place)


                metrics: root.metrics
                cellsConfig: modelData.cells || []
                output: root.screenItem ? root.screenItem.name : ""
                edge: root.edge
                windowLine: root.windowLine
                opensAway: root.edge === "top" || root.edge === "left"
                orientation: modelData.orientation || (root.horizontal ? "horizontal" : "vertical")
                padding: modelData.padding !== undefined
                         ? Math.max(2, Math.min(12, modelData.padding)) * root.metrics.factor
                         : root.metrics.tissuePadding
                fillOpacity: modelData.opacity !== undefined ? modelData.opacity : Config.get("tissue.opacity", 0.5)

                anchorSide: root.anchorFor(index, modelData)
                slotLength: (modelData.percentage || 0) / 100 * root.usableLength

                x: root.horizontal ? root.offsetFor(tissue, index) : root.crossOffset
                y: root.horizontal ? root.crossOffset : root.offsetFor(tissue, index)

                onVisibleChanged: root.refreshRegions()
                onRevisionChanged: root.refreshRegions()
                // What the tissue could not fit takes no input and is not
                // blurred, so the regions follow the placement as well as the
                // revision — and they follow it from here rather than from a
                // bump inside the tissue, which would be the tissue asking
                // itself to recompute what it had just computed.
                onPlacementChanged: root.refreshRegions()
            }
        }
    }

    // A tissue's place: its anchor, and which of that anchor's tissues it is
    // — tissues of one anchor stack in declared order.
    function placesOf(list) {
        const seen = {};
        return list.map((entry, index) => {
            const anchor = root.anchorFor(index, entry, list.length);
            const nth = seen[anchor] || 0;
            seen[anchor] = nth + 1;
            return `${anchor}#${nth}`;
        });
    }

    function entryAt(place) {
        const at = root.placesOf(root.tissuesConfig).indexOf(place);
        return at >= 0 ? root.tissuesConfig[at] : ({});
    }

    // The model follows the configuration row by row: what left is removed,
    // what arrived is inserted, what stayed is moved to where it now is and
    // keeps its instance.
    property int placesRevision: 0

    function syncPlaces() {
        const wanted = root.placesOf(root.tissuesConfig);
        for (let i = places.count - 1; i >= 0; i--)
            if (wanted.indexOf(places.get(i).place) < 0)
                places.remove(i);
        for (let i = 0; i < wanted.length; i++) {
            let at = -1;
            for (let j = i; j < places.count; j++)
                if (places.get(j).place === wanted[i]) {
                    at = j;
                    break;
                }
            if (at < 0)
                places.insert(i, { "place": wanted[i] });
            else if (at !== i)
                places.move(at, i, 1);
        }
        root.placesRevision++;
    }


    readonly property list<Item> tissues: {
        root.placesRevision;
        const out = [];
        for (let i = 0; i < tissueRepeater.count; i++) {
            const item = tissueRepeater.itemAt(i);
            if (item)
                out.push(item);
        }
        return out;
    }

    // ---- Placement ---------------------------------------------------------

    readonly property real membraneLength: horizontal ? width : height
    readonly property real usableLength: Math.max(0, membraneLength - metrics.marginEdge * 2)

    // The distance from the screen edge. The edge margin is a thin frame: the
    // tissue never touches the screen edge, and an expansion grows away from it
    // into the screen.
    readonly property real crossOffset: {
        if (edge === "top" || edge === "left")
            return metrics.marginEdge;
        return (horizontal ? height : width) - metrics.marginEdge - tissueThickness;
    }

    // Growth moves away from the anchor, so the anchor has to be known. The
    // configuration declares `growth`; where the tissue sits is derived from
    // its place in the list, which is what the three-tissue default means when
    // it reads left, centre, right. An explicit `anchor` overrides it.
    function anchorFor(index, config, count) {
        if (config.anchor)
            return config.anchor;
        if (config.growth === "symmetric")
            return "centre";
        if (index === 0)
            return "start";
        if (index === (count !== undefined ? count : tissuesConfig.length) - 1)
            return "end";
        return "centre";
    }

    // Tissues of the same anchor stack in declared order; the centred ones are
    // centred as a group. Collision is impossible as long as the percentages
    // hold, and when they do not the group is pushed inside the free span
    // rather than allowed to overlap.
    function offsetFor(tissue, index) {
        const margin = metrics.marginEdge;
        // The margin is measured to the **cell**, not to the band around it, so
        // the outermost cell on a membrane lines up with the edge of the
        // windows the compositor draws. The tissue's own padding therefore
        // hangs outside it.
        const outer = Math.max(0, margin - tissue.padding);
        let startRun = 0;
        let endRun = 0;
        let centreTotal = 0;
        let centreBefore = 0;

        // Every length here is the tissue's **animated** size, not the value it
        // is heading for. Placement then follows the growth frame by frame: a
        // centred tissue widens around its own middle rather than snapping to
        // the centre its final width would have.
        for (let i = 0; i < tissues.length; i++) {
            const other = tissues[i];
            if (!other || !other.visible)
                continue;
            const side = other.anchorSide;
            const length = root.horizontal ? other.width : other.height;

            if (side === "start" && i < index)
                startRun += length + margin;
            else if (side === "end" && i > index)
                endRun += length + margin;

            if (side === "centre") {
                centreTotal += length + (centreTotal > 0 ? margin : 0);
                if (i < index)
                    centreBefore += length + margin;
            }
        }

        const own = root.horizontal ? tissue.width : tissue.height;
        const side = tissue.anchorSide;
        if (side === "start")
            return outer + startRun;
        if (side === "end")
            return membraneLength - outer - endRun - own;

        // Centred: the group is centred on the membrane, then clamped between
        // whatever the corner tissues occupy.
        let groupStart = (membraneLength - centreTotal) / 2;
        const leftLimit = margin + root.runLength("start");
        const rightLimit = membraneLength - margin - root.runLength("end");
        if (groupStart < leftLimit)
            groupStart = leftLimit;
        if (groupStart + centreTotal > rightLimit)
            groupStart = Math.max(leftLimit, rightLimit - centreTotal);
        return groupStart + centreBefore;
    }

    function runLength(side) {
        let total = 0;
        for (const tissue of tissues) {
            if (tissue && tissue.visible && tissue.anchorSide === side)
                total += (root.horizontal ? tissue.width : tissue.height) + metrics.marginEdge;
        }
        return total;
    }

    // Percentages are ceilings, not reservations, and must not exceed 100.
    function validate() {
        let total = 0;
        for (const entry of tissuesConfig)
            total += entry.percentage || 0;
        if (total > 100)
            console.warn(`Bioma: membrane ${edge} on ${screenItem ? screenItem.name : "?"} declares ${total}% of tissue — above 100, tissues will be clamped`);
        root.checkRoom();
    }

    // And a ceiling has to be high enough for what is under it. A band granted
    // less than its cells need at their narrowest does not break — the tissue
    // leaves out what it cannot fit — but what the person sees is cells
    // missing from their membrane with nothing said about it, so it is said
    // here, in the one unit that fixes it: the percentage to raise it to.
    property string lastShortfall: ""

    // Measured once the surface has one, and once the configuration has
    // settled: an output-sized surface is a few pixels wide for an instant
    // while it is built, and a membrane that says a workspaces cell needs a
    // hundred and thirty per cent of a seventy-pixel screen is the log crying
    // wolf.
    Timer {
        id: roomSettled
        interval: Timing.reflow + 80
        onTriggered: root.reportRoom()
    }

    function checkRoom() {
        if (root.usableLength > 0)
            roomSettled.restart();
    }

    function reportRoom() {
        if (root.usableLength <= 0)
            return;

        const short = [];
        for (let i = 0; i < tissuesConfig.length; i++) {
            const entry = tissuesConfig[i];
            const granted = (entry.percentage || 0) / 100 * root.usableLength;
            const needed = Registry.roomFor(entry.cells || [], root.metrics);
            if (needed > granted + 0.5)
                short.push(`tissue ${i + 1} holds ${(entry.cells || []).length} cells and needs `
                           + `${Math.ceil(needed / root.usableLength * 100)}% rather than `
                           + `${entry.percentage || 0}%`);
        }

        const said = short.join("; ");
        if (said === root.lastShortfall)
            return;
        root.lastShortfall = said;
        if (said.length > 0)
            console.warn(`Bioma: the ${root.edge} membrane on `
                         + `${screenItem ? screenItem.name : "this monitor"} is granted less `
                         + `than it was asked to hold — ${said}`);
    }

    onTissuesConfigChanged: {
        root.syncPlaces();
        validate();
    }
    onUsableLengthChanged: checkRoom()

    // ---- Blur and input ----------------------------------------------------

    property var maskRegion: null
    property var blurRegion: null

    // Until the first rebuild the mask has to be **empty**, not absent: a null
    // mask means the whole surface takes the pointer, and this surface is the
    // size of the output. A region with no item and no size claims nothing.
    Region { id: nothing }

    mask: maskRegion ? maskRegion : nothing
    BackgroundEffect.blurRegion: blurRegion

    // Where this surface sits on its output. A layer surface has no position of
    // its own as far as Qt is concerned — the compositor places it — so it is
    // derived from the edge it is anchored to and the size it has. Covering the
    // output, as it now always does, that offset is nothing; the arithmetic
    // stays because a membrane on an edge it does not fill is still a case the
    // engine has to answer, and because it is what makes the catcher's
    // coordinates true.
    readonly property real originX: edge === "right" ? (screen ? screen.width : 0) - width : 0
    readonly property real originY: edge === "bottom" ? (screen ? screen.height : 0) - height : 0

    // Everything on this membrane that takes input: the cells, and the panel of
    // whichever is open — as rectangles on the output, not as items. The
    // full-screen catcher subtracts these from its own region so that a press
    // on a cell never reaches it, and it lives on another surface: handed items,
    // it punched its holes wherever those items sat inside *this* window, which
    // for a bottom membrane is a screen's height away from the truth.
    function inputRects() {
        const out = [];
        for (const tissue of root.tissues) {
            if (!tissue || !tissue.visible)
                continue;
            for (const cell of tissue.cells) {
                if (!cell.placed)
                    continue;
                for (const shape of cell.claims()) {
                    const item = shape.item;
                    if (!item)
                        continue;
                    const here = item.mapToItem(null, 0, 0);
                    out.push({
                        "x": here.x + root.originX,
                        "y": here.y + root.originY,
                        "width": item.width,
                        "height": item.height,
                        "radius": shape.radius
                    });
                }
            }
        }
        return out;
    }

    // The offset above changes with the surface, so the catcher has to be told
    // when the surface changes size. It no longer does so for an expansion —
    // it is the size of the output from the start — but a monitor that changes
    // mode still moves every cell in the catcher's coordinates.
    onHeightChanged: root.refreshRegions()
    onWidthChanged: root.refreshRegions()

    // `reread`: the shapes did not change, but where they are did, in a way the
    // leaves cannot see (a transform) — every leaf is let go and bound again,
    // which is what makes a leaf read its item's geometry.
    function refreshRegions(reread) {
        if (reread === true) {
            Regions.bind(root.maskRegion, []);
            Regions.bind(root.blurRegion, []);
        }

        const input = [];
        const blur = [];

        for (const tissue of root.tissues) {
            if (!tissue || !tissue.visible)
                continue;
            for (const cell of tissue.cells) {
                if (!cell.placed)
                    continue;
                for (const shape of cell.claims())
                    input.push(shape);
                if (!cell.blur)
                    continue;
                for (const shape of cell.shapes())
                    blur.push(shape);
            }
        }

        // Hidden, the only thing that may catch the pointer is the reveal
        // zone — and **nothing at all is blurred**. The cells are still there,
        // slid out of view by a transform on their container, and a region
        // bound to an item does not follow that transform: what stayed behind
        // was the silhouette of a membrane that had gone, blurring the window
        // underneath it.
        if (root.autoHide && !root.revealed) {
            input.splice(0, input.length, { "item": revealStrip, "radius": 0 });
            blur.length = 0;
        } else if (root.autoHide) {
            input.push({ "item": revealBand, "radius": 0 });
        }

        root.maskRegion = Regions.rebind(root, root.maskRegion, input);
        root.blurRegion = Regions.rebind(root, root.blurRegion, blur);

        // The catcher builds its own region out of these.
        Focus.bump();
    }

    onRevealedChanged: refreshRegions()

    // niri keeps the blur region it had when the region shrinks while the
    // overview is opening: the window title leaves as the overview takes the
    // focus, the region without it is sent and committed — verified in the
    // protocol trace — and its glass stays on the backdrop until the region
    // is sent again. Seen on the laptop only, 2026-10-02. So once niri has
    // settled, every membrane declares its regions once more.
    Connections {
        target: Niri
        function onOverviewOpenChanged() {
            overviewSettled.restart();
        }
    }

    Timer {
        id: overviewSettled
        interval: Timing.overviewSettle
        onTriggered: root.refreshRegions(true)
    }

    Component.onCompleted: {
        root.syncPlaces();
        Focus.register(root);
        refreshRegions();
    }

    Component.onDestruction: Focus.unregister(root)
}
