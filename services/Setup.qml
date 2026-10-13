pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The first run: what a new user meets the first time the shell starts.
//
// Setup is the settings cell in another form — steps where the categories
// stand — so this holds what the steps know and do, and the cell draws it
// (cells/settings/SettingsExpansion.qml). One singleton, because the settings
// cell exists once per monitor and the walk-through is one.
//
// It opens by itself when the shell starts with no override file at all:
// someone updating from a beta has one, and never sees it. `setup.pending` is
// written at once, so the walk-through survives its own first write — the
// preset it applies creates the override — and Escape means *later*. DONE and
// SKIP write `setup.done`, and it opens again only when asked for by IPC.
//
// What it finds out comes from scripts, asked when it opens and again after
// each action: `install --report` (programs, services, niri, a polkit agent),
// `greeter-setup status`, and `setup-scan list` (other shells). Nothing polls.
//
// See docs/design/SETUP.md.
Singleton {
    id: root

    // ---- Where it is ---------------------------------------------------------

    // Shown, in the settings cell of this output.
    property bool active: false
    property string output: ""
    property string step: "welcome"

    readonly property bool done: Config.get("setup.done", false) !== false
    readonly property bool pending: Config.get("setup.pending", false) === true

    // CONFLICTS and SYSTEM exist when they have something to say.
    readonly property var steps: {
        const out = [
            { "key": "welcome", "label": "WELCOME", "glyph": "mark",
              "hint": "what this is", "width": 520 },
            { "key": "layout", "label": "LAYOUT", "glyph": "structure",
              "hint": "where everything goes", "width": 640 },
            { "key": "look", "label": "LOOK", "glyph": "theme",
              "hint": "palette and wallpaper", "width": 520 },
            { "key": "niri", "label": "NIRI", "glyph": "window",
              "hint": "keys and autostart", "width": 520 },
            { "key": "login", "label": "LOGIN", "glyph": "lock",
              "hint": "the login screen", "width": 520 }
        ];
        if (root.conflicts.length > 0)
            out.push({ "key": "conflicts", "label": "CONFLICTS", "glyph": "bell",
                       "hint": "another shell is running", "width": 640 });
        if (root.systemWanted)
            out.push({ "key": "system", "label": "SYSTEM", "glyph": "screen",
                       "hint": "what is missing", "width": 600 });
        out.push({ "key": "keys", "label": "KEYS", "glyph": "keyboard",
                   "hint": "where to start", "width": 520 });
        return out;
    }

    readonly property int stepIndex: {
        for (let i = 0; i < root.steps.length; i++)
            if (root.steps[i].key === root.step)
                return i;
        return 0;
    }

    readonly property bool last: root.stepIndex === root.steps.length - 1

    // A step that stops existing while it is shown — the last conflict
    // stopped — hands over to the one that came after it.
    property int shownIndex: 0
    onStepIndexChanged: if (root.steps.some(entry => entry.key === root.step)) root.shownIndex = root.stepIndex
    onStepsChanged: if (!root.steps.some(entry => entry.key === root.step))
        root.step = root.steps[Math.min(root.shownIndex, root.steps.length - 1)].key

    // What each visited step chose, said in its capsule's line.
    property var outcomes: ({})

    function note(step, line) {
        const next = Object.assign({}, root.outcomes);
        next[step] = line;
        root.outcomes = next;
    }

    // `muted`, `active` (wants attention) or `alert` (an action failed): the
    // colour of a step's glyph when it is not the chosen one.
    function stateOf(key) {
        if (key === "niri" && root.niriError.length > 0)
            return "alert";
        if (key === "login" && root.loginError.length > 0)
            return "alert";
        if (key === "conflicts" && root.conflicts.length > 0)
            return "active";
        if (key === "system" && (root.missing.length > 0 || root.disabled.length > 0 || !root.polkitAgent))
            return "active";
        return "muted";
    }

    function go(key) {
        root.step = key;
    }

    function next() {
        if (root.stepIndex < root.steps.length - 1)
            root.step = root.steps[root.stepIndex + 1].key;
    }

    function back() {
        if (root.stepIndex > 0)
            root.step = root.steps[root.stepIndex - 1].key;
    }

    // ---- Opening and closing -------------------------------------------------

    // Asked for: the settings cell of that output, in its setup form.
    function open(output) {
        root.output = output || root.primaryOutput();
        if (!root.active) {
            root.step = root.steps[0].key;
            root.refresh();
        }
        root.active = true;
        const cell = Focus.cellFor("settings", root.output);
        if (!cell || !cell.open)
            Focus.invoke("settings", root.output);
    }

    // The settings cell closed under it — Escape, a press outside: later.
    function closed() {
        if (root.finishing)
            return;
        root.active = false;
    }

    // The cell it was shown in is gone: a preset that rebuilt the band it sat
    // in. The walk-through is still under way, so it reopens in the new one.
    function lost() {
        if (root.active && !root.finishing)
            reopen.restart();
    }

    Timer {
        id: reopen
        interval: Timing.reflow + Timing.open
        onTriggered: if (root.active) root.open(root.output)
    }

    property bool finishing: false

    // DONE and SKIP. Skipping changes nothing that was not already changed.
    function finish() {
        root.finishing = true;
        Config.setMany([["setup.done", true], ["setup.pending", false]]);
        Focus.retire("settings", root.output);
        root.active = false;
        root.finishing = false;
        // A notification daemon was stopped: Bioma's server registered before
        // the name was free, and only a new start claims it.
        if (root.restartAtEnd)
            Quickshell.execDetached(["setsid", "-f", Quickshell.shellPath("scripts/shell"), "restart"]);
    }

    function primaryOutput() {
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    // ---- The first start -----------------------------------------------------

    // Decided once, when both layers have been read and the shipped presets
    // are known: a fresh account gets Complete — the base layout with its
    // organisms — and the walk-through.
    property bool decided: false
    readonly property bool canDecide: Config.ready && Config.overrideRead
                                      && Presets.find("Complete") !== null

    onCanDecideChanged: root.decide()

    function decide() {
        if (root.decided || !root.canDecide)
            return;
        root.decided = true;
        if (!Config.overrideExists) {
            console.info("Bioma: first start — the setup opens");
            Presets.apply("Complete");
            Config.set("setup.pending", true);
        }
        if (root.pending && !root.done)
            firstOpen.start();
    }

    // Once the shell has settled: it comes up as it always does, the services
    // fill in, and then the settings cell expands into the setup.
    Timer {
        id: firstOpen
        interval: Timing.settle
        onTriggered: if (!root.active) root.open(root.primaryOutput())
    }

    // ---- What the machine has ------------------------------------------------

    property bool reportRead: false
    property var required: []        // [{ name, what, package, ok }]
    property var optional: []
    property var disabled: []        // unit names
    property var niriState: ({})     // config, binds, include, include-binds, autostart → ok | missing
    property string niriConfig: ""
    property bool polkitAgent: true

    readonly property var missing: root.required.filter(entry => !entry.ok)
    readonly property bool systemWanted: root.reportRead
        && (root.missing.length > 0 || root.disabled.length > 0 || !root.polkitAgent)

    readonly property bool niriSet: root.niriState.binds === "ok" && root.niriState.include === "ok"
                                    && root.niriState["include-binds"] === "ok"
    readonly property bool autostartSet: root.niriState.autostart === "ok"

    function refresh() {
        report.collected = [];
        report.running = true;
        greeter.collected = [];
        greeter.running = true;
        scan.collected = [];
        scan.running = true;
    }

    Process {
        id: report
        property var collected: []
        command: [Quickshell.shellPath("scripts/install"), "--report"]
        stdout: SplitParser { onRead: line => report.collected.push(line) }
        onExited: {
            const required = [];
            const optional = [];
            const disabled = [];
            const niri = {};
            let agent = true;
            for (const line of report.collected) {
                const f = line.split("\t");
                if (f[0] === "required" || f[0] === "optional") {
                    const entry = { "ok": f[1] === "ok", "name": f[2], "what": f[3], "package": f[4] };
                    (f[0] === "required" ? required : optional).push(entry);
                } else if (f[0] === "service" && f[1] === "disabled") {
                    disabled.push(f[2]);
                } else if (f[0] === "niri") {
                    niri[f[1]] = f[2];
                    if (f[1] === "config" && f[3])
                        root.niriConfig = f[3];
                } else if (f[0] === "polkit") {
                    agent = f[2] === "ok";
                }
            }
            root.required = required;
            root.optional = optional;
            root.disabled = disabled;
            root.niriState = niri;
            root.polkitAgent = agent;
            root.reportRead = true;
        }
    }

    // ---- The login screen ----------------------------------------------------

    property string manager: ""              // display-manager.service's unit, or "none"
    property bool biomaGreeter: false
    property bool greeterRead: false

    readonly property string managerName: {
        const unit = root.manager.replace(/\.service$/, "");
        if (unit === "none" || unit.length === 0)
            return "TEXT LOGIN";
        return unit.toUpperCase();
    }

    Process {
        id: greeter
        property var collected: []
        command: [Quickshell.shellPath("scripts/greeter-setup"), "status"]
        stdout: SplitParser { onRead: line => greeter.collected.push(line) }
        onExited: {
            for (const line of greeter.collected) {
                const f = line.split("\t");
                if (f[0] === "manager")
                    root.manager = f[1];
                else if (f[0] === "greeter")
                    root.biomaGreeter = f[1] === "bioma";
            }
            root.greeterRead = true;
        }
    }

    property bool loginBusy: false
    property string loginError: ""

    // The command a person runs when nothing can ask for the password.
    function loginCommand(enable) {
        return `pkexec ${Quickshell.shellPath("scripts/greeter-setup")} ${enable ? "enable" : "disable"}`;
    }

    function setGreeter(enable) {
        if (root.loginBusy || enable === root.biomaGreeter)
            return;
        root.loginError = "";
        root.loginBusy = true;
        login.collected = [];
        login.command = ["pkexec", Quickshell.shellPath("scripts/greeter-setup"), enable ? "enable" : "disable"];
        login.running = true;
    }

    Process {
        id: login
        property var collected: []
        stderr: SplitParser { onRead: line => login.collected.push(line) }
        onExited: code => {
            root.loginBusy = false;
            // pkexec: 126 when the password was not given, 127 when nothing
            // could ask for it.
            if (code === 126)
                root.loginError = "The password was not given, so nothing changed.";
            else if (code === 127)
                root.loginError = "Nothing could ask for the password. Run the command below in a terminal.";
            else if (code !== 0)
                root.loginError = login.collected.length > 0 ? login.collected[login.collected.length - 1]
                                                             : "It did not complete.";
            greeter.collected = [];
            greeter.running = true;
        }
    }

    // ---- niri ----------------------------------------------------------------

    property bool niriBusy: false
    property string niriError: ""

    function setUpNiri(autostart) {
        if (root.niriBusy)
            return;
        root.niriError = "";
        root.niriBusy = true;
        niri.collected = [];
        niri.command = [Quickshell.shellPath("scripts/install"), "--niri-only"]
            .concat(autostart ? ["--autostart"] : []);
        niri.running = true;
    }

    Process {
        id: niri
        property var collected: []
        stderr: SplitParser { onRead: line => niri.collected.push(line) }
        onExited: code => {
            root.niriBusy = false;
            if (code !== 0) {
                // The first line niri refused, under the script's own sentence.
                const lines = niri.collected.filter(line => line.trim().length > 0
                                                            && !line.startsWith("niri refused"));
                root.niriError = lines.length > 0 ? lines[0].trim() : "niri refused the configuration.";
            }
            report.collected = [];
            report.running = true;
        }
    }

    // ---- Other shells --------------------------------------------------------

    property var conflicts: []      // [{ pid, name, what, from }]
    property bool restartAtEnd: false
    property var stopping: ({})     // pid → true while it is being stopped
    property var stopErrors: ({})   // pid → the line niri refused

    Process {
        id: scan
        property var collected: []
        command: [Quickshell.shellPath("scripts/setup-scan"), "list"]
        stdout: SplitParser { onRead: line => scan.collected.push(line) }
        onExited: {
            root.conflicts = scan.collected.map(line => {
                const f = line.split("\t");
                return { "pid": f[0], "name": f[1], "what": f[2], "from": f[3] || "none" };
            });
        }
    }

    function stop(conflict) {
        if (root.stopping[conflict.pid])
            return;
        const marks = Object.assign({}, root.stopping);
        marks[conflict.pid] = true;
        root.stopping = marks;
        if (conflict.what === "notifications")
            root.restartAtEnd = true;

        const runner = stopper.createObject(root, { "conflict": conflict });
        runner.running = true;
    }

    Component {
        id: stopper

        Process {
            id: run
            property var conflict: ({})
            property var collected: []
            command: [Quickshell.shellPath("scripts/setup-scan"), "stop",
                      run.conflict.pid, run.conflict.name, run.conflict.from]
            stderr: SplitParser { onRead: line => run.collected.push(line) }
            onExited: code => {
                const marks = Object.assign({}, root.stopping);
                delete marks[run.conflict.pid];
                root.stopping = marks;
                const errors = Object.assign({}, root.stopErrors);
                if (code !== 0)
                    errors[run.conflict.pid] = run.collected.length > 0
                        ? run.collected[run.collected.length - 1] : "It could not be stopped.";
                root.stopErrors = errors;
                scan.collected = [];
                scan.running = true;
                run.destroy();
            }
        }
    }

    // ---- Services ------------------------------------------------------------

    property var enabling: ({})     // unit → true while pkexec runs
    property var enableErrors: ({})

    function enableService(unit) {
        if (root.enabling[unit])
            return;
        const marks = Object.assign({}, root.enabling);
        marks[unit] = true;
        root.enabling = marks;
        const runner = enabler.createObject(root, { "unit": unit });
        runner.running = true;
    }

    Component {
        id: enabler

        Process {
            id: run
            property string unit: ""
            command: ["pkexec", "systemctl", "enable", "--now", run.unit]
            onExited: code => {
                const marks = Object.assign({}, root.enabling);
                delete marks[run.unit];
                root.enabling = marks;
                const errors = Object.assign({}, root.enableErrors);
                if (code === 126)
                    errors[run.unit] = "not given";
                else if (code === 127)
                    errors[run.unit] = "no agent";
                else if (code !== 0)
                    errors[run.unit] = "failed";
                else
                    delete errors[run.unit];
                root.enableErrors = errors;
                report.collected = [];
                report.running = true;
                run.destroy();
            }
        }
    }

    // The one command that installs what is missing: pacman for the
    // repositories, paru for the AUR. Bioma never runs a package manager.
    readonly property string installCommand: {
        const repo = [];
        const aur = [];
        for (const entry of root.missing) {
            const name = (entry.package || "").replace(/^AUR /, "");
            if (name.length === 0 || name.indexOf(" ") >= 0)
                continue;
            ((entry.package || "").startsWith("AUR ") ? aur : repo).push(name);
        }
        const parts = [];
        if (repo.length > 0)
            parts.push(`sudo pacman -S --needed ${repo.join(" ")}`);
        if (aur.length > 0)
            parts.push(`paru -S --needed ${aur.join(" ")}`);
        return parts.join(" && ");
    }

    readonly property string dictationCommand:
        "paru -S whisper-cpp ggml-vulkan whisper.cpp-model-large-v3-turbo-q5_0 python-evdev"

    readonly property bool dictationMissing: root.optional.some(entry => !entry.ok
        && (entry.name === "whisper-cli" || entry.name === "model"))

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    // ---- The keys ------------------------------------------------------------

    // The seven to know, by the title niri's hotkey overlay shows them under,
    // so what is drawn is what is actually bound in the user's own file.
    readonly property var keyList: [
        { "title": "Bioma: launcher", "line": "Applications, and files by name." },
        { "title": "Bioma: settings", "line": "This, and the whole layout." },
        { "title": "Bioma: theme", "line": "Palette and wallpaper." },
        { "title": "Bioma: capture", "line": "Screenshots, recordings, text from a region." },
        { "title": "Bioma: vitals", "line": "What the machine is doing." },
        { "title": "Bioma: system", "line": "Lock, sleep, log out, shut down." },
        { "title": "Bioma: lock", "line": "The lock screen." }
    ]

    readonly property var keys: root.keyList.map(entry => {
        let caps = [];
        for (const bind of Keybinds.binds)
            if (!bind.shadowed && bind.props && bind.props["hotkey-overlay-title"] === entry.title)
                caps = bind.caps;
        return { "caps": caps, "line": entry.line, "name": entry.title.replace(/^Bioma: /, "").toUpperCase() };
    })
}
