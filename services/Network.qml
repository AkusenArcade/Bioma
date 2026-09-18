pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking as Net

// Networking: wired and wireless, from one push-based source.
//
// Prisma took Wi-Fi from this same module but polled ethernet every ten seconds
// with `nmcli -t -f TYPE,STATE,DEVICE,CONNECTION device`, accumulating into
// scratch properties to survive the race between two runs. None of that is here:
// `Quickshell.Networking` exposes `WiredDevice` alongside `WifiDevice`, so the
// poll, the parser and the race it was guarding against all go away. Nothing in
// this file runs a process.
//
// A ten second poll was in any case too slow for the connectivity cell, whose
// whole idea is that its width says how many connections are live (PRD §9.11):
// plugging a cable in would have taken up to ten seconds to widen the cell.
//
// The import is namespaced because the module exports a type called `Network`,
// which would otherwise collide with this file's own name inside qs.services.
Singleton {
    id: root

    // ── Backend ──────────────────────────────────────────────────────────

    readonly property int backend: Net.Networking.backend
    readonly property bool available: backend !== Net.NetworkBackendType.None
    readonly property string backendName: Net.NetworkBackendType.toString(backend)

    readonly property var devices: Net.Networking.devices?.values ?? []

    function describeState(state) {
        return Net.ConnectionState.toString(state ?? Net.ConnectionState.Unknown);
    }

    // ── Wired ────────────────────────────────────────────────────────────

    readonly property var wiredDevice: devices.find(d => d.type === Net.DeviceType.Wired) ?? null

    readonly property bool wiredPresent: wiredDevice !== null
    readonly property bool wiredConnected: wiredDevice?.connected ?? false

    // A cable in a dead switch has a link and no connection, and a connection
    // being negotiated has a link before it has an address. The cell draws
    // `wiredConnected`; `wiredHasLink` is what tells a settings page the
    // difference between "unplugged" and "plugged in, going nowhere".
    readonly property bool wiredHasLink: wiredDevice?.hasLink ?? false

    readonly property string wiredInterface: wiredDevice?.name ?? ""
    readonly property string wiredName: wiredDevice?.network?.name ?? ""
    readonly property string wiredAddress: wiredDevice?.address ?? ""
    readonly property int wiredSpeed: wiredDevice?.linkSpeed ?? 0  // Mb/s
    readonly property int wiredState: wiredDevice?.state ?? Net.ConnectionState.Unknown

    function disconnectWired() {
        root.wiredDevice?.disconnect();
    }

    // ── Wi-Fi ────────────────────────────────────────────────────────────

    readonly property var wifiDevice: devices.find(d => d.type === Net.DeviceType.Wifi) ?? null
    readonly property bool wifiPresent: wifiDevice !== null

    // Two different offs. `wifiEnabled` is the soft switch, ours to set;
    // `wifiHardwareEnabled` is rfkill's hard block, and while it is false the
    // soft switch cannot be turned on — a toggle that ignores this appears to
    // fail at random.
    readonly property bool wifiEnabled: Net.Networking.wifiEnabled
    readonly property bool wifiHardwareEnabled: Net.Networking.wifiHardwareEnabled

    readonly property var wifiNetworks: wifiDevice?.networks?.values ?? []
    readonly property var activeWifi: wifiNetworks.find(n => n.connected) ?? null

    readonly property bool wifiConnected: activeWifi !== null
    readonly property string ssid: activeWifi?.name ?? ""
    readonly property int wifiState: wifiDevice?.state ?? Net.ConnectionState.Unknown

    // A fraction, 0–1. Measured, because it matters: NetworkManager's own
    // number is 0–100 and Quickshell divides it before handing it over.
    // Prisma bucketed this as if it were still 0–100, so every network in its
    // list drew one bar whatever its strength — 0.4 is not 40 and falls in the
    // first bucket. Do not copy those thresholds back.
    readonly property real signalStrength: activeWifi?.signalStrength ?? 0
    readonly property int signalPercent: Math.round(signalStrength * 100)

    // Four buckets, because an indicator with five states is read as a number
    // and a number at rest is what §5.1 forbids.
    readonly property int signalBars: barsFor(signalStrength)

    function barsFor(strength) {
        const s = strength ?? 0;
        if (s <= 0)
            return 0;
        if (s <= 0.25)
            return 1;
        if (s <= 0.5)
            return 2;
        if (s <= 0.75)
            return 3;
        return 4;
    }

    function percentFor(strength) {
        return Math.round((strength ?? 0) * 100);
    }

    // Written straight through, with no check against the hard block. The check
    // was here and was wrong: `wifiHardwareEnabled` reads false for the first
    // moment of the session, before the module has answered, so a guarded
    // toggle silently did nothing and reported success. NetworkManager refuses
    // the write itself while rfkill holds the radio, which is the right place
    // for that decision; `wifiHardwareEnabled` is for saying why the switch
    // will not move, not for deciding whether to try.
    function setWifiEnabled(on) {
        Net.Networking.wifiEnabled = on;
    }

    // ── Scanning ─────────────────────────────────────────────────────────
    //
    // Scanning wakes the radio and costs power, and it is only ever wanted
    // while someone is looking at the list. The expanded cell owns this: it
    // turns the scanner on when it opens and off when it closes. Nothing here
    // starts it.

    property bool scanning: false

    // Declared rather than assigned in a handler: the device can arrive after
    // the scanner has been asked for — NetworkManager takes a moment to present
    // an interface that was rfkilled a second ago — and a handler that already
    // fired would leave the list empty and no scan running.
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.scanning
        when: root.wifiDevice !== null
    }

    // The visible list. Hidden networks broadcast no name and cannot be joined
    // from a list, so they are dropped; a repeater publishing one SSID from
    // several radios collapses to its strongest. Connected first, then what is
    // already known, then by strength — the order a person reads the list in.
    readonly property var visibleNetworks: {
        const best = ({});
        for (const network of root.wifiNetworks) {
            if (!network.name || network.name.length === 0)
                continue;
            const previous = best[network.name];
            if (!previous || network.connected || network.signalStrength > previous.signalStrength)
                best[network.name] = network;
        }
        return Object.values(best).sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.known !== b.known)
                return a.known ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
    }

    // ── Security ─────────────────────────────────────────────────────────

    function security(network) {
        return Net.WifiSecurityType.toString(network?.security ?? Net.WifiSecurityType.Unknown);
    }

    function isSecured(network) {
        if (!network)
            return false;
        return network.security !== Net.WifiSecurityType.Open
            && network.security !== Net.WifiSecurityType.Unknown;
    }

    // Whether the cell has to raise a password field. A known network has its
    // secret in NetworkManager already, so joining it is one call.
    function needsPassword(network) {
        return root.isSecured(network) && !(network?.known ?? false);
    }

    // ── Joining ──────────────────────────────────────────────────────────
    //
    // Failure arrives as a signal on the network object, not as a return value,
    // so the network being joined is held until it resolves one way or the
    // other. `pending` is also what a cell binds to draw a spinner against a
    // single row rather than the whole list.

    property var pending: null
    property string lastError: ""

    function join(network) {
        if (!network)
            return;
        root.lastError = "";
        root.pending = network;
        network.connect();
    }

    function joinWithPassword(network, password) {
        if (!network)
            return;
        root.lastError = "";
        root.pending = network;
        network.connectWithPsk(password);
    }

    function leave(network) {
        const target = network ?? root.activeWifi;
        if (target === root.pending)
            root.pending = null;
        target?.disconnect();
    }

    function forget(network) {
        if (network === root.pending)
            root.pending = null;
        network?.forget();
    }

    // NoSecrets is the wrong-password case and is the one worth saying plainly;
    // the rest are named as the backend names them, because inventing friendlier
    // words for six failure modes only makes them harder to look up.
    function describeFailure(reason) {
        if (reason === Net.ConnectionFailReason.NoSecrets)
            return "wrong password";
        return Net.ConnectionFailReason.toString(reason);
    }

    Connections {
        target: root.pending

        function onConnectionFailed(reason) {
            root.lastError = root.describeFailure(reason);
            root.pending = null;
        }

        function onConnectedChanged() {
            if (root.pending?.connected ?? false) {
                root.lastError = "";
                root.pending = null;
            }
        }
    }

    // ── Reachability ─────────────────────────────────────────────────────
    //
    // Being connected and being online are different claims. NetworkManager's
    // connectivity check answers the second, and only when it is enabled —
    // otherwise it reports Unknown forever, and a cell that reads Unknown as
    // "offline" will call a working connection dead.

    readonly property bool canCheckReachability: Net.Networking.canCheckConnectivity
    readonly property int reachability: Net.Networking.connectivity
    readonly property string reachabilityName: Net.NetworkConnectivity.toString(reachability)

    readonly property bool reachabilityKnown: canCheckReachability
        && reachability !== Net.NetworkConnectivity.Unknown

    readonly property bool online: reachabilityKnown
        && reachability === Net.NetworkConnectivity.Full

    // A captive portal is the case that looks like a working connection and is
    // not, so it is worth its own name rather than a comparison at each call.
    readonly property bool captivePortal: reachability === Net.NetworkConnectivity.Portal

    function checkReachability() {
        if (root.canCheckReachability)
            Net.Networking.checkConnectivity();
    }

    // ── What the cell composes itself from ───────────────────────────────
    //
    // One entry per live connection (PRD §9.11). Bluetooth is a separate domain
    // and arrives from its own service; the cell concatenates. With nothing
    // live this is empty, and an empty cell is an absent cell.

    readonly property var active: {
        const entries = [];
        if (root.wiredConnected)
            entries.push({
                kind: "wired",
                label: root.wiredName.length > 0 ? root.wiredName : root.wiredInterface,
                detail: root.wiredSpeed > 0 ? `${root.wiredSpeed} Mb/s` : ""
            });
        if (root.wifiConnected)
            entries.push({
                kind: "wifi",
                label: root.ssid,
                detail: `${root.signalPercent}%`,
                bars: root.signalBars
            });
        return entries;
    }

    readonly property bool connected: wiredConnected || wifiConnected
}
