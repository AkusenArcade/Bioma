pragma Singleton

import QtQuick
import Quickshell

// Scale is a discrete step set, not a free value, and it is a membrane
// property — a smaller second monitor can run `compact`.
//
// Scale and density are separate concerns. Wayland reports each surface's
// output scale factor and Qt applies it, so everything here is written as
// though that factor were 1: these are logical units, the equivalent of
// Android `dp`. Scale is the aesthetic preference layered on top; it
// multiplies the density, it does not replace it.
Singleton {
    id: root

    readonly property var steps: ({
        "compact": {
            "factor": 0.85,
            "cellHeight": 24,
            "tissuePadding": 4,
            "gap": 4,
            "fontSize": 12
        },
        "normal": {
            "factor": 1.0,
            "cellHeight": 30,
            "tissuePadding": 6,
            "gap": 6,
            "fontSize": 14
        },
        "comfortable": {
            "factor": 1.15,
            "cellHeight": 36,
            "tissuePadding": 8,
            "gap": 8,
            "fontSize": 15
        }
    })

    function step(name) {
        return root.steps[name] !== undefined ? root.steps[name] : root.steps["normal"];
    }

    // Hairlines, thread strokes and icon strokes must land on whole physical
    // pixels under fractional scaling, or they blur or vanish. Layouts stay
    // fluid — only critical dimensions are rounded.
    function crisp(logical, devicePixelRatio) {
        const ratio = devicePixelRatio > 0 ? devicePixelRatio : 1;
        return Math.max(1, Math.round(logical * ratio)) / ratio;
    }
}
