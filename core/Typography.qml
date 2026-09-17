pragma Singleton

import QtQuick
import Quickshell

// Two registers, declared as roles rather than by name so a machine without
// the intended faces degrades instead of breaking.
//
//   If the string came from a human, expressive.
//   If the system measured it, technical.
//
// Contracted cells are nearly textless, so the expressive serif is the more
// visible of the two at rest — it ends up carrying the shell's identity.
Singleton {
    id: root

    // Human language: clock, window title, track metadata, notification body.
    readonly property string expressive: Config.get("fonts.expressive", "Spectral")
    readonly property string expressiveFallback: "serif"

    // Machine measurement: percentages, frequencies, memory, labels, controls.
    readonly property string technical: Config.get("fonts.technical", "Barlow")
    readonly property string technicalFallback: "sans-serif"

    // Continuously changing figures must use tabular numerals, or their width
    // dances on every update and the tissue reflows for nothing.
    function tabular(font) {
        font.features = { "tnum": 1 };
        return font;
    }
}
