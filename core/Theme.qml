pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colour, as an animated singleton.
//
// Cells bind to these properties; they never copy a value. That is what lets
// the theme cell retint the whole desktop live while the pointer is still on a
// swatch, and it is why every palette change is animated rather than applied.
//
// Four interface roles come from a theme source — matugen (wallpaper-reactive)
// or a manual palette data file. The three state roles never do: they are a
// semantic code, and a blue wallpaper would turn them into three blues. They
// are declared by hand in a light and a dark variant, because the same hex
// values lose contrast on a light background — amber especially.
//
// Everything else — elevated surfaces, the cell fill, the outline family,
// muted text, shadows, gradients — is derived here, in HSL, from those four.
// Derived roles cost the user nothing and stay coherent by construction. The
// derivations are calibrated so that the shipped palette reproduces the values
// in docs/design/tokens.css; any other palette lands in the same relations.
Singleton {
    id: root

    // ---- Interface roles (theme source) ----------------------------------

    property color background: "#12160F"
    property color text: "#EAF1E6"
    property color primary: "#B9DE6B"
    property color secondary: "#3FBFA0"

    // ---- State roles (fixed, never from matugen) --------------------------

    readonly property color calm: isDark ? stateDark.calm : stateLight.calm
    readonly property color active: isDark ? stateDark.active : stateLight.active
    readonly property color alert: isDark ? stateDark.alert : stateLight.alert

    readonly property var stateDark: Config.get("theme.state.dark", {
        "calm": "#6EE7A6",
        "active": "#F2C14E",
        "alert": "#FF6B5D"
    })
    readonly property var stateLight: Config.get("theme.state.light", {
        "calm": "#2E9C6A",
        "active": "#B37414",
        "alert": "#C43A2E"
    })

    // Load is measured, so it speaks in state colours. A scale the user moves —
    // volume, brightness, colour temperature — is a control and stays primary
    // for its whole travel: red on a slider would mean "past threshold", and
    // turning the volume up is not an alarm.
    //
    // Three states, two boundaries, no dead zone. Flicker around a boundary is
    // cured upstream on the reading — values arrive already smoothed — never
    // with hysteresis here.
    readonly property real thresholdCalm: 0.30
    readonly property real thresholdAlert: 0.80

    function stateFor(load) {
        if (load >= root.thresholdAlert)
            return root.alert;
        if (load >= root.thresholdCalm)
            return root.active;
        return root.calm;
    }

    // ---- Light or dark ----------------------------------------------------

    // Inferred from the background, never configured.
    readonly property real backgroundLuminance: luminance(background)
    readonly property bool isDark: backgroundLuminance < 0.5

    // ---- Derived surfaces -------------------------------------------------

    // Lightness steps away from the background, in the background's own hue:
    // a tinted surface family rather than a grey one laid over a colour.
    readonly property color surface: lift(background, 0.045)
    readonly property color elevated: lift(background, 0.045)
    readonly property color cell: lift(background, 0.075)
    readonly property color wellSurface: lift(background, 0.02)

    readonly property color textMuted: Qt.alpha(text, 0.56)
    readonly property color textFaint: Qt.alpha(text, 0.38)
    readonly property color border: Qt.alpha(text, isDark ? 0.09 : 0.14)

    readonly property color shadow: Qt.alpha("#000000", isDark ? 0.45 : 0.22)
    readonly property color shadowFloat: Qt.alpha("#000000", isDark ? 0.60 : 0.30)

    // ---- The outline family ----------------------------------------------
    //
    // Outlines, threads, nodes and the rim are one family at three lightnesses:
    // the line recedes, the node marks an attachment, the rim is the single
    // light source on the top edge. They follow the background's hue — that is
    // what keeps them reading as structure rather than as accent — and borrow
    // the primary's only when the background has no hue of its own.

    readonly property real structuralHue: background.hslSaturation > 0.05 && background.hslHue >= 0
                                          ? background.hslHue
                                          : Math.max(0, primary.hslHue)
    readonly property real structuralSaturation: Math.max(
        Math.min(background.hslSaturation + 0.04, 0.40),
        Math.min(primary.hslSaturation * 0.33, 0.28))

    readonly property color line: structural(isDark ? 0.32 : 0.72)
    readonly property color node: structural(isDark ? 0.43 : 0.62)
    readonly property color rim: structural(isDark ? 0.55 : 0.50)

    function structural(lightness) {
        return Qt.hsla(root.structuralHue, root.structuralSaturation, lightness, 1);
    }

    // ---- Gradients --------------------------------------------------------
    //
    // The gradient simulates light: one source, from above, identical across
    // the shell — fixed 165°, two tones of the same hue, the top lighter and
    // the bottom darker and more saturated. It goes on indicators, value
    // digits, header icons and selected controls; never on a fill, a thread,
    // a thin line icon, and never as a glow.

    readonly property real gradientAngle: 165

    function gradientTop(base) {
        return Qt.hsla(Math.max(0, base.hslHue),
                       Math.min(1, base.hslSaturation + 0.14),
                       Math.min(1, base.hslLightness + 0.16),
                       base.a);
    }

    function gradientBottom(base) {
        return Qt.hsla(Math.max(0, base.hslHue),
                       Math.max(0, base.hslSaturation - 0.15),
                       Math.max(0, base.hslLightness - 0.15),
                       base.a);
    }

    // ---- Helpers ----------------------------------------------------------

    function luminance(colour) {
        // Rec. 709 relative luminance, good enough to pick a side.
        return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b;
    }

    // Moves a colour away from the background's side: lighter on a dark theme,
    // darker on a light one, keeping hue and saturation.
    function lift(colour, amount) {
        const step = root.isDark ? amount : -amount;
        return Qt.hsla(Math.max(0, colour.hslHue),
                       colour.hslSaturation,
                       Math.max(0, Math.min(1, colour.hslLightness + step)),
                       colour.a);
    }

    // ---- Source ---------------------------------------------------------

    // "matugen" | "manual"
    readonly property string source: Config.get("theme.source", "matugen")
    readonly property string manualPalette: Config.get("theme.palette", "default")

    // matugen writes this file through a template; the shell watches it and
    // hot-reloads. There is no direct dependency on matugen — if the file is
    // absent the manual palette stands.
    readonly property string matugenPath: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/bioma/generated/palette.json`

    readonly property string manualPath: Qt.resolvedUrl(`../config/palettes/${manualPalette}.json`).toString().replace("file://", "")

    function applyPalette(palette) {
        if (!palette)
            return;
        if (palette.background) root.background = palette.background;
        if (palette.text) root.text = palette.text;
        if (palette.primary) root.primary = palette.primary;
        if (palette.secondary) root.secondary = palette.secondary;
    }

    function load(text, label) {
        if (!text)
            return;
        try {
            root.applyPalette(JSON.parse(text));
        } catch (error) {
            console.warn(`Bioma: ${label} is not valid JSON — ${error.message}`);
        }
    }

    FileView {
        id: matugenFile
        path: root.source === "matugen" ? root.matugenPath : ""
        watchChanges: true
        onLoaded: root.load(text(), "palette.json")
        onFileChanged: reload()
    }

    FileView {
        id: manualFile
        path: root.source === "manual" ? root.manualPath : ""
        watchChanges: true
        onLoaded: root.load(text(), root.manualPath)
        onFileChanged: reload()
    }

    // A theme change crosses every surface together, in one transition. If each
    // cell animated on its own the desktop would change colour in patches.
    Behavior on background { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
    Behavior on text { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
    Behavior on primary { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
    Behavior on secondary { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
}
