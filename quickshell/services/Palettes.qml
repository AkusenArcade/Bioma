pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The user's own palettes: made, edited and deleted from Settings → Appearance.
//
// A palette of the user's is a file in `~/.config/bioma/palettes/`, in the
// shipped palettes' own form — a name and the four interface roles — so
// copying one file to somebody else gives them the theme, and Theme lists it
// beside Bioma's without knowing who wrote it (core/Theme.qml). The three
// state roles are not in it: they are a semantic code and no theme changes
// them (Akusen, 2026-10-18).
//
// A palette is edited while it is the one on screen: choosing it is what opens
// it, and every change is the desktop changing under the hand, as on the rest
// of the page. The file is written once the hand rests.
//
// NEW starts from the colours on screen now, whatever made them — a shipped
// palette, a palette of the user's, or matugen reading the wallpaper — so a
// wallpaper's colours can be kept, and then changed.
//
// And each wallpaper remembers the palette it was last worn with, with no
// one asking it to: going back to a picture brings its palette back. The pair
// is the source and what the source was told: for a manual one which palette,
// for matugen which scheme it read the picture with — tonal spot, content,
// expressive — since the same picture makes a different desktop under each
// (Akusen, 2026-10-18). A picture never paired keeps whatever is on screen.
// Noctalia did this and Akusen missed it, 2026-10-18.
Singleton {
    id: root

    readonly property var roles: ["background", "text", "primary", "secondary"]

    // The palette on screen, if a palette is what is on screen.
    readonly property var current: {
        if (Theme.source !== "manual")
            return null;
        return Theme.palettes.find(palette => palette.file === Theme.manualPalette) || null;
    }

    readonly property bool editable: root.current !== null && root.current.own

    // What is being written: the file's own content, until a change makes a
    // draft of it. The draft stays after it is written, so the editor does not
    // step back to the file for the moment the file takes to be read again.
    property var draft: null
    property string draftFile: ""

    readonly property var colours: root.current === null ? ({})
        : root.draft !== null && root.draftFile === root.current.file ? root.draft
        : root.current.colours

    // ---- Colours as text -------------------------------------------------------

    function hex(colour) {
        return String(colour).toUpperCase();
    }

    // `#RRGGBB`, from what somebody typed, or "" when it is not a colour.
    function parse(text) {
        const match = String(text).trim().match(/^#?([0-9a-fA-F]{6})$/);
        return match ? `#${match[1].toUpperCase()}` : "";
    }

    // ---- Choosing ----------------------------------------------------------------

    function choose(file) {
        root.flush();
        Config.set("theme.source", "manual");
        Config.set("theme.palette", file);
    }

    function freeFile() {
        let n = 1;
        while (Theme.palettes.some(palette => palette.file === `custom-${n}`))
            n++;
        return `custom-${n}`;
    }

    function freeName(base) {
        let n = 1;
        let name = base;
        while (Theme.palettes.some(palette => palette.name === name))
            name = `${base} ${++n}`;
        return name;
    }

    function nameTaken(name) {
        return Theme.palettes.some(palette => palette.name === name
                                   && (root.current === null || palette.file !== root.current.file));
    }

    // ---- Making, changing, deleting ----------------------------------------------

    function create() {
        root.flush();
        const file = root.freeFile();
        const data = {
            "name": root.freeName("Custom"),
            "background": root.hex(Theme.backgroundTarget),
            "text": root.hex(Theme.textTarget),
            "primary": root.hex(Theme.primaryTarget),
            "secondary": root.hex(Theme.secondaryTarget)
        };
        // Chosen once it is on disk: asked for before, Theme looks for a file
        // that is not there yet and falls back to the shipped folder.
        root.write(file, data, () => root.choose(file));
    }

    function change(patch) {
        if (!root.editable)
            return;
        root.draft = Object.assign({}, root.colours, patch);
        root.draftFile = root.current.file;
        settle.restart();
    }

    function setRole(role, colour) {
        if (!root.editable || root.roles.indexOf(role) < 0)
            return;
        const hex = root.parse(colour);
        if (hex.length === 0)
            return;
        root.change({ [role]: hex });
        Theme.immediate = true;
        Theme.applyPalette(root.draft);
    }

    function rename(name) {
        const trimmed = String(name).trim();
        if (!root.editable || trimmed.length === 0 || root.nameTaken(trimmed))
            return;
        if (trimmed !== root.colours.name)
            root.change({ "name": trimmed });
    }

    // Back to Bioma's own palette first, so the desktop is never left wearing
    // a palette that has no file.
    function remove() {
        if (!root.editable)
            return;
        const file = root.current.file;
        settle.stop();
        root.draft = null;
        root.draftFile = "";
        root.choose("default");
        Quickshell.execDetached(["rm", "-f", `${Theme.userPalettesDirectory}/${file}.json`]);
        root.forget(file);
    }

    // ---- Writing -----------------------------------------------------------------

    function flush() {
        if (!settle.running)
            return;
        settle.stop();
        root.save();
    }

    function save() {
        if (root.draft === null || root.draftFile.length === 0)
            return;
        root.write(root.draftFile, root.draft, null);
    }

    Timer {
        id: settle
        interval: Timing.debounce
        onTriggered: root.save()
    }

    property var afterSave: null

    function write(file, data, then) {
        root.afterSave = then;
        // Let go of the last file first: the same text to the same path was
        // taken for already written, and a palette deleted and made again
        // with the same colours never reached the disk.
        writer.path = "";
        writer.path = `${Theme.userPalettesDirectory}/${file}.json`;
        writer.setText(JSON.stringify(data, null, 2) + "\n");
    }

    FileView {
        id: writer
        printErrors: false
        onSaved: {
            Theme.immediate = false;
            const then = root.afterSave;
            root.afterSave = null;
            if (then)
                then();
        }
        onSaveFailed: error => {
            Theme.immediate = false;
            root.afterSave = null;
            console.warn(`Bioma: could not write ${writer.path} — ${error}`);
        }
    }

    // ---- Each wallpaper's palette ------------------------------------------------
    //
    // `theme.pairs`, in the override layer: { "<image>": { "source": "manual",
    // "palette": "custom-1" } } or { "<image>": { "source": "matugen",
    // "scheme": "scheme-content" } }.
    // Written whole, never by a path: an image's path is full of dots.

    readonly property var pairs: {
        const saved = Config.get("theme.pairs", {});
        return saved && typeof saved === "object" && !Array.isArray(saved) ? saved : {};
    }

    readonly property var pairNow: Theme.source === "matugen"
        ? { "source": "matugen", "scheme": Matugen.scheme }
        : { "source": "manual", "palette": Theme.manualPalette }

    // A wallpaper and a palette are a pair once they have stayed together for
    // `Timing.pair`: the pictures a carousel runs past are not.
    Timer {
        id: together
        interval: Timing.pair
        onTriggered: root.remember()
    }

    function settleTogether() {
        if (Config.ready && Wallpaper.loaded && Wallpaper.current.length > 0)
            together.restart();
    }

    function remember() {
        const image = Wallpaper.current;
        if (image.length === 0)
            return;
        const now = root.pairNow;
        const saved = root.pairs[image];
        if (saved && JSON.stringify(saved) === JSON.stringify(now))
            return;
        const next = Object.assign({}, root.pairs);
        next[image] = now;
        Config.set("theme.pairs", next);
    }

    // A deleted palette is forgotten by every picture that wore it, so none
    // asks for it again.
    function forget(file) {
        const next = {};
        let dropped = false;
        for (const image of Object.keys(root.pairs)) {
            const pair = root.pairs[image];
            if (pair && pair.source === "manual" && pair.palette === file)
                dropped = true;
            else
                next[image] = pair;
        }
        if (dropped)
            Config.set("theme.pairs", next);
    }

    // The picture's own palette, if it has one and that palette still exists.
    function recall(image) {
        const pair = root.pairs[image];
        if (!pair)
            return;
        if (pair.source === "matugen") {
            root.flush();
            // The scheme first: matugen runs once, with the picture's own.
            if (typeof pair.scheme === "string" && pair.scheme.length > 0)
                Config.set("theme.matugen.scheme", pair.scheme);
            Config.set("theme.source", "matugen");
        } else if (pair.source === "manual"
                   && Theme.palettes.some(palette => palette.file === pair.palette)) {
            root.choose(pair.palette);
        }
    }

    // The first image is the one the session starts on, already with its own
    // palette: only a change of picture recalls anything.
    property string lastImage: ""

    Connections {
        target: Wallpaper
        function onImageChanged(imagePath) {
            const before = root.lastImage;
            root.lastImage = imagePath;
            if (before.length > 0 && imagePath !== before)
                root.recall(imagePath);
            root.settleTogether();
        }
    }

    onPairNowChanged: root.settleTogether()

    // This service starts after the wallpaper has been announced, so the
    // picture on screen is taken as it is once both are known: unpaired, it
    // is paired with what it is wearing, and the first change of picture has
    // something to change from.
    readonly property bool awake: Config.ready && Wallpaper.loaded

    function wake() {
        if (root.lastImage.length === 0)
            root.lastImage = Wallpaper.current;
        root.settleTogether();
    }

    onAwakeChanged: if (root.awake) root.wake()
    Component.onCompleted: if (root.awake) root.wake()

    // ---- The eyedropper ----------------------------------------------------------

    // niri's own picker, through the capture service: the colour comes back
    // here and nowhere else — not to the clipboard, not to the utility's list.
    property string picking: ""

    function pick(role) {
        if (!root.editable)
            return;
        root.picking = role;
        Capture.pickColour(false);
    }

    Connections {
        target: Capture
        function onPicked(hex) {
            const role = root.picking;
            root.picking = "";
            if (role.length > 0 && !Capture.pickKept)
                root.setRole(role, hex);
        }
        function onCancelled() { root.picking = ""; }
        function onFailed() { root.picking = ""; }
    }
}
