import QtQuick
import qs.core

// One answer among several, as a row: a ring that fills when it is the one
// chosen, the answer in Orbitron, and what it means in Spectral under it.
// Pressed, it is chosen. The LOGIN step's two rows.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property string label: ""
    property string line: ""
    property bool chosen: false
    property bool busy: false
    property bool alarmed: false

    signal activated()

    readonly property real factor: metrics.factor

    readonly property bool navigable: true

    function activate() {
        root.activated();
    }

    width: parent ? parent.width : 0
    height: Math.max(48 * factor, text.implicitHeight + 16 * factor)

    KeyMark {
        factor: root.factor
    }

    Rectangle {
        anchors.fill: parent
        radius: root.metrics.radiusWell
        antialiasing: true
        color: hover.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent"
        border.width: Metrics.rim(Screen.devicePixelRatio)
        border.color: root.chosen ? Theme.primary : Qt.alpha(Theme.line, 0.7)
    }

    Rectangle {
        id: ring
        anchors.left: parent.left
        anchors.leftMargin: 14 * root.factor
        anchors.verticalCenter: parent.verticalCenter
        width: 12 * root.factor
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Metrics.rim(Screen.devicePixelRatio)
        border.color: root.chosen ? Theme.primary : Theme.textMuted
        antialiasing: true
        visible: !root.busy

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.5
            height: width
            radius: width / 2
            color: Theme.primary
            visible: root.chosen
            antialiasing: true
        }
    }

    Sweep {
        anchors.centerIn: ring
        width: 16 * root.factor
        height: width
        running: root.busy
        visible: root.busy
    }

    Column {
        id: text
        anchors.left: ring.right
        anchors.leftMargin: 12 * root.factor
        anchors.right: parent.right
        anchors.rightMargin: 14 * root.factor
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * root.factor

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.label
            color: root.chosen ? Theme.primary : Theme.text
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": Math.round(12 * root.factor),
                "weight": root.chosen ? Typography.weightTitle : Typography.weightLabel,
                "letterSpacing": Typography.tracking(Math.round(12 * root.factor), 0.04)
            })
        }

        Text {
            width: parent.width
            visible: root.line.length > 0
            wrapMode: Text.WordWrap
            text: root.line
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }

    HoverHandler { id: hover }
    TapHandler { onTapped: root.activated() }
}
