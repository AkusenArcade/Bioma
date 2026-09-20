pragma Singleton

import QtQuick
import Quickshell

// Two voices, declared as roles rather than by name so a machine without the
// intended faces degrades instead of breaking.
//
//   If the system measured it, technical — Orbitron.
//   If it came from a human, expressive — Spectral.
//
// A piece of text always belongs to one of the two; if it is unclear which, it
// is probably badly written. Contracted cells are nearly textless, so the
// expressive serif is the more visible of the two at rest — it ends up carrying
// the shell's identity.
//
// Sizes are not here: they follow the membrane's density step and live in
// Metrics.step(). This singleton owns families, weights and numeral features.
Singleton {
    id: root

    // Human language: clock, window title, track metadata, notification body,
    // application, city and month names.
    readonly property string expressive: Config.get("fonts.expressive", "Spectral")
    readonly property string expressiveFallback: "serif"

    // Machine measurement: percentages, frequencies, memory, labels, controls.
    readonly property string technical: Config.get("fonts.technical", "Orbitron")
    readonly property string technicalFallback: "sans-serif"

    // ---- Weights -----------------------------------------------------------
    //
    // 700 is for titles only — a city name above a clock, `Workspace 1`, the
    // window title. Values and metadata stay at their scale weights, or a list
    // turns heavy.

    readonly property int weightValue: Font.Medium      // 500 — primary values
    readonly property int weightLabel: Font.Medium      // 500 — titles and labels
    readonly property int weightSecondary: Font.Normal  // 400 — secondary values, names
    readonly property int weightTitle: Font.Bold        // 700 — titles beside expressive text

    // Labels are uppercase and tracked out: CPU, FORMAT, WEEK STARTS.
    readonly property real labelTracking: 0.06          // em

    // Continuously changing figures must use tabular numerals, or their width
    // dances on every update and the tissue reflows for nothing. Every figure
    // in Bioma changes continuously, so this is the default and not an option.
    function tabular(font) {
        font.features = { "tnum": 1 };
        return font;
    }

    // Letter spacing is declared in em in the style guide and in pixels by Qt.
    function tracking(pixelSize, em) {
        return pixelSize * em;
    }
}
