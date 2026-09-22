import QtQuick
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
    readonly property var devices: Bluetooth.pairedDevices

    // The scanner costs power and is wanted only while the list is being
    // looked at. The cell owns it: on when the panel is here, off when it goes.
    Component.onCompleted: Network.scanning = true
    Component.onDestruction: Network.scanning = false

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

    readonly property real contentHeight: wellSpacing + wifiHeight + deviceHeight

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

        signal switched(bool on)

        height: 30 * family.factor

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
                onSwitched: value => Bluetooth.setEnabled(value)
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

                    readonly property bool connected: deviceRow.modelData.connected
                    readonly property bool busy: Bluetooth.isBusy(deviceRow.modelData)

                    // Form says the domain: a headset is drawn as a headset,
                    // whatever it is called. The shell's own wireless mark
                    // stands for everything it has no drawing for.
                    readonly property string glyph: {
                        const name = (Bluetooth.icon(deviceRow.modelData) || "").toLowerCase();
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
                        text: deviceRow.busy ? "Working"
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
                        text: Bluetooth.describe(deviceRow.modelData)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                    }

                    // No selection among devices: each row stands alone,
                    // because more than one can be connected at a time.
                    TapHandler {
                        onTapped: {
                            if (deviceRow.connected)
                                Bluetooth.disconnectDevice(deviceRow.modelData);
                            else
                                Bluetooth.connectDevice(deviceRow.modelData);
                        }
                    }
                }
            }
        }
    }
}
