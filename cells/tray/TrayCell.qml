import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// What other programs put on the shell.
//
// The only cell whose content belongs to somebody else: an application
// registers a StatusNotifierItem and hands over an icon drawn in its own style.
// The shell carries it without pretending otherwise — PRD §6.4 says the icons
// stay third-party whatever we do — so the row adds nothing of its own except
// the one thing that is the shell's to say: which of them is asking for
// attention.
//
// It exists only while something is in it. An empty tray is not a tray with
// nothing in it, it is no tray.
//
// The gestures are the protocol's, not ours: a press activates, the middle
// button is the secondary action, the wheel scrolls, and an item that says it
// has only a menu gets its menu instead of an activation it does not have.
Cell {
    id: root

    domain: "tray"

    readonly property real glyphSize: 18 * metrics.factor
    readonly property real spacing: 12 * metrics.factor

    readonly property var items: Tray.items

    paddingLeading: (metrics.cellHeight - glyphSize) / 2 + 2 * metrics.factor
    paddingTrailing: paddingLeading

    contentWidth: Math.max(glyphSize,
                           root.items.length * glyphSize
                           + Math.max(0, root.items.length - 1) * root.spacing)

    // Conditional, it is there from the moment an item changes state until
    // the pointer has been over it — somebody has seen it — and then for the
    // dwell after the pointer leaves.
    property bool calling: false

    Variants {
        model: root.items

        Connections {
            required property var modelData
            target: modelData
            function onStatusChanged() {
                if (root.settled)
                    root.calling = true;
            }
        }
    }

    onHoveredChanged: if (root.hovered) root.calling = false

    condition: root.calling ? 1 : 0

    // Which item's menu is open, if any. The cell opens because an item was
    // asked about, never on its own: a tray that opened as a whole would be
    // answering for applications that were not pressed.
    property var chosen: null

    opensOnTap: false
    claimsFocus: true

    onOpenChanged: if (!root.open) root.chosen = null

    function show(item) {
        if (!item || !item.hasMenu)
            return;
        root.chosen = item;
        root.open = true;
    }

    function press(item) {
        if (Tray.opens(item))
            root.show(item);
        else
            Tray.activate(item);
    }

    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("TrayMenu.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
    }

    // ---- The row -------------------------------------------------------------

    Row {
        anchors.centerIn: parent
        spacing: root.spacing

        Repeater {
            model: root.items

            delegate: Item {
                id: entry

                required property var modelData

                readonly property bool attending: Tray.attending(entry.modelData)
                readonly property string source: Tray.iconFor(entry.modelData)
                readonly property bool showing: root.chosen === entry.modelData

                width: root.glyphSize
                height: root.glyphSize

                // The shell's one word about somebody else's icon: this is the
                // one asking. A ring rather than a tint — the icon is not ours
                // to recolour.
                Ring {
                    anchors.centerIn: parent
                    width: parent.width + 8 * root.metrics.factor
                    height: width
                    visible: entry.attending || entry.showing
                    radius: width / 2
                    thickness: Metrics.crisp(1.5 * root.metrics.factor, Screen.devicePixelRatio)
                    colour: entry.attending ? Theme.alert : Theme.primary
                }

                Image {
                    anchors.fill: parent
                    visible: entry.source !== ""
                    source: entry.source
                    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                // A name the icon theme does not have is a chequerboard from
                // the image provider rather than a failure, so an icon that
                // did not resolve is never asked for — the glyph stands in.
                Icon {
                    anchors.centerIn: parent
                    visible: entry.source === ""
                    width: parent.width
                    height: width
                    name: "app-fallback"
                    colour: Theme.textMuted
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.press(entry.modelData)
                }

                // A touch carries no button and Qt passes it to every
                // TapHandler; only the pointer may ask for the other two.
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onTapped: root.show(entry.modelData)
                }

                TapHandler {
                    acceptedButtons: Qt.MiddleButton
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onTapped: Tray.secondary(entry.modelData)
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => Tray.scroll(entry.modelData,
                                                  event.angleDelta.y > 0 ? 1 : -1)
                }
            }
        }
    }
}
