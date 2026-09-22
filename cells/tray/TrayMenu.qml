import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// An application's own menu, drawn in the shell's hand.
//
// The entries come from D-Bus — text, an icon name, whether they are checked,
// whether they open a submenu — and the drawing is ours: the same well, the
// same rows, the same voice as everything else the shell lists. A native menu
// dropped in here would be the one surface in the shell wearing another
// system's face.
//
// A submenu replaces the list rather than hanging off it. A menu is already a
// digression, and a second capsule beside the first would be a third thing on
// screen to aim at.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property real panelWidth: 240 * factor
    readonly property real padding: 8 * factor
    readonly property real rowHeight: 32 * factor
    readonly property real headerHeight: 30 * factor
    readonly property int shownRows: 10

    readonly property var item: root.cell ? root.cell.chosen : null

    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    // Where in the menu the eye is. The root handle is the item's own; going
    // into a submenu pushes its handle, and the back row pops it.
    property var trail: []

    readonly property var handle: root.trail.length > 0
                                ? root.trail[root.trail.length - 1].handle
                                : (root.item ? root.item.menu : null)

    readonly property string heading: root.trail.length > 0
                                    ? root.trail[root.trail.length - 1].text
                                    : Tray.nameOf(root.item)

    onItemChanged: root.trail = []

    QsMenuOpener {
        id: opener
        menu: root.handle
    }

    readonly property var entries: opener.children ? opener.children.values : []

    function enter(entry) {
        root.trail = root.trail.concat([{ "handle": entry, "text": entry.text || "" }]);
    }

    function back() {
        const next = root.trail.slice();
        next.pop();
        root.trail = next;
    }

    function choose(entry) {
        if (!entry || entry.isSeparator || !entry.enabled)
            return;
        if (entry.hasChildren) {
            root.enter(entry);
            return;
        }
        entry.triggered();
        if (root.cell)
            root.cell.open = false;
    }

    // ---- Measure -------------------------------------------------------------

    readonly property real listHeight: Math.min(root.shownRows, Math.max(1, root.entries.length))
                                     * root.rowHeight

    readonly property real panelHeight: root.padding * 2 + root.headerHeight
                                      + root.listHeight

    implicitWidth: panelWidth
    implicitHeight: panelHeight

    width: implicitWidth
    height: implicitHeight

    Panel {
        id: panel

        metrics: root.metrics
        padding: root.padding
        targetWidth: root.panelWidth
        targetHeight: root.panelHeight
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        // The composition's own box is placed by the cell; inside it the
        // panel sits at the top whichever way the membrane opens. What
        // changes is the edge it grows *from* — the one nearest the cell.
        anchorX: 0
        anchorY: 0
        nodeX: root.panelWidth / 2
        nodeY: root.upward ? root.panelHeight : 0

        Item {
            anchors.fill: parent

            // Whose menu this is — or, one level in, what was opened. The name
            // is the application's own word for itself, so it keeps the human
            // voice; the way back is a mark, not a word.
            Item {
                id: header

                width: parent.width
                height: root.headerHeight

                Icon {
                    id: back

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.trail.length > 0
                    width: 14 * root.factor
                    height: width
                    name: "chevron-right"
                    colour: backHover.hovered ? Theme.text : Theme.textMuted
                    rotation: 180
                }

                HoverHandler { id: backHover }

                TapHandler {
                    enabled: root.trail.length > 0
                    onTapped: root.back()
                }

                Text {
                    anchors.left: root.trail.length > 0 ? back.right : parent.left
                    anchors.leftMargin: root.trail.length > 0 ? 8 * root.factor : 2 * root.factor
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.heading
                    elide: Text.ElideRight
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }
            }

            Well {
                id: well

                metrics: root.metrics
                inset: 6 * root.factor
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                anchors.bottom: parent.bottom

                ListView {
                    id: list

                    anchors.fill: parent
                    anchors.margins: 4 * root.factor
                    model: root.entries
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    delegate: Item {
                        id: row

                        required property var modelData

                        readonly property bool usable: !row.modelData.isSeparator
                                                    && row.modelData.enabled

                        width: ListView.view.width
                        height: row.modelData.isSeparator ? 9 * root.factor : root.rowHeight

                        // A separator is a rule, not a row: the thinnest the
                        // screen can draw, at the weight of every other line
                        // in the shell.
                        Rectangle {
                            anchors.centerIn: parent
                            visible: row.modelData.isSeparator
                            width: parent.width - 12 * root.factor
                            height: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                            color: Theme.line
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.rightMargin: 2 * root.factor
                            visible: !row.modelData.isSeparator && rowHover.hovered && row.usable
                            radius: Metrics.radiusFor(height, root.metrics)
                            color: Qt.alpha(Theme.primary, 0.12)
                            antialiasing: true
                        }

                        // What the entry says it is: checked, or one of a
                        // set. The same filled mark the shell uses for a
                        // chosen device — the state is the menu's, the mark is
                        // ours, and the shell has one mark for "this one".
                        Rectangle {
                            id: mark

                            anchors.left: parent.left
                            anchors.leftMargin: 8 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator
                                  && row.modelData.checkState === Qt.Checked
                            width: 7 * root.factor
                            height: width
                            radius: width / 2
                            color: Theme.primary
                            antialiasing: true
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8 * root.factor + (mark.visible
                                                                   ? mark.width + 6 * root.factor
                                                                   : 0)
                            anchors.right: chevron.visible ? chevron.left : parent.right
                            anchors.rightMargin: 8 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator
                            text: row.modelData.text || ""
                            elide: Text.ElideRight
                            color: row.usable ? Theme.text : Theme.textFaint
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        Icon {
                            id: chevron

                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.modelData.isSeparator && row.modelData.hasChildren
                            width: 12 * root.factor
                            height: width
                            name: "chevron-right"
                            colour: Theme.textMuted
                        }

                        HoverHandler { id: rowHover }

                        TapHandler {
                            enabled: row.usable
                            onTapped: root.choose(row.modelData)
                        }
                    }
                }

                Scroller {
                    flick: list
                    factor: root.factor
                    x: well.width - width - 4 * root.factor
                }
            }
        }
    }

    function shapes() {
        return [{ "item": panel, "radius": panel.radius }];
    }
}
