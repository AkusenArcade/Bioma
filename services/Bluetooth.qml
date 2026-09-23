pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bluez

// Bluetooth: adapter, devices, pairing.
//
// There is no bluetooth service in Prisma to port — only a settings page that
// drove `bluetoothctl` through four processes: `show` scraped for `Powered:`,
// `devices` scraped for MAC and name, then one `bluetoothctl info` per device
// walked one at a time to find out which were connected, and a ten second scan
// timer on top. Every one of those is a property here, pushed from BlueZ over
// D-Bus by `Quickshell.Bluetooth`. None of that page is the starting point, and
// the 372 lines it cost are not a measure of the work.
//
// The import is namespaced because the module exports a `Bluetooth` singleton,
// which would otherwise collide with this file's own name inside qs.services.
Singleton {
    id: root

    // ── Adapter ──────────────────────────────────────────────────────────

    readonly property var adapter: Bluez.Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null

    readonly property string adapterName: adapter?.name ?? ""
    readonly property string adapterId: adapter?.adapterId ?? ""

    readonly property bool enabled: adapter?.enabled ?? false
    readonly property int state: adapter?.state ?? Bluez.BluetoothAdapterState.Disabled
    readonly property string stateName: Bluez.BluetoothAdapterState.toString(state)

    // rfkill, and the reason a power toggle can refuse. Distinguishing it from
    // a plain off is what stops the toggle looking broken.
    readonly property bool blocked: state === Bluez.BluetoothAdapterState.Blocked

    // Enabling and disabling are not instant — BlueZ passes through Enabling
    // and Disabling — and a toggle that snaps to its new position before the
    // adapter agrees is lying about the state of the machine.
    readonly property bool settling: state === Bluez.BluetoothAdapterState.Enabling
        || state === Bluez.BluetoothAdapterState.Disabling

    // No check against `blocked`, for the same reason as the Wi-Fi switch: the
    // adapter reads as blocked before BlueZ has answered, and a guarded toggle
    // would eat the first press of the session. BlueZ refuses the write while
    // rfkill holds the radio; `blocked` is for saying why nothing moved.
    function setEnabled(on) {
        if (root.adapter)
            root.adapter.enabled = on;
    }

    // ── Discovery ────────────────────────────────────────────────────────
    //
    // Discovery costs power and floods the list with every phone in the room,
    // so like the Wi-Fi scanner it belongs to the expanded cell and runs only
    // while someone is looking. Nothing here starts it.

    property bool discovering: false

    Binding {
        target: root.adapter
        property: "discovering"
        value: root.discovering
        when: root.adapter !== null && root.enabled
    }

    // Whether the adapter is actually discovering, which is not the same as
    // having asked it to: it stops on its own, and it cannot start while off.
    readonly property bool scanning: adapter?.discovering ?? false

    // ── Devices ──────────────────────────────────────────────────────────

    // Every adapter's devices, not just the default one's. A machine with a
    // dongle as well as a built-in radio has two, and a headset connected
    // through either one is connected as far as the cell is concerned.
    readonly property var devices: Bluez.Bluetooth.devices?.values ?? []

    readonly property var connectedDevices: devices.filter(d => d.connected)
    readonly property var pairedDevices: devices.filter(d => d.paired)
    readonly property var discoveredDevices: devices.filter(d => !d.paired)

    readonly property bool anyConnected: connectedDevices.length > 0

    // The device the contracted cell speaks for when several are connected.
    // Whatever connected first, which is stable — sorting by name would reorder
    // the glyph under the user's hand for no reason.
    readonly property var primary: connectedDevices[0] ?? null

    // A device is in the middle of something: BlueZ reports Connecting and
    // Disconnecting, and pairing is its own flag.
    function isBusy(device) {
        if (!device)
            return false;
        return device.pairing
            || device.state === Bluez.BluetoothDeviceState.Connecting
            || device.state === Bluez.BluetoothDeviceState.Disconnecting;
    }

    function describeState(device) {
        return Bluez.BluetoothDeviceState.toString(
            device?.state ?? Bluez.BluetoothDeviceState.Disconnected);
    }

    // A device's own words for itself. `name` is the alias, which is what the
    // user renamed it to if they ever did; `deviceName` is what the device
    // broadcasts. The address is the last resort and is never pretty.
    function describe(device) {
        if (!device)
            return "";
        return device.name || device.deviceName || device.address || "";
    }

    // A freedesktop icon name — `audio-headset`, `input-mouse`, `phone`. This
    // is what lets the cell say which domain a device belongs to by its form
    // rather than by its name (PRD §5.3).
    function icon(device) {
        return device?.icon ?? "";
    }

    // ── Battery ──────────────────────────────────────────────────────────
    //
    // Only some devices report one, and `batteryAvailable` is the only way to
    // tell a device with no battery from one reading zero.

    function hasBattery(device) {
        return device?.batteryAvailable ?? false;
    }

    // Raw, as BlueZ gives it.
    function battery(device) {
        return device?.battery ?? 0;
    }

    // The scale is not verified. BlueZ's own Battery1 percentage is 0–100,
    // Quickshell's UPower device reports 0–1, and this machine has no bluetooth
    // device to settle which convention this module follows — so it is read as
    // a fraction below 1 and as a percentage above, which is right either way
    // except for a device sitting at exactly 1%. Verify against a real headset
    // and then delete this.
    function batteryPercent(device) {
        const value = root.battery(device);
        return Math.round(value <= 1 ? value * 100 : value);
    }

    // ── Actions ──────────────────────────────────────────────────────────

    function connectDevice(device) {
        device?.connect();
    }

    function disconnectDevice(device) {
        device?.disconnect();
    }

    function pair(device) {
        device?.pair();
    }

    // Pairing a found device is the start, not the end: somebody pressing a
    // headset in the list wants to hear it. So once it pairs it is trusted —
    // it may reconnect by itself from then on — and connected. Pairing needs
    // no agent for a device that asks for nothing (headsets, mice, speakers);
    // one that shows a code to confirm cannot be paired from here, since
    // Quickshell registers no agent, and it says so by failing.
    property var pending: null
    property string failedAddress: ""

    function pairAndConnect(device) {
        if (!device)
            return;
        root.failedAddress = "";
        root.pending = device;
        device.pair();
    }

    Connections {
        target: root.pending
        function onPairedChanged() {
            const device = root.pending;
            if (!device || !device.paired)
                return;
            device.trusted = true;
            device.connect();
            root.pending = null;
        }
        function onPairingChanged() {
            const device = root.pending;
            if (device && !device.pairing && !device.paired) {
                root.failedAddress = device.address;
                root.pending = null;
            }
        }
    }

    // What discovery has found that is worth a row: it has a name. Nameless
    // devices are the neighbours' fridges.
    readonly property var foundDevices: discoveredDevices.filter(d => (d.name || d.deviceName || "").length > 0
                                                                      && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(d.name || ""))

    function cancelPair(device) {
        device?.cancelPair();
    }

    function forget(device) {
        device?.forget();
    }

    function setTrusted(device, trusted) {
        if (device)
            device.trusted = trusted;
    }

    // ── What the cell composes itself from ───────────────────────────────
    //
    // PRD §9.11: no active device, no glyph. A powered adapter with nothing
    // connected has nothing to say, so this is empty — the cell does not
    // announce that bluetooth exists.

    readonly property var active: connectedDevices.map(device => ({
        kind: "bluetooth",
        label: root.describe(device),
        icon: root.icon(device),
        detail: root.hasBattery(device) ? `${root.batteryPercent(device)}%` : "",
        device: device
    }))
}
