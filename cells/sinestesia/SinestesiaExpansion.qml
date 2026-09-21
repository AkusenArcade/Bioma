import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.core
import qs.components
import qs.services

// Sinestesia, opened: the band with room, and the track hung underneath it.
//
// The panel hangs **from** the visualiser and not the other way round. Sound is
// always there and a track only sometimes, so the thread says which of the two
// holds the other — and with no MPRIS source the panel does not exist rather
// than standing empty. It arrives and goes as a track appears and ends, without
// the cell closing.
//
// See docs/design/CELLS.md §04.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property real capsuleWidth: 372 * factor
    readonly property real capsuleHeight: 88 * factor
    readonly property real bandWidth: 268 * factor
    readonly property real bandHeight: 52 * factor
    readonly property int bars: 34

    readonly property real panelWidth: 372 * factor
    readonly property real panelHeight: 164 * factor
    readonly property real gap: 24 * factor

    readonly property bool hasTrack: Media.hasMetadata

    // Which way the cell opened. The composition is ordered from the cell
    // outwards: the visualiser is always the shape the cell's thread lands on,
    // and the track panel goes beyond it.
    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    readonly property real capsuleY: upward && hasTrack ? panelHeight + gap : 0
    readonly property real panelY: upward ? 0 : capsuleHeight + gap
    readonly property real capsuleNear: upward ? capsuleY + capsuleHeight : capsuleY

    implicitWidth: capsuleWidth
    implicitHeight: hasTrack ? capsuleHeight + gap + panelHeight : capsuleHeight

    width: implicitWidth
    height: implicitHeight

    readonly property var bandLeft: Sinestesia.fold(Sinestesia.left, root.bars / 2)
    readonly property var bandRight: Sinestesia.fold(Sinestesia.right, root.bars / 2)

    // ---- The cascade --------------------------------------------------------

    property real cascade: 0

    function stage(index) {
        const span = Timing.grow + Timing.stagger * 2;
        const started = root.cascade * span - index * Timing.stagger;
        return Math.max(0, Math.min(1, started / Timing.grow));
    }

    readonly property real linkProgress: stage(0)
    readonly property real panelProgress: stage(1)

    Connections {
        target: root.cell
        function onOpenChanged() {
            cascade.stop();
            cascade.to = root.cell.open ? 1 : 0;
            cascade.duration = root.cell.open ? Timing.open : Timing.close;
            cascade.start();
        }
    }

    NumberAnimation {
        id: cascade
        target: root
        property: "cascade"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    onCellChanged: {
        if (root.cell && root.cell.open) {
            cascade.to = 1;
            cascade.restart();
        }
    }

    // ---- The visualiser -----------------------------------------------------

    Panel {
        id: visualiser

        metrics: root.metrics
        radius: root.capsuleHeight / 2
        targetWidth: root.capsuleWidth
        targetHeight: root.capsuleHeight
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        anchorX: 0
        anchorY: root.capsuleY
        nodeX: root.width / 2
        nodeY: root.capsuleNear

        Band {
            anchors.centerIn: parent
            width: root.bandWidth
            height: root.bandHeight
            count: root.bars
            barWidth: 4 * root.factor
            pitch: 8 * root.factor
            leftChannel: root.bandLeft
            rightChannel: root.bandRight
        }
    }

    // The thread between the two, its ends on the shapes rather than on the
    // coordinates they settle at.
    Thread {
        id: descent

        readonly property real headY: root.upward ? track.y + track.height
                                                  : visualiser.y + visualiser.height
        readonly property real footY: root.upward ? visualiser.y : track.y

        visible: root.hasTrack
        vertical: true
        progress: root.hasTrack ? root.linkProgress : 0
        width: implicitWidth
        height: Math.max(0, descent.footY - descent.headY)
        x: root.width / 2 - width / 2
        y: descent.headY
    }

    // ---- The track ----------------------------------------------------------

    Panel {
        id: track

        readonly property real inset: 10 * root.factor
        readonly property real cover: 88 * root.factor
        readonly property real column: root.panelWidth - track.inset * 2 - track.cover - 16 * root.factor

        metrics: root.metrics
        padding: track.inset
        targetWidth: root.panelWidth
        targetHeight: root.panelHeight
        growth: root.hasTrack ? root.panelProgress : 0
        contentReady: root.hasTrack && root.panelProgress > 0.999
        visible: root.hasTrack && root.panelProgress > 0

        anchorX: 0
        anchorY: root.panelY
        nodeX: root.width / 2
        nodeY: root.upward ? track.anchorY + root.panelHeight : track.anchorY

        Item {
            anchors.fill: parent

            // The cover, concentric inside the panel: a well ten pixels in from
            // a radius of twenty takes ten.
            Item {
                id: art

                width: track.cover
                height: width
                y: 0

                Rectangle {
                    id: artShape
                    anchors.fill: parent
                    radius: Metrics.innerRadius(root.metrics.radiusPanel, track.inset)
                    color: Qt.alpha(Theme.lift(Theme.background, -0.01), 0.8)
                    antialiasing: true
                    visible: !Media.hasArt
                }

                // The artwork belongs to the record, not to the palette, so it
                // is not tinted — like the application icons in the window
                // title. Where there is none, the well stands and the mark goes
                // in it, and that one does follow the palette.
                Image {
                    id: cover
                    anchors.fill: parent
                    source: Media.hasArt ? Media.artUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    sourceSize.width: Math.round(track.cover * Screen.devicePixelRatio)
                    visible: false
                    layer.enabled: true
                }

                Rectangle {
                    id: coverShape
                    anchors.fill: parent
                    radius: artShape.radius
                    antialiasing: true
                    visible: false
                    layer.enabled: true
                }

                OpacityMask {
                    anchors.fill: parent
                    visible: Media.hasArt
                    source: cover
                    maskSource: coverShape
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !Media.hasArt
                    name: "mark"
                    width: parent.width * 0.4
                    height: width
                    colour: Theme.textMuted
                }
            }

            // Title, then who made it: a name is human language and takes the
            // expressive face, in both sizes.
            Column {
                x: track.cover + 16 * root.factor
                width: track.column
                spacing: 2 * root.factor

                Text {
                    width: parent.width
                    text: Media.title
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(19 * root.factor)
                }

                Text {
                    width: parent.width
                    text: Media.album.length > 0 && Media.artist.length > 0
                          ? `${Media.artist} · ${Media.album}`
                          : (Media.artist.length > 0 ? Media.artist : Media.album)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(15 * root.factor)
                }
            }

            // Where the track is. The node rides the head of the line, because
            // a progress bar without a head says how much rather than where.
            Item {
                id: progress

                x: track.cover + 16 * root.factor
                y: 62 * root.factor
                width: track.column
                height: 14 * root.factor

                visible: Media.hasLength

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 3 * root.factor
                    radius: height / 2
                    color: Qt.alpha(Theme.line, 0.55)
                    antialiasing: true
                }

                Rectangle {
                    id: elapsed
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.max(0, Math.min(1, Media.progress))
                    height: 3 * root.factor
                    radius: height / 2
                    antialiasing: true

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                        GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: elapsed.width - width / 2
                    width: 7 * root.factor
                    height: width
                    radius: width / 2
                    color: Theme.gradientTop(Theme.primary)
                    antialiasing: true
                }

                TapHandler {
                    enabled: Media.canSeek
                    onTapped: event => Media.seekTo(Media.length * (event.position.x / progress.width))
                }
            }

            Text {
                x: track.cover + 16 * root.factor
                y: 78 * root.factor
                visible: Media.hasLength
                text: Media.formatTime(Media.position)
                color: Theme.textMuted
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "weight": Typography.weightSecondary
                }))
            }

            Text {
                x: track.cover + 16 * root.factor + track.column - width
                y: 78 * root.factor
                visible: Media.hasLength
                text: Media.formatTime(Media.length)
                color: Theme.textMuted
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "weight": Typography.weightSecondary
                }))
            }

            // ---- Transport --------------------------------------------------
            //
            // The one that acts is filled and larger; the two that step are
            // rings. A control is not a surface: the filled one carries the
            // primary gradient and takes the colour of the fill it sits on.

            component Step: Item {
                id: step

                property string glyph: ""
                property bool enabled: true
                signal pressed

                width: 36 * root.factor
                height: width
                opacity: step.enabled ? 1 : 0.38

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                    border.color: Theme.line
                    antialiasing: true
                }

                Icon {
                    anchors.centerIn: parent
                    name: step.glyph
                    width: 16 * root.factor
                    height: width
                    colour: Theme.text
                }

                TapHandler {
                    enabled: step.enabled
                    onTapped: step.pressed()
                }
            }

            Row {
                id: transport

                y: 104 * root.factor
                x: track.cover + 16 * root.factor
                spacing: 14 * root.factor

                Step {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "skip-previous"
                    enabled: Media.canGoPrevious
                    onPressed: Media.previous()
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44 * root.factor
                    height: width

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        antialiasing: true

                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                            GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        name: Media.playing ? "pause" : "play"
                        width: 18 * root.factor
                        height: width
                        colour: Theme.background
                    }

                    TapHandler {
                        enabled: Media.canToggle || Media.canPlay
                        onTapped: Media.playPause()
                    }
                }

                Step {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "skip-next"
                    enabled: Media.canGoNext
                    onPressed: Media.next()
                }
            }

            // The selector appears only with more than one source, and it
            // changes **only** this panel: the band is the whole machine and
            // has nothing to do with which player is chosen.
            Item {
                id: chooser

                readonly property real pad: 12 * root.factor

                // What is left of the row once the transport has taken its
                // place, which is the transport's, not a share: the controls
                // that act are not negotiable and a name can be shortened.
                readonly property real room: track.column + track.cover + 16 * root.factor
                                             - (transport.x + transport.width) - 14 * root.factor
                readonly property real natural: chosen.implicitWidth + chooser.pad * 2
                                                + 7 * root.factor + arrow.width

                visible: Media.count > 1 && chooser.room > 60 * root.factor
                x: track.column + track.cover + 16 * root.factor - width
                y: transport.y + (44 * root.factor - height) / 2
                width: Math.min(chooser.natural, chooser.room)
                height: 30 * root.factor

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
                        id: chosen
                        anchors.verticalCenter: parent.verticalCenter
                        text: Media.identity.length > 0 ? Media.identity : "Player"
                        width: Math.min(implicitWidth,
                                        chooser.width - chooser.pad * 2 - 7 * root.factor - arrow.width)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }

                    Icon {
                        id: arrow
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down"
                        width: 9 * root.factor
                        height: width
                        colour: Qt.alpha(Theme.text, 0.6)
                    }
                }

                // One press, the next source: a list of two entries is a menu
                // nobody needs, and with three the round is quicker than
                // opening something.
                TapHandler {
                    onTapped: {
                        const players = Media.players;
                        if (players.length < 2)
                            return;
                        const here = players.indexOf(Media.player);
                        const next = players[(here + 1) % players.length];
                        if (next)
                            Media.select(next.dbusName);
                    }
                }
            }
        }
    }

    // What the membrane has to mask and blur: the surfaces, never the threads.
    function shapes() {
        const out = [{ "item": visualiser, "radius": visualiser.radius }];
        if (root.hasTrack && root.panelProgress > 0)
            out.push({ "item": track, "radius": track.radius });
        return out;
    }
}
