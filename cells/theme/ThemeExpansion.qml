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
    readonly property real dropdownBottom: (capsuleHeight + stackHeight) / 2

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

        // Born from the node of the cell's own thread, which lands on its top
        // edge under the middle of the cell.
        anchorX: 0
        anchorY: 0
        nodeX: root.width - (root.cell ? root.cell.width / 2 : 0)
        nodeY: 0

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
    Thread {
        vertical: true
        progress: root.linkProgress
        width: implicitWidth
        height: root.gap
        x: root.capsuleWidth / 2 - width / 2
        y: root.carouselHeight
    }

    Thread {
        vertical: false
        progress: root.linkProgress
        width: root.gap
        height: implicitHeight
        x: root.capsuleWidth
        y: root.carouselHeight + root.gap + root.capsuleHeight / 2 - height / 2
    }

    // ---- Source -------------------------------------------------------------

    component Segmented: Item {
        id: control

        property var options: []
        property string current: ""
        signal chose(string key)

        implicitWidth: track.width
        implicitHeight: track.height

        readonly property real buttonHeight: 26 * root.factor
        readonly property real buttonPadding: 14 * root.factor
        readonly property real trackPadding: 3 * root.factor

        // The selected option carries the gradient, so it is set in the bold
        // weight and every button is measured at that weight: a pill that
        // resized itself on selection would be a second animation nobody asked
        // for, over the one that is meant to be seen.
        readonly property var buttonFont: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.fontControl,
            "weight": Typography.weightTitle,
            "letterSpacing": Typography.tracking(root.fontControl, 0.04)
        })

        Well {
            id: track
            metrics: root.metrics
            clip: false
            width: buttons.width + control.trackPadding * 2
            height: control.buttonHeight + control.trackPadding * 2
            radius: height / 2
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: Theme.line

            // The selection slides to the chosen option with the opening
            // timings: it does not vanish on one side and appear on the other.
            Rectangle {
                id: selection

                readonly property int index: {
                    for (let i = 0; i < control.options.length; i++)
                        if (control.options[i].key === control.current)
                            return i;
                    return -1;
                }

                readonly property Item chosenItem: selection.index >= 0 && selection.index < buttonList.count
                                                   ? buttonList.itemAt(selection.index) : null

                x: control.trackPadding + (selection.chosenItem ? selection.chosenItem.x : 0)
                y: control.trackPadding
                width: selection.chosenItem ? selection.chosenItem.width : 0
                height: control.buttonHeight
                radius: height / 2
                antialiasing: true
                visible: width > 0

                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                    GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
                }

                Behavior on x {
                    NumberAnimation {
                        duration: Timing.transition
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Timing.easeOpenFlat
                    }
                }

                Behavior on width {
                    NumberAnimation {
                        duration: Timing.transition
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Timing.easeOpenFlat
                    }
                }
            }

            Row {
                id: buttons
                x: control.trackPadding
                y: control.trackPadding
                spacing: 2 * root.factor

                Repeater {
                    id: buttonList
                    model: control.options

                    delegate: Item {
                        id: button

                        required property var modelData

                        readonly property bool chosen: button.modelData.key === control.current

                        width: label.implicitWidth + control.buttonPadding * 2
                        height: control.buttonHeight

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: button.modelData.label
                            // A selected control is not a surface: it takes the
                            // fill it sits on, and the others stay quiet.
                            color: button.chosen ? Theme.background : Theme.textMuted
                            font: control.buttonFont
                        }

                        TapHandler { onTapped: control.chose(button.modelData.key) }
                    }
                }
            }
        }
    }

    Panel {
        id: source

        metrics: root.metrics
        radius: root.capsuleHeight / 2
        padding: 14 * root.factor
        targetWidth: root.capsuleWidth
        targetHeight: root.capsuleHeight
        growth: root.sourceProgress
        contentReady: root.sourceProgress > 0.999

        // Born from the node where the vertical thread meets its cap.
        anchorX: 0
        anchorY: root.carouselHeight + root.gap
        nodeX: root.capsuleWidth / 2
        nodeY: root.carouselHeight + root.gap

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

        // Born from the far node of the horizontal thread.
        anchorX: root.capsuleWidth + root.gap
        anchorY: root.carouselHeight + root.gap
        nodeX: root.capsuleWidth + root.gap
        nodeY: root.carouselHeight + root.gap + root.capsuleHeight / 2

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

        // The dropdown's own bottom edge, computed rather than read off the
        // item: the capsule's content is still growing when the list starts,
        // and a shape born from a moving point is born from the wrong one.
        readonly property real originX: root.capsuleWidth + root.gap + root.capsuleWidth / 2
        readonly property real originY: root.carouselHeight + root.gap + root.dropdownBottom

        anchorX: list.originX - targetWidth / 2
        anchorY: list.originY + 8 * root.factor
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
