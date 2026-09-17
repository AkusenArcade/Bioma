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
// Everything else — elevated surfaces, muted text, borders, shadows — is
// derived here. Derived roles cost the user nothing and stay coherent by
// construction.
Singleton {
    id: root

    // ---- Interface roles (theme source) ----------------------------------

    property color background: "#12110F"
    property color text: "#EDE6DC"
    property color primary: "#C9A227"
    property color secondary: "#7C8B7A"

    // ---- State roles (fixed, never from matugen) --------------------------

    readonly property color calm: isDark ? stateDark.calm : stateLight.calm
    readonly property color active: isDark ? stateDark.active : stateLight.active
    readonly property color alert: isDark ? stateDark.alert : stateLight.alert

    readonly property var stateDark: Config.get("theme.state.dark", {
        "calm": "#6FA88A",
        "active": "#E0A63C",
        "alert": "#D5624C"
    })
    readonly property var stateLight: Config.get("theme.state.light", {
        "calm": "#3F7D5E",
        "active": "#B37414",
        "alert": "#B03A24"
    })

    // ---- Derived --------------------------------------------------------

    // Light or dark is inferred from the background, never configured.
    readonly property real backgroundLuminance: luminance(background)
    readonly property bool isDark: backgroundLuminance < 0.5

    readonly property color surface: shift(background, isDark ? 0.06 : -0.04)
    readonly property color elevated: shift(background, isDark ? 0.12 : -0.08)
    readonly property color border: Qt.alpha(text, isDark ? 0.14 : 0.18)
    readonly property color textMuted: Qt.alpha(text, 0.62)
    readonly property color textFaint: Qt.alpha(text, 0.38)
    readonly property color shadow: Qt.alpha("#000000", isDark ? 0.55 : 0.22)

    // Maps a 0..1 load onto the state colours, per the nominal bands
    // calm 0–30 / active 31–70 / critical 71–100. Hysteresis belongs to the
    // visibility condition, not here.
    function stateFor(load) {
        if (load >= 0.71)
            return root.alert;
        if (load >= 0.31)
            return root.active;
        return root.calm;
    }

    function luminance(colour) {
        // Rec. 709 relative luminance, good enough to pick a side.
        return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b;
    }

    function shift(colour, amount) {
        const target = amount >= 0 ? Qt.rgba(1, 1, 1, colour.a) : Qt.rgba(0, 0, 0, colour.a);
        return Qt.tint(colour, Qt.alpha(target, Math.abs(amount)));
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

    Behavior on background { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
    Behavior on text { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
    Behavior on primary { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
    Behavior on secondary { ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad } }
}
