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
    readonly property real tileRadius: 10 * factor

    readonly property real capsuleWidth: 268 * factor
    readonly property real capsuleHeight: 96 * factor
    readonly property real gap: 24 * factor

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
    readonly property real carouselY: upward ? capsuleHeight + gap : 0
    readonly property real capsuleY: upward ? 0 : carouselHeight + gap
    readonly property real carouselNear: upward ? carouselY + carouselHeight : carouselY
    readonly property real capsuleNear: upward ? capsuleY + capsuleHeight : capsuleY

    // Orbitron 12 for the dropdown is CELLS.md §07's own figure, and the
    // controls beside it are the same voice at the same size: a segmented
    // control and a dropdown are one family, and two sizes inside one capsule
    // read as a mistake.
    readonly property int fontControl: Math.round(12 * factor)

    implicitWidth: carouselWidth
    implicitHeight: carouselHeight + gap + capsuleHeight

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
        root.listing = false;
    }

    // ---- The cascade --------------------------------------------------------
    //
    // The carousel grows on the cell's own thread; then the threads under it,
    // then the two capsules, sixteen milliseconds apart. Each shape still grows
    // in `Timing.grow` — the opening figure is reached by tightening the
    // cascade, never by shortening a growth.

    property real cascade: 0

    function stage(index) {
        const span = Timing.grow + Timing.stagger * 2;
        const started = root.cascade * span - index * Timing.stagger;
        return Math.max(0, Math.min(1, started / Timing.grow));
    }

    readonly property real linkProgress: stage(0)
    readonly property real sourceProgress: stage(1)
    readonly property real paletteProgress: stage(2)

    Connections {
        target: root.cell
        function onOpenChanged() {
            capsules.stop();
            capsules.to = root.cell.open ? 1 : 0;
            capsules.duration = root.cell.open ? Timing.open : Timing.close;
            capsules.start();
            if (!root.cell.open)
                root.listing = false;
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

    // Wallpapers are looked at inside shapes of their own: the current one at
    // full light in the centre, its neighbours half-seen at the sides. That is
    // what makes the carousel read as a strip that continues past the panel,
    // without a fade over the edges to fake it.
    component Tile: Item {
        id: tile

        property string image: ""
        property real corner: root.tileRadius
        property bool current: false

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
            smooth: true
            // Decoded at the size it is actually shown at, so a 4000 px
            // photograph in a 100 px pill costs what the pill costs.
            sourceSize.width: Math.round(tile.width * Screen.devicePixelRatio)
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
            visible: tile.current
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
                    Wallpaper.step(-1);
                else if (event.angleDelta.y < 0)
                    Wallpaper.step(1);
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: root.tilePitch

            Tile {
                width: root.neighbourWidth
                height: root.tileHeight
                image: Wallpaper.neighbour(-1)
                opacity: 0.40
                TapHandler { onTapped: Wallpaper.step(-1) }
            }

            Tile {
                width: root.tileWidth
                height: root.tileHeight
                image: Wallpaper.path
                current: true
            }

            Tile {
                width: root.neighbourWidth
                height: root.tileHeight
                image: Wallpaper.neighbour(1)
                opacity: 0.40
                TapHandler { onTapped: Wallpaper.step(1) }
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
        radius: root.capsuleHeight / 2
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
                    root.listing = false;
                }
            }
        }
    }

    // ---- What comes out of it ----------------------------------------------

    Panel {
        id: palette

        metrics: root.metrics
        radius: root.capsuleHeight / 2
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
                        radius: 5 * root.factor
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
            Item {
                id: dropdown

                anchors.horizontalCenter: parent.horizontalCenter
                width: chosenText.width + 12 * root.factor * 2 + 7 * root.factor + chevron.width
                height: root.dropdownHeight

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
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

                TapHandler { onTapped: root.listing = !root.listing }
            }
        }
    }

    // ---- The list the dropdown opens ---------------------------------------
    //
    // It is born from the dropdown, like everything else in the shell, and it
    // is a shape of the cell: the membrane masks and blurs it with the rest, so
    // a press inside it is not a press outside the cell.

    property bool listing: false

    // Closing the list when the source changes under it, so a matugen method
    // never stands open over a list of Bioma palettes.
    onFromWallpaperChanged: root.listing = false

    property real listGrowth: root.listing ? 1 : 0

    Behavior on listGrowth {
        NumberAnimation {
            duration: root.listing ? Timing.grow : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.listing ? Timing.easeOpen : Timing.easeClose
        }
    }

    readonly property real listRow: metrics.rowHeight
    readonly property real listPadding: 6 * factor

    Panel {
        id: list

        metrics: root.metrics
        radius: root.metrics.radiusWell
        padding: root.listPadding
        targetWidth: root.capsuleWidth - 40 * root.factor
        targetHeight: root.options.length * root.listRow + root.listPadding * 2
        growth: root.listGrowth
        contentReady: root.listGrowth > 0.999
        visible: root.listGrowth > 0

        // The dropdown's own edge, computed rather than read off the item: the
        // capsule's content is still growing when the list starts, and a shape
        // born from a moving point is born from the wrong one.
        //
        // It opens away from the composition, which on a membrane at the bottom
        // of the screen means upwards: opening downwards there would lay the
        // list over the carousel.
        readonly property real originX: root.capsuleWidth + root.gap + root.capsuleWidth / 2
        readonly property real originY: root.capsuleY + (root.upward ? root.dropdownTop
                                                                     : root.dropdownBottom)

        // It is born from the dropdown's own edge and settles clear of the
        // capsule: a list that stopped eight pixels from the dropdown would
        // stand on the capsule's cap, and two glass surfaces over each other
        // read as one misdrawn shape rather than as two.
        anchorX: list.originX - targetWidth / 2
        anchorY: root.upward ? root.capsuleY - 8 * root.factor - targetHeight
                             : root.capsuleY + root.capsuleHeight + 8 * root.factor
        nodeX: list.originX
        nodeY: list.originY

        Column {
            width: parent.width

            Repeater {
                model: root.options

                delegate: Item {
                    id: option

                    required property var modelData

                    width: list.targetWidth - root.listPadding * 2
                    height: root.listRow

                    readonly property bool current: option.modelData.key === root.chosen

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

                    TapHandler { onTapped: root.choose(option.modelData.key) }
                }
            }
        }
    }

    // What the membrane has to mask and blur: the surfaces, never the threads.
    function shapes() {
        const out = [
            { "item": carousel, "radius": carousel.radius },
            { "item": source, "radius": source.radius },
            { "item": palette, "radius": palette.radius }
        ];
        if (root.listGrowth > 0)
            out.push({ "item": list, "radius": list.radius });
        return out;
    }
}
