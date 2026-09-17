pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Palette generation from the wallpaper.
//
// This service runs matugen and nothing else. It does not read matugen's output
// format and it hands colours to nobody: matugen renders Bioma's own template
// into the config directory, `core/Theme.qml` watches that file, and the two
// never meet. There is no direct dependency on matugen — with it absent, or the
// source set to a manual palette, the shell simply keeps the palette it has.
//
// Prisma took the other road, parsing `--json` output directly and carrying
// three matugen format versions to do it. Going through a template means format
// drift lands in a text file instead of in the shell, and it is the same
// mechanism that will later propagate the palette to GTK and niri — one config
// block each, no shell change.
//
// Bioma's matugen config is passed explicitly with `--config`, so the user's own
// `~/.config/matugen/` is neither read nor written.
Singleton {
    id: root

    readonly property bool enabled: Config.get("theme.source", "matugen") === "matugen"

    // dark | light | smart — which mode the template's `default` resolves to.
    readonly property string variant: Config.get("theme.matugen.variant", "dark")
    readonly property string scheme: Config.get("theme.matugen.scheme", "scheme-tonal-spot")

    // An image usually offers several candidate source colours. Picking by
    // dominance keeps the choice reproducible; without it matugen 4.x asks, and
    // asking from a process with no terminal is an error, not a prompt.
    readonly property int sourceColorIndex: Config.get("theme.matugen.source_color_index", 0)

    readonly property string configDirectory: Qt.resolvedUrl("../config/matugen")
                                                 .toString().replace("file://", "")

    readonly property bool running: matugen.running
    property string lastError: ""
    property string lastImage: ""

    signal generated(string imagePath)
    signal failed(string message)

    function generate(imagePath) {
        if (!root.enabled || !imagePath || imagePath.length === 0)
            return;
        pending.image = imagePath;
        debounce.restart();
    }

    QtObject {
        id: pending
        property string image: ""
    }

    // The theme cell retints on hover, so images can arrive faster than matugen
    // can answer. Only the last one is worth generating.
    Timer {
        id: debounce
        interval: 250
        onTriggered: root.run(pending.image)
    }

    function run(imagePath) {
        root.lastError = "";
        matugen.errorLines = [];
        matugen.image = imagePath;
        matugen.command = [
            "matugen",
            "--config", "config.toml",
            "--mode", root.variant,
            "--type", root.scheme,
            "--source-color-index", String(root.sourceColorIndex),
            "image", imagePath
        ];
        matugen.running = false;
        matugen.running = true;
    }

    // matugen decorates its progress and error lines with ANSI colour.
    function plain(text) {
        return text.replace(/\x1b\[[0-9;]*m/g, "").trim();
    }

    // matugen reports a failure as a numbered chain, deepest cause last,
    // followed by two lines about backtraces. Taking the last line of stderr
    // therefore reports "Run with RUST_BACKTRACE=full" instead of the actual
    // problem; taking the first reports "Failed to get source color", which is
    // barely better. The deepest numbered line is the one worth showing.
    function rootCause(lines) {
        for (let i = lines.length - 1; i >= 0; i--) {
            if (/^\s*\d+:\s/.test(lines[i]))
                return lines[i].replace(/^\s*\d+:\s*/, "");
        }
        return lines.length > 0 ? lines[0] : "";
    }

    Process {
        id: matugen
        property string image: ""
        property var errorLines: []
        running: false
        workingDirectory: root.configDirectory

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const message = root.plain(line);
                if (message.length > 0)
                    matugen.errorLines.push(message);
            }
        }

        onExited: code => {
            if (code === 0) {
                root.lastError = "";
                root.lastImage = matugen.image;
                // Nothing is handed over. matugen has written the palette file;
                // Theme is watching it and picks the change up itself.
                root.generated(matugen.image);
            } else {
                const cause = root.rootCause(matugen.errorLines);
                const message = cause.length > 0 ? cause : `matugen exited ${code}`;
                root.lastError = message;
                console.warn("Matugen:", message);
                root.failed(message);
            }
        }
    }

    // The wallpaper is the only input. Connecting here, rather than having the
    // wallpaper service call out, keeps the two independent: either can be
    // absent and neither knows the other exists.
    Connections {
        target: Wallpaper
        function onImageChanged(imagePath) { root.generate(imagePath); }
    }

    // Regenerate when the variant or scheme is changed from settings, using
    // whatever image is current.
    onVariantChanged: root.generate(Wallpaper.path)
    onSchemeChanged: root.generate(Wallpaper.path)
}
