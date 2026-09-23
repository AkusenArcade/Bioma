pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Where the monitors are, relative to each other.
//
// Each output is a rectangle drawn to scale, with its name and its mode on two
// lines in the middle — centred, so they read at any size. **Dragged and
// snapped**, including one below the other: a column is as common as a row,
// and the area is shaped to hold either. While a rectangle moves, the edges
// and centres it could line up with pull it in, and the line it has snapped to
// is drawn across the area — the guide is the snap, so it is there only while
// something is snapping.
//
// Let go and the layout is written: positions in logical units, the top-left
// monitor at the origin, into niri's own `output` sections. niri re-reads its
// configuration and moves the desktop, and the rectangles are then drawn from
// what niri reports, not from where the hand left them. Two monitors may not
// overlap — niri would quietly move one — so a drop that overlaps goes back.
//
// Below the area, the chosen monitor: its name, whether it is the one niri
// focuses at startup — niri's only notion of a primary output — and its scale.
//
// See docs/design/CELLS.md §12.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property real footerHeight: 44 * factor
    readonly property real margin: 36 * factor
    readonly property real snapDistance: 12 * factor

    readonly property var outputs: Monitors.outputs

    // The monitor being looked at, shared with the Structure page: choosing
    // one there and coming here should be looking at the same screen.
    readonly property string chosen: {
        const wanted = root.cell ? root.cell.monitor : "";
        for (const output of root.outputs)
            if (output.name === wanted)
                return wanted;
        return root.outputs.length > 0 ? root.outputs[0].name : "";
    }

    readonly property var chosenOutput: Monitors.outputOf(root.chosen)

    function choose(name) {
        if (root.cell)
            root.cell.monitor = name;
    }

    Component.onCompleted: Monitors.refresh()

    // ---- The layout, as drawn ------------------------------------------------

    // Where each monitor is while the hand has it, in logical units. Empty
    // otherwise: at rest, everything is drawn from what niri reports.
    property var moving: ({})
    property string held: ""

    function positionOf(output) {
        const moved = root.moving[output.name];
        return moved ? moved : { "x": output.x, "y": output.y };
    }

    // The scale and offset from logical units to the area. Frozen while
    // something is carried: a canvas that refits itself under the pointer
    // moves the very thing being aimed at.
    property var frozen: null

    readonly property var fit: {
        if (root.frozen)
            return root.frozen;
        if (root.outputs.length === 0 || area.width <= 0)
            return { "scale": 1, "x": 0, "y": 0, "minX": 0, "minY": 0 };

        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const output of root.outputs) {
            minX = Math.min(minX, output.x);
            minY = Math.min(minY, output.y);
            maxX = Math.max(maxX, output.x + output.width);
            maxY = Math.max(maxY, output.y + output.height);
        }
        const width = maxX - minX, height = maxY - minY;
        const scale = Math.min((area.width - 2 * root.margin) / width,
                               (area.height - 2 * root.margin) / height);
        return {
            "scale": scale,
            "x": (area.width - width * scale) / 2,
            "y": (area.height - height * scale) / 2,
            "minX": minX,
            "minY": minY
        };
    }

    function toArea(x, y) {
        return { "x": root.fit.x + (x - root.fit.minX) * root.fit.scale,
                 "y": root.fit.y + (y - root.fit.minY) * root.fit.scale };
    }

    function toLogical(x, y) {
        return { "x": (x - root.fit.x) / root.fit.scale + root.fit.minX,
                 "y": (y - root.fit.y) / root.fit.scale + root.fit.minY };
    }

    // ---- Snapping --------------------------------------------------------------
    //
    // Per axis, the nearest of: this edge against that edge (side by side, or
    // one below the other), this edge in line with that edge, centre in line
    // with centre. Within reach it wins; the guide is where it snapped.

    property var guideX: null
    property var guideY: null

    function snapped(name, x, y) {
        const self = root.outputs.find(output => output.name === name);
        const reach = root.snapDistance / root.fit.scale;
        let bestX = null, bestY = null;

        const consider = (best, value, target, line) =>
            Math.abs(value - target) <= reach
                && (best === null || Math.abs(value - target) < Math.abs(best.delta))
                ? { "delta": target - value, "line": line } : best;

        for (const other of root.outputs) {
            if (other.name === name)
                continue;
            const left = other.x, right = other.x + other.width, middle = other.x + other.width / 2;
            const top = other.y, bottom = other.y + other.height, centre = other.y + other.height / 2;

            bestX = consider(bestX, x, right, right);
            bestX = consider(bestX, x + self.width, left, left);
            bestX = consider(bestX, x, left, left);
            bestX = consider(bestX, x + self.width, right, right);
            bestX = consider(bestX, x + self.width / 2, middle, middle);

            bestY = consider(bestY, y, bottom, bottom);
            bestY = consider(bestY, y + self.height, top, top);
            bestY = consider(bestY, y, top, top);
            bestY = consider(bestY, y + self.height, bottom, bottom);
            bestY = consider(bestY, y + self.height / 2, centre, centre);
        }

        root.guideX = bestX ? bestX.line : null;
        root.guideY = bestY ? bestY.line : null;
        return { "x": Math.round(x + (bestX ? bestX.delta : 0)),
                 "y": Math.round(y + (bestY ? bestY.delta : 0)) };
    }

    function overlaps(positions) {
        const boxes = root.outputs.map(output => ({
            "x": positions[output.name].x, "y": positions[output.name].y,
            "w": output.width, "h": output.height
        }));
        for (let i = 0; i < boxes.length; i++)
            for (let j = i + 1; j < boxes.length; j++) {
                const a = boxes[i], b = boxes[j];
                if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h)
                    return true;
            }
        return false;
    }

    property string refusal: ""

    function take(name) {
        root.frozen = root.fit;
        root.held = name;
        root.refusal = "";
        root.choose(name);
    }

    function carry(name, x, y) {
        const next = Object.assign({}, root.moving);
        next[name] = root.snapped(name, x, y);
        root.moving = next;
    }

    // Let go: the whole layout, moved so its top-left is the origin, and
    // written if anything actually moved.
    function drop() {
        const positions = {};
        for (const output of root.outputs)
            positions[output.name] = root.positionOf(output);

        root.held = "";
        root.guideX = null;
        root.guideY = null;

        if (root.overlaps(positions)) {
            root.refusal = "Monitors cannot overlap";
            root.moving = ({});
            root.frozen = null;
            return;
        }

        let minX = Infinity, minY = Infinity;
        for (const name in positions) {
            minX = Math.min(minX, positions[name].x);
            minY = Math.min(minY, positions[name].y);
        }
        for (const name in positions)
            positions[name] = { "x": positions[name].x - minX, "y": positions[name].y - minY };

        // Put back where it was: nothing to write, and nothing from niri
        // will come to release the frozen canvas.
        const moved = root.outputs.some(output =>
            positions[output.name].x !== output.x || positions[output.name].y !== output.y);
        if (!moved) {
            root.moving = ({});
            root.frozen = null;
            return;
        }

        Monitors.place(positions);
    }

    // What niri reports next is the layout from then on.
    Connections {
        target: Monitors
        function onLiveChanged() {
            if (root.held.length > 0)
                return;
            root.moving = ({});
            root.frozen = null;
        }
        function onErrorChanged() {
            if (Monitors.error.length > 0 && root.held.length === 0) {
                root.moving = ({});
                root.frozen = null;
            }
        }
    }

    // ---- The area ----------------------------------------------------------------

    Well {
        id: area

        metrics: root.metrics
        inset: 6 * root.factor
        width: parent.width
        height: parent.height - root.footerHeight

        // The guides, only while something is snapping to them.
        Rectangle {
            visible: root.guideX !== null
            x: root.guideX !== null ? Math.round(root.toArea(root.guideX, 0).x) : 0
            y: 0
            width: Metrics.crisp(1, Screen.devicePixelRatio)
            height: area.height
            color: Qt.alpha(Theme.primary, 0.6)
        }

        Rectangle {
            visible: root.guideY !== null
            x: 0
            y: root.guideY !== null ? Math.round(root.toArea(0, root.guideY).y) : 0
            width: area.width
            height: Metrics.crisp(1, Screen.devicePixelRatio)
            color: Qt.alpha(Theme.primary, 0.6)
        }

        Repeater {
            model: root.outputs

            delegate: Item {
                id: monitor

                required property var modelData

                readonly property bool isChosen: root.chosen === monitor.modelData.name
                readonly property bool carried: root.held === monitor.modelData.name
                readonly property var at: root.toArea(root.positionOf(monitor.modelData).x,
                                                      root.positionOf(monitor.modelData).y)

                x: monitor.at.x
                y: monitor.at.y
                width: monitor.modelData.width * root.fit.scale
                height: monitor.modelData.height * root.fit.scale
                z: monitor.carried ? 2 : 1

                // Settling where niri put it, not jumping there.
                Behavior on x {
                    enabled: !monitor.carried
                    NumberAnimation {
                        duration: Timing.transition
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Timing.easeOpenFlat
                    }
                }

                Behavior on y {
                    enabled: !monitor.carried
                    NumberAnimation {
                        duration: Timing.transition
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Timing.easeOpenFlat
                    }
                }

                // Inset, so two monitors that touch read as two and not as
                // one shape with a line through it.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2 * root.factor
                    radius: 10 * root.factor
                    antialiasing: true
                    color: Qt.alpha(Theme.lift(Theme.background,
                                               monitor.isChosen ? 0.06 : 0.02), 0.9)
                    border.width: Metrics.crisp(monitor.isChosen ? 1.5 : Metrics.rimWidth,
                                                Screen.devicePixelRatio)
                    border.color: monitor.isChosen ? Theme.primary : Theme.line

                    Behavior on border.color { ColorAnimation { duration: Timing.transition } }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 16 * root.factor
                    spacing: 4 * root.factor

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: monitor.modelData.name
                        color: monitor.isChosen ? Theme.text : Theme.textMuted
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontSecondary,
                            "weight": monitor.isChosen ? Typography.weightTitle
                                                       : Typography.weightLabel,
                            "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                                 Typography.labelTracking)
                        })
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: monitor.modelData.modeWidth + " × " + monitor.modelData.modeHeight
                              + " · " + Math.round(monitor.modelData.refresh) + " Hz"
                        color: Theme.textMuted
                        font: Typography.tabular(Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                 Typography.labelTracking)
                        }))
                    }
                }

                TapHandler {
                    onTapped: root.choose(monitor.modelData.name)
                }

                // Carried from where it was touched, not by its middle.
                DragHandler {
                    id: drag

                    target: null
                    enabled: !Monitors.busy

                    property real grabX: 0
                    property real grabY: 0

                    onActiveChanged: {
                        if (active) {
                            const here = area.mapFromItem(null, centroid.scenePosition.x,
                                                          centroid.scenePosition.y);
                            drag.grabX = here.x - monitor.x;
                            drag.grabY = here.y - monitor.y;
                            root.take(monitor.modelData.name);
                        } else {
                            root.drop();
                        }
                    }

                    onCentroidChanged: {
                        if (!active)
                            return;
                        const here = area.mapFromItem(null, centroid.scenePosition.x,
                                                      centroid.scenePosition.y);
                        const logical = root.toLogical(here.x - drag.grabX, here.y - drag.grabY);
                        root.carry(monitor.modelData.name, logical.x, logical.y);
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.outputs.length === 0
            text: "Asking niri…"
            color: Theme.textFaint
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }

    // ---- The chosen one ------------------------------------------------------

    Item {
        id: foot

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.footerHeight

        Text {
            id: chosenName

            anchors.left: parent.left
            anchors.leftMargin: 4 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: root.chosen
            color: Theme.text
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontLabel,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.metrics.fontLabel,
                                                     Typography.labelTracking)
            })
        }

        // What went wrong, in the one place that says anything here.
        Text {
            anchors.left: chosenName.right
            anchors.leftMargin: 14 * root.factor
            anchors.right: role.left
            anchors.rightMargin: 14 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.refusal.length > 0 ? root.refusal : Monitors.error
            color: Theme.alert
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontMeta
        }

        Segmented {
            id: role

            anchors.right: scaleLabel.left
            anchors.rightMargin: 14 * root.factor
            anchors.verticalCenter: parent.verticalCenter

            metrics: root.metrics
            fontSize: root.metrics.fontMeta
            buttonHeight: 26 * root.factor
            buttonPadding: 14 * root.factor

            current: root.chosenOutput && root.chosenOutput.primary ? "primary" : "secondary"

            options: [
                { "key": "primary", "label": "Primary", "dimmed": Monitors.busy },
                { "key": "secondary", "label": "Secondary", "dimmed": Monitors.busy }
            ]

            onChose: key => {
                if (Monitors.busy || !root.chosenOutput)
                    return;
                if (key === "primary")
                    Monitors.makePrimary(root.chosen);
                else if (root.chosenOutput.primary)
                    Monitors.makePrimary("");
            }
        }

        Text {
            id: scaleLabel

            anchors.right: parent.right
            anchors.rightMargin: 4 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: root.chosenOutput ? "scale " + root.chosenOutput.scale.toFixed(1) : ""
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }
}
