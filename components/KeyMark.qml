import QtQuick
import qs.core

// Where the keyboard is, inside the open cell: the launcher's selection, the
// same fill, drawn behind whatever the arrows have reached.
//
// A fill and never an outline, for the launcher's reason: the lit outline
// means "surface" in this shell, and a row wearing one would read as a cell
// inside a cell. It is there only once a key has asked for it — see
// `Focus.marked` — so a hand on the pointer never sees it.
//
// A stop declares one as its own child. `outset` is how far it reaches past
// the stop, for a control smaller than the hand's target: a slider is a
// 14 px handle on a 3 px track, and a fill that hugged it would be a smudge.
// A row in a clipped list reaches sideways only (`outsetY: 0`), into the
// list's side margins, since above and below it is the clip.
//
// A `Panel` hands what it is given to its content slot, so a mark declared
// in one has the slot for a parent, not the panel: it names its stop.
Rectangle {
    property Item stop: parent
    property real factor: 1
    property real outset: 0
    property real outsetX: outset
    property real outsetY: outset

    anchors.fill: parent
    anchors.leftMargin: -outsetX
    anchors.rightMargin: -outsetX
    anchors.topMargin: -outsetY
    anchors.bottomMargin: -outsetY
    z: -1
    visible: Focus.marked !== null && Focus.marked === stop
    radius: Metrics.shaped(Math.min(height / 2, 14 * factor))
    color: Qt.alpha(Theme.primary, 0.12)
    antialiasing: true
}
