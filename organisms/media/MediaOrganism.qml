import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.core
import qs.components
import qs.services

// What is playing, with the sound rising out of its cover.
//
// Not the sinestesia cell's track panel made bigger. There the cover is a
// thumbnail beside the words and the band a strip; here the cover is the
// surface — edge to edge — and the band is the largest moving thing on the
// desktop (Akusen, 2026-10-04). The band is the sound leaving the machine,
// from the same capture as the cell; the track is the active MPRIS source.
//
// See docs/design/ORGANISMS.md §02.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    // The cover is the surface: no padding, and the rim drawn over it.
    readonly property bool bleeds: true

    // Present while a track is loaded — playing or paused. A paused track is
    // still the track; stopped, or a source with nothing to say, it leaves.
    readonly property bool present: Media.available && Media.hasMetadata && (Media.playing || Media.paused)

    readonly property bool showsBand: root.entry.band !== false

    implicitWidth: 420 * root.factor
    implicitHeight: 420 * root.factor

    readonly property real radius: root.metrics.radiusPanel
    readonly property real inset: 20 * root.factor

    // ---- The band ------------------------------------------------------------------

    // It moves whenever there is sound. It was held still while the screen's
    // workspace had a window on it, to spare the frames nobody saw — but niri
    // leaves the desktop showing between and beside the windows, and there a
    // still band beside a playing track said silence while the music played
    // (Akusen, 2026-10-04). Where the windows are on screen is not something
    // niri tells a shell — a tiled window has no position in its reports — so
    // the organism cannot know it is covered, and a band that may be seen
    // has to be true.
    readonly property bool sounding: root.present && root.showsBand && Media.playing

    onSoundingChanged: Sinestesia.hold(root, root.sounding)
    Component.onCompleted: {
        Sinestesia.hold(root, root.sounding);
        root.present_(root.art);
    }
    Component.onDestruction: Sinestesia.hold(root, false)

    readonly property int bars: 48
    readonly property var bandLeft: root.sounding ? Sinestesia.fold(Sinestesia.left, root.bars / 2) : []
    readonly property var bandRight: root.sounding ? Sinestesia.fold(Sinestesia.right, root.bars / 2) : []

    // ---- The cover ----------------------------------------------------------------

    // Two layers, so a new track's cover crosses over the old one rather than
    // replacing it with a blink.
    property bool showingSecond: false
    property string shown: ""

    readonly property string art: Media.hasArt ? Media.artUrl : ""

    onArtChanged: root.present_(root.art)

    // Not `present`: that is the organism's word for being there at all.
    function present_(url) {
        if (url === root.shown)
            return;
        root.shown = url;
        const next = root.showingSecond ? first : second;
        next.source = url;
        root.showingSecond = !root.showingSecond;
    }

    Item {
        id: art
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Image {
            id: first
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            sourceSize.width: Math.round(root.width * Screen.devicePixelRatio)
            opacity: !root.showingSecond && status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        }

        Image {
            id: second
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            sourceSize.width: Math.round(root.width * Screen.devicePixelRatio)
            opacity: root.showingSecond && status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        }

        // Under the words the theme's own background comes up, so they are
        // read on the shell's colour whatever the picture is: clear down to a
        // third of the height, then rising to nearly solid at the foot.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Theme.background, 0) }
                GradientStop { position: 0.36; color: Qt.alpha(Theme.background, 0) }
                GradientStop { position: 0.60; color: Qt.alpha(Theme.background, 0.80) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.background, 0.92) }
            }
        }
    }

    // The picture is cut to the panel's own radius — the image is shaped, the
    // panel is never clipped, so the rim drawn over it stays whole.
    Rectangle {
        id: shape
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        visible: false
        layer.enabled: true
    }

    OpacityMask {
        anchors.fill: parent
        visible: Media.hasArt
        source: art
        maskSource: shape
    }

    // No cover: the panel is glass, and the cell's own glyph holds the
    // picture's place in the upper half. A record without a picture, not the
    // shell introducing itself.
    Icon {
        visible: !Media.hasArt
        name: "sinestesia"
        colour: Theme.textMuted
        width: 96 * root.factor
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: 52 * root.factor
    }

    // ---- The band and the words, on the foot of the panel -----------------------------

    Column {
        id: words

        x: root.inset
        width: root.width - root.inset * 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.inset
        spacing: 0

        Band {
            visible: root.showsBand
            width: parent.width
            height: 96 * root.factor
            count: root.bars
            barWidth: 4 * root.factor
            pitch: 8 * root.factor
            leftChannel: root.bandLeft
            rightChannel: root.bandRight
        }

        Item {
            width: 1
            height: root.showsBand ? 16 * root.factor : 0
        }

        Text {
            width: parent.width
            text: Media.title
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: Math.round(22 * root.factor)
            font.weight: Font.Bold
        }

        Text {
            width: parent.width
            visible: text.length > 0
            text: Media.artist
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: Math.round(16 * root.factor)
        }

        Text {
            width: parent.width
            visible: text.length > 0
            text: Media.album
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.textFaint
            font.family: Typography.expressive
            font.pixelSize: Math.round(13 * root.factor)
            font.italic: true
        }

        // Progress, with the times under it — not for a stream that has no
        // length to measure against.
        Item {
            width: 1
            height: Media.hasLength ? 14 * root.factor : 0
        }

        Item {
            visible: Media.hasLength
            width: parent.width
            height: track.height + 5 * root.factor + times.height

            Rectangle {
                id: track
                width: parent.width
                height: Metrics.crisp(3 * root.factor, Screen.devicePixelRatio)
                radius: height / 2
                color: Qt.alpha(Theme.text, 0.16)

                Rectangle {
                    width: parent.width * Media.progress
                    height: parent.height
                    radius: height / 2
                    color: Theme.primary
                }

                Rectangle {
                    width: 7 * root.factor
                    height: width
                    radius: width / 2
                    color: Theme.primary
                    antialiasing: true
                    x: parent.width * Media.progress - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                id: times
                y: track.height + 5 * root.factor
                width: parent.width
                height: elapsed.implicitHeight

                readonly property font face: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta
                }))

                Text {
                    id: elapsed
                    text: Media.formatTime(Media.position)
                    color: Theme.textMuted
                    font: times.face
                }

                Text {
                    anchors.right: parent.right
                    text: Media.formatTime(Media.length)
                    color: Theme.textMuted
                    font: times.face
                }
            }
        }
    }
}
