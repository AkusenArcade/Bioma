import QtQuick
import qs.core

// A well on a setup page: its label, perhaps a control on the same line, then
// what it holds. The Session page's arrangement (SettingsSession.qml), shared
// by every step, because a walk-through whose pages were laid out seven ways
// would read as seven programs.
Well {
    id: root

    property string label: ""
    property alias trailing: trailingSlot.data
    default property alias content: body.data

    readonly property real factor: metrics.factor
    readonly property real pad: 14 * factor
    readonly property real headerHeight: 28 * factor

    width: parent ? parent.width : 0
    height: pad * 2 + headerHeight + body.childrenRect.height
            + (body.childrenRect.height > 0 ? 6 * factor : 0)

    Text {
        x: root.pad
        y: root.pad
        height: root.headerHeight
        verticalAlignment: Text.AlignVCenter
        text: root.label
        color: Theme.text
        font: Qt.font({
            "family": Typography.technical,
            "pixelSize": root.metrics.fontSecondary,
            "letterSpacing": Typography.tracking(root.metrics.fontSecondary, Typography.labelTracking)
        })
    }

    Item {
        id: trailingSlot
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        y: root.pad
        width: childrenRect.width
        height: root.headerHeight
    }

    Column {
        id: body
        x: root.pad
        y: root.pad + root.headerHeight + 6 * root.factor
        width: root.width - root.pad * 2
        spacing: 10 * root.factor
    }
}
