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
// While the setup is under way the same composition holds its steps instead:
// the capsules are the steps, each line saying what was chosen once it is,
// and the panel ends in BACK and NEXT (docs/design/SETUP.md). A wizard with a
// window of its own would be the one part of the shell not speaking its
// language.
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // Wide and tall enough for a glyph, a name and a line saying what is
    // inside (Akusen's mockup, 2026-09-29): the glyphs give the column an
    // order the eye can hold before it reads.
    readonly property real capsuleWidth: 240 * factor
    readonly property real capsuleHeight: 64 * factor
    readonly property real capsulePitch: 76 * factor
    readonly property real glyphSize: 26 * factor
    readonly property real threadLength: metrics.gap

    readonly property real rowHeight: 44 * factor
    readonly property real listRow: 38 * factor
    readonly property real padding: 14 * factor

    readonly property var categories: [
        { "key": "structure", "label": "STRUCTURE", "glyph": "structure",
          "hint": "membranes, tissues, order", "width": 644 },
        { "key": "cells", "label": "CELLS", "glyph": "cells",
          "hint": "options and visibility", "width": 560 },
        { "key": "organisms", "label": "ORGANISMS", "glyph": "organisms",
          "hint": "on the desktop, by hand", "width": 560 },
        { "key": "appearance", "label": "APPEARANCE", "glyph": "appearance",
          "hint": "opacity, blur, radius, scale", "width": 440 },
        { "key": "monitors", "label": "MONITORS", "glyph": "monitors",
          "hint": "position, scale, snapping", "width": 720 },
        { "key": "keybinds", "label": "KEYBINDS", "glyph": "keyboard",
          "hint": "shortcuts · niri.kdl", "width": 560 },
        { "key": "session", "label": "SESSION", "glyph": "lock",
          "hint": "locking, power profile", "width": 540 }
    ]

    // The setup's steps, or the categories.
    readonly property bool setup: root.cell ? root.cell.inSetup === true : false
    readonly property var entries: root.setup ? Setup.steps : root.categories

    readonly property string chosen: root.setup ? Setup.step
                                   : root.cell ? root.cell.category : "appearance"

    readonly property int chosenIndex: {
        for (let i = 0; i < root.entries.length; i++)
            if (root.entries[i].key === root.chosen)
                return i;
        return 0;
    }

    function choose(key) {
        if (root.setup)
            Setup.go(key);
        else if (root.cell)
            root.cell.category = key;
    }

    readonly property real panelWidth: root.entries[root.chosenIndex].width * factor
    // One height for every category, and tall enough that none of them
    // scrolls as a page: Structure is the tallest, with the floating places
    // between its two edges and three rows of cell chips under them.
    readonly property real panelHeight: 540 * factor

    readonly property real columnHeight: root.entries.length * capsulePitch - (capsulePitch - capsuleHeight)

    implicitWidth: capsuleWidth + threadLength + panelWidth
    implicitHeight: Math.max(columnHeight, panelHeight)

    width: implicitWidth
    height: implicitHeight

    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    // ---- The cascade --------------------------------------------------------

    // Every shape that arrives in order: the capsules, the thread, the
    // panel. The stagger's span is measured from this — a cascade told it has
    // three shapes when it has seven never finishes the last of them.
    readonly property int shapeCount: root.entries.length + 2

    // The composition keeps its capsules on the left wherever the cell is, so
    // which shape comes first depends on what the cell's thread lands on. At
    // the start of an edge it lands on the column, and the capsules come out
    // first and feed the panel. At the end — or centred — it lands on the
    // panel, and the panel has to come out of the cell first: grown from the
    // column, it opened towards the cell and closed away from it, retracting
    // to the far side of the screen (Akusen, 2026-09-28).
    readonly property real panelX: root.capsuleWidth + root.threadLength
    readonly property bool fromPanel: root.cell ? root.cell.threadX > root.panelX : false

    readonly property int panelStage: root.fromPanel ? 0 : root.entries.length + 1
    readonly property int linkStage: root.fromPanel ? 1 : root.entries.length

    function capsuleStage(index) {
        return root.fromPanel ? index + 2 : index;
    }

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
            // The opening curve run backwards is not a closing curve: it
            // starts fast and ends slow, so the shapes fell out of the
            // composition in the first fifty milliseconds and then crawled the
            // rest of the way. Closing takes the closing curve — it opens
            // calmly and closes quickly.
            cascade.easing.bezierCurve = root.cell.open ? Timing.easeOpenFlat
                                                     : Timing.easeClose;
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
            model: root.entries

            delegate: Panel {
                id: capsule

                required property var modelData
                required property int index

                metrics: root.metrics
                radius: Metrics.radiusFor(root.capsuleHeight, root.metrics)
                padding: 0
                fixedWidth: root.capsuleWidth
                fixedHeight: root.capsuleHeight
                growth: root.stage(root.capsuleStage(capsule.index))
                contentReady: root.stage(root.capsuleStage(capsule.index)) > 0.999

                anchorX: 0
                anchorY: capsule.index * root.capsulePitch
                // Fed by the panel, a capsule comes out of the side the thread
                // reaches it from.
                nodeX: root.fromPanel ? root.capsuleWidth : root.capsuleWidth / 2
                nodeY: capsule.index * root.capsulePitch + root.capsuleHeight / 2

                readonly property bool chosen: root.chosen === capsule.modelData.key

                // A category is a stop, and Enter chooses it as a press does.
                readonly property bool navigable: true

                function activate() {
                    root.choose(capsule.modelData.key);
                }

                // In the setup, what was chosen replaces what the step is
                // about, and the glyph says whether the step wants attention.
                readonly property string outcome: root.setup ? (Setup.outcomes[capsule.modelData.key] || "") : ""
                readonly property string state: root.setup ? Setup.stateOf(capsule.modelData.key) : "muted"

                // The capsule has no padding, so the mark sits inside its rim.
                KeyMark {
                    stop: capsule
                    factor: root.factor
                    outset: -4 * root.factor
                    radius: Math.max(0, capsule.radius - 4 * root.factor)
                }

                // The glyph, then the name and what is inside, in the session
                // menu's arrangement. The chosen one says so by being where
                // the thread starts; here it only carries more light — the
                // glyph takes the primary gradient, as an active control's
                // does, and the name the primary.
                Icon {
                    id: glyph

                    anchors.left: parent.left
                    anchors.leftMargin: 21 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.glyphSize
                    height: width
                    name: capsule.modelData.glyph
                    gradient: capsule.chosen
                    colour: capsule.state === "alert" ? Theme.alert
                          : capsule.state === "active" ? Theme.active : Theme.textMuted
                }

                Column {
                    anchors.left: glyph.right
                    anchors.leftMargin: 16 * root.factor
                    anchors.right: parent.right
                    anchors.rightMargin: 20 * root.factor
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3 * root.factor

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: capsule.modelData.label
                        color: capsule.chosen ? Theme.primary : Theme.text
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontLabel,
                            "weight": capsule.chosen ? Typography.weightTitle : Typography.weightLabel,
                            "letterSpacing": Typography.tracking(root.metrics.fontLabel,
                                                                 Typography.labelTracking)
                        })
                    }

                    // What is inside is said in words, so it is the human voice.
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: capsule.outcome.length > 0 ? capsule.outcome : capsule.modelData.hint
                        color: capsule.outcome.length > 0 ? Theme.text : Theme.textMuted
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }
                }

                TapHandler {
                    onTapped: root.choose(capsule.modelData.key)
                }
            }
        }
    }

    // The thread leaves the chosen capsule and feeds the panel: it moves when
    // the choice does, which is the whole of the selection.
    Thread {
        id: link

        vertical: false
        reversed: root.fromPanel
        progress: root.stage(root.linkStage)
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
        growth: root.stage(root.panelStage)
        contentReady: root.stage(root.panelStage) > 0.999

        anchorX: root.panelX
        anchorY: (root.height - root.panelHeight) / 2
        // Out of the cell's thread when that is where it lands, out of the
        // chosen capsule's thread otherwise.
        nodeX: root.fromPanel
               ? Math.min(root.cell.threadX, root.panelX + root.panelWidth)
               : root.panelX
        nodeY: root.fromPanel
               ? (root.upward ? anchorY + root.panelHeight : anchorY)
               : link.y + link.height / 2

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
                anchors.bottomMargin: root.setup ? footer.height + root.padding : 0

                source: {
                    if (root.setup) {
                        // The step as the list has it, so a choice made a
                        // moment before the list caught up loads nothing.
                        const key = root.entries[root.chosenIndex].key;
                        if (!Setup.steps.some(step => step.key === key))
                            return "";
                        return Qt.resolvedUrl("Setup" + key.charAt(0).toUpperCase() + key.slice(1) + ".qml");
                    }
                    if (root.chosen === "appearance")
                        return Qt.resolvedUrl("SettingsAppearance.qml");
                    if (root.chosen === "cells")
                        return Qt.resolvedUrl("SettingsCells.qml");
                    if (root.chosen === "structure")
                        return Qt.resolvedUrl("SettingsStructure.qml");
                    if (root.chosen === "organisms")
                        return Qt.resolvedUrl("SettingsOrganisms.qml");
                    if (root.chosen === "monitors")
                        return Qt.resolvedUrl("SettingsMonitors.qml");
                    if (root.chosen === "keybinds")
                        return Qt.resolvedUrl("SettingsKeybinds.qml");
                    if (root.chosen === "session")
                        return Qt.resolvedUrl("SettingsSession.qml");
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

            // The setup's way through: SKIP SETUP at the start, BACK and NEXT
            // at the end, DONE in NEXT's place on the last step. The capsules
            // can be pressed in any order, so NEXT is a convenience, not a
            // gate.
            Item {
                id: footer

                visible: root.setup
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 26 * root.factor

                Text {
                    id: skip

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SKIP SETUP"
                    color: skipHover.hovered ? Theme.primary : Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })

                    readonly property bool navigable: root.setup

                    function activate() {
                        Setup.finish();
                    }

                    KeyMark {
                        factor: root.factor
                        outset: 4 * root.factor
                    }

                    HoverHandler { id: skipHover }
                    TapHandler { onTapped: Setup.finish() }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.factor

                    // Nothing comes before the welcome, so there is no way
                    // back from it; the way forward is the start.
                    Choice {
                        metrics: root.metrics
                        label: "BACK"
                        visible: Setup.stepIndex > 0
                        onActivated: Setup.back()
                    }

                    Choice {
                        metrics: root.metrics
                        label: Setup.last ? "DONE" : Setup.stepIndex === 0 ? "START" : "NEXT"
                        kind: "primary"
                        onActivated: Setup.last ? Setup.finish() : Setup.next()
                    }
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
