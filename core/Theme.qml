pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
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
    //
    // The palette as loaded is one thing and the palette on screen is another:
    // a theme change crosses every surface together over `Timing.theme`, so
    // what cells bind to is the colour in transit. The target is kept beside it
    // for the one thing that needs the destination rather than the journey —
    // the theme cell's chips, which have to arrive one at a time and cannot do
    // that while chasing the shell's own transition.

    property color backgroundTarget: "#12160F"
    property color textTarget: "#EAF1E6"
    property color primaryTarget: "#B9DE6B"
    property color secondaryTarget: "#3FBFA0"

    property color background: root.backgroundTarget
    property color text: root.textTarget
    property color primary: root.primaryTarget
    property color secondary: root.secondaryTarget

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

    readonly property real structuralHue: hueOf(background, primary)
    readonly property real structuralSaturation: saturationOf(background, primary)

    readonly property color line: structural(isDark ? 0.32 : 0.72)
    readonly property color node: structural(isDark ? 0.43 : 0.62)
    readonly property color rim: structural(isDark ? 0.55 : 0.50)

    function hueOf(bg, accent) {
        return bg.hslSaturation > 0.05 && bg.hslHue >= 0 ? bg.hslHue : Math.max(0, accent.hslHue);
    }

    function saturationOf(bg, accent) {
        return Math.max(Math.min(bg.hslSaturation + 0.04, 0.40),
                        Math.min(accent.hslSaturation * 0.33, 0.28));
    }

    function structuralWith(bg, accent, lightness) {
        return Qt.hsla(root.hueOf(bg, accent), root.saturationOf(bg, accent), lightness, 1);
    }

    function structural(lightness) {
        return root.structuralWith(root.background, root.primary, lightness);
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
        return root.liftAway(colour, amount, root.isDark);
    }

    function liftAway(colour, amount, dark) {
        const step = dark ? amount : -amount;
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
        if (palette.background) root.backgroundTarget = palette.background;
        if (palette.text) root.textTarget = palette.text;
        if (palette.primary) root.primaryTarget = palette.primary;
        if (palette.secondary) root.secondaryTarget = palette.secondary;
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

    // ---- The seven roles, where the palette is going ------------------------
    //
    // What the theme cell shows: the background it sits on, the raised surface,
    // the two structural tones, the two accents and the text — the roles the
    // eye can actually check against the shell around them. The three state
    // colours are not among them: they are a semantic code, they do not come
    // from the theme source and they do not change when it does.

    readonly property bool targetIsDark: luminance(backgroundTarget) < 0.5

    readonly property var targetRoles: [
        root.backgroundTarget,
        root.liftAway(root.backgroundTarget, 0.045, root.targetIsDark),
        root.structuralWith(root.backgroundTarget, root.primaryTarget, root.targetIsDark ? 0.32 : 0.72),
        root.structuralWith(root.backgroundTarget, root.primaryTarget, root.targetIsDark ? 0.55 : 0.50),
        root.primaryTarget,
        root.secondaryTarget,
        root.textTarget
    ]

    // ---- The palettes on offer ---------------------------------------------
    //
    // A manual palette is a data file, one per theme: drop one into
    // `config/palettes/` and it appears in the theme cell's list without the
    // shell changing. The name comes from inside the file rather than from its
    // name on disk, because a theme has a name and the name is what is
    // remembered.

    readonly property string palettesDirectory:
        Qt.resolvedUrl("../config/palettes").toString().replace("file://", "")

    property var paletteNames: ({})

    // [{ "file": "default", "name": "Bioma" }], in the folder's own order.
    readonly property var palettes: {
        const out = [];
        for (let i = 0; i < paletteFiles.count; i++) {
            const file = String(paletteFiles.get(i, "fileBaseName"));
            out.push({ "file": file, "name": root.paletteNames[file] || file });
        }
        return out;
    }

    readonly property string paletteName: {
        for (const palette of root.palettes)
            if (palette.file === root.manualPalette)
                return palette.name;
        return root.manualPalette;
    }

    function noteName(file, text) {
        if (!text)
            return;
        try {
            const palette = JSON.parse(text);
            const names = Object.assign({}, root.paletteNames);
            names[file] = palette.name || file;
            root.paletteNames = names;
        } catch (error) {
            console.warn(`Bioma: palette ${file}.json is not valid JSON — ${error.message}`);
        }
    }

    FolderListModel {
        id: paletteFiles
        folder: `file://${root.palettesDirectory}`
        nameFilters: ["*.json"]
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    // One reader per file, so that adding a palette is adding a file. They are
    // read once, at their own size — four colours and a sentence — and then sit
    // idle; nothing here watches or polls.
    Instantiator {
        model: paletteFiles

        delegate: QtObject {
            id: entry

            required property string fileBaseName
            required property string filePath

            readonly property FileView view: FileView {
                path: entry.filePath
                blockLoading: true
                printErrors: false
                onLoaded: root.noteName(entry.fileBaseName, text())
            }
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
