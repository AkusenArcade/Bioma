pragma Singleton

import QtQuick
import Quickshell

// Where the pointer was last seen, and on which output.
//
// Wayland gives a client no way to ask where the pointer is. It tells a
// surface when the pointer enters it, and where — and it tells it on the
// frame the surface appears under a pointer that has not moved, which is what
// makes this usable (checked against niri 26.04: a full-screen surface mapped
// under a still pointer reported it within two pixels of where the cursor was
// drawn). So every surface that covers an output reports what it sees here,
// and a cell that has to appear at the pointer asks for a sighting newer than
// the moment it asked (PRD §8).
//
// Coordinates are the output's own, in logical units: the surfaces that
// report are the size of the output.
Singleton {
    id: root

    property string output: ""
    property real x: 0
    property real y: 0

    // Bumped on every sighting, so a question can tell a fresh answer from
    // one that was already there when it was asked.
    property int seen: 0

    function saw(output, x, y) {
        root.output = output;
        root.x = x;
        root.y = y;
        root.seen++;
    }
}
