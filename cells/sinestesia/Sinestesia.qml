import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// The sound leaving the machine, made visible — and when there is a track, the
// track too.
//
// The one cell where movement does not measure a load: it measures the sound
// itself, which is the only reason it may move continuously at all. It exists
// on the **signal**, not on playback: a browser video, a game and a music
// player are all the same thing to it, and when the sound stops it goes.
//
// Two independent inputs, and that is the point. The band shows everything
// leaving the machine; the panel underneath shows the chosen MPRIS source.
// Changing player does not touch the band — if they were one thing, choosing
// Spotify would switch off the browser's video.
//
// See docs/design/CELLS.md §04.
Cell {
    id: root

    domain: "sinestesia"

    paddingLeading: 16
    paddingTrailing: 16

    readonly property real bandWidth: 81 * metrics.factor
    readonly property real bandHeight: 22 * metrics.factor
    readonly property int bars: 14
    readonly property real spacing: 14 * metrics.factor

    // The condition is the signal, and nothing else. The thresholds and the
    // four-second dwell live in the configuration, because the silence between
    // two tracks must not make the cell flicker.
    condition: Audio.peak

    // The bands cost a process, so it runs only while the cell is on screen —
    // and whether it is on screen is decided by the peak monitor, which is
    // already running for everything else.
    onPlacedChanged: Sinestesia.active = root.placed

    // Half the bars to a channel: the row is mirrored about its middle.
    // Half the bars to a channel: the row is mirrored about its middle.
    readonly property var bandLeft: Sinestesia.fold(Sinestesia.left, root.bars / 2)
    readonly property var bandRight: Sinestesia.fold(Sinestesia.right, root.bars / 2)

    // What the cell says beside the band. A track only sometimes: without
    // metadata the band stands alone and the cell narrows to it.
    readonly property string track: Media.hasMetadata
        ? (Media.artist.length > 0 ? `${Media.title} · ${Media.artist}` : Media.title)
        : ""

    readonly property bool named: root.track.length > 0

    // A name needs room to be a name. Below it the cell says the band alone and
    // centres it in whatever the tissue could give — the same answer the design
    // gives for a track with no metadata, reached from the other direction.
    readonly property real leastName: 60 * metrics.factor
    readonly property bool showsName: root.named && root.available >= root.leastName

    contentWidth: bandWidth + (named ? spacing + label.implicitWidth : 0)

    readonly property real available: Math.max(0, width - paddingLeading - paddingTrailing
                                                 - bandWidth - spacing)

    // ---- Open ---------------------------------------------------------------

    headerTitle: "SINESTESIA"
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "sinestesia"
            gradient: true
        }
    }

    replacesContent: true

    // A press opens the track panel. The wheel does nothing on purpose: volume
    // is another cell, and confusing the two here would be easy to do and
    // horrible to use.

    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("SinestesiaExpansion.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
    }

    // ---- Contracted ---------------------------------------------------------

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: root.showsName ? 0 : Math.max(0, (parent.width - root.bandWidth) / 2)
        spacing: root.spacing

        Band {
            anchors.verticalCenter: parent.verticalCenter
            width: root.bandWidth
            height: root.bandHeight
            count: root.bars
            barWidth: 3 * root.metrics.factor
            pitch: 6 * root.metrics.factor
            leftChannel: root.bandLeft
            rightChannel: root.bandRight
        }

        // The track's name is human language, so it takes the expressive face —
        // and it crosses over rather than swapping, at the window title's own
        // delay, because a track change is the same kind of event.
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showsName
            width: root.available
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontTitle
        }
    }

    onTrackChanged: {
        if (label.text === "")
            label.text = root.track;
        else
            settle.restart();
    }

    Timer {
        id: settle
        interval: Timing.debounce
        onTriggered: if (label.text !== root.track) crossfade.restart()
    }

    SequentialAnimation {
        id: crossfade
        NumberAnimation { target: label; property: "opacity"; to: 0; duration: Timing.contentFade }
        ScriptAction { script: label.text = root.track }
        NumberAnimation { target: label; property: "opacity"; to: 1; duration: Timing.contentFade }
    }

    Component.onCompleted: {
        label.text = root.track;
        Sinestesia.active = root.placed;
    }
}
