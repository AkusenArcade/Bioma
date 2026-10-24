pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// What asks the shell to step back: a game registered with GameMode, or a
// window of one of the applications on the performance list. It hands what
// it finds to core/Performance.qml, which decides.
//
// Neither is polled.
//
//   - GameMode (Feral's `gamemoded`): `gdbus monitor` on its object prints a
//     line for every game that registers or leaves and for every change of
//     owner, and each line is only the signal to read `ClientCount` again.
//     Read with auto-start off, so watching does not start the daemon on a
//     machine that has it installed and idle. A game launched without
//     `gamemoderun` (or Steam's GameMode option) is not seen here; the list
//     is for that.
//   - The list: app-ids matched against niri's windows, which the event
//     stream already keeps (services/Niri.qml). `*` stands for anything —
//     Steam's games are `steam_app_*` under XWayland and `steam_proton`
//     under Proton's Wayland driver — and case does not count.
Singleton {
    id: root

    readonly property bool watchesGames: Config.get("performance.gamemode", true) === true
    readonly property var patterns: Config.get("performance.apps", [])

    // Clients GameMode counts now. A Wine game registers several processes,
    // so this is not a number of games, only whether there is one.
    property int games: 0

    onWatchesGamesChanged: {
        if (root.watchesGames)
            count.running = true;
        else
            root.games = 0;
    }

    Process {
        id: watch

        // Told by the kernel when the shell goes, as in Printers: a monitor
        // left to systemd would outlive the shell, one more per restart.
        command: ["setpriv", "--pdeathsig", "TERM", "gdbus", "monitor", "--session",
                  "--dest", "com.feralinteractive.GameMode",
                  "--object-path", "/com/feralinteractive/GameMode"]
        running: root.watchesGames
        property double startedAt: 0
        onStarted: {
            watch.startedAt = Date.now();
            count.running = true;
        }
        stdout: SplitParser {
            onRead: again.restart()
        }
        onExited: {
            if (!root.watchesGames)
                return;
            // One that held for a while was a bus that restarted; one that
            // fails at once has no gdbus to run, and asking for ever is a poll.
            rewatch.interval = Date.now() - watch.startedAt > 60000
                ? 5000 : Math.min(rewatch.interval * 2, 10 * 60 * 1000);
            rewatch.start();
        }
    }

    Timer {
        id: rewatch
        interval: 5000
        onTriggered: watch.running = root.watchesGames
    }

    // A game registering is several signals in a row; one read answers them.
    Timer {
        id: again
        interval: 100
        onTriggered: count.running = true
    }

    Process {
        id: count

        command: ["busctl", "--user", "--auto-start=no", "get-property",
                  "com.feralinteractive.GameMode", "/com/feralinteractive/GameMode",
                  "com.feralinteractive.GameMode", "ClientCount"]
        stdout: StdioCollector {
            onStreamFinished: {
                // `i 2`; nothing at all when GameMode is not running.
                const found = /^i\s+(\d+)/.exec(this.text.trim());
                root.games = root.watchesGames && found ? parseInt(found[1], 10) : 0;
            }
        }
    }

    // ---- The list -----------------------------------------------------------

    function matcher(pattern) {
        const escaped = String(pattern).trim().replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
        return new RegExp(`^${escaped}$`, "i");
    }

    readonly property var matchers: (Array.isArray(root.patterns) ? root.patterns : [])
        .filter(pattern => String(pattern).trim().length > 0)
        .map(pattern => root.matcher(pattern))

    // The applications on the list with a window open, by name, once each.
    readonly property var apps: {
        const out = [];
        if (root.matchers.length === 0)
            return out;
        for (const id in Niri.windows) {
            const appId = Niri.windows[id].appId;
            if (!appId || !root.matchers.some(m => m.test(appId)))
                continue;
            const entry = Apps.entryFor(appId);
            const name = entry && entry.name ? entry.name : appId;
            if (out.indexOf(name) < 0)
                out.push(name);
        }
        return out;
    }

    readonly property var triggers: {
        const out = [];
        if (root.games > 0)
            out.push({ "kind": "game", "name": "GameMode" });
        for (const name of root.apps)
            out.push({ "kind": "app", "name": name });
        return out;
    }

    Binding {
        target: Performance
        property: "triggers"
        value: root.triggers
    }
}
