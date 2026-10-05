pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

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
//
// Bioma's own cursors are drawn in the palette (`scripts/cursors`,
// docs/design/CURSORS.md): rebuilt whenever the palette settles, and installed
// as themes beside the others, so they are chosen like any of them. niri and
// the toolkits keep a cursor theme loaded by its name, so the desktop is set to
// one of the theme's two slots, `<id>.a` or `<id>.b`, and moved to the other
// after a rebuild — the new name is what makes the new colours show.
Singleton {
    id: root

    // [{ "id", "name" }] — what is installed, by the themes' own names.
    property var icons: []
    property var cursors: []

    // What the desktop is set to now. `cursorTheme` is the theme as listed;
    // `cursorLive` the name the desktop holds, which for a slotted theme is
    // one of its slots.
    property string iconTheme: ""
    property string cursorTheme: ""
    property string cursorLive: ""
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

    // The name to set the desktop to for `id`: itself, or the slot it is not
    // on now, so niri and the toolkits load it afresh.
    function liveName(id) {
        const found = root.cursors.find(t => t.id === id);
        if (!found || !found.slotted)
            return id;
        return root.cursorLive === `${id}.a` ? `${id}.b` : `${id}.a`;
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
                    root.cursorLive = data.current.live || root.cursorTheme;
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
        root.applyCursor(theme, px);
    }

    function applyCursor(theme, px) {
        const live = root.liveName(theme);
        root.cursorTheme = theme;
        root.cursorLive = live;
        root.cursorSize = px;
        root.error = "";
        Quickshell.execDetached([Quickshell.shellPath("scripts/looks"), "cursor", live, String(px)]);

        const quote = value => `"${String(value).replace(/["\\]/g, "")}"`;
        cursorWriter.body = "// Written by Bioma's theme cell (DESKTOP). Choosing a cursor there rewrites it.\n"
                          + `cursor {\n    xcursor-theme ${quote(live)}\n    xcursor-size ${px}\n}`;
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

    // ---- Bioma's cursors --------------------------------------------------------

    // The colours the cursors are drawn in, from the palette's targets — not
    // the animated values, which pass through every colour in between — made
    // the way the shell makes its own surfaces and outlines.
    readonly property var cursorColours: {
        const bg = Theme.backgroundTarget;
        const p = Theme.primaryTarget;
        const dark = Theme.targetIsDark;
        const hex = c => Qt.rgba(c.r, c.g, c.b, 1).toString();
        return {
            "background": hex(bg),
            "text": hex(Theme.textTarget),
            "primary": hex(p),
            "cell": hex(Theme.liftAway(bg, 0.075, dark)),
            "rim": hex(Theme.structuralWith(bg, p, dark ? 0.55 : 0.50)),
            "line": hex(Theme.structuralWith(bg, p, dark ? 0.32 : 0.72))
        };
    }

    readonly property string cursorRequest: JSON.stringify({
        "colours": root.cursorColours,
        "loader": { "ms": Timing.loader, "ease": [Timing.sweep[0], Timing.sweep[1], Timing.sweep[2], Timing.sweep[3]] }
    })

    onCursorRequestChanged: if (cursorSettle.settled) cursorDebounce.restart()

    // Once the shell has settled, and again whenever the palette rests.
    Timer {
        id: cursorSettle
        property bool settled: false
        interval: Timing.settle
        running: true
        onTriggered: {
            settled = true;
            root.buildCursors();
        }
    }

    Timer {
        id: cursorDebounce
        interval: Timing.debounce
        onTriggered: root.buildCursors()
    }

    function buildCursors() {
        if (cursorBuilder.running) {
            cursorBuilder.again = true;
            return;
        }
        cursorBuilder.request = root.cursorRequest;
        cursorBuilder.running = true;
    }

    Process {
        id: cursorBuilder

        property string request: ""
        property bool again: false

        command: [Quickshell.shellPath("scripts/cursors"), "build"]
        stdinEnabled: true

        onStarted: {
            cursorBuilder.write(cursorBuilder.request);
            cursorBuilder.stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let built = false;
                try {
                    built = JSON.parse(this.text).built === true;
                } catch (e) {
                    return;
                }
                if (!built)
                    return;
                // New themes appear in the list; the one on the desktop, if it
                // is ours, is moved to its other slot so the new colours show.
                root.refresh();
                if (root.cursorLive !== root.cursorTheme)
                    root.applyCursor(root.cursorTheme, root.cursorSize);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const reason = this.text.trim();
                if (reason.length > 0)
                    console.warn("Bioma: the cursors —", reason);
            }
        }

        onExited: {
            cursorBuilder.stdinEnabled = true;
            if (cursorBuilder.again) {
                cursorBuilder.again = false;
                root.buildCursors();
            }
        }
    }
}
