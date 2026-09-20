import QtQuick
import qs.core

// A well holds rows inside a panel: a darker flat surface, concentric with the
// panel that contains it, and the one place scrolling may be clipped.
//
// Clip the **well**, never the panel: any clipping on a surface that carries
// the rim eats it, which is exactly how the outline vanished the first time.
Rectangle {
    id: root

    property var metrics: Metrics.step("normal")

    // Concentric by construction: a well inset by `inset` inside a panel of
    // radius R takes R − inset.
    property real inset: 10 * metrics.factor
    radius: Metrics.innerRadius(metrics.radiusPanel, inset)

    color: Qt.alpha(Theme.lift(Theme.background, -0.01), 0.8)
    antialiasing: true
    clip: true
}
