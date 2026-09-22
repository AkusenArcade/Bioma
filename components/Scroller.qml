import QtQuick
import qs.core

// The mark down the side of a list that is longer than its room.
//
// **It exists only while the list is moving.** At rest the interface does not
// speak, and a bar that stays is a figure nobody asked for — so it fades in
// under the hand and goes again when the list stops. A list that fits shows
// nothing at all.
//
// It is not a control: nothing here answers a press. It reports where in the
// list the eye is, which is a measurement, and it is the same measurement in
// every list in the shell — the process table, the workspace list, the
// launcher's results, the settings catalogue.
//
// The caller gives it the list and places it across the axis; it takes its
// own length and position from what the list is doing.
Rectangle {
    id: root

    property Flickable flick: null
    property real factor: 1

    readonly property bool longer: root.flick !== null
                                 && root.flick.contentHeight > root.flick.height

    z: 1
    width: 3 * factor
    radius: width / 2
    color: Theme.line
    antialiasing: true

    visible: root.longer
    opacity: root.flick && (root.flick.moving || root.flick.flicking || root.flick.dragging)
             ? 1 : 0

    // As long as the visible share of the list, and never so short that it
    // stops reading as a bar.
    height: root.longer
            ? Math.max(root.width * 4,
                       root.flick.height * root.flick.height
                       / Math.max(1, root.flick.contentHeight))
            : 0

    y: (root.flick ? root.flick.y : 0)
       + (root.longer
          ? (root.flick.contentY / (root.flick.contentHeight - root.flick.height))
            * (root.flick.height - root.height)
          : 0)

    Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
}
