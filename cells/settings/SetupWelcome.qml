import QtQuick
import qs.core
import qs.components
import qs.services

// The setup's first page: what this is, before anything is asked.
//
// The greeter's welcome, set inside the panel rather than over the screen: a
// splash of its own would appear from nowhere, and the mark belongs to the
// settings cell alone (CELLS.md §12) — which is where this is. "Welcome to",
// then the mark, the name and the line, one after the next at the welcome's
// own pace, each let in from just above; then what the steps are for. It runs
// once, as the page arrives, and is still from then on.
//
// See docs/design/SETUP.md, step 0.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // The greeter's arithmetic (components/Gate.qml): each line starts a
    // stagger after the one before, and eases out over the welcome's opening.
    property real greeting: 0
    readonly property real greetingSpan: Timing.welcomeOpen + 4 * Timing.welcomeStagger

    function greeted(index) {
        const elapsed = root.greeting * root.greetingSpan - index * Timing.welcomeStagger;
        const linear = Math.max(0, Math.min(1, elapsed / Timing.welcomeOpen));
        return 1 - Math.pow(1 - linear, 3);
    }

    NumberAnimation {
        id: arrival
        target: root
        property: "greeting"
        from: 0
        to: 1
        duration: root.greetingSpan
    }

    Component.onCompleted: arrival.start()

    Column {
        anchors.centerIn: parent
        width: parent.width - 48 * root.factor
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.greeted(0)
            transform: Translate { y: (1 - root.greeted(0)) * -4 * root.factor }
            text: "Welcome to"
            color: Theme.textMuted
            font.family: Typography.expressive
            font.pixelSize: Math.round(18 * root.factor)
        }

        Item { width: 1; height: 20 * root.factor }

        Logotype {
            anchors.horizontalCenter: parent.horizontalCenter
            width: implicitWidth
            height: implicitHeight
            markHeight: Math.round(96 * root.factor)
            markShown: root.greeted(1)
            nameShown: root.greeted(2)
            lineShown: root.greeted(3)
            travel: -4 * root.factor
        }

        Item { width: 1; height: 36 * root.factor }

        Text {
            width: parent.width
            opacity: root.greeted(4)
            transform: Translate { y: (1 - root.greeted(4)) * -4 * root.factor }
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            text: "A few steps put the desktop together: where things go, how it looks, its keys in niri, "
                  + "and the login screen. Every answer can be changed later, and any step can be skipped."
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }
}
