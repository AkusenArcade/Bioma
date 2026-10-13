import QtQuick
import Quickshell
import qs.core

// A command for a terminal, with COPY: what the setup offers when it must not
// or cannot do something itself — a package manager, or a password with no
// agent to ask for it.
Rectangle {
    id: root

    property var metrics: Metrics.step("normal")
    property string command: ""

    readonly property real factor: metrics.factor

    width: parent ? parent.width : 0
    height: Math.max(38 * factor, line.implicitHeight + 16 * factor)
    radius: metrics.radiusWell
    color: Qt.alpha(Theme.text, 0.04)
    border.width: Metrics.rim(Screen.devicePixelRatio)
    border.color: Theme.line
    antialiasing: true

    property bool copied: false

    Text {
        id: line
        anchors.left: parent.left
        anchors.leftMargin: 12 * root.factor
        anchors.right: copy.left
        anchors.rightMargin: 10 * root.factor
        anchors.verticalCenter: parent.verticalCenter
        text: root.command
        wrapMode: Text.WrapAnywhere
        color: Theme.text
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontMeta,
            "letterSpacing": Typography.tracking(root.metrics.fontMeta, 0.02)
        })
    }

    Choice {
        id: copy
        anchors.right: parent.right
        anchors.rightMargin: 6 * root.factor
        anchors.verticalCenter: parent.verticalCenter
        metrics: root.metrics
        label: root.copied ? "COPIED" : "COPY"
        onActivated: {
            Quickshell.execDetached(["wl-copy", "--", root.command]);
            root.copied = true;
        }
    }

    onCommandChanged: root.copied = false
}
