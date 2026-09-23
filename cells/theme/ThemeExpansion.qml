import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.core
import qs.components
import qs.services

// The theme, opened: the wallpaper carousel, and under it where the palette
// comes from and which one it is.
//
// There is no preview and no "apply". Choosing retints the shell while you
// watch it — the colour singleton is what makes that possible, and the shell
// itself is the only honest preview: a swatch panel shows a palette on one
// surface, and a palette is a relation between all of them.
//
// Two capsules rather than one, joined by a thread: the source and the result
// are two different questions — *where it comes from* and *which one* — and the
// thread says which is first. The dropdown is always in the same place and only
// changes what it lists: matugen's calculation methods, or the names of Bioma's
// own palettes.
//
// Under them, DESKTOP: the desktop's icon theme and cursor, which are not the
// palette but are the same question — how the desktop looks — and belong where
// that question is asked (Akusen, 2026-09-23). See services/Looks.qml.
//
// Beside the dropdown, APPS calls up the applications the palette is carried to
// outside the shell — niri, the toolkits, the terminals (services/Templates.qml).
// It is asked for rather than always there: it is a setting made once, not a
// choice made every time the theme changes, and it opens where the dropdown's
// list opens, so the two take turns.
//
// See docs/design/CELLS.md §07.
Item {
    id: root

    // The cell this grew out of, for its cascade and its metrics.
    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // Which way the cell opened. A composition is ordered from the cell
    // outwards — the shape the cell's own thread lands on comes first — so on a
    // membrane at the bottom of the screen the order is upside down: the
    // carousel sits against the cell and the capsules go beyond it. Everything
    // below is written once and reads this.
    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    readonly property real carouselWidth: 560 * factor
    readonly property real carouselHeight: 160 * factor
    readonly property real tileWidth: 320 * factor
    readonly property real tileHeight: 140 * factor
    readonly property real neighbourWidth: 100 * factor
    readonly property real tilePitch: 10 * factor
    readonly property real tileRadius: Metrics.shaped(10 * factor)

    readonly property real capsuleWidth: 268 * factor
    readonly property real capsuleHeight: 96 * factor
    readonly property real gap: metrics.gap

    // What the capsules hold, stated here because the list the dropdown opens
    // has to be born from the dropdown's own bottom edge — and that edge is
    // arithmetic rather than a measurement taken off an item which, at the
    // moment the list starts, is still growing.
    readonly property real chipSize: 20 * factor
    readonly property real chipPitch: 5 * factor
    readonly property real stackSpacing: 12 * factor
    readonly property real dropdownHeight: 30 * factor
    readonly property real stackHeight: chipSize + stackSpacing + dropdownHeight
    readonly property real stackTop: (capsuleHeight - stackHeight) / 2
    readonly property real dropdownTop: stackTop + chipSize + stackSpacing
    readonly property real dropdownBottom: dropdownTop + dropdownHeight

    // Where each block sits in the composition. The near edge is the one facing
    // the cell, and it is where the thread from the cell lands.
    // A little taller than the two above it: under the icons there is room
    // kept for one line, so the capsule does not change size when it appears.
    readonly property real desktopHeight: 108 * factor
    readonly property real carouselY: upward ? desktopHeight + gap + capsuleHeight + gap : 0
    readonly property real capsuleY: upward ? desktopHeight + gap : carouselHeight + gap
    readonly property real desktopY: upward ? 0 : capsuleY + capsuleHeight + gap
    readonly property real carouselNear: upward ? carouselY + carouselHeight : carouselY
    readonly property real capsuleNear: upward ? capsuleY + capsuleHeight : capsuleY

    // The dropdown and APPS share a row centred in the palette capsule. Both
    // widths are the controls' own — text and padding — which do not change
    // while the capsule grows, so each control's centre is arithmetic.
    readonly property real controlSpacing: 8 * factor
    readonly property real paletteCentreX: capsuleWidth + gap + capsuleWidth / 2
    readonly property real controlsWidth: dropdown.width + controlSpacing + appsButton.width
    readonly property real appsButtonCentreX: paletteCentreX + controlsWidth / 2 - appsButton.width / 2

    // Orbitron 12 for the dropdown is CELLS.md §07's own figure, and the
    // controls beside it are the same voice at the same size: a segmented
    // control and a dropdown are one family, and two sizes inside one capsule
    // read as a mistake.
    readonly property int fontControl: Math.round(12 * factor)

    implicitWidth: carouselWidth
    implicitHeight: carouselHeight + gap + capsuleHeight + gap + desktopHeight

    width: implicitWidth
    height: implicitHeight

    // ---- What the two capsules are about ------------------------------------

    readonly property bool fromWallpaper: Theme.source === "matugen"

    // matugen's own scheme names. The method is a user choice and not a
    // constant: content and tonal spot from one wallpaper give two different
    // desktops, and hiding that would imply the derived palette is the only
    // one possible.
    readonly property var schemes: [
        { "key": "scheme-content", "label": "Content" },
        { "key": "scheme-expressive", "label": "Expressive" },
        { "key": "scheme-fidelity", "label": "Fidelity" },
        { "key": "scheme-fruit-salad", "label": "Fruit salad" },
        { "key": "scheme-monochrome", "label": "Monochrome" },
        { "key": "scheme-neutral", "label": "Neutral" },
        { "key": "scheme-rainbow", "label": "Rainbow" },
        { "key": "scheme-smart", "label": "Smart" },
        { "key": "scheme-tonal-spot", "label": "Tonal spot" },
        { "key": "scheme-vibrant", "label": "Vibrant" }
    ]

    // Bioma's palettes are data files, one per theme, so this list is whatever
    // is in the folder and never a list in the shell.
    readonly property var presets: Theme.palettes.map(palette => ({
        "key": palette.file,
        "label": palette.name
    }))

    readonly property var options: root.fromWallpaper ? root.schemes : root.presets
    readonly property string chosen: root.fromWallpaper ? Matugen.scheme : Theme.manualPalette

    readonly property string chosenLabel: {
        for (const option of root.options)
            if (option.key === root.chosen)
                return option.label;
        return root.chosen;
    }

    function choose(key) {
        Config.set(root.fromWallpaper ? "theme.matugen.scheme" : "theme.palette", key);
        root.listing = "";
    }

    // ---- The cascade --------------------------------------------------------
    //
    // The carousel grows on the cell's own thread; then the threads under it,
    // then the two capsules, sixteen milliseconds apart. Each shape still grows
    // in `Timing.grow` — the opening figure is reached by tightening the
    // cascade, never by shortening a growth.

    property real cascade: 0

    function stage(index) {
        return Timing.stage(root.cascade, index, 4);
    }

    readonly property real linkProgress: stage(0)
    readonly property real sourceProgress: stage(1)
    readonly property real paletteProgress: stage(2)
    readonly property real desktopProgress: stage(3)

    Connections {
        target: root.cell
        function onOpenChanged() {
            capsules.stop();
            capsules.to = root.cell.open ? 1 : 0;
            capsules.duration = root.cell.open ? Timing.open : Timing.close;
            // The opening curve run backwards is not a closing curve: it
            // starts fast and ends slow, so the shapes fell out of the
            // composition in the first fifty milliseconds and then crawled the
            // rest of the way. Closing takes the closing curve — it opens
            // calmly and closes quickly.
            capsules.easing.bezierCurve = root.cell.open ? Timing.easeOpenFlat
                                                     : Timing.easeClose;
            capsules.start();
            if (!root.cell.open) {
                root.listing = "";
                root.appsOpen = false;
            }
        }
    }

    NumberAnimation {
        id: capsules
        target: root
        property: "cascade"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    // A Loader sets its item's properties after the item is built, so the
    // cascade starts when the cell arrives rather than when this item does.
    onCellChanged: {
        if (root.cell && root.cell.open) {
            capsules.to = 1;
            capsules.restart();
        }
    }

    // ---- The carousel -------------------------------------------------------
    //
    // Stepping through the folder is a movement that answers a gesture, like
    // the segmented control's pill and the slider's travel — not an indicator,
    // so nothing is encoded in its rate. It is an event: the strip travels one
    // place at the transition timing and is still again.
    //
    // The strip is five places wide and clipped to the panel's inside, so the
    // two beyond the neighbours are what a step brings in. A place is as wide
    // as its distance from the centre says: the wallpaper arriving grows from
    // the neighbour's width to the middle one's while the one leaving shrinks,
    // which is the movement itself rather than a slide with a swap at the end.

    readonly property int reach: 2
    readonly property real stripWidth: carouselWidth - 20 * factor

    property real travel: 0

    NumberAnimation {
        id: glide
        target: root
        property: "travel"
        to: 0
        duration: Timing.transition
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    // The wallpaper changes first and the strip is then displaced by one place
    // in the opposite direction, so the first frame of the animation is what
    // was on screen before the step and the last is the truth.
    function slide(delta) {
        if (Wallpaper.entries.length < 2)
            return;
        glide.stop();
        Wallpaper.step(delta);
        root.travel = -delta;
        glide.start();
    }

    function closeness(place) {
        return Math.max(0, 1 - Math.abs(place));
    }

    function placeWidth(place) {
        return root.neighbourWidth + (root.tileWidth - root.neighbourWidth) * root.closeness(place);
    }

    // Every place's left edge, shifted so that the point the carousel is
    // centred on — which during a step falls between two places — lands in the
    // middle of the strip.
    readonly property var places: {
        const widths = [];
        for (let i = -root.reach; i <= root.reach; i++)
            widths.push(root.placeWidth(i - root.travel));

        const lefts = [];
        let x = 0;
        for (let k = 0; k < widths.length; k++) {
            lefts.push(x);
            x += widths[k] + root.tilePitch;
        }

        const centreOf = k => lefts[k] + widths[k] / 2;
        const base = Math.max(0, Math.min(widths.length - 1, root.travel + root.reach));
        const first = Math.floor(base);
        const second = Math.min(widths.length - 1, Math.ceil(base));
        const middle = centreOf(first) + (centreOf(second) - centreOf(first)) * (base - first);
        const shift = root.stripWidth / 2 - middle;

        return { "widths": widths, "lefts": lefts.map(left => left + shift) };
    }

    // Wallpapers are looked at inside shapes of their own: the current one at
    // full light in the centre, its neighbours half-seen at the sides. That is
    // what makes the carousel read as a strip that continues past the panel,
    // without a fade over the edges to fake it.
    component Tile: Item {
        id: tile

        property string image: ""
        property real corner: root.tileRadius
        // 1 in the middle, 0 at the sides: the lit border belongs to the
        // wallpaper being looked at, and it arrives with it.
        property real lit: 0

        // The width to decode at, which is not the width to draw at.
        property real decode: root.tileWidth

        visible: tile.image.length > 0

        // Asking for the picture and asking for a small copy of it to be made
        // are two different things, and the second one cannot happen inside a
        // binding — see `Wallpaper.thumbnail`.
        onImageChanged: Wallpaper.prepare(tile.image)
        Component.onCompleted: Wallpaper.prepare(tile.image)

        Image {
            id: picture
            anchors.fill: parent
            source: tile.image.length > 0 ? `file://${Wallpaper.thumbnail(tile.image)}` : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            // Decoded once, at the widest a place ever gets — not at the width
            // it happens to have. Bound to the live width it is a different
            // decode on every frame of a step: nothing hits the image cache,
            // each frame starts an asynchronous load, and the picture blinks
            // through every one of them. The cost of the fixed size is one
            // decode per wallpaper at the middle place's size, and scaling a
            // decoded image down is free.
            sourceSize.width: Math.round(tile.decode * Screen.devicePixelRatio)
            // Qt 6 draws nothing for a mask to sample unless the source renders
            // itself: both halves carry their own layer.
            visible: false
            layer.enabled: true
        }

        Rectangle {
            id: shape
            anchors.fill: parent
            radius: tile.corner
            antialiasing: true
            visible: false
            layer.enabled: true
        }

        OpacityMask {
            anchors.fill: parent
            source: picture
            maskSource: shape
        }

        // Only the current one is lit: the rim is the light on the surface the
        // user is looking at.
        Rim {
            anchors.fill: parent
            radius: tile.corner
            opacity: tile.lit
            visible: tile.lit > 0
        }
    }

    Panel {
        id: carousel

        metrics: root.metrics
        targetWidth: root.carouselWidth
        targetHeight: root.carouselHeight
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        // Born from the node of the cell's own thread, which lands on the edge
        // facing the cell, under the middle of it.
        anchorX: 0
        anchorY: root.carouselY
        nodeX: root.width - (root.cell ? root.cell.width / 2 : 0)
        nodeY: root.carouselNear

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                if (event.angleDelta.y > 0)
                    root.slide(-1);
                else if (event.angleDelta.y < 0)
                    root.slide(1);
            }
        }

        // Clipped here and not on the panel: the strip has to run past the
        // inside edges, and the rim belongs to the panel, which is a different
        // item. Clipping a surface that carries the rim eats it.
        Item {
            anchors.centerIn: parent
            width: root.stripWidth
            height: root.tileHeight
            clip: true

            Repeater {
                model: root.reach * 2 + 1

                delegate: Tile {
                    id: place

                    required property int index

                    readonly property int offset: place.index - root.reach
                    readonly property real position: place.offset - root.travel

                    x: root.places.lefts[place.index]
                    y: 0
                    width: root.places.widths[place.index]
                    height: root.tileHeight

                    image: Wallpaper.neighbour(place.offset)
                    // Full light in the middle, the shipped 0.40 at the sides,
                    // and everything between while it travels.
                    opacity: 0.40 + 0.60 * root.closeness(place.position)
                    lit: root.closeness(place.position)

                    // The two beyond the neighbours exist so a step has
                    // something to bring in; they are outside the strip and
                    // answer nothing.
                    TapHandler {
                        enabled: Math.abs(place.offset) === 1 && Math.abs(place.position) > 0.5
                        onTapped: root.slide(place.offset)
                    }
                }
            }
        }

        // An empty folder is not a broken cell: it says where it looked.
        Text {
            anchors.centerIn: parent
            visible: Wallpaper.entries.length === 0
            text: `No images in ${Wallpaper.folder}`
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
        }
    }

    // The carousel hangs the source capsule off its own edge, at that capsule's
    // centre line — the thread is computed from both shapes, never placed.
    // Both threads have their ends on the shapes they touch rather than on the
    // coordinates those shapes settle at. It is the same rule the design states
    // for the opening — a thread stays attached while a shape grows — and it is
    // the closing that shows what breaks without it: the shapes retract towards
    // the cell and a thread computed from resting coordinates stays behind,
    // hanging between two places where nothing is any more.
    Thread {
        id: descent

        // Not `top` and `bottom`: an Item declares those final, and shadowing
        // them costs a warning and the binding.
        readonly property real headY: root.upward ? source.y + source.height
                                                  : carousel.y + carousel.height
        readonly property real footY: root.upward ? carousel.y : source.y

        vertical: true
        progress: root.linkProgress
        width: implicitWidth
        height: Math.max(0, descent.footY - descent.headY)
        x: Math.max(source.x, Math.min(source.x + source.width, root.capsuleWidth / 2)) - width / 2
        y: descent.headY
    }

    Thread {
        id: crossing

        readonly property real from: source.x + source.width

        vertical: false
        progress: root.linkProgress
        width: Math.max(0, palette.x - crossing.from)
        height: implicitHeight
        x: crossing.from
        y: Math.max(source.y, Math.min(source.y + source.height,
                                       root.capsuleY + root.capsuleHeight / 2)) - height / 2
    }

    // ---- Source -------------------------------------------------------------

    Panel {
        id: source

        metrics: root.metrics
        radius: Metrics.radiusFor(root.capsuleHeight, root.metrics)
        padding: 14 * root.factor
        targetWidth: root.capsuleWidth
        targetHeight: root.capsuleHeight
        growth: root.sourceProgress
        contentReady: root.sourceProgress > 0.999

        // Born from the node where the vertical thread meets its cap — on the
        // carousel's edge as it is, not as it will be.
        anchorX: 0
        anchorY: root.capsuleY
        nodeX: Math.max(carousel.x, Math.min(carousel.x + carousel.width, root.capsuleWidth / 2))
        nodeY: root.upward ? carousel.y : carousel.y + carousel.height

        Column {
            anchors.centerIn: parent
            spacing: root.stackSpacing

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SOURCE"
                color: Theme.text
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.fontControl,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.fontControl, Typography.labelTracking)
                })
            }

            Segmented {
                anchors.horizontalCenter: parent.horizontalCenter
                metrics: root.metrics
                fontSize: root.fontControl
                options: [
                    { "key": "matugen", "label": "matugen" },
                    { "key": "manual", "label": "Bioma" }
                ]
                current: Theme.source
                onChose: key => {
                    Config.set("theme.source", key);
                    root.listing = "";
                }
            }
        }
    }

    // ---- What comes out of it ----------------------------------------------

    Panel {
        id: palette

        metrics: root.metrics
        radius: Metrics.radiusFor(root.capsuleHeight, root.metrics)
        padding: 14 * root.factor
        targetWidth: root.capsuleWidth
        targetHeight: root.capsuleHeight
        growth: root.paletteProgress
        contentReady: root.paletteProgress > 0.999

        // Born from the far node of the horizontal thread, which rides on the
        // source capsule's edge.
        anchorX: root.capsuleWidth + root.gap
        anchorY: root.capsuleY
        nodeX: source.x + source.width
        nodeY: Math.max(source.y, Math.min(source.y + source.height,
                                           root.capsuleY + root.capsuleHeight / 2))

        Column {
            anchors.centerIn: parent
            spacing: root.stackSpacing

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.chipPitch

                Repeater {
                    model: Theme.targetRoles

                    delegate: Rectangle {
                        id: chip

                        required property var modelData
                        required property int index

                        width: root.chipSize
                        height: width
                        radius: Metrics.shaped(5 * root.factor)
                        antialiasing: true
                        color: chip.modelData

                        // The same replacement the contracted cell makes, at
                        // the same rate: it is the same seven roles.
                        Behavior on color {
                            SequentialAnimation {
                                PauseAnimation { duration: chip.index * Timing.stagger }
                                ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            // One place to learn: the dropdown never moves and never changes
            // shape, only what it lists.
            Row {
                id: controls

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.controlSpacing

                Item {
                    id: dropdown

                    width: chosenText.width + 12 * root.factor * 2 + 7 * root.factor + chevron.width
                    height: root.dropdownHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        color: "transparent"
                        border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                        border.color: Theme.line
                        antialiasing: true
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 7 * root.factor

                        Text {
                            id: chosenText
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.chosenLabel
                            color: Theme.text
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.fontControl,
                                "weight": Typography.weightLabel,
                                "letterSpacing": Typography.tracking(root.fontControl, 0.04)
                            })
                        }

                        Icon {
                            id: chevron
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron-down"
                            width: 9 * root.factor
                            height: width
                            colour: Qt.alpha(Theme.text, 0.6)
                        }
                    }

                    TapHandler { onTapped: root.toggleList("palette", dropdown) }
                }

                // Lit while its capsule is out: the same mark a lit pill makes
                // everywhere else in the shell.
                Item {
                    id: appsButton

                    width: appsText.implicitWidth + 12 * root.factor * 2
                    height: root.dropdownHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        color: root.appsOpen ? Qt.alpha(Theme.primary, 0.16) : "transparent"
                        border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                        border.color: root.appsOpen ? Theme.primary
                                    : appsHover.hovered ? Theme.text : Theme.line
                        antialiasing: true
                    }

                    Text {
                        id: appsText
                        anchors.centerIn: parent
                        text: "APPS"
                        color: root.appsOpen ? Theme.text : Theme.textMuted
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.fontControl,
                            "weight": Typography.weightLabel,
                            "letterSpacing": Typography.tracking(root.fontControl, Typography.labelTracking)
                        })
                    }

                    HoverHandler { id: appsHover }
                    TapHandler { onTapped: root.appsOpen = !root.appsOpen }
                }
            }
        }
    }

    // ---- How the desktop looks ---------------------------------------------
    //
    // The desktop's icon theme and cursor. It hangs from the source capsule on
    // the same line the source hangs from the carousel: one spine down the
    // composition, and the palette beside it.

    Thread {
        id: descentDesktop

        readonly property real headY: root.upward ? desktop.y + desktop.height
                                                  : source.y + source.height
        readonly property real footY: root.upward ? source.y : desktop.y

        vertical: true
        progress: root.linkProgress
        width: implicitWidth
        height: Math.max(0, descentDesktop.footY - descentDesktop.headY)
        x: root.capsuleWidth / 2 - width / 2
        y: descentDesktop.headY
    }

    // A dropdown in the desktop capsule: the same shape as the palette's, and
    // lit while its list is out.
    component LookDropdown: Item {
        id: drop

        property string label: ""
        property bool open: false
        signal pressed

        // At most this wide, so the two of them and the sizes fit the capsule;
        // a longer name is elided — the list shows it whole.
        readonly property real widest: 164 * root.factor

        width: Math.min(drop.widest,
                        dropText.implicitWidth + 12 * root.factor * 2 + 7 * root.factor + dropChevron.width)
        height: root.dropdownHeight

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            color: "transparent"
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: drop.open ? Theme.primary : dropHover.hovered ? Theme.text : Theme.line
            antialiasing: true
        }

        Row {
            anchors.centerIn: parent
            spacing: 7 * root.factor

            Text {
                id: dropText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, drop.widest - 12 * root.factor * 2
                                                - 7 * root.factor - dropChevron.width)
                text: drop.label
                elide: Text.ElideRight
                color: Theme.text
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.fontControl,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.fontControl, 0.04)
                })
            }

            Icon {
                id: dropChevron
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-down"
                width: 9 * root.factor
                height: width
                colour: Qt.alpha(Theme.text, 0.6)
            }
        }

        HoverHandler { id: dropHover }
        TapHandler { onTapped: drop.pressed() }
    }

    component LookLabel: Text {
        color: Theme.text
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.fontControl,
            "weight": Typography.weightLabel,
            "letterSpacing": Typography.tracking(root.fontControl, Typography.labelTracking)
        })
    }

    Panel {
        id: desktop

        metrics: root.metrics
        // A panel's radius, not a pill's: it is as wide as the carousel, and
        // a pill's caps would bring the labels at its corners too close to
        // the edge (Akusen, 2026-09-23).
        padding: 14 * root.factor
        targetWidth: root.carouselWidth
        targetHeight: root.desktopHeight
        growth: root.desktopProgress
        contentReady: root.desktopProgress > 0.999

        // Born from the node where its thread meets the source capsule's edge.
        anchorX: 0
        anchorY: root.desktopY
        nodeX: Math.max(source.x, Math.min(source.x + source.width, root.capsuleWidth / 2))
        nodeY: root.upward ? source.y : source.y + source.height

        Row {
            anchors.centerIn: parent
            spacing: 24 * root.factor

            Column {
                spacing: root.stackSpacing

                LookLabel { text: "ICONS" }

                LookDropdown {
                    id: iconsDrop
                    label: Looks.nameOf(Looks.icons, Looks.iconTheme)
                    open: root.listing === "icons"
                    onPressed: root.toggleList("icons", iconsDrop)
                }

                // The shell's own icons are the one thing that cannot follow a
                // change live; it says so rather than looking as though the
                // choice half failed. Held to the dropdown's width, so the
                // capsule's row does not grow when it appears.
                Item {
                    width: iconsDrop.width
                    height: pending.implicitHeight

                    Text {
                        id: pending
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: Looks.iconsPending
                        text: "SHELL: NEXT START"
                        elide: Text.ElideRight
                        color: Theme.textFaint
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                        })
                    }
                }
            }

            Column {
                spacing: root.stackSpacing

                Row {
                    spacing: 8 * root.factor

                    LookLabel { text: "CURSOR" }

                    LookLabel {
                        visible: Looks.error.length > 0
                        text: "· REFUSED"
                        color: Theme.alert
                    }
                }

                Row {
                    spacing: 8 * root.factor

                    LookDropdown {
                        id: cursorDrop
                        label: Looks.nameOf(Looks.cursors, Looks.cursorTheme)
                        open: root.listing === "cursor"
                        onPressed: root.toggleList("cursor", cursorDrop)
                    }

                    Segmented {
                        anchors.verticalCenter: parent.verticalCenter
                        metrics: root.metrics
                        fontSize: root.fontControl
                        options: Looks.sizes.map(size => ({ "key": String(size), "label": String(size) }))
                        current: String(Looks.cursorSize)
                        onChose: key => Looks.setCursor("", parseInt(key, 10))
                    }
                }
            }
        }
    }

    // ---- The list the dropdown opens ---------------------------------------
    //
    // It is born from the dropdown, like everything else in the shell, and it
    // is a shape of the cell: the membrane masks and blurs it with the rest, so
    // a press inside it is not a press outside the cell.

    // Which list is open: the palette's, the icon themes, the cursors — or
    // none. One at a time, because they all open in the same place.
    property string listing: ""

    // The list that is showing, kept while it closes: the one being put away
    // still has its rows until it is gone.
    property string listShown: ""

    // Where the control that asked for it is — read when it is pressed, when
    // the capsule that holds it has long finished growing.
    property real listOriginX: 0
    property real listOriginY: 0

    function toggleList(which, control) {
        if (root.listing === which) {
            root.listing = "";
            return;
        }
        const at = control.mapToItem(root, control.width / 2, root.upward ? 0 : control.height);
        root.listOriginX = at.x;
        root.listOriginY = at.y;
        root.listShown = which;
        root.listing = which;
    }

    // The list and the APPS capsule open in the same place, so asking for one
    // puts the other away.
    onListingChanged: if (root.listing.length > 0) root.appsOpen = false

    // Closing the list when the source changes under it, so a matugen method
    // never stands open over a list of Bioma palettes.
    onFromWallpaperChanged: if (root.listing === "palette") root.listing = ""

    readonly property var listOptions: root.listShown === "palette" ? root.options
        : root.listShown === "icons" ? Looks.icons.map(t => ({ "key": t.id, "label": t.name }))
        : root.listShown === "cursor" ? Looks.cursors.map(t => ({ "key": t.id, "label": t.name }))
        : []

    readonly property string listChosen: root.listShown === "palette" ? root.chosen
        : root.listShown === "icons" ? Looks.iconTheme
        : root.listShown === "cursor" ? Looks.cursorTheme
        : ""

    function listChoose(key) {
        if (root.listShown === "palette")
            root.choose(key);
        else if (root.listShown === "icons")
            Looks.setIcons(key);
        else if (root.listShown === "cursor")
            Looks.setCursor(key, 0);
        root.listing = "";
    }

    // Past this many rows the list scrolls: there are two dozen cursors on a
    // machine that has a few, and a list taller than the screen is not a list.
    readonly property int listRows: 8

    property real listGrowth: root.listing.length > 0 ? 1 : 0

    // The list is a shape of its own, and the cell's regions are rectangles
    // read once its shapes stop moving — so a shape that moves says so, or
    // the region is whatever it was when something else last did.
    onListGrowthChanged: if (root.cell) root.cell.shapesSettling()

    Behavior on listGrowth {
        NumberAnimation {
            duration: root.listing.length > 0 ? Timing.grow : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.listing.length > 0 ? Timing.easeOpen : Timing.easeClose
        }
    }

    readonly property real listRow: metrics.rowHeight
    readonly property real listPadding: 6 * factor

    Panel {
        id: list

        metrics: root.metrics
        radius: root.metrics.radiusWell
        padding: root.listPadding
        targetWidth: root.listShown === "palette" ? root.capsuleWidth - 40 * root.factor
                                                  : 300 * root.factor
        targetHeight: Math.min(root.listOptions.length, root.listRows) * root.listRow + root.listPadding * 2
        growth: root.listGrowth
        contentReady: root.listGrowth > 0.999
        visible: root.listGrowth > 0

        // It opens away from the composition, past its last capsule, which on
        // a membrane at the bottom of the screen means upwards: opening
        // downwards there would lay the list over the carousel. It is born
        // from the edge of the control that asked for it and settles clear of
        // the composition: two glass surfaces over each other read as one
        // misdrawn shape rather than as two.
        anchorX: Math.max(0, Math.min(root.carouselWidth - targetWidth, root.listOriginX - targetWidth / 2))
        anchorY: root.upward ? root.desktopY - 8 * root.factor - targetHeight
                             : root.desktopY + root.desktopHeight + 8 * root.factor
        nodeX: root.listOriginX
        nodeY: root.listOriginY

        ListView {
            id: listView

            width: list.targetWidth - root.listPadding * 2
            height: Math.min(root.listOptions.length, root.listRows) * root.listRow
            model: root.listOptions
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Opened on a long list, the choice is where the eye is. After the
            // rows exist, and from the top: one view serves every list, and
            // the last one's scroll is not this one's.
            function reveal() {
                listView.positionViewAtBeginning();
                const at = root.listOptions.findIndex(o => o.key === root.listChosen);
                if (at >= 0)
                    listView.positionViewAtIndex(at, ListView.Contain);
            }

            onModelChanged: Qt.callLater(listView.reveal)

                delegate: Item {
                    id: option

                    required property var modelData

                    width: listView.width
                    height: root.listRow

                    readonly property bool current: option.modelData.key === root.listChosen

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: option.modelData.label
                        color: option.current ? Theme.text : Theme.textMuted
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.fontControl,
                            "weight": Typography.weightLabel,
                            "letterSpacing": Typography.tracking(root.fontControl, 0.04)
                        })
                    }

                    // The choice is exclusive, so the mark may be a dot: on a
                    // list where several can be on at once it would lie.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 6 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        visible: option.current
                        width: 6 * root.factor
                        height: width
                        radius: width / 2
                        color: Theme.primary
                        antialiasing: true
                    }

                    TapHandler { onTapped: root.listChoose(option.modelData.key) }
                }
        }

        Scroller {
            flick: listView
            factor: root.factor
            x: list.targetWidth - root.listPadding * 2 - width
            visible: root.listOptions.length > root.listRows
        }
    }

    // ---- Where the palette goes ---------------------------------------------

    property bool appsOpen: false

    onAppsOpenChanged: if (root.appsOpen) root.listing = ""

    property real appsGrowth: root.appsOpen ? 1 : 0

    onAppsGrowthChanged: if (root.cell) root.cell.shapesSettling()

    Behavior on appsGrowth {
        NumberAnimation {
            duration: root.appsOpen ? Timing.grow : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.appsOpen ? Timing.easeOpen : Timing.easeClose
        }
    }

    readonly property real appsPadding: 14 * factor

    // What failed, said once under the chips: the first template that did not
    // render, with the reason its program gave.
    readonly property var failed: {
        for (const entry of Templates.catalogue)
            if (Templates.isOn(entry.id) && Templates.failures[entry.id] !== undefined)
                return { "name": entry.name, "error": Templates.failures[entry.id] };
        return null;
    }

    Panel {
        id: apps

        metrics: root.metrics
        radius: root.metrics.radiusWell
        padding: root.appsPadding
        fixedWidth: root.carouselWidth
        growth: root.appsGrowth
        contentReady: root.appsGrowth > 0.999
        visible: root.appsGrowth > 0

        // Born from the button's own edge and settled clear of the capsule,
        // away from the composition — the same place and the same rule as the
        // dropdown's list, which is why the two take turns.
        anchorX: 0
        anchorY: root.upward ? root.desktopY - 8 * root.factor - targetHeight
                             : root.desktopY + root.desktopHeight + 8 * root.factor
        nodeX: root.appsButtonCentreX
        nodeY: root.capsuleY + (root.upward ? root.dropdownTop : root.dropdownBottom)

        Column {
            width: root.carouselWidth - root.appsPadding * 2
            spacing: 10 * root.factor

            Flow {
                width: parent.width
                spacing: 6 * root.factor

                Repeater {
                    model: Templates.catalogue

                    delegate: AppChip {
                        required property var modelData
                        entry: modelData
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.failed !== null
                text: root.failed ? `${root.failed.name}: ${root.failed.error}` : ""
                color: Theme.alert
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: Typography.technical
                font.pixelSize: root.metrics.fontMeta
            }
        }
    }

    // One application. Lit when the palette goes to it; an application that is
    // not on this machine is dimmed and cannot be switched on — only off, if it
    // was on before it went.
    component AppChip: Item {
        id: chip

        property var entry: ({})

        readonly property bool on: Templates.isOn(chip.entry.id)
        readonly property bool here: chip.entry.installed === true
        readonly property bool alert: chip.on && Templates.failures[chip.entry.id] !== undefined

        width: chipText.implicitWidth + 24 * root.factor
        height: 24 * root.factor
        opacity: chip.here || chip.on ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            color: chip.on ? Qt.alpha(chip.alert ? Theme.alert : Theme.primary, 0.16) : "transparent"
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: chip.alert ? Theme.alert : chip.on ? Theme.primary
                        : chipHover.hovered && tap.enabled ? Theme.text : Theme.line
        }

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.entry.name || ""
            color: chip.alert ? Theme.alert : chip.on ? Theme.text : Theme.textMuted
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
            })
        }

        HoverHandler { id: chipHover }

        TapHandler {
            id: tap
            enabled: chip.here || chip.on
            onTapped: Templates.setOn(chip.entry.id, !chip.on)
        }
    }

    // What the membrane has to mask and blur: the surfaces, never the threads.
    function shapes() {
        const out = [
            { "item": carousel, "radius": carousel.radius },
            { "item": source, "radius": source.radius },
            { "item": palette, "radius": palette.radius },
            { "item": desktop, "radius": desktop.radius }
        ];
        if (root.listGrowth > 0)
            out.push({ "item": list, "radius": list.radius });
        if (root.appsGrowth > 0)
            out.push({ "item": apps, "radius": apps.radius });
        return out;
    }
}
