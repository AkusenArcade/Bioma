import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Screenshots, regions, text recognition and recording.
//
// The first purely functional cell: at rest it has nothing to represent, so it
// shows its icon and nothing else — no figure, no state colour, because it
// measures nothing.
//
// It is also the only cell that generates another one. A recording has a
// duration, and what has a duration needs a cell to say so; this one stays put
// and available while `cells/recording` counts. If it changed shape instead,
// taking a screenshot during a recording would have become impossible.
//
// See docs/design/CELLS.md §06.
Cell {
    id: root

    domain: "utility"

    // The icon is the whole content, so the padding is what makes the cell
    // square: 20 between two tens.
    readonly property real iconSize: 20 * metrics.factor
    // A square around its glyph. What the cell wears when it opens keeps its
    // own margins, which the engine works out from the header's mark.
    paddingLeading: 10 * metrics.factor
    paddingTrailing: 10 * metrics.factor

    // Open, the cell becomes the title of the panel it opened: the glyph of its
    // domain and its name, in the technical voice, like every other cell with
    // an expansion.
    //
    // Its category rather than what it does today. `CAPTURE` would be the truer
    // word for a cell that only captures, and the wrong one for a cell expected
    // to grow other functions — a title that has to be renamed when it does is
    // the wrong title. Akusen's call, 2026-09-22.
    headerTitle: "UTILITY"
    headerMarkSize: iconSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "capture"
            gradient: true
        }
    }

    contentWidth: iconSize

    replacesContent: true

    // Two independent choices — what is captured, and where from. They are two
    // rows rather than six buttons, and the last pair used stays selected,
    // which is why they are remembered in the configuration rather than in the
    // cell.
    readonly property string what: Config.get("capture.what", "image")
    readonly property string from: Config.get("capture.from", "screen")

    // Video is the recorder's, and it cannot record a window: `wl-screenrec`
    // takes an output or a region and nothing else. Text is `tesseract` over a
    // captured region, and a window has no region here — niri reports no window
    // position, so the compositor captures it by id. A pair that cannot be done
    // is shown as unavailable rather than offered and then refused.
    function supports(what, from) {
        if (from !== "window")
            return true;
        return what === "image";
    }

    Icon {
        anchors.centerIn: parent
        name: "capture"
        width: root.iconSize
        height: width
        gradient: true
    }

    // ---- Doing it -----------------------------------------------------------

    function capture(what, from) {
        if (!root.supports(what, from))
            return;

        Config.set("capture.what", what);
        Config.set("capture.from", from);
        Capture.pendingAction = what === "video" ? "record"
                              : what === "text" ? "text" : "still";

        // The cell closes first and the capture follows, because the panel is
        // on the screen being photographed. The service holds its own frame of
        // settling for the same reason; this is the part of it the cell owns.
        root.open = false;

        if (from === "region") {
            Capture.selectRegion();
            return;
        }

        if (from === "window") {
            Capture.captureWindow(Niri.focusedWindow ? Niri.focusedWindow.id : 0);
            return;
        }

        if (what === "video")
            Capture.recordOutput(root.output);
        else if (what === "text")
            // A whole screen of text is a region like any other: the output's
            // own rectangle, in the layout coordinates grim wants.
            Capture.recogniseRegion(root.outputRegion());
        else
            Capture.captureOutput(root.output);
    }

    function outputRegion() {
        for (const screen of Quickshell.screens)
            if (screen.name === root.output)
                return `${screen.x},${screen.y} ${screen.width}x${screen.height}`;
        return "";
    }

    panel: Component {
        Loader {
            id: panelLoader
            source: Qt.resolvedUrl("UtilityPanel.qml")

            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }
}
