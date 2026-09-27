import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// What the threshold (Gate.qml) shows and how, read from where the shell left
// it: the wallpaper and its mode, the density, and whether the clock says
// 24 hours. The lock screen and the greeter both read it; the greeter runs as
// another user, with XDG_CONFIG_HOME pointed at the copy the shell keeps for
// it, so the same paths lead to the same values.
//
// Read, never written, and without the wallpaper service: that one scans the
// library and makes thumbnails, which is no work for a lock screen to be doing.
Item {
    id: root

    FileView {
        id: wallpaperState
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/bioma/wallpaper.json`
        blockLoading: true
        printErrors: false
    }

    readonly property var wallpaper: {
        try {
            return JSON.parse(wallpaperState.text()) || {};
        } catch (error) {
            return {};
        }
    }

    readonly property string wallpaperMode: root.wallpaper.mode || "fill"

    function wallpaperFor(screenName) {
        const perMonitor = root.wallpaper.perMonitorPaths || {};
        let path = root.wallpaperMode === "per_monitor" && perMonitor[screenName]
                 ? perMonitor[screenName] : (root.wallpaper.path || "");
        if (path.startsWith("~/"))
            path = Quickshell.env("HOME") + path.slice(1);
        return path;
    }

    // The density the Appearance page sets on every membrane at once.
    readonly property string density: {
        for (const membrane of Config.get("membranes", []))
            if (membrane.scale)
                return membrane.scale;
        return "normal";
    }

    // The clock says the time the way the clock cell does, wherever that cell
    // is placed.
    readonly property bool twentyFourHour: {
        const lists = [Config.get("membranes", []), Config.get("floating", [])];
        for (const list of lists)
            for (const block of list)
                for (const group of (block.tissues || [block]))
                    for (const cell of (group.cells || []))
                        if (cell.type === "clock" && cell.options && cell.options.format)
                            return cell.options.format === "24h";
        return true;
    }

    // The screen the keyboard is on, asked of niri once. niri hands the keys
    // to the surface of the focused output — at a greeter, the one marked
    // `focus-at-startup`, the primary.
    property string focusedOutput: ""

    Process {
        running: true
        command: ["niri", "msg", "--json", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const output = JSON.parse(text);
                    if (output && output.name)
                        root.focusedOutput = output.name;
                } catch (error) {
                    // Not niri, or not answering: the first screen will do.
                }
                if (root.focusedOutput.length === 0 && Quickshell.screens.length > 0)
                    root.focusedOutput = Quickshell.screens[0].name;
            }
        }
    }
}
