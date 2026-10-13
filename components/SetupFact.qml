import QtQuick
import qs.core

// A fact on a setup page and its state: a dot, the name in Orbitron, and
// beside it what it is. Calm when it is in place, muted when it is not yet,
// alert when it failed — colour says state.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property string label: ""
    property string detail: ""
    property string state: "muted"     // "calm" | "muted" | "active" | "alert"
    property alias trailing: trailingSlot.data

    readonly property real factor: metrics.factor

    width: parent ? parent.width : 0
    height: Math.max(26 * factor, detailText.implicitHeight)

    Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 7 * root.factor
        height: width
        radius: width / 2
        antialiasing: true
        color: root.state === "calm" ? Theme.calm
             : root.state === "active" ? Theme.active
             : root.state === "alert" ? Theme.alert : Theme.textFaint
    }

    Text {
        id: name
        anchors.left: dot.right
        anchors.leftMargin: 10 * root.factor
        anchors.verticalCenter: parent.verticalCenter
        width: 150 * root.factor
        elide: Text.ElideRight
        text: root.label
        color: Theme.text
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontMeta,
            "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
        })
    }

    Text {
        id: detailText
        anchors.left: name.right
        anchors.leftMargin: 8 * root.factor
        anchors.right: trailingSlot.left
        anchors.rightMargin: 8 * root.factor
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WordWrap
        text: root.detail
        color: Theme.textMuted
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontSecondary
    }

    Item {
        id: trailingSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
