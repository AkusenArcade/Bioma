pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core

// How hard the machine is allowed to work: saver, balanced, performance.
//
// The daemon does the work — power-profiles-daemon, or tuned's stand-in for it,
// both on `org.freedesktop.UPower.PowerProfiles` — and Quickshell already talks
// to it, so this file only names the three in the shell's words and says
// whether there is anyone to talk to at all.
//
// That second part is the one Quickshell does not answer. With no daemon its
// profile simply stays at its default, balanced, which reads exactly like a
// machine that is balanced. So the bus is asked once whether the name has an
// owner, and asked again each time somebody looks while the answer is still no.
// Nothing polls.
//
// On a machine with a battery the profile can follow the power source:
// `power.on_battery` and `power.on_mains`, each a profile or `keep`. It is
// applied when the source changes, when the shell starts, and when the
// setting itself changes — and nowhere else, so a profile chosen by hand
// holds until the plug does something.
Singleton {
    id: root

    // Bound, not read: Quickshell's singletons start on their first binding.
    readonly property int current: PowerProfiles.profile
    readonly property bool performanceAvailable: PowerProfiles.hasPerformanceProfile
    readonly property int degradation: PowerProfiles.degradationReason

    // Whether a daemon answers on the bus.
    property bool present: false

    readonly property string profile: root.current === PowerProfile.PowerSaver ? "saver"
                                    : root.current === PowerProfile.Performance ? "performance"
                                    : "balanced"

    // Why performance is running below itself, in a person's words, or "" when
    // it is not. The daemon decides; the laptop on a lap or running hot is not
    // something the shell can change, only say.
    readonly property string heldBack: {
        if (root.profile !== "performance")
            return "";
        if (root.degradation === PerformanceDegradationReason.LapDetected)
            return "Held back: the machine is on a lap";
        if (root.degradation === PerformanceDegradationReason.HighTemperature)
            return "Held back: the machine is running hot";
        return "";
    }

    // ---- Following the power source -----------------------------------------

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: (root.battery?.isLaptopBattery ?? false)
        && (root.battery?.isPresent ?? false)
    readonly property bool onBattery: UPower.onBattery

    // UPower answers in pieces: the display device can be ready a moment
    // before `onBattery` has its real value, and starting unplugged would then
    // set the mains profile and the battery one straight after.
    readonly property bool settled: root.present && root.hasBattery
        && (root.battery?.ready ?? false)

    readonly property string onBatteryProfile: Config.get("power.on_battery", "keep")
    readonly property string onMainsProfile: Config.get("power.on_mains", "keep")
    readonly property string wanted: root.onBattery ? root.onBatteryProfile : root.onMainsProfile

    onSettledChanged: follow.restart()
    onOnBatteryChanged: follow.restart()
    onWantedChanged: follow.restart()

    // Short enough that nobody waits for it, long enough to let UPower finish
    // answering — and a plug that is wiggled sets the profile once, not four
    // times.
    Timer {
        id: follow
        interval: 400
        onTriggered: {
            if (root.settled && root.wanted !== "keep")
                root.set(root.wanted);
        }
    }

    function set(key) {
        if (!root.present)
            return;
        if (key === "saver")
            PowerProfiles.profile = PowerProfile.PowerSaver;
        else if (key === "performance" && root.performanceAvailable)
            PowerProfiles.profile = PowerProfile.Performance;
        else if (key === "balanced")
            PowerProfiles.profile = PowerProfile.Balanced;
    }

    // Called when the panel that shows this opens.
    function ask() {
        if (!root.present && !owner.running)
            owner.running = true;
    }

    Process {
        id: owner
        command: ["busctl", "--system", "--no-pager", "status",
                  "org.freedesktop.UPower.PowerProfiles"]
        running: true
        onExited: code => root.present = code === 0
    }
}
