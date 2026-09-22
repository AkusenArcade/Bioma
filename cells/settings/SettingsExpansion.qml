import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.cells
import qs.services

// Settings, opened: the categories on one side and the chosen one on the
// other, with a thread between them.
//
// **The selection is the thread.** There is no "selected" outline to invent —
// the chosen capsule is the one the thread leaves from, and the others stay
// identical. It is the one thing in this shell that already means "this feeds
// that", and it applies to every two-level case that comes after.
//
// The height is fixed and the panel scrolls inside it: a settings surface that
// changes height with every category is unbearable to move around in. The
// width is not — a category is as wide as it needs, and Structure needs more
// than Appearance.
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property real capsuleWidth: 160 * factor
    readonly property real capsuleHeight: 44 * factor
    readonly property real capsulePitch: 52 * factor
    readonly property real threadLength: metrics.gap

    readonly property real rowHeight: 44 * factor
    readonly property real listRow: 38 * factor
    readonly property real padding: 14 * factor

    readonly property var categories: [
        { "key": "appearance", "label": "APPEARANCE", "width": 440 },
        { "key": "structure", "label": "STRUCTURE", "width": 720 },
        { "key": "cells", "label": "CELLS", "width": 560 },
        { "key": "monitors", "label": "MONITORS", "width": 720 },
        { "key": "keybinds", "label": "KEYBINDS", "width": 560 }
    ]

    readonly property string chosen: root.cell ? root.cell.category : "appearance"

    readonly property int chosenIndex: {
        for (let i = 0; i < root.categories.length; i++)
            if (root.categories[i].key === root.chosen)
                return i;
        return 0;
    }

    readonly property real panelWidth: root.categories[root.chosenIndex].width * factor
    readonly property real panelHeight: 420 * factor

    readonly property real columnHeight: root.categories.length * capsulePitch - (capsulePitch - capsuleHeight)

    implicitWidth: capsuleWidth + threadLength + panelWidth
    implicitHeight: Math.max(columnHeight, panelHeight)

    width: implicitWidth
    height: implicitHeight

    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    // ---- The cascade --------------------------------------------------------

    // Every shape that arrives in order: the five capsules, the thread, the
    // panel. The stagger's span is measured from this — a cascade told it has
    // three shapes when it has seven never finishes the last of them.
    readonly property int shapeCount: root.categories.length + 2

    property real cascade: 0

    function stage(index) {
        return Timing.stage(root.cascade, index, root.shapeCount);
    }

    Connections {
        target: root.cell
        function onOpenChanged() {
            cascade.stop();
            cascade.to = root.cell.open ? 1 : 0;
            cascade.duration = root.cell.open ? Timing.open : Timing.close;
            cascade.start();
        }
    }

    NumberAnimation {
        id: cascade
        target: root
        property: "cascade"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    onCellChanged: {
        if (root.cell && root.cell.open) {
            cascade.to = 1;
            cascade.restart();
        }
    }

    // ---- The categories ------------------------------------------------------

    Item {
        id: column

        width: root.capsuleWidth
        height: root.columnHeight
        y: (root.height - height) / 2

        Repeater {
            model: root.categories

            delegate: Panel {
                id: capsule

                required property var modelData
                required property int index

                metrics: root.metrics
                radius: Metrics.radiusFor(root.capsuleHeight, root.metrics)
                padding: 0
                fixedWidth: root.capsuleWidth
                fixedHeight: root.capsuleHeight
                growth: root.stage(capsule.index)
                contentReady: root.stage(capsule.index) > 0.999

                anchorX: 0
                anchorY: capsule.index * root.capsulePitch
                nodeX: root.capsuleWidth / 2
                nodeY: capsule.index * root.capsulePitch + root.capsuleHeight / 2

                Text {
                    anchors.centerIn: parent
                    text: capsule.modelData.label
                    // The chosen one says so by being where the thread starts;
                    // what changes here is only how much light it carries.
                    color: root.chosen === capsule.modelData.key ? Theme.text : Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontLabel,
                        "weight": root.chosen === capsule.modelData.key
                                  ? Typography.weightTitle : Typography.weightLabel,
                        "letterSpacing": Typography.tracking(root.metrics.fontLabel,
                                                             Typography.labelTracking)
                    })
                }

                TapHandler {
                    onTapped: if (root.cell) root.cell.category = capsule.modelData.key
                }
            }
        }
    }

    // The thread leaves the chosen capsule and feeds the panel: it moves when
    // the choice does, which is the whole of the selection.
    Thread {
        id: link

        vertical: false
        progress: root.stage(root.categories.length)
        height: implicitHeight
        width: root.threadLength
        x: root.capsuleWidth
        y: column.y + root.chosenIndex * root.capsulePitch + root.capsuleHeight / 2 - height / 2

        Behavior on y {
            NumberAnimation {
                duration: Timing.transition
                easing.type: Easing.Bezier
                easing.bezierCurve: Timing.easeOpenFlat
            }
        }
    }

    // ---- The page ------------------------------------------------------------

    Panel {
        id: page

        metrics: root.metrics
        padding: root.padding
        fixedWidth: root.panelWidth
        fixedHeight: root.panelHeight
        growth: root.stage(root.categories.length + 1)
        contentReady: root.stage(root.categories.length + 1) > 0.999

        anchorX: root.capsuleWidth + root.threadLength
        anchorY: (root.height - root.panelHeight) / 2
        nodeX: root.capsuleWidth + root.threadLength
        nodeY: link.y + link.height / 2

        Behavior on fixedWidth {
            NumberAnimation {
                duration: Timing.reflow
                easing.type: Easing.Bezier
                easing.bezierCurve: Timing.easeOpenFlat
            }
        }

        HoverHandler {
            onHoveredChanged: if (root.cell) root.cell.panelHovered = hovered
        }

        // No title in the panel. The capsule the thread leaves from already
        // says which category this is, twenty-four pixels away: a heading here
        // would be the same word written twice.
        Item {
            anchors.fill: parent

            Loader {
                id: body

                anchors.fill: parent

                source: {
                    if (root.chosen === "appearance")
                        return Qt.resolvedUrl("SettingsAppearance.qml");
                    if (root.chosen === "cells")
                        return Qt.resolvedUrl("SettingsCells.qml");
                    if (root.chosen === "structure")
                        return Qt.resolvedUrl("SettingsStructure.qml");
                    return "";
                }

                onLoaded: {
                    item.metrics = Qt.binding(() => root.metrics);
                    // A page that keeps state across a close asks the cell for
                    // it; the ones that do not declare no such property.
                    if (item.cell !== undefined)
                        item.cell = root.cell;
                }

                // The categories that are not written yet say so rather than
                // showing an empty panel: a page with nothing in it reads as
                // a page that failed to load.
                Text {
                    anchors.centerIn: parent
                    visible: body.source.toString().length === 0
                    text: "Not built yet"
                    color: Theme.textFaint
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontTitle
                }
            }
        }
    }

    function shapes() {
        const out = [{ "item": page, "radius": page.radius }];
        for (let i = 0; i < column.children.length; i++) {
            const capsule = column.children[i];
            if (capsule && capsule.radius !== undefined && capsule.width > 0)
                out.push({ "item": capsule, "radius": capsule.radius });
        }
        return out;
    }
}
