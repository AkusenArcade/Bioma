import QtQuick
import qs.core

// What a person reads on a setup page: the human voice, wrapped.
Text {
    property var metrics: Metrics.step("normal")

    width: parent ? parent.width : 0
    wrapMode: Text.WordWrap
    color: Theme.text
    font.family: Typography.expressive
    font.pixelSize: metrics.fontSecondary
    lineHeight: 1.15
}
