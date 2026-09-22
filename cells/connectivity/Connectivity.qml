import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Ethernet, Wi-Fi and the wireless devices — one glyph per live connection.
//
// The only cell that **composes itself**: its width says how many connections
// there are without writing a number, which is the reason it is not a single
// icon with a state colour. Three glyphs mean three connections, read without
// reading.
//
// With none it does not shrink to an empty pill: it goes. A struck-through
// icon would claim something is broken, and being offline is a condition, not
// a fault — the application that needs the network will say so itself.
//
// See docs/design/CELLS.md §11, PRD §9.11.
Cell {
    id: root

    domain: "connectivity"

    readonly property real glyphSize: 18 * metrics.factor
    readonly property real pitch: 10 * metrics.factor

    paddingLeading: 14 * metrics.factor
    paddingTrailing: 14 * metrics.factor

    // What is actually carrying traffic, in the order the design lists it:
    // the wire first, because it is the one that does not negotiate.
    readonly property var glyphs: {
        const out = [];
        if (Network.wiredConnected)
            out.push("ethernet");
        if (Network.wifiConnected)
            out.push("wifi");
        if (Bluetooth.anyConnected)
            out.push("wireless-link");
        return out;
    }

    condition: glyphs.length

    contentWidth: glyphs.length > 0
        ? glyphs.length * glyphSize + (glyphs.length - 1) * pitch
        : glyphSize

    // ---- Open ---------------------------------------------------------------

    // The cell composes itself, and so does its header: the mark is whichever
    // connection leads the row, so the glyph that was there a moment ago is
    // still the glyph the cell wears.
    readonly property string leadGlyph: glyphs.length > 0 ? glyphs[0] : "wireless-link"

    headerTitle: "CONNECTIVITY"
    headerMarkSize: glyphSize
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: root.leadGlyph
            gradient: true
        }
    }

    replacesContent: true

    // The keyboard, for the one field in the shell that is asked for at the
    // edge of the screen: a network's password. Same rule as the vitals
    // filter — the request follows the pointer onto the panel, and stays up
    // while a password is actually being asked for, because the pointer may
    // well leave the panel while it is being typed.
    property bool panelHovered: false
    property bool asking: false

    wantsKeyboard: root.open && (root.panelHovered || root.asking)

    onOpenChanged: {
        if (!root.open) {
            root.panelHovered = false;
            root.asking = false;
        }
    }

    panel: Component {
        Loader {
            id: panelLoader
            source: Qt.resolvedUrl("ConnectivityPanel.qml")

            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }
        }
    }

    // ---- Contracted ---------------------------------------------------------

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pitch

        Repeater {
            model: root.glyphs

            delegate: Icon {
                required property string modelData

                anchors.verticalCenter: parent.verticalCenter
                name: modelData
                width: root.glyphSize
                height: width
                gradient: true
            }
        }
    }
}
