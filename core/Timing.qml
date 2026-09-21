pragma Singleton

import QtQuick
import Quickshell

// The single named timing set. No duration is written anywhere else.
//
// Opening is slower than closing on purpose. Reach the opening figure by
// tightening the cascade, never by shortening an individual growth: each shape
// still grows over roughly `grow`, the phases simply overlap more.
//
// Because every duration passes through here, a user-facing "animation speed"
// setting is one multiplier away.
Singleton {
    id: root

    readonly property real speed: Config.get("timing.speed", 1.0)

    function scaled(base) {
        return Math.round(base * root.speed);
    }

    readonly property int open: scaled(Config.get("timing.open", 250))
    readonly property int close: scaled(Config.get("timing.close", 150))

    // One shape's own growth inside the opening cascade.
    readonly property int grow: scaled(Config.get("timing.grow", 100))

    // Delay between consecutive capsules in a staggered entrance.
    readonly property int stagger: scaled(Config.get("timing.stagger", 16))

    // A state change with no live value behind it: the workspace bars shifting
    // one step, a segmented control's pill sliding to the chosen option. It is
    // an event, not an indicator, and it is still the rest of the time.
    readonly property int transition: scaled(Config.get("timing.transition", 180))

    // Titles rewrite on every browser tab; a reflow triggered by one character
    // of width is motion with nothing behind it. Both wait this long.
    readonly property int debounce: scaled(Config.get("timing.debounce", 180))

    // A cell appearing or disappearing reflows its tissue. This is a design
    // moment, not an incidental animation.
    readonly property int reflow: scaled(Config.get("timing.reflow", 220))

    // Palette changes are animated, never instantaneous, and every surface
    // crosses together.
    readonly property int theme: scaled(Config.get("timing.theme", 250))

    // How long after the pointer leaves before an auto-hiding membrane slides out.
    readonly property int autoHide: scaled(Config.get("timing.auto_hide", 500))

    // Default notification dwell; urgency overrides it, critical never expires.
    readonly property int notification: scaled(Config.get("timing.notification", 5000))

    // Content enters only once its shape has reached its size.
    readonly property int contentFade: scaled(Config.get("timing.content_fade", 120))

    // The loader's round trip: 600 ms out, 600 ms back. The one motion in the
    // shell that runs while nothing is being measured — because the movement
    // *is* the measurement, and it means "no value yet". It stops on the frame
    // the value lands. See docs/design/icons/LOADER.md.
    readonly property int loader: scaled(Config.get("timing.loader", 1200))

    // Wallpaper crossfade. Slower than a palette change: the picture is the
    // whole screen, and anything quick here reads as a flicker rather than a
    // change of scene.
    readonly property int wallpaper: scaled(Config.get("timing.wallpaper", 600))

    // ---- Curves ----------------------------------------------------------
    //
    // In the form QML wants for `easing.bezierCurve`: the two control points
    // followed by the end point. Small capsules may overshoot. Large panels may
    // not — there it reads as a bounce and conflicts with the intended
    // register. Closing never overshoots: it opens calmly, it closes quickly.

    // The loader's own curve, and nothing else's: symmetric, so the segment
    // eases out of each end and crosses the middle at speed. It reads as
    // breathing rather than as a progress bar, which is exactly what it must
    // not be mistaken for.
    readonly property list<real> sweep: [0.45, 0, 0.55, 1, 1, 1]

    readonly property list<real> easeOpen: [0.2, 0.9, 0.3, 1.15, 1, 1]
    readonly property list<real> easeOpenFlat: [0.2, 0.9, 0.3, 1.0, 1, 1]
    readonly property list<real> easeClose: [0.5, 0.0, 0.9, 0.5, 1, 1]
}
