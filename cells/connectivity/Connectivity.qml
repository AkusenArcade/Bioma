import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Ethernet, Wi-Fi and the wireless devices — one glyph per live connection,
// and the printer while it prints.
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

    readonly property bool composed: root.glyphs.length > 1

    // One glyph is a round cell, not a short bar. A single mark in a pill twice
    // its own width reads as a cell that has lost its content — the minimum in
    // the handoff belongs to the composed form, where the width is the count.
    // Akusen's call, 2026-09-22, against the 64 px in CELLS §11.
    readonly property real configuredMin: config.min_width && config.min_width.value !== undefined
                                          ? config.min_width.value : 64

    minWidth: composed ? configuredMin : metrics.cellHeight

    // With one glyph the padding is whatever makes the cell square around it,
    // so the glyph stays concentric with the cap.
    paddingLeading: composed ? 14 * metrics.factor : (metrics.cellHeight - glyphSize) / 2
    paddingTrailing: paddingLeading

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
        // A tunnel up is a connection too, and the one most worth seeing.
        if (Vpn.anyActive)
            out.push("lock");
        // A printer is not a connection, but a job going out to it is traffic
        // with an end, and the only time a printer has something to say.
        if (Printers.printing)
            out.push("printer");
        return out;
    }

    // Conditional, it is there for a moment when something connects that was
    // not connected before: the wire, a wireless network — a different one
    // counts — or a Bluetooth device. Going away is not news.
    readonly property var connections: {
        const out = [];
        if (Network.wiredConnected)
            out.push("wired:" + Network.wiredName);
        if (Network.wifiConnected)
            out.push("wifi:" + Network.ssid);
        for (const device of Bluetooth.connectedDevices)
            out.push("bluetooth:" + device.address);
        for (const profile of Vpn.active)
            out.push("vpn:" + profile.uuid);
        for (const queue of Printers.printingQueues)
            out.push("printer:" + queue);
        return out;
    }

    property var known: []

    onConnectionsChanged: {
        const arrived = root.connections.some(key => root.known.indexOf(key) < 0);
        root.known = root.connections;
        if (arrived)
            root.pulse();
    }

    condition: root.pulsing ? 1 : 0

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
        Glyph {
            anchors.fill: parent
            name: root.leadGlyph
        }
    }

    // The Wi-Fi glyph carries the signal: the arcs the strength reaches are
    // lit, the rest are drawn dim, in the same four steps as the bars in the
    // panel — the dot alone, then one, two and three arcs. A live reading in
    // the glyph's extent, never a figure and never a state colour: a weak
    // signal is not past any threshold (Akusen, 2026-09-27).
    readonly property int wifiArcs: Network.signalBars >= 4 ? 3 : Math.max(0, Network.signalBars - 1)

    component Glyph: Item {
        id: glyph

        required property string name

        readonly property bool wifi: glyph.name === "wifi"

        Icon {
            anchors.fill: parent
            visible: glyph.wifi && root.wifiArcs < 3
            name: "wifi"
            colour: Theme.line
        }

        Icon {
            anchors.fill: parent
            name: glyph.wifi && root.wifiArcs < 3 ? `wifi-signal-${root.wifiArcs}` : glyph.name
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

            delegate: Glyph {
                required property string modelData

                name: modelData
                width: root.glyphSize
                height: width
            }
        }
    }
}
