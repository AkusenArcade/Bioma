import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Bioma's own settings, and nothing else's.
//
// Not a control panel: anything that has a cell of its own does not come back
// here as a category. Volume is the audio cell's, the palette is the theme
// cell's, do-not-disturb is the notification cell's. What is left is the shell
// itself — how it looks, how it is laid out, when each cell exists, the
// monitors and the keys.
//
// At rest it is the mark, and **this is the only place the mark appears**: a
// shell that puts its logo in several places is advertising itself on somebody
// else's desktop.
//
// See docs/design/CELLS.md §12, PRD §9.12.
Cell {
    id: root

    domain: "settings"

    readonly property real markSize: 20 * metrics.factor

    paddingLeading: (metrics.cellHeight - markSize) / 2
    paddingTrailing: paddingLeading

    contentWidth: markSize

    // Which category is being looked at. It lives on the cell rather than in
    // the expansion so that closing and reopening comes back to the same
    // place — somebody adjusting a margin closes this to look at the result.
    property string category: "appearance"

    // The keyboard, for the one page that has a field in it. Same rule as
    // everywhere: asked for over the panel, not because something is open.
    property bool panelHovered: false

    wantsKeyboard: root.open && root.panelHovered

    onOpenChanged: if (!root.open) root.panelHovered = false

    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("SettingsExpansion.qml")
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

    Icon {
        anchors.centerIn: parent
        name: "mark"
        width: root.markSize
        height: width
        gradient: true
    }
}
