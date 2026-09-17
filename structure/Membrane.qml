import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// One edge of one monitor. Tissues anchored to it share its length.
//
// `reserve_space`, `auto_hide` and `scale` govern every tissue and cell on this
// membrane, the dock included. Hiding a membrane hides everything on it.
//
// Phase 0 skeleton — see PRD §4.1.
PanelWindow {
    id: root

    required property var modelData          // the Quickshell screen
    required property string edge            // "top" | "bottom" | "left" | "right"

    property bool reserveSpace: false
    property bool autoHide: false
    property string scaleStep: "normal"
    property list<Item> tissues: []

    readonly property var metrics: Scale.step(scaleStep)
    readonly property bool horizontal: edge === "top" || edge === "bottom"

    // Geometric rule, no exceptions: only horizontal edges may reserve.
    readonly property bool reserving: reserveSpace && horizontal && !autoHide

    // True while the pointer is at the edge or inside the membrane.
    property bool revealed: !autoHide

    screen: modelData
    color: "transparent"

    anchors {
        top: edge !== "bottom"
        bottom: edge !== "top"
        left: edge !== "right"
        right: edge !== "left"
    }

    // When space is reserved it stays reserved even while a conditional cell
    // inside is invisible — the "slot" model, so windows never reflow.
    exclusiveZone: reserving ? implicitThickness : 0

    readonly property int implicitThickness: metrics.cellHeight + metrics.tissuePadding * 2

    implicitHeight: horizontal ? implicitThickness : 0
    implicitWidth: horizontal ? 0 : implicitThickness

    // An auto-hidden membrane must remain present as a surface with a few-pixel
    // reveal zone — destroying and recreating it would leave nothing to catch
    // the pointer at the edge. The reveal zone stays inside the surface bounds:
    // a bug Prisma already hit and fixed.
    readonly property int revealZone: 2

    // TODO Phase 0: slide transform driven by `revealed`, hide timer from
    // Timing.autoHide, and percentage-based placement of `tissues` along the
    // membrane's length (ceilings, not reservations; warn above 100 in total).
}
