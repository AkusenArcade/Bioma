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
// Bioma's own cursors and icons are drawn in the palette (`scripts/cursors`,
// `scripts/icon-theme`; docs/design/CURSORS.md, ICON_THEME.md): rebuilt
// whenever the palette settles, and installed as themes beside the others, so
// they are chosen like any of them. niri and the toolkits keep a theme loaded
// by its name, so the desktop is set to one of the theme's two slots, `<id>.a`
// or `<id>.b`, and moved to the other after a rebuild — the new name is what
// makes the new colours show. Bioma's icon themes draw folders and files only;
// everything else comes from `iconBase`, the theme they sit on.
Singleton {
    id: root

    // [{ "id", "name" }] — what is installed, by the themes' own names.
    property var icons: []
    property var cursors: []

    // What the desktop is set to now. `iconTheme` and `cursorTheme` are the
    // themes as listed; `iconLive` and `cursorLive` the names the desktop
    // holds, which for a slotted theme are one of its slots.
    property string iconTheme: ""
    property string iconLive: ""
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

    // The theme Bioma's icon themes sit on: applications and every icon they
    // do not draw come from it. Taken from the theme in use when one of them
    // is first chosen, and changed from the theme cell.
    readonly property string iconBase: Config.get("theme.icon_base", "") || "Adwaita"

    // The shell's icons follow the theme, not the slot: a palette change moves
    // the slot, and the shell redraws the rest of itself live anyway.
    readonly property string shellIcons: Quickshell.env("QS_ICON_THEME") || ""
    readonly property bool iconsPending: root.iconTheme.length > 0
        && root.themeOf(root.icons, root.shellIcons) !== root.iconTheme

    // The last thing that was refused, in its own words.
    property string error: ""

    function nameOf(list, id) {
        const found = list.find(t => t.id === id);
        return found ? found.name : id;
    }

    function isSlotted(list, id) {
        const found = list.find(t => t.id === id);
        return !!found && !!found.slotted;
    }

    // The name to set the desktop to for `id`: itself, or the slot it is not
    // on now (`live`), so niri and the toolkits load it afresh.
    function liveName(list, id, live) {
        if (!root.isSlotted(list, id))
            return id;
        return live === `${id}.a` ? `${id}.b` : `${id}.a`;
    }

    // The theme a live name stands for.
    function themeOf(list, live) {
        const base = live.replace(/\.[ab]$/, "");
        return base !== live && root.isSlotted(list, base) ? base : live;
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
                    root.iconLive = data.current.iconsLive || root.iconTheme;
                    root.cursorTheme = data.current.cursor || "";
                    root.cursorLive = data.current.live || root.cursorTheme;
                    root.cursorSize = data.current.size || 24;
                    root.adopt();
                } catch (e) {}
            }
        }
    }

    // ---- The first start ---------------------------------------------------------------

    // Bioma's own looks are put on the desktop once, the first time they have
    // been built: a fresh install comes up in its own icons and cursor rather
    // than in whatever was there (Akusen, 2026-10-06). Once — `looks_adopted`
    // is written either way — so a theme chosen afterwards is never taken
    // back, and not over one of Bioma's themes already chosen. The icon theme
    // that was on the desktop becomes the base, as `setIcons` does whenever
    // one of Bioma's is chosen.
    readonly property bool adopted: Config.get("theme.looks_adopted", false)

    // Set by the shell, and only by it: the probe binds this service too, and
    // a probe touches nothing.
    property bool adopting: false
    onAdoptingChanged: root.adopt()
    readonly property string adoptedIcons: "bioma-icons"
    readonly property string adoptedCursor: "bioma"

    function adopt() {
        if (!root.adopting || root.adopted || !settle.settled)
            return;
        // Not built yet: the next listing, after the builders, tries again.
        if (!root.isSlotted(root.icons, root.adoptedIcons) || !root.isSlotted(root.cursors, root.adoptedCursor))
            return;
        if (!root.isSlotted(root.icons, root.iconTheme))
            root.setIcons(root.adoptedIcons);
        if (!root.isSlotted(root.cursors, root.cursorTheme))
            root.applyCursor(root.adoptedCursor, root.cursorSize > 0 ? root.cursorSize : 24);
        Config.set("theme.looks_adopted", true);
    }

    // ---- Setting -------------------------------------------------------------------

    function setIcons(id) {
        if (!id || id === root.iconTheme)
            return;
        // Leaving a theme of somebody else's for one of Bioma's: what was on
        // the desktop becomes what Bioma's sits on, so the applications look
        // as they did.
        if (root.isSlotted(root.icons, id) && root.iconTheme.length > 0
                && !root.isSlotted(root.icons, root.iconTheme) && root.iconTheme !== root.iconBase)
            Config.set("theme.icon_base", root.iconTheme);
        root.applyIcons(id);
    }

    function applyIcons(id) {
        const live = root.liveName(root.icons, id, root.iconLive);
        root.iconTheme = id;
        root.iconLive = live;
        root.error = "";
        Quickshell.execDetached([Quickshell.shellPath("scripts/looks"), "icons", live]);
    }

    function setIconBase(id) {
        if (!id || id === root.iconBase || root.isSlotted(root.icons, id))
            return;
        Config.set("theme.icon_base", id);
    }

    function setCursor(id, size) {
        const theme = id || root.cursorTheme;
        const px = size > 0 ? size : root.cursorSize;
        if (theme === root.cursorTheme && px === root.cursorSize)
            return;
        root.applyCursor(theme, px);
    }

    function applyCursor(theme, px) {
        const live = root.liveName(root.cursors, theme, root.cursorLive);
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

    // ---- Bioma's cursors and icons ------------------------------------------------

    // The colours they are drawn in, from the palette's targets — not the
    // animated values, which pass through every colour in between — made the
    // way the shell makes its own surfaces, outlines and gradients.
    readonly property var drawnColours: {
        const bg = Theme.backgroundTarget;
        const p = Theme.primaryTarget;
        const dark = Theme.targetIsDark;
        const hex = c => Qt.rgba(c.r, c.g, c.b, 1).toString();
        // A folder's back, behind its primary face: the same hue, in shade.
        const shade = (s, l) => Qt.hsla(Math.max(0, p.hslHue), Math.max(0, p.hslSaturation - s),
                                        Math.max(0, p.hslLightness - l), 1);
        return {
            "background": hex(bg),
            "text": hex(Theme.textTarget),
            "primary": hex(p),
            "cell": hex(Theme.liftAway(bg, 0.075, dark)),
            "raised": hex(Theme.liftAway(bg, 0.12, dark)),
            "rim": hex(Theme.structuralWith(bg, p, dark ? 0.55 : 0.50)),
            "line": hex(Theme.structuralWith(bg, p, dark ? 0.32 : 0.72)),
            "grad_top": hex(Theme.gradientTop(p)),
            "grad_bottom": hex(Theme.gradientBottom(p)),
            "back_top": hex(shade(0.1, 0.18)),
            "back_bottom": hex(shade(0.2, 0.3))
        };
    }

    readonly property string cursorRequest: JSON.stringify({
        "colours": root.drawnColours,
        "loader": { "ms": Timing.loader, "ease": [Timing.sweep[0], Timing.sweep[1], Timing.sweep[2], Timing.sweep[3]] }
    })

    readonly property string iconRequest: JSON.stringify({
        "colours": root.drawnColours,
        "base": root.iconBase
    })

    onCursorRequestChanged: if (settle.settled) cursorDebounce.restart()
    onIconRequestChanged: if (settle.settled) iconDebounce.restart()

    // Once the shell has settled, and again whenever the palette rests.
    Timer {
        id: settle
        property bool settled: false
        interval: Timing.settle
        running: true
        onTriggered: {
            settled = true;
            cursorBuilder.build(root.cursorRequest);
            iconBuilder.build(root.iconRequest);
            // Themes built by an earlier start are listed already, and an
            // unchanged build lists nothing again.
            root.adopt();
        }
    }

    Timer {
        id: cursorDebounce
        interval: Timing.debounce
        onTriggered: cursorBuilder.build(root.cursorRequest)
    }

    Timer {
        id: iconDebounce
        interval: Timing.debounce
        onTriggered: iconBuilder.build(root.iconRequest)
    }

    // New themes appear in the list; the one on the desktop, if it is ours, is
    // moved to its other slot so the new colours show.
    Builder {
        id: cursorBuilder
        script: "scripts/cursors"
        onBuilt: {
            root.refresh();
            if (root.cursorLive !== root.cursorTheme)
                root.applyCursor(root.cursorTheme, root.cursorSize);
        }
    }

    Builder {
        id: iconBuilder
        script: "scripts/icon-theme"
        onBuilt: {
            root.refresh();
            if (root.iconLive !== root.iconTheme)
                root.applyIcons(root.iconTheme);
        }
    }

    // Runs one of the builders with a request; a request that arrives while
    // it runs is built after it, the latest one only.
    component Builder: Process {
        id: builder

        property string script: ""
        property string request: ""
        property string next: ""

        signal built()

        function build(request) {
            if (builder.running) {
                builder.next = request;
                return;
            }
            builder.request = request;
            builder.running = true;
        }

        command: [Quickshell.shellPath(builder.script), "build"]
        stdinEnabled: true

        onStarted: {
            builder.write(builder.request);
            builder.stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (JSON.parse(this.text).built === true)
                        builder.built();
                } catch (e) {}
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const reason = this.text.trim();
                if (reason.length > 0)
                    console.warn(`Bioma: ${builder.script} —`, reason);
            }
        }

        onExited: {
            builder.stdinEnabled = true;
            if (builder.next.length > 0) {
                const request = builder.next;
                builder.next = "";
                builder.build(request);
            }
        }
    }
}
