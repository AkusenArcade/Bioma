import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Emoji, found by name and put where the keyboard is pointed.
//
// It is asked for, never there by itself: an emoji is wanted in the middle of
// a sentence, and the key that brings the cell is the whole of the way to it.
// Placed nowhere — the default — the key summons it into the middle of the
// screen; put on a membrane by somebody who would rather have a face to aim
// at, it is its glyph, and the same panel hangs off it.
//
// Open, it is a field, the emoji in a grid under it, and the name of the one
// chosen under that. Enter, or a press, closes the cell and pastes the emoji
// into the window that had the focus (services/Emoji.qml). With an empty field
// the last ones sent come first; one skin tone, chosen beside the field,
// applies to everything that has one.
//
// See docs/design/CELLS.md §17.
Cell {
    id: root

    domain: "emoji"

    readonly property real glyphSize: 20 * metrics.factor

    paddingLeading: (metrics.cellHeight - glyphSize) / 2
    paddingTrailing: paddingLeading
    contentWidth: glyphSize

    headerTitle: "EMOJI"
    headerMarkSize: glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "emoji"
            gradient: true
        }
    }
    replacesContent: true

    // Open, it is a field to type into and nothing else, so it holds the keys
    // for as long as it is open. On a membrane it **takes** them, for the
    // launcher's reason: opened by its key or by a press, the surface would
    // otherwise be focusable and not focused, and every letter would go to
    // the window behind. A float already holds them outright.
    wantsKeyboard: root.open
    takesKeyboard: root.open && !root.floating

    // The set is read the first time the cell opens, and the keyboard that
    // pastes is made then too: niri takes a moment to follow a new device,
    // and that moment is spent while the user searches.
    onOpenChanged: {
        if (root.open)
            Emoji.wanted = true;
        Emoji.ready = root.open;
    }
    Component.onDestruction: if (root.open) Emoji.ready = false

    function send(entry) {
        if (!entry)
            return;
        Emoji.send(entry);
        root.open = false;
        root.visibility.invoked = false;
    }

    panel: Component {
        Loader {
            source: Qt.resolvedUrl("EmojiPanel.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }

    // The cell's only content, so it wears the light gradient, as every
    // contracted glyph does.
    Icon {
        anchors.centerIn: parent
        width: root.glyphSize
        height: width
        name: "emoji"
        gradient: true
    }
}
