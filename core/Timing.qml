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

    // A shadow's opacity for a shape at `growth` (0 gone, 1 whole). The shadow
    // leaves before the shape and arrives after it: it is gone by the time the
    // shape is half retracted, and comes in over the second half of the
    // growth. Tied to the growth one for one, the wide blur outlived the
    // shrinking shape and stood alone in the last frames, a halo with nothing
    // in it (Akusen, 2026-09-27).
    function shadowFor(growth) {
        return Math.max(0, Math.min(1, (growth - 0.5) * 2));
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

    // How long a cell that appears at the pointer waits to be told where the
    // pointer is before it gives up and takes the middle of the screen. Not
    // an animation, so the speed setting leaves it alone: the pointer does
    // not answer faster because the shell was asked to move slower.
    readonly property int locate: Config.get("timing.locate", 120)

    // How long the launcher waits after the last letter before it walks the
    // home for files: one walk per word rather than one per keystroke. Not an
    // animation, so not scaled — the disk does not answer slower because the
    // shell was asked to move slower.
    readonly property int search: Config.get("timing.search", 150)

    // How long an event is held as a condition — long enough for the
    // visibility's confirm step to see it, and then the dwell carries the
    // cell. Not an animation, so not scaled.
    readonly property int pulse: Config.get("timing.pulse", 120)

    // How long after start the shell is learning the state of the machine
    // rather than watching it change: the services fill in, the volume goes
    // from nothing to what it is, and none of that is an event a cell should
    // appear for. Not scaled either.
    readonly property int settle: Config.get("timing.settle", 3000)

    // How long after niri's overview opens or closes the membranes declare
    // their blur again. It has to outlast niri's own animation and the cells
    // that leave while it runs; see `Membrane.qml`. Not scaled: niri does not
    // move at Bioma's speed.
    readonly property int overviewSettle: Config.get("timing.overview_settle", 800)

    // How long the on-screen display stays after the last change it shows.
    // A dwell, not an animation, so the speed setting leaves it alone.
    readonly property int osd: Config.get("timing.osd", 1500)

    // How long after dictation has pasted the clipboard stays quiet: the
    // restore of what the user had copied reaches the history a moment later,
    // and it is not a copy the clipboard cell should announce. Not scaled.
    readonly property int hush: Config.get("timing.hush", 1000)

    // How long the greeter's welcome stays before the screen goes dark: long
    // enough to be read once. A dwell too, so the speed setting leaves it alone.
    readonly property int welcome: Config.get("timing.welcome", 900)

    // The welcome's own pace, slower than the shell's: it is a moment that
    // happens once per session, not a response to a hand. Each line opens over
    // `welcomeOpen`, the next starting `welcomeStagger` after it, and the
    // screen darkens over `welcomeFade` (Akusen, 2026-09-27: "softer").
    readonly property int welcomeOpen: scaled(Config.get("timing.welcome_open", 450))
    readonly property int welcomeStagger: scaled(Config.get("timing.welcome_stagger", 100))
    readonly property int welcomeFade: scaled(Config.get("timing.welcome_fade", 1000))

    // Wallpaper crossfade. Slower than a palette change: the picture is the
    // whole screen, and anything quick here reads as a flicker rather than a
    // change of scene.
    readonly property int wallpaper: scaled(Config.get("timing.wallpaper", 600))

    // ---- The cascade -----------------------------------------------------
    //
    // A staggered entrance as a fraction per shape: `cascade` runs 0 to 1 over
    // the whole opening, each shape starts one `stagger` after the one before
    // it, and each grows over `grow`.
    //
    // The span has to hold every phase, so it depends on **how many shapes
    // there are**. Three of them make it `grow + 2 stagger`, which is the
    // figure every expansion was carrying by hand — and a panel with seven
    // shapes that kept that figure left its last two half-grown for as long as
    // it stayed open. Whoever draws a cascade knows its length; the arithmetic
    // belongs here, once.
    function stage(cascade, index, count) {
        const span = root.grow + root.stagger * Math.max(0, count - 1);
        const started = cascade * span - index * root.stagger;
        return Math.max(0, Math.min(1, started / root.grow));
    }

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
