pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core

// The machine's vital signs: load, memory, clock, GPU, battery, processes.
//
// A rewrite, not a port. Prisma's service had CPU percent, RAM and a process
// list and nothing else — no clock, no GPU, no battery — which is to say it had
// none of the four quantities that make vitals move (PRD §9.2). Every motion in
// that cell is a rate, and a rate needs a number Prisma never sampled.
//
// It also spawned three processes every two to three seconds to read two files:
// `sh -c head -1 /proc/stat`, `sh -c grep /proc/meminfo`, and `ps`. Nothing here
// spawns anything on the sampling path. `FileView` reads /proc and sysfs
// directly, kernel files included — verified, despite their reporting a size of
// zero — so the steady state of this service is a timer and six file reads.
//
// Two processes remain, neither of them per sample: one `sh` glob at startup to
// find the GPU, the same shape as the backlight probe in Brightness.qml, and
// `ps` while the expanded cell is open and asking for a process list.
Singleton {
    id: root

    // ── Sampling ─────────────────────────────────────────────────────────
    //
    // One cadence for everything. Two timers at 2 s and 3 s, as Prisma had,
    // means two wakeups where one does, and it makes any relationship between
    // two figures — a load rising as a clock falls — impossible to trust,
    // because they were not read at the same moment.

    readonly property int interval: Config.get("vitals.interval", 2000)

    Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    function sample() {
        statFile.reload();
        memoryFile.reload();
        clockFile.reload();
        if (root.gpuPath.length > 0) {
            gpuBusyFile.reload();
            gpuClockFile.reload();
            gpuVramFile.reload();
        }
        if (root.temperaturePath.length > 0)
            temperatureFile.reload();
    }

    // `reload()` is asynchronous, and this is the trap in it: the text is
    // unchanged for the rest of the tick, so reading it straight after the call
    // returns the previous sample. Read it in `onLoaded` — which fires on every
    // reload, not only the first — and never immediately after asking.
    //
    // Reading it inline looks like it works: the figures are plausible, merely
    // one tick stale, and a CPU delta computed from two identical readings is
    // a flat zero that looks like an idle machine.

    // ── CPU load ─────────────────────────────────────────────────────────

    property real cpuPercent: 0

    // The previous cumulative counters. Load is a delta between two samples,
    // so the first sample after start has nothing to compare against and
    // reports zero rather than a fabricated figure.
    property var previousCpu: null

    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
        onLoaded: root.readLoad(statFile.text())
    }

    function readLoad(text) {
        // Only the aggregate line is wanted, and it is the first. The rest of
        // the file is per-core and several kilobytes; splitting it every tick
        // to throw it away is work for nothing.
        const end = text.indexOf("\n");
        const line = end < 0 ? text : text.slice(0, end);
        const parts = line.trim().split(/\s+/);
        if (parts[0] !== "cpu")
            return;

        const numbers = parts.slice(1).map(Number);
        const idle = numbers[3] + (numbers[4] ?? 0);  // idle + iowait
        const total = numbers.reduce((a, b) => a + b, 0);

        if (root.previousCpu) {
            const idleDelta = idle - root.previousCpu.idle;
            const totalDelta = total - root.previousCpu.total;
            if (totalDelta > 0)
                root.cpuPercent = Math.max(0, Math.min(100,
                    (1 - idleDelta / totalDelta) * 100));
        }
        root.previousCpu = { idle: idle, total: total };
    }

    // ── CPU clock ────────────────────────────────────────────────────────
    //
    // This is what the cardiac beat rate is made of, and PRD §9.2 requires a
    // moving average: a real clock swings hundreds of megahertz between two
    // samples as cores boost and drop, and a beat following that raw figure is
    // arrhythmic rather than alive.

    readonly property int averageWindow: Config.get("vitals.clock_average", 5)

    property real cpuClockRaw: 0   // MHz, this sample
    property real cpuClock: 0      // MHz, averaged over the window
    property var clockSamples: []
    property int cores: 0

    FileView {
        id: clockFile
        path: "/proc/cpuinfo"
        blockLoading: true
        onLoaded: root.readClock(clockFile.text())
    }

    function readClock(text) {
        // Averaged across cores, then across time. The per-core figure is not
        // interesting on its own — one core at 5 GHz while thirty-one idle is
        // not a machine working hard — and the cell draws one heart.
        const pattern = /cpu MHz\s*:\s*([\d.]+)/g;
        let sum = 0;
        let count = 0;
        let match = pattern.exec(text);
        while (match !== null) {
            sum += parseFloat(match[1]);
            count++;
            match = pattern.exec(text);
        }
        if (count === 0)
            return;

        root.cores = count;
        root.cpuClockRaw = sum / count;

        const samples = root.clockSamples.slice();
        samples.push(root.cpuClockRaw);
        while (samples.length > Math.max(1, root.averageWindow))
            samples.shift();
        root.clockSamples = samples;

        root.cpuClock = samples.reduce((a, b) => a + b, 0) / samples.length;
    }

    // The clock's own range, so that no cell has to carry a hardcoded ceiling.
    // A fraction is what the beat mapping wants: §9.2 warns against a fixed
    // ratio, because 5 GHz → 50 bpm makes an 800 MHz idle an 8 bpm beat, which
    // reads as a dead machine rather than a calm one. The cell maps this
    // fraction onto a legible cardiac range; the service supplies the fraction.
    property real cpuClockMin: 0   // MHz
    property real cpuClockMax: 0   // MHz

    readonly property bool cpuClockRangeKnown: cpuClockMax > cpuClockMin

    readonly property real cpuClockFraction: cpuClockRangeKnown
        ? Math.max(0, Math.min(1, (cpuClock - cpuClockMin) / (cpuClockMax - cpuClockMin)))
        : 0

    // Read once, not sampled: these do not change. A machine without cpufreq —
    // a virtual machine, typically — simply has no range, and says so through
    // `cpuClockRangeKnown` rather than through a plausible wrong number.
    FileView {
        id: clockMinFile
        path: "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"
        blockLoading: true
        printErrors: false
        onLoaded: root.cpuClockMin = parseInt(clockMinFile.text().trim(), 10) / 1000
    }

    FileView {
        id: clockMaxFile
        path: "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
        blockLoading: true
        printErrors: false
        onLoaded: root.cpuClockMax = parseInt(clockMaxFile.text().trim(), 10) / 1000
    }

    // ── Memory ───────────────────────────────────────────────────────────

    property real ramTotal: 0   // MiB
    property real ramUsed: 0    // MiB
    readonly property real ramPercent: ramTotal > 0 ? (ramUsed / ramTotal) * 100 : 0

    readonly property real ramUsedGb: Math.round(ramUsed / 1024 * 10) / 10
    readonly property real ramTotalGb: Math.round(ramTotal / 1024 * 10) / 10

    property real swapTotal: 0  // MiB
    property real swapUsed: 0   // MiB
    readonly property real swapPercent: swapTotal > 0 ? (swapUsed / swapTotal) * 100 : 0

    FileView {
        id: memoryFile
        path: "/proc/meminfo"
        blockLoading: true
        onLoaded: root.readMemory(memoryFile.text())
    }

    function readMemory(text) {
        function field(name) {
            const match = text.match(new RegExp("^" + name + ":\\s+(\\d+)", "m"));
            return match ? parseInt(match[1], 10) / 1024 : 0;  // kB → MiB
        }

        const total = field("MemTotal");
        if (total <= 0)
            return;

        // Used is total minus *available*, not minus free. Free excludes the
        // page cache, which Linux fills with everything it has ever read; a
        // figure built on it reports a healthy machine as 95% full.
        root.ramTotal = total;
        root.ramUsed = Math.max(0, total - field("MemAvailable"));

        const swap = field("SwapTotal");
        root.swapTotal = swap;
        root.swapUsed = swap > 0 ? Math.max(0, swap - field("SwapFree")) : 0;
    }

    // ── GPU ──────────────────────────────────────────────────────────────
    //
    // On AMD every figure here is a sysfs read, no more expensive than
    // /proc/stat — the PRD's worry about GPU sampling cost does not apply to
    // this hardware. It does apply on NVIDIA, where the same numbers come out
    // of `nvidia-smi`, so the sampler is shaped to let the source be swapped:
    // everything below reads from `gpuPath`, and nothing else knows where the
    // figures come from.

    property string gpuPath: ""
    property string gpuName: ""
    readonly property bool gpuPresent: gpuPath.length > 0

    // Picking by index is wrong: card0 on this machine is a 512 MB integrated
    // Raphael and card1 the 17 GB discrete card, and the interesting one is the
    // second. The largest VRAM wins, and the configuration overrides.
    readonly property string configuredCard: Config.get("vitals.gpu_card", "")

    Process {
        id: gpuProbe
        property var found: []

        command: ["sh", "-c",
                  "for d in /sys/class/drm/card*/device; do "
                  + "[ -e \"$d/gpu_busy_percent\" ] || continue; "
                  + "printf '%s %s\\n' \"$d\" \"$(cat \"$d/mem_info_vram_total\" 2>/dev/null || echo 0)\"; "
                  + "done"]
        running: true

        onRunningChanged: if (running) gpuProbe.found = []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.trim().split(/\s+/);
                if (parts.length < 2)
                    return;
                gpuProbe.found.push({ path: parts[0], vram: parseInt(parts[1], 10) || 0 });
            }
        }

        onExited: {
            const found = gpuProbe.found;
            if (found.length === 0)
                return;

            let chosen = found[0];
            if (root.configuredCard.length > 0) {
                const match = found.find(c => c.path.indexOf(root.configuredCard) >= 0);
                if (match)
                    chosen = match;
            } else {
                for (const candidate of found)
                    if (candidate.vram > chosen.vram)
                        chosen = candidate;
            }

            root.vramTotal = chosen.vram / (1024 * 1024);  // bytes → MiB
            root.gpuName = chosen.path.split("/")[4] ?? "";  // cardN
            root.gpuPath = chosen.path;
            root.sample();
        }
    }

    // Utilisation and clock are deliberately separate, and §9.2 is explicit
    // about why: they diverge. A card at 30% utilisation can sit at full clock,
    // and the cell encodes one as colour and the other as rotation — a fast
    // green satellite meaning "working quickly without strain". Collapsing
    // them into one number destroys the only thing that cell says.

    property real gpuPercent: 0

    FileView {
        id: gpuBusyFile
        path: root.gpuPath.length > 0 ? root.gpuPath + "/gpu_busy_percent" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.gpuPercent = parseInt(gpuBusyFile.text().trim(), 10) || 0
    }

    property real gpuClock: 0      // MHz
    property real gpuClockMin: 0   // MHz
    property real gpuClockMax: 0   // MHz
    property bool gpuAsleep: false

    readonly property real gpuClockFraction: gpuClockMax > gpuClockMin
        ? Math.max(0, Math.min(1, (gpuClock - gpuClockMin) / (gpuClockMax - gpuClockMin)))
        : 0

    FileView {
        id: gpuClockFile
        path: root.gpuPath.length > 0 ? root.gpuPath + "/pp_dpm_sclk" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.readGpuClock(gpuClockFile.text())
    }

    // `pp_dpm_sclk` is a table of power states, one per line, the current one
    // marked with an asterisk:
    //
    //     0: 500Mhz
    //     1: 1602Mhz *
    //     2: 2520Mhz
    //
    // and the table gives the card's own range, so the rotation has a ceiling
    // without one being written into a cell.
    //
    // A sleeping card answers `S: 68Mhz *` — a state, not an index. Measured
    // here on the discrete card, exactly as the inventory predicted. It means
    // asleep, not broken and not zero: a satellite frozen because a card idled
    // would say "the GPU has stopped" when nothing is wrong.
    function readGpuClock(text) {
        let current = -1;
        let lowest = -1;
        let highest = -1;
        let asleep = false;

        for (const line of text.split("\n")) {
            const match = line.match(/^\s*(\S+):\s*(\d+)\s*Mhz\s*(\*?)/i);
            if (!match)
                continue;

            const index = match[1];
            const value = parseInt(match[2], 10);
            const isCurrent = match[3] === "*";

            if (isCurrent) {
                current = value;
                asleep = isNaN(parseInt(index, 10));
            }

            // Sleep states are not part of the operating range and must not
            // drag the floor down, or every clock above idle reads as maximal.
            if (isNaN(parseInt(index, 10)))
                continue;
            if (lowest < 0 || value < lowest)
                lowest = value;
            if (value > highest)
                highest = value;
        }

        if (lowest >= 0) {
            root.gpuClockMin = lowest;
            root.gpuClockMax = highest;
        }
        if (current >= 0) {
            root.gpuClock = current;
            root.gpuAsleep = asleep;
        }
    }

    property real vramTotal: 0  // MiB
    property real vramUsed: 0   // MiB
    readonly property real vramPercent: vramTotal > 0 ? (vramUsed / vramTotal) * 100 : 0

    FileView {
        id: gpuVramFile
        path: root.gpuPath.length > 0 ? root.gpuPath + "/mem_info_vram_used" : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.vramUsed = (parseInt(gpuVramFile.text().trim(), 10) || 0) / (1024 * 1024)
    }

    // ── CPU temperature ──────────────────────────────────────────────────
    //
    // What the lava organism is heated by. One figure for the package, the one
    // the fans follow: `Tctl` on AMD (k10temp; `Tdie` under zenpower), `Package
    // id 0` on Intel (coretemp). A machine with neither falls back to the
    // thermal zones — `x86_pkg_temp`, then a CPU zone on ARM, then `acpitz`,
    // which on many laptops is the closest thing to a CPU reading there is.
    //
    // Found once at startup by the same kind of glob as the GPU. Which hwmon
    // is which changes between boots, so the index is never trusted; the name
    // and the label are. `vitals.temperature_sensor` overrides the choice with
    // any part of the input file's path.

    property string temperaturePath: ""
    property real cpuTemperature: 0   // °C
    readonly property bool cpuTemperatureKnown: temperaturePath.length > 0

    readonly property string configuredSensor: Config.get("vitals.temperature_sensor", "")

    Process {
        id: temperatureProbe
        property var found: []

        command: ["sh", "-c",
                  "for h in /sys/class/hwmon/hwmon*; do "
                  + "n=$(cat \"$h/name\" 2>/dev/null); "
                  + "for i in \"$h\"/temp*_input; do [ -e \"$i\" ] || continue; "
                  + "l=$(cat \"${i%_input}_label\" 2>/dev/null); "
                  + "printf 'hwmon\\t%s\\t%s\\t%s\\n' \"$n\" \"$l\" \"$i\"; done; done; "
                  + "for z in /sys/class/thermal/thermal_zone*; do [ -e \"$z/temp\" ] || continue; "
                  + "printf 'zone\\t%s\\t\\t%s\\n' \"$(cat \"$z/type\" 2>/dev/null)\" \"$z/temp\"; done"]
        running: true

        onRunningChanged: if (running) temperatureProbe.found = []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.split("\t");
                if (parts.length < 4)
                    return;
                temperatureProbe.found.push({ kind: parts[0], name: parts[1], label: parts[2], path: parts[3] });
            }
        }

        onExited: {
            const found = temperatureProbe.found;
            let chosen = null;

            if (root.configuredSensor.length > 0)
                chosen = found.find(s => s.path.indexOf(root.configuredSensor) >= 0) ?? null;

            // In order of trust: the vendor's package sensor, then the zones.
            const wanted = [
                s => s.name === "k10temp" && s.label === "Tctl",
                s => s.name === "zenpower" && s.label === "Tdie",
                s => s.name === "k10temp",
                s => s.name === "coretemp" && s.label.indexOf("Package") === 0,
                s => s.kind === "zone" && s.name === "x86_pkg_temp",
                s => s.kind === "zone" && /^cpu/.test(s.name),
                s => s.kind === "zone" && s.name === "acpitz"
            ];
            for (const test of wanted) {
                if (chosen)
                    break;
                chosen = found.find(test) ?? null;
            }

            if (!chosen)
                return;
            root.temperaturePath = chosen.path;
            temperatureFile.reload();
        }
    }

    FileView {
        id: temperatureFile
        path: root.temperaturePath
        blockLoading: true
        printErrors: false
        // Millidegrees, for hwmon and the zones alike.
        onLoaded: {
            const value = parseInt(temperatureFile.text().trim(), 10);
            if (!isNaN(value))
                root.cpuTemperature = value / 1000;
        }
    }

    // ── Battery ──────────────────────────────────────────────────────────
    //
    // Native, and the reason vitals is the first cell whose composition varies
    // with the hardware: three indicators on a desktop, four on a laptop, from
    // one cell and one config block. `isLaptopBattery` is the presence test —
    // UPower always has a display device, and on a desktop it is a placeholder
    // that would otherwise draw a permanently empty battery.

    readonly property var batteryDevice: UPower.displayDevice
    readonly property bool hasBattery: (batteryDevice?.isLaptopBattery ?? false)
        && (batteryDevice?.isPresent ?? false)

    // UPower's own scale, unverified here: this machine has no battery, and
    // `/sys/class/power_supply/` is empty. `Networking.signalStrength` turned
    // out to be a fraction where Prisma assumed a percentage (INVENTORY §15.2),
    // so this is left raw and named for what it is rather than converted on a
    // guess. Verify on a laptop before a cell divides it by anything.
    readonly property real batteryLevelRaw: batteryDevice?.percentage ?? 0

    readonly property int batteryState: batteryDevice?.state ?? UPowerDeviceState.Unknown
    readonly property string batteryStateName: UPowerDeviceState.toString(batteryState)

    readonly property bool charging: batteryState === UPowerDeviceState.Charging
        || batteryState === UPowerDeviceState.PendingCharge
    readonly property bool full: batteryState === UPowerDeviceState.FullyCharged

    // Seconds. The direction that matters is the one the machine is going in:
    // while charging the cell inverts, the level rising rather than falling.
    readonly property real batterySecondsLeft: charging
        ? (batteryDevice?.timeToFull ?? 0)
        : (batteryDevice?.timeToEmpty ?? 0)

    // The line under the battery's figure: how long is left, not that it is
    // discharging, and while charging how long until full. Nothing else draws
    // the charge, so the second says FULL — "FULL IN" does not fit the matrix's
    // 120 px pod. UPower answers 0 while it is still estimating, and then the
    // state is all there is to say.
    readonly property bool discharging: batteryState === UPowerDeviceState.Discharging
    readonly property string batteryDetail: {
        if ((discharging || batteryState === UPowerDeviceState.Charging) && batterySecondsLeft > 0) {
            const minutes = Math.round(batterySecondsLeft / 60);
            const h = Math.floor(minutes / 60);
            const m = minutes % 60;
            const time = h > 0 ? `${h} H ${String(m).padStart(2, "0")} M` : `${m} M`;
            return discharging ? time : `FULL ${time}`;
        }
        return batteryStateName;
    }

    readonly property bool onBattery: UPower.onBattery

    // ── Processes ────────────────────────────────────────────────────────
    //
    // The one sample that cannot come from a couple of files: a process list
    // means reading a directory of a few hundred entries, which `ps` already
    // does well. It is therefore the one sample that is not taken unless it is
    // being looked at — the expanded cell sets `listProcesses` when it opens
    // and clears it when it closes, and nothing runs in between.
    //
    // Prisma ran `ps` every three seconds for the life of the session to feed a
    // list that is visible for a few seconds at a time.

    property bool listProcesses: false
    property var processes: []

    readonly property int processInterval: Config.get("vitals.process_interval", 3000)
    readonly property int processCount: Config.get("vitals.process_count", 60)

    Timer {
        interval: root.processInterval
        running: root.listProcesses
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshProcesses()
    }

    onListProcessesChanged: if (!root.listProcesses) root.processes = [];

    function refreshProcesses() {
        processProbe.running = false;
        processProbe.running = true;
    }

    Process {
        id: processProbe
        property var found: []

        // Sorted by CPU here, and re-sorted in the cell: §9.2 sorts by RAM by
        // default and re-sorts when an indicator is clicked, which is a change
        // of view, not a reason to run `ps` again.
        command: ["sh", "-c",
                  "ps -eo pid,comm,pcpu,pmem,rss --sort=-%cpu --no-headers 2>/dev/null | head -"
                  + root.processCount]
        running: false

        onRunningChanged: if (running) processProbe.found = []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.trim().split(/\s+/);
                if (parts.length < 5)
                    return;
                processProbe.found.push({
                    pid: parseInt(parts[0], 10),
                    name: parts[1],
                    cpu: parseFloat(parts[2]),
                    memPercent: parseFloat(parts[3]),
                    memMb: Math.round(parseInt(parts[4], 10) / 1024)
                });
            }
        }

        // Applied at once, never appended to a live list: a list that grows a
        // row at a time under the user's hand moves the row they were reaching
        // for.
        onExited: root.processes = processProbe.found.slice()
    }

    // TERM, not KILL. §9.2 puts a confirmation in front of this, and the
    // confirmation grows out of the row being terminated — but the refusal to
    // escalate belongs here: a shell that SIGKILLs on a single click loses
    // whatever the application had not written to disk.
    function terminate(pid) {
        killProcess.command = ["kill", "-TERM", String(pid)];
        killProcess.running = false;
        killProcess.running = true;
    }

    Process {
        id: killProcess
        running: false
        onExited: if (root.listProcesses) root.refreshProcesses()
    }
}
