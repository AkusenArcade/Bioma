import QtQuick
import QtQuick.Dialogs
import Quickshell
import qs.core
import qs.components
import qs.services

// Connectivity, opened: one well per family, each with the switch that turns
// the family off — never the cell.
//
// Two wells and two different truths about choice. A radio dot marks the
// Wi-Fi network, because you are on one at a time and there the dot does not
// lie; the devices have none, because several can be connected at once and a
// dot among them would claim otherwise. A device says what it is with its
// glyph, lit when connected and dim when only paired.
//
// See docs/design/CELLS.md §11.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // The shape is 340 wide; the Panel that holds this content adds the
    // padding, so the content is what is left inside it.
    readonly property real panelPadding: 10 * factor
    readonly property real contentWidth: 340 * factor - panelPadding * 2
    readonly property real wellPadding: 8 * factor
    readonly property real wellInset: 10 * factor
    readonly property real wellSpacing: 8 * factor
    readonly property real rowHeight: 38 * factor
    readonly property real headerHeight: 30 * factor

    // Three rows of each family before the well starts scrolling: enough to
    // recognise the place you are in, not enough to become a page.
    readonly property int shownRows: 3

    readonly property var networks: Network.visibleNetworks
    // The paired devices, then — while searching — what the search has found,
    // each marked by which it is.
    readonly property var devices: {
        const out = Bluetooth.pairedDevices.map(device => ({ "device": device, "found": false }));
        if (Bluetooth.discovering)
            for (const device of Bluetooth.foundDevices)
                out.push({ "device": device, "found": true });
        return out;
    }

    // The scanner costs power and is wanted only while the list is being
    // looked at. The cell owns it: on when the panel is here, off when it goes.
    // The Bluetooth search is asked for by hand — it floods the list with the
    // room's devices — and ends with the panel all the same.
    Component.onCompleted: Network.scanning = true
    Component.onDestruction: {
        Network.scanning = false;
        Bluetooth.discovering = false;
    }

    // ---- Asking for a password ---------------------------------------------
    //
    // The row opens into a field rather than into a dialog: the network being
    // joined stays visible above what is being typed, and the list behind it
    // is not covered by anything.

    property var asked: null

    readonly property bool failed: root.asked !== null && Network.lastError.length > 0

    function ask(network) {
        root.asked = network;
        if (root.cell)
            root.cell.asking = true;
    }

    function stopAsking() {
        root.asked = null;
        if (root.cell)
            root.cell.asking = false;
    }

    function act(network) {
        if (!network)
            return;
        if (network.connected) {
            Network.leave(network);
            return;
        }
        if (Network.needsPassword(network)) {
            root.ask(network);
            return;
        }
        Network.join(network);
    }

    // A network that came up is a question answered.
    Connections {
        target: Network
        function onWifiConnectedChanged() {
            if (Network.wifiConnected)
                root.stopAsking();
        }
    }

    readonly property real fieldHeight: 34 * factor
    readonly property real errorHeight: 20 * factor
    readonly property real askedExtra: root.fieldHeight + 8 * factor
                                     + (root.failed ? root.errorHeight : 0)

    // ---- Size ---------------------------------------------------------------

    function wellHeight(rows, extra) {
        return root.wellPadding * 2 + root.headerHeight
             + Math.max(1, Math.min(rows, root.shownRows)) * root.rowHeight + extra;
    }

    readonly property real wifiHeight: wellHeight(Network.wifiEnabled ? networks.length : 0,
                                                  root.asked !== null ? root.askedExtra : 0)
    readonly property real deviceHeight: wellHeight(Bluetooth.enabled ? devices.length : 0, 0)

    // The VPN well holds its profiles, or — while one is being added — the
    // form that adds it.
    readonly property real formHeight: 4 * root.fieldHeight + 5 * 8 * factor
                                       + (Vpn.error.length > 0 ? root.errorHeight : 0)
    readonly property real vpnHeight: root.adding
        ? root.wellPadding * 2 + root.headerHeight + root.formHeight
        : wellHeight(Vpn.profiles.length, root.chipRoom
                     + (Vpn.error.length > 0 ? root.errorHeight : 0))
    readonly property real chipRoom: 34 * factor

    // ---- Proxies ---------------------------------------------------------------
    //
    // While one is being edited the other wells step aside: the form is tall,
    // and four wells and a form do not fit above a membrane on a 1080 screen.

    property var editing: null
    property bool editingNew: false
    property bool removingProxy: false

    readonly property real proxyRow: 44 * factor

    // What the form offers as triggers: every VPN profile, the wireless
    // network the machine is on and any already chosen, and the wire.
    readonly property var triggerChoices: {
        const out = [];
        for (const profile of Vpn.profiles)
            out.push({ "kind": "vpn", "uuid": profile.uuid, "name": profile.name });
        const ssids = [];
        if (Network.wifiConnected && Network.ssid.length > 0)
            ssids.push(Network.ssid);
        if (root.editing)
            for (const t of (root.editing.triggers || []))
                if (t.kind === "wifi" && ssids.indexOf(t.ssid) < 0)
                    ssids.push(t.ssid);
        for (const ssid of ssids)
            out.push({ "kind": "wifi", "ssid": ssid });
        out.push({ "kind": "wired" });
        return out;
    }

    function sameTrigger(a, b) {
        return a.kind === b.kind && (a.kind !== "vpn" || a.uuid === b.uuid)
            && (a.kind !== "wifi" || a.ssid === b.ssid);
    }

    function hasTrigger(trigger) {
        return root.editing !== null && (root.editing.triggers || []).some(t => root.sameTrigger(t, trigger));
    }

    function flipTrigger(trigger) {
        const copy = JSON.parse(JSON.stringify(root.editing));
        const list = copy.triggers || [];
        const index = list.findIndex(t => root.sameTrigger(t, trigger));
        if (index >= 0)
            list.splice(index, 1);
        else
            list.push(trigger);
        copy.triggers = list;
        root.editing = copy;
    }

    function edit(profile) {
        root.adding = false;
        root.removingProxy = false;
        root.editingNew = profile === null;
        root.editing = profile !== null ? JSON.parse(JSON.stringify(profile))
            : { "id": Proxy.newId(), "name": "", "type": "http", "host": "", "port": 8080,
                "noProxy": "localhost,127.0.0.1,::1", "triggers": [] };
        proxyName.text = root.editing.name;
        proxyHost.text = root.editing.host;
        proxyPort.text = String(root.editing.port || "");
        proxyExceptions.text = root.editing.noProxy || "";
    }

    function stopEditing() {
        root.editing = null;
        root.removingProxy = false;
    }

    onEditingChanged: if (root.cell) root.cell.asking = root.editing !== null || root.adding

    readonly property bool proxyValid: proxyHost.text.trim().length > 0
                                       && parseInt(proxyPort.text, 10) > 0

    function saveProxy() {
        if (!root.proxyValid)
            return;
        const profile = JSON.parse(JSON.stringify(root.editing));
        profile.name = proxyName.text.trim().length > 0 ? proxyName.text.trim() : proxyHost.text.trim();
        profile.host = proxyHost.text.trim();
        profile.port = parseInt(proxyPort.text, 10);
        profile.noProxy = proxyExceptions.text.trim();
        Proxy.save(profile);
        root.stopEditing();
    }

    readonly property real chipPitch: 32 * factor
    readonly property int triggerRows: Math.ceil(root.triggerChoices.length / 3)
    readonly property real proxyFormHeight: 4 * (root.fieldHeight + 8 * factor)
                                            + 30 * factor + 20 * factor
                                            + root.triggerRows * root.chipPitch
                                            + 24 * factor + 16 * factor
    readonly property real proxyHeight: root.editing !== null
        ? root.wellPadding * 2 + root.headerHeight + root.proxyFormHeight
        : root.wellPadding * 2 + root.headerHeight
          + Math.max(1, Proxy.profiles.length) * root.proxyRow + root.chipRoom

    readonly property real contentHeight: root.editing !== null
        ? root.proxyHeight
        : wellSpacing * 3 + wifiHeight + deviceHeight + vpnHeight + proxyHeight

    // ---- Adding a VPN profile ------------------------------------------------

    property bool adding: false
    property url chosenFile: ""
    property string confirming: ""

    onAddingChanged: {
        if (root.cell)
            root.cell.asking = root.adding || root.editing !== null;
        if (root.adding) {
            root.chosenFile = "";
            userField.text = "";
            passwordField.text = "";
            Vpn.error = "";
        }
    }

    Connections {
        target: Vpn
        function onImported() { root.adding = false; }
    }


    implicitWidth: contentWidth
    implicitHeight: contentHeight

    width: implicitWidth
    height: implicitHeight

    HoverHandler {
        onHoveredChanged: if (root.cell) root.cell.panelHovered = hovered
    }

    // ---- Pieces --------------------------------------------------------------

    component FamilyHeader: Item {
        id: family

        property string title: ""
        property bool on: false
        property bool settling: false
        property var metrics: Metrics.step("normal")
        property real factor: 1

        // A family that can look for more says so beside its switch: the
        // Bluetooth devices. While it looks, the loader runs beside the word —
        // the one movement that means "nothing yet".
        property bool searchable: false
        property bool searching: false

        signal switched(bool on)
        signal searchToggled

        height: 30 * family.factor

        Item {
            id: search

            visible: family.searchable && family.on
            anchors.right: toggle.left
            anchors.rightMargin: 10 * family.factor
            anchors.verticalCenter: parent.verticalCenter
            width: searchRow.implicitWidth + 20 * family.factor
            height: 22 * family.factor

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusFor(height, family.metrics)
                antialiasing: true
                color: family.searching ? Qt.alpha(Theme.primary, 0.16) : "transparent"
                border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                border.color: family.searching ? Theme.primary : searchHover.hovered ? Theme.text : Theme.line
            }

            Row {
                id: searchRow
                anchors.centerIn: parent
                spacing: 6 * family.factor

                Sweep {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: family.searching
                    running: family.searching
                    width: 16 * family.factor
                    height: width
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: family.searching ? "STOP" : "SEARCH"
                    color: family.searching ? Theme.text : Theme.textMuted
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": family.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(family.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }
            }

            HoverHandler { id: searchHover }
            TapHandler { onTapped: family.searchToggled() }
        }

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: family.title
            color: Theme.textMuted
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": family.metrics.fontLabel,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(family.metrics.fontLabel,
                                                     Typography.labelTracking)
            })
        }

        Switch {
            id: toggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            factor: family.factor
            on: family.on
            settling: family.settling
            onToggled: value => family.switched(value)
        }
    }

    // ---- Wi-Fi ---------------------------------------------------------------

    Column {
        anchors.fill: parent
        spacing: root.wellSpacing

        Well {
            id: wifiWell

            visible: root.editing === null

            metrics: root.metrics
            inset: root.wellInset
            width: parent.width
            height: root.wifiHeight

            FamilyHeader {
                x: root.wellInset
                y: root.wellPadding
                width: wifiWell.width - root.wellInset * 2
                metrics: root.metrics
                factor: root.factor
                title: "WI-FI"
                on: Network.wifiEnabled
                settling: !Network.wifiHardwareEnabled
                onSwitched: value => Network.setWifiEnabled(value)
            }

            Scroller {
                flick: wifiList
                factor: root.factor
                x: wifiWell.width - width - 4 * root.factor
            }

            // With the radio off the well stays, empty and available: the
            // switch turns the family off, not the well it lives in.
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.headerHeight / 2
                visible: !Network.wifiEnabled
                text: "Wi-Fi is off"
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
            }

            ListView {
                id: wifiList

                x: root.wellInset
                y: root.wellPadding + root.headerHeight
                width: wifiWell.width - root.wellInset * 2
                height: wifiWell.height - y - root.wellPadding
                visible: Network.wifiEnabled
                model: root.networks
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                delegate: Item {
                    id: networkRow

                    required property var modelData

                    readonly property bool asked: root.asked === networkRow.modelData

                    width: ListView.view.width
                    height: root.rowHeight + (networkRow.asked ? root.askedExtra : 0)

                    Item {
                        id: line
                        width: parent.width
                        height: root.rowHeight

                        // The dot only where the choice is exclusive, and here
                        // it is: one network at a time.
                        Item {
                            id: mark
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * root.factor
                            height: width
                            visible: !networkRow.asked

                            Ring {
                                anchors.fill: parent
                                visible: !networkRow.modelData.connected
                                radius: width / 2
                                thickness: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                                colour: Theme.line
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: networkRow.modelData.connected
                                radius: width / 2
                                antialiasing: true

                                gradient: Gradient {
                                    GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                                    GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                visible: networkRow.modelData.connected
                                width: parent.width / 2
                                height: width
                                radius: width / 2
                                color: Theme.background
                                antialiasing: true
                            }
                        }

                        Strength {
                            id: signal
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            factor: root.factor
                            bars: Network.barsFor(networkRow.modelData.signalStrength)
                        }

                        Icon {
                            id: lock
                            anchors.right: signal.left
                            anchors.rightMargin: 10 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Network.isSecured(networkRow.modelData)
                            width: 12 * root.factor
                            height: width
                            name: "lock"
                            colour: Theme.textMuted
                        }

                        // A network's name is what someone typed into a router,
                        // which makes it human language.
                        Text {
                            anchors.left: networkRow.asked ? parent.left : mark.right
                            anchors.leftMargin: networkRow.asked ? 0 : 12 * root.factor
                            anchors.right: lock.visible ? lock.left : signal.left
                            anchors.rightMargin: 10 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: networkRow.modelData.name
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        TapHandler {
                            onTapped: root.act(networkRow.modelData)
                        }
                    }

                    // The field, under the row it belongs to. The primary
                    // outline says the keyboard has been borrowed here and
                    // that it will be given back; the alert outline says the
                    // password was wrong, and the reason arrives under it
                    // without a dialog and without losing what was typed.
                    Item {
                        id: ask

                        visible: networkRow.asked
                        y: root.rowHeight + 4 * root.factor
                        width: parent.width
                        height: root.fieldHeight

                        onVisibleChanged: {
                            if (!visible)
                                return;
                            secret.text = "";
                            secret.forceActiveFocus();
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            color: "transparent"
                            border.width: Metrics.crisp(1.5, Screen.devicePixelRatio)
                            border.color: root.failed ? Theme.alert : Theme.primary
                            antialiasing: true

                            Behavior on border.color { ColorAnimation { duration: Timing.transition } }
                        }

                        Text {
                            id: connect

                            readonly property real pad: 14 * root.factor

                            anchors.right: parent.right
                            anchors.rightMargin: 6 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Connect"
                            color: Theme.text
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontSecondary,
                                "weight": Typography.weightLabel
                            })

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + connect.pad * 2
                                height: root.fieldHeight - 10 * root.factor
                                radius: Metrics.radiusFor(height, root.metrics)
                                z: -1
                                color: "transparent"
                                border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                                border.color: Theme.line
                                antialiasing: true
                            }

                            TapHandler {
                                onTapped: Network.joinWithPassword(root.asked, secret.text)
                            }
                        }

                        TextInput {
                            id: secret
                            anchors.left: parent.left
                            anchors.leftMargin: 16 * root.factor
                            anchors.right: connect.left
                            anchors.rightMargin: 20 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                            selectByMouse: true

                            onAccepted: Network.joinWithPassword(root.asked, secret.text)
                            Keys.onEscapePressed: root.stopAsking()
                        }

                        TapHandler {
                            onTapped: secret.forceActiveFocus()
                        }
                    }

                    Text {
                        visible: networkRow.asked && root.failed
                        y: root.rowHeight + 4 * root.factor + root.fieldHeight + 2 * root.factor
                        x: 16 * root.factor
                        text: Network.lastError
                        color: Theme.alert
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontMeta
                    }
                }
            }
        }

        // ---- Devices ---------------------------------------------------------

        Well {
            id: deviceWell

            visible: root.editing === null

            metrics: root.metrics
            inset: root.wellInset
            width: parent.width
            height: root.deviceHeight

            FamilyHeader {
                x: root.wellInset
                y: root.wellPadding
                width: deviceWell.width - root.wellInset * 2
                metrics: root.metrics
                factor: root.factor
                title: "DEVICES"
                on: Bluetooth.enabled
                settling: Bluetooth.settling
                searchable: true
                searching: Bluetooth.scanning
                onSwitched: value => Bluetooth.setEnabled(value)
                onSearchToggled: Bluetooth.discovering = !Bluetooth.discovering
            }

            Scroller {
                flick: deviceList
                factor: root.factor
                x: deviceWell.width - width - 4 * root.factor
            }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.headerHeight / 2
                visible: !Bluetooth.enabled || root.devices.length === 0
                text: !Bluetooth.available ? "No adapter"
                    : !Bluetooth.enabled ? "Wireless is off"
                    : Bluetooth.scanning ? "Looking…"
                    : "Nothing paired"
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
            }

            ListView {
                id: deviceList

                x: root.wellInset
                y: root.wellPadding + root.headerHeight
                width: deviceWell.width - root.wellInset * 2
                height: deviceWell.height - y - root.wellPadding
                visible: Bluetooth.enabled
                model: root.devices
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                delegate: Item {
                    id: deviceRow

                    required property var modelData

                    readonly property var device: deviceRow.modelData.device
                    readonly property bool found: deviceRow.modelData.found
                    readonly property bool connected: deviceRow.device.connected
                    readonly property bool busy: Bluetooth.isBusy(deviceRow.device)
                    readonly property bool failed: deviceRow.found
                                                   && Bluetooth.failedAddress === deviceRow.device.address

                    // Form says the domain: a headset is drawn as a headset,
                    // whatever it is called. The shell's own wireless mark
                    // stands for everything it has no drawing for.
                    readonly property string glyph: {
                        const name = (Bluetooth.icon(deviceRow.device) || "").toLowerCase();
                        if (name.indexOf("headset") >= 0 || name.indexOf("headphone") >= 0
                            || name.indexOf("audio") >= 0)
                            return "headphones";
                        if (name.indexOf("mouse") >= 0 || name.indexOf("pointing") >= 0)
                            return "mouse";
                        return "wireless-link";
                    }

                    width: ListView.view.width
                    height: root.rowHeight

                    Icon {
                        id: kind
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.factor
                        height: width
                        name: deviceRow.glyph
                        gradient: deviceRow.connected
                        colour: Theme.textMuted
                    }

                    // The machine's own word for the state, so it takes the
                    // technical voice; the name beside it is the device's, and
                    // takes the other one.
                    Text {
                        id: state
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: deviceRow.found
                              ? (deviceRow.device.pairing ? "Pairing" : deviceRow.failed ? "Failed" : "Pair")
                              : deviceRow.busy ? "Working"
                              : deviceRow.connected ? "Connected" : "Paired"
                        color: Theme.textMuted
                        font.family: Typography.technical
                        font.pixelSize: root.metrics.fontMeta
                    }

                    Text {
                        anchors.left: kind.right
                        anchors.leftMargin: 12 * root.factor
                        anchors.right: state.left
                        anchors.rightMargin: 12 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        text: Bluetooth.describe(deviceRow.device)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        // Found, not yet ours: said more quietly than what is.
                        color: deviceRow.found ? Theme.textMuted : Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }

                    // No selection among devices: each row stands alone,
                    // because more than one can be connected at a time.
                    TapHandler {
                        onTapped: {
                            if (deviceRow.found)
                                Bluetooth.pairAndConnect(deviceRow.device);
                            else if (deviceRow.connected)
                                Bluetooth.disconnectDevice(deviceRow.device);
                            else
                                Bluetooth.connectDevice(deviceRow.device);
                        }
                    }

                    // Forgetting a paired device: a cross that appears under
                    // the pointer, in place of the state it covers.
                    Item {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.factor
                        height: width
                        visible: !deviceRow.found && rowHover.hovered

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Theme.background
                        }

                        Icon {
                            anchors.centerIn: parent
                            width: 9 * root.factor
                            height: width
                            name: "close"
                            colour: forgetHover.hovered ? Theme.alert : Theme.textMuted
                        }

                        HoverHandler { id: forgetHover }
                        TapHandler { onTapped: Bluetooth.forget(deviceRow.device) }
                    }

                    HoverHandler { id: rowHover }
                }
            }
        }

        // ---- VPN -------------------------------------------------------------
        //
        // One row per profile NetworkManager keeps, each with its own switch:
        // several may exist and each goes up alone. Removing one asks first —
        // the row becomes the question, as the session's commands do — since
        // a removed profile takes its credentials with it.

        Well {
            id: vpnWell

            visible: root.editing === null

            metrics: root.metrics
            inset: root.wellInset
            width: parent.width
            height: root.vpnHeight

            Text {
                x: root.wellInset
                y: root.wellPadding
                height: root.headerHeight
                verticalAlignment: Text.AlignVCenter
                text: "VPN"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontLabel,
                                                         Typography.labelTracking)
                })
            }

            // The profiles.
            Column {
                visible: !root.adding
                x: root.wellInset
                y: root.wellPadding + root.headerHeight
                width: vpnWell.width - root.wellInset * 2

                Repeater {
                    model: Vpn.profiles

                    delegate: Item {
                        id: profileRow

                        required property var modelData

                        readonly property bool up: profileRow.modelData.state === "activated"
                        readonly property bool moving: Vpn.working === profileRow.modelData.uuid
                                                       || (profileRow.modelData.state.length > 0 && !profileRow.up)
                        readonly property bool asked: root.confirming === profileRow.modelData.uuid

                        width: parent.width
                        height: root.rowHeight

                        Icon {
                            id: shield
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * root.factor
                            height: width
                            name: "lock"
                            gradient: profileRow.up
                            colour: Theme.textMuted
                        }

                        Text {
                            anchors.left: shield.right
                            anchors.leftMargin: 12 * root.factor
                            anchors.right: controls.left
                            anchors.rightMargin: 10 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: profileRow.asked ? "Remove this profile?" : profileRow.modelData.name
                            elide: Text.ElideRight
                            color: profileRow.asked ? Theme.alert : Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        Row {
                            id: controls
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10 * root.factor

                            // Asking: the answer and the way back.
                            PanelPill {
                                visible: profileRow.asked
                                label: "REMOVE"
                                alert: true
                                onPressed: {
                                    root.confirming = "";
                                    Vpn.remove(profileRow.modelData);
                                }
                            }

                            PanelPill {
                                visible: profileRow.asked
                                label: "KEEP"
                                onPressed: root.confirming = ""
                            }

                            Text {
                                visible: !profileRow.asked
                                anchors.verticalCenter: parent.verticalCenter
                                text: profileRow.moving ? "Working" : profileRow.up ? "Connected" : ""
                                color: Theme.textMuted
                                font.family: Typography.technical
                                font.pixelSize: root.metrics.fontMeta
                            }

                            Item {
                                visible: !profileRow.asked && profileHover.hovered
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16 * root.factor
                                height: width

                                Icon {
                                    anchors.centerIn: parent
                                    width: 9 * root.factor
                                    height: width
                                    name: "close"
                                    colour: removeHover.hovered ? Theme.alert : Theme.textMuted
                                }

                                HoverHandler { id: removeHover }
                                TapHandler { onTapped: root.confirming = profileRow.modelData.uuid }
                            }

                            Switch {
                                visible: !profileRow.asked
                                anchors.verticalCenter: parent.verticalCenter
                                factor: root.factor
                                on: profileRow.up
                                settling: profileRow.moving
                                onToggled: value => Vpn.toggle(profileRow.modelData, value)
                            }
                        }

                        HoverHandler { id: profileHover }
                    }
                }

                Text {
                    visible: Vpn.profiles.length === 0
                    width: parent.width
                    height: root.rowHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "No profiles"
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }

                Text {
                    visible: Vpn.error.length > 0
                    width: parent.width
                    height: root.errorHeight
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: Vpn.error
                    color: Theme.alert
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontMeta
                }

                Item {
                    width: parent.width
                    height: root.chipRoom

                    PanelPill {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        label: "+ PROFILE"
                        dashed: true
                        onPressed: root.adding = true
                    }
                }
            }

            // Adding one: the file a provider hands out, and the user name
            // and password it expects. The password field says the keyboard
            // is borrowed; the password leaves by stdin and is not kept here.
            Column {
                visible: root.adding
                x: root.wellInset
                y: root.wellPadding + root.headerHeight
                width: vpnWell.width - root.wellInset * 2
                spacing: 8 * root.factor

                Item {
                    width: parent.width
                    height: root.fieldHeight

                    PanelPill {
                        id: choose
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        label: "CHOOSE FILE"
                        onPressed: ovpnPicker.open()
                    }

                    Text {
                        anchors.left: choose.right
                        anchors.leftMargin: 10 * root.factor
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        text: root.chosenFile.toString().length > 0
                              ? decodeURIComponent(root.chosenFile.toString().split("/").pop())
                              : "an .ovpn file"
                        color: root.chosenFile.toString().length > 0 ? Theme.text : Theme.textFaint
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }
                }

                PanelField {
                    id: userField
                    placeholder: "User name"
                }

                PanelField {
                    id: passwordField
                    placeholder: "Password"
                    secret: true
                    onAccepted: importButton.pressed()
                }

                Text {
                    visible: Vpn.error.length > 0
                    width: parent.width
                    height: root.errorHeight
                    elide: Text.ElideRight
                    text: Vpn.error
                    color: Theme.alert
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontMeta
                }

                Row {
                    spacing: 8 * root.factor

                    PanelPill {
                        id: importButton
                        label: Vpn.busy ? "IMPORTING" : "IMPORT"
                        lit: root.chosenFile.toString().length > 0 && !Vpn.busy
                        onPressed: {
                            if (root.chosenFile.toString().length === 0 || Vpn.busy)
                                return;
                            Vpn.importProfile(root.chosenFile, userField.text, passwordField.text);
                            passwordField.text = "";
                        }
                    }

                    PanelPill {
                        label: "CANCEL"
                        onPressed: root.adding = false
                    }
                }
            }

            FileDialog {
                id: ovpnPicker
                title: "Choose a VPN profile"
                nameFilters: ["OpenVPN profiles (*.ovpn *.conf)"]
                onAccepted: root.chosenFile = ovpnPicker.selectedFile
            }
        }

        // ---- Proxy -----------------------------------------------------------
        //
        // One row per profile, with the switch that forces it on; AUTO gives
        // the choice back to the triggers. A row pressed opens it for editing.

        Well {
            id: proxyWell

            metrics: root.metrics
            inset: root.wellInset
            width: parent.width
            height: root.proxyHeight

            Text {
                x: root.wellInset
                y: root.wellPadding
                height: root.headerHeight
                verticalAlignment: Text.AlignVCenter
                text: "PROXY"
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightLabel,
                    "letterSpacing": Typography.tracking(root.metrics.fontLabel,
                                                         Typography.labelTracking)
                })
            }

            PanelPill {
                visible: root.editing === null && Proxy.profiles.length > 0
                x: proxyWell.width - width - root.wellInset
                y: root.wellPadding + (root.headerHeight - height) / 2
                label: "AUTO"
                lit: Proxy.mode === "auto"
                onPressed: Proxy.setMode("auto")
            }

            Column {
                visible: root.editing === null
                x: root.wellInset
                y: root.wellPadding + root.headerHeight
                width: proxyWell.width - root.wellInset * 2

                Repeater {
                    model: Proxy.profiles

                    delegate: Item {
                        id: proxyRowItem

                        required property var modelData

                        readonly property bool active: Proxy.current !== null
                                                       && Proxy.current.id === proxyRowItem.modelData.id

                        width: parent.width
                        height: root.proxyRow

                        Column {
                            anchors.left: parent.left
                            anchors.right: proxySwitch.left
                            anchors.rightMargin: 10 * root.factor
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: proxyRowItem.modelData.name
                                color: Theme.text
                                font.family: Typography.expressive
                                font.pixelSize: root.metrics.fontSecondary
                            }

                            // The address, and what turns it on by itself.
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: {
                                    const p = proxyRowItem.modelData;
                                    const kind = p.type === "socks5" ? "SOCKS5" : "HTTP";
                                    const triggers = (p.triggers || []).map(t => Proxy.describe(t)).join(", ");
                                    return `${kind} · ${p.host}:${p.port}` + (triggers ? ` · ${triggers}` : "");
                                }
                                color: Theme.textFaint
                                font.family: Typography.technical
                                font.pixelSize: root.metrics.fontMeta
                            }
                        }

                        TapHandler { onTapped: root.edit(proxyRowItem.modelData) }

                        Switch {
                            id: proxySwitch
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            factor: root.factor
                            on: proxyRowItem.active
                            onToggled: value => Proxy.setMode(value ? proxyRowItem.modelData.id : "off")
                        }
                    }
                }

                Text {
                    visible: Proxy.profiles.length === 0
                    width: parent.width
                    height: root.proxyRow
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "No proxies"
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }

                Item {
                    width: parent.width
                    height: root.chipRoom

                    PanelPill {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        label: "+ PROXY"
                        dashed: true
                        onPressed: root.edit(null)
                    }
                }
            }

            // Editing one.
            Column {
                visible: root.editing !== null
                x: root.wellInset
                y: root.wellPadding + root.headerHeight
                width: proxyWell.width - root.wellInset * 2
                spacing: 8 * root.factor

                PanelField {
                    id: proxyName
                    placeholder: "Name"
                    onEscaped: root.stopEditing()
                }

                Segmented {
                    metrics: root.metrics
                    fontSize: root.metrics.fontMeta
                    buttonHeight: 24 * root.factor
                    buttonPadding: 14 * root.factor
                    current: root.editing ? root.editing.type : "http"
                    options: [
                        { "key": "http", "label": "HTTP" },
                        { "key": "socks5", "label": "SOCKS5" }
                    ]
                    onChose: key => {
                        const copy = JSON.parse(JSON.stringify(root.editing));
                        copy.type = key;
                        root.editing = copy;
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8 * root.factor

                    PanelField {
                        id: proxyHost
                        width: parent.width - proxyPort.width - parent.spacing
                        placeholder: "Host"
                        onEscaped: root.stopEditing()
                    }

                    PanelField {
                        id: proxyPort
                        width: 86 * root.factor
                        placeholder: "Port"
                        digits: true
                        onEscaped: root.stopEditing()
                    }
                }

                PanelField {
                    id: proxyExceptions
                    placeholder: "Not for: localhost, *.lan"
                    onEscaped: root.stopEditing()
                    onAccepted: root.saveProxy()
                }

                Text {
                    height: 20 * root.factor
                    verticalAlignment: Text.AlignBottom
                    text: "ON BY ITSELF WITH"
                    color: Theme.textFaint
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
                    })
                }

                Flow {
                    width: parent.width
                    spacing: 8 * root.factor

                    Repeater {
                        model: root.triggerChoices

                        delegate: PanelPill {
                            required property var modelData
                            label: modelData.kind === "wired" ? "WIRED"
                                 : modelData.kind === "wifi" ? modelData.ssid
                                 : modelData.name
                            lit: root.hasTrigger(modelData)
                            onPressed: root.flipTrigger(modelData)
                        }
                    }
                }

                Row {
                    spacing: 8 * root.factor

                    PanelPill {
                        label: "SAVE"
                        lit: root.proxyValid
                        onPressed: root.saveProxy()
                    }

                    PanelPill {
                        label: "CANCEL"
                        onPressed: root.stopEditing()
                    }

                    // Removing asks, by asking again.
                    PanelPill {
                        visible: !root.editingNew
                        label: root.removingProxy ? "REMOVE?" : "REMOVE"
                        alert: root.removingProxy
                        onPressed: {
                            if (!root.removingProxy) {
                                root.removingProxy = true;
                                return;
                            }
                            Proxy.remove(root.editing.id);
                            root.stopEditing();
                        }
                    }
                }
            }
        }
    }

    component PanelPill: Item {
        id: pill

        property string label: ""
        property bool lit: false
        property bool alert: false
        property bool dashed: false
        signal pressed

        width: pillText.implicitWidth + 24 * root.factor
        height: 24 * root.factor

        DashedSlot {
            anchors.fill: parent
            visible: pill.dashed
            radius: Metrics.radiusFor(parent.height, root.metrics)
        }

        Rectangle {
            anchors.fill: parent
            visible: !pill.dashed
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            color: pill.lit ? Qt.alpha(Theme.primary, 0.16)
                 : pill.alert && pillHover.hovered ? Qt.alpha(Theme.alert, 0.16) : "transparent"
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: pill.alert ? Theme.alert : pill.lit ? Theme.primary
                        : pillHover.hovered ? Theme.text : Theme.line
        }

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.alert ? Theme.alert : pill.lit ? Theme.text : Theme.textMuted
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontMeta,
                "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
            })
        }

        HoverHandler { id: pillHover }
        TapHandler { onTapped: pill.pressed() }
    }

    component PanelField: Item {
        id: field

        property string placeholder: ""
        property bool secret: false
        property bool digits: false
        property alias text: input.text
        signal accepted
        signal escaped

        width: parent ? parent.width : 0
        height: root.fieldHeight

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            color: "transparent"
            border.width: Metrics.crisp(input.activeFocus ? 1.5 : Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: input.activeFocus ? Theme.primary : Theme.line
            antialiasing: true
        }

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.leftMargin: 16 * root.factor
            anchors.right: parent.right
            anchors.rightMargin: 16 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
            clip: true
            inputMethodHints: field.digits ? Qt.ImhDigitsOnly : Qt.ImhNone
            validator: field.digits ? portRule : null
            onAccepted: field.accepted()
            Keys.onEscapePressed: {
                root.adding = false;
                field.escaped();
            }

            IntValidator { id: portRule; bottom: 1; top: 65535 }

            Text {
                visible: input.text.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                color: Theme.textFaint
                font: input.font
            }
        }

        TapHandler { onTapped: input.forceActiveFocus() }
    }
}
