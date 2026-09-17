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

    // A cell appearing or disappearing reflows its tissue. This is a design
    // moment, not an incidental animation.
    readonly property int reflow: scaled(Config.get("timing.reflow", 220))

    // Palette changes are animated, never instantaneous.
    readonly property int theme: scaled(Config.get("timing.theme", 400))

    // How long after the pointer leaves before an auto-hiding membrane slides out.
    readonly property int autoHide: scaled(Config.get("timing.auto_hide", 500))

    // Default notification dwell; urgency overrides it, critical never expires.
    readonly property int notification: scaled(Config.get("timing.notification", 5000))

    // Content enters only once its shape has reached its size.
    readonly property int contentFade: scaled(Config.get("timing.content_fade", 120))

    // Small capsules may overshoot. Large panels may not — there it reads as a
    // bounce and conflicts with the intended register.
    readonly property list<real> overshoot: [0.2, 0.9, 0.3, 1.15]
    readonly property list<real> standard: [0.2, 0.0, 0.0, 1.0]
}
