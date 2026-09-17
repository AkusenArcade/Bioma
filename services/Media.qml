pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MPRIS: what is playing, and the controls for it.
//
// This is one of Sinestesia's **two independent inputs**, and the smaller one.
// The visualiser is fed by the audio signal leaving the system; this service
// feeds only the metadata and the transport. Choosing a different player
// changes what is written beside the visualiser and nothing about the
// visualiser itself — they are not the same thing and must not be implemented
// as though they were.
//
// It follows that this service is not what raises the Sinestesia cell. Audio
// from a source with no MPRIS player — a game, a browser tab without metadata —
// still has a signal, and the cell's condition is the signal.
Singleton {
    id: root

    readonly property var players: Mpris.players?.values ?? []
    readonly property int count: players.length

    // The user's explicit choice from the expanded cell's dropdown, held as the
    // player's D-Bus name. It survives that player disappearing: when it comes
    // back, it is selected again rather than the choice being silently lost.
    //
    // Not `uniqueId`, despite the name: in Quickshell 0.3.1 two simultaneous
    // players both report `uniqueId` 1, so selecting by it silently picks
    // whichever happens to be first. `dbusName` is unique by construction.
    property string selectedName: ""

    // Preference order: what the user picked, then whatever is playing, then
    // whatever there is.
    readonly property MprisPlayer player: {
        if (root.selectedName.length > 0) {
            const chosen = root.players.find(p => p.dbusName === root.selectedName);
            if (chosen)
                return chosen;
        }
        for (const candidate of root.players) {
            if (candidate.playbackState === MprisPlaybackState.Playing)
                return candidate;
        }
        return root.players[0] ?? null;
    }

    readonly property bool available: player !== null

    function select(dbusName) {
        root.selectedName = dbusName ?? "";
    }

    function clearSelection() {
        root.selectedName = "";
    }

    readonly property bool chosenExplicitly: selectedName.length > 0 && player !== null

    // ── Metadata ─────────────────────────────────────────────────────────
    //
    // Everything here is human language and belongs in the expressive register,
    // not the technical one — with the single exception of the times below.

    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string album: player?.trackAlbum ?? ""
    readonly property string albumArtist: player?.trackAlbumArtist ?? ""
    readonly property string identity: player?.identity ?? ""

    // May be a local file, or a remote URL the player has published. Consumers
    // must cope with it being absent or failing to load: a great many tracks
    // have no art at all, and the expanded cell cannot leave a hole where it
    // would be.
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property bool hasArt: artUrl.length > 0

    // True when there is something worth writing beside the visualiser. A
    // player that is running but has no track is not worth a line of text.
    readonly property bool hasMetadata: title.length > 0 || artist.length > 0

    // ── Playback ─────────────────────────────────────────────────────────

    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing
    readonly property bool paused: player?.playbackState === MprisPlaybackState.Paused

    readonly property bool canPlay: player?.canPlay ?? false
    readonly property bool canPause: player?.canPause ?? false
    readonly property bool canToggle: player?.canTogglePlaying ?? false
    readonly property bool canGoNext: player?.canGoNext ?? false
    readonly property bool canGoPrevious: player?.canGoPrevious ?? false
    readonly property bool canSeek: player?.canSeek ?? false

    readonly property bool hasLength: (player?.lengthSupported ?? false) && length > 0
    readonly property real length: player?.length ?? 0

    // ── Position ─────────────────────────────────────────────────────────
    //
    // MPRIS does not push position: a player reports it when asked, and emits
    // `Seeked` only when the position jumps. A progress indicator therefore has
    // to ask, and the tick below is the only poll in this service.
    //
    // It runs solely while something is playing and the player answers position
    // at all, so a paused or absent player costs nothing. One second is the
    // right granularity for text; a smooth bar interpolates between ticks
    // rather than asking more often.
    property int positionTick: 0

    readonly property bool positionSupported: player?.positionSupported ?? false
    readonly property real position: {
        root.positionTick;                      // re-evaluate on every tick
        return root.player?.position ?? 0;
    }

    readonly property real progress: hasLength && position > 0
        ? Math.max(0, Math.min(1, position / length))
        : 0

    Timer {
        interval: 1000
        repeat: true
        running: root.playing && root.positionSupported
        onTriggered: root.positionTick++
    }

    // ── Controls ─────────────────────────────────────────────────────────

    function playPause() {
        if (root.player?.canTogglePlaying)
            root.player.togglePlaying();
    }

    function play() {
        if (root.player?.canPlay)
            root.player.play();
    }

    function pause() {
        if (root.player?.canPause)
            root.player.pause();
    }

    function next() {
        if (root.player?.canGoNext)
            root.player.next();
    }

    function previous() {
        if (root.player?.canGoPrevious)
            root.player.previous();
    }

    function seekBy(seconds) {
        if (root.player?.canSeek)
            root.player.seek(seconds);
    }

    function seekTo(seconds) {
        if (root.player?.canSeek)
            root.player.position = seconds;
    }

    // Formats a duration for display. Machine measurement, so it belongs in the
    // technical register with tabular numerals — without them the width dances
    // on every tick and reflows the tissue for nothing.
    function formatTime(seconds) {
        if (!(seconds > 0))
            return "0:00";
        const total = Math.floor(seconds);
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const secs = total % 60;
        const pad = n => (n < 10 ? "0" : "") + n;
        return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}`
                         : `${minutes}:${pad(secs)}`;
    }
}
