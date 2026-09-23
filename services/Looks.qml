pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop's look outside the palette: its icon theme and its cursor.
//
// Neither is the shell's to keep. The icon theme is the desktop's setting
// (`org.gnome.desktop.interface`), which GTK reads live, plus qt5ct and qt6ct's
// own; the cursor is the same setting for the toolkits and niri's `cursor`
// section for everything niri draws and starts — written as `bioma-cursor.kdl`
// through `scripts/niri-include`, included last so it overrides the user's own
// `cursor` block property by property. So what is shown is read from the
// desktop, and nothing is written until something is chosen.
//
// The shell's own icons are the one thing that cannot follow live: Quickshell
// takes its icon theme from `QS_ICON_THEME` when it starts, and `scripts/bioma`
// sets that from the desktop's. `iconsPending` says a restart is owed.
Singleton {
    id: root

    // [{ "id", "name" }] — what is installed, by the themes' own names.
    property var icons: []
    property var cursors: []

    // What the desktop is set to now.
    property string iconTheme: ""
    property string cursorTheme: ""
    property int cursorSize: 24

    // Sizes worth offering; the one set now is kept among them whatever it is.
    readonly property var sizes: {
        const out = [24, 32, 48];
        if (root.cursorSize > 0 && out.indexOf(root.cursorSize) < 0)
            out.push(root.cursorSize);
        return out.sort((a, b) => a - b);
    }

    readonly property string shellIcons: Quickshell.env("QS_ICON_THEME") || ""
    readonly property bool iconsPending: root.iconTheme.length > 0 && root.shellIcons !== root.iconTheme

    // The last thing that was refused, in its own words.
    property string error: ""

    function nameOf(list, id) {
        const found = list.find(t => t.id === id);
        return found ? found.name : id;
    }

    // ---- Reading -----------------------------------------------------------------

    function refresh() {
        if (!reader.running)
            reader.running = true;
    }

    Process {
        id: reader

        running: true
        command: [Quickshell.shellPath("scripts/looks"), "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.icons = data.icons || [];
                    root.cursors = data.cursors || [];
                    root.iconTheme = data.current.icons || "";
                    root.cursorTheme = data.current.cursor || "";
                    root.cursorSize = data.current.size || 24;
                } catch (e) {}
            }
        }
    }

    // ---- Setting -------------------------------------------------------------------

    function setIcons(id) {
        if (!id || id === root.iconTheme)
            return;
        root.iconTheme = id;
        root.error = "";
        Quickshell.execDetached([Quickshell.shellPath("scripts/looks"), "icons", id]);
    }

    function setCursor(id, size) {
        const theme = id || root.cursorTheme;
        const px = size > 0 ? size : root.cursorSize;
        if (theme === root.cursorTheme && px === root.cursorSize)
            return;
        root.cursorTheme = theme;
        root.cursorSize = px;
        root.error = "";
        Quickshell.execDetached([Quickshell.shellPath("scripts/looks"), "cursor", theme, String(px)]);

        const quote = value => `"${String(value).replace(/["\\]/g, "")}"`;
        cursorWriter.body = "// Written by Bioma's theme cell (DESKTOP). Choosing a cursor there rewrites it.\n"
                          + `cursor {\n    xcursor-theme ${quote(theme)}\n    xcursor-size ${px}\n}`;
        if (cursorWriter.running)
            cursorWriter.again = true;
        else
            cursorWriter.running = true;
    }

    Process {
        id: cursorWriter

        property string body: ""
        property bool again: false

        command: [Quickshell.shellPath("scripts/niri-include"), "cursor"]
        stdinEnabled: true

        onStarted: {
            cursorWriter.write(cursorWriter.body);
            cursorWriter.stdinEnabled = false;
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const reason = this.text.trim();
                if (reason.length > 0)
                    root.error = "niri refused it: " + reason;
            }
        }

        onExited: {
            cursorWriter.stdinEnabled = true;
            if (cursorWriter.again) {
                cursorWriter.again = false;
                cursorWriter.running = true;
            }
        }
    }
}
