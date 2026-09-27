import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.services

// The lock screen on one monitor.
//
// Every screen gets the wallpaper, blurred and veiled: the desktop is still
// there, and nothing on it can be read. Only the screen the keyboard is on
// holds anything else — the time, the date, who is logged in and the field.
// Two fields would be two places to type into and one of them deaf; a press on
// another screen moves everything there, because that is where the hand is.
//
// Nothing moves on its own once it is there. It arrives from the desktop it
// covers — the photograph lock.qml took a moment before, blurring and
// dissolving into the wallpaper — and the composition follows, one element
// after the next; it leaves the same way backwards, onto the same picture.
// Between the two the only change is the minute.
WlSessionLockSurface {
    id: root

    required property var lockState

    readonly property bool active: root.screen && root.lockState.active === root.screen.name
    readonly property var metrics: Metrics.step("normal")
    readonly property real factor: metrics.factor

    color: Theme.background

    // ---- Arriving and leaving -----------------------------------------------------

    // 0 is the desktop as it was, sharp; 1 is the wallpaper blurred and
    // veiled. The blur, the photograph and the veil all follow this one value.
    property real dissolve: 0

    // The composition, one element after another: each takes `Timing.open`,
    // the next one starting `stagger` after it.
    property real cascade: 0
    readonly property int stagger: Timing.stagger * 3
    readonly property int steps: 5
    readonly property real cascadeSpan: Timing.open + (steps - 1) * stagger

    // How far element `index` has arrived, eased out: it starts quickly and
    // settles, like every opening in the shell.
    function arrived(index) {
        const elapsed = root.cascade * root.cascadeSpan - index * root.stagger;
        const linear = Math.max(0, Math.min(1, elapsed / Timing.open));
        return 1 - Math.pow(1 - linear, 3);
    }

    SequentialAnimation {
        id: arrival
        running: true

        ParallelAnimation {
            // The wallpaper's own crossfade, and its curve: slow at both ends,
            // so the desktop is seen to melt rather than to vanish.
            NumberAnimation {
                target: root
                property: "dissolve"
                to: 1
                duration: Timing.wallpaper
                easing.type: Easing.InOutQuad
            }

            SequentialAnimation {
                PauseAnimation { duration: Timing.open }
                NumberAnimation {
                    target: root
                    property: "cascade"
                    to: 1
                    duration: root.cascadeSpan
                }
            }
        }
    }

    // Leaving: the composition goes quickly, last element first, then the
    // picture clears back to the desktop. lock.qml unlocks when both are done.
    SequentialAnimation {
        id: departure

        NumberAnimation {
            target: root
            property: "cascade"
            to: 0
            duration: Timing.close
        }

        NumberAnimation {
            target: root
            property: "dissolve"
            to: 0
            duration: Timing.open
            easing.type: Easing.InOutQuad
        }
    }

    Connections {
        target: root.lockState
        function onLeavingChanged() {
            if (!root.lockState.leaving)
                return;
            arrival.stop();
            departure.start();
        }
    }

    // ---- Behind ------------------------------------------------------------------

    // How far the blurred picture runs past the screen's edges. A blur fades to
    // nothing at the edge of what it blurs, and a picture blurred only to the
    // screen's edge would be a picture with a dark frame.
    readonly property real bleed: 96

    Item {
        x: -root.bleed
        y: -root.bleed
        width: root.width + root.bleed * 2
        height: root.height + root.bleed * 2
        clip: root.lockState.wallpaperMode === "span"

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.dissolve
            blurMax: 64
            autoPaddingEnabled: false
        }

        WallpaperImage {
            source: root.screen ? root.lockState.wallpaperFor(root.screen.name) : ""
            mode: root.lockState.wallpaperMode
            screen: root.screen
            density: 0.25
        }

        // The desktop as it was, over the wallpaper, until the dissolve takes
        // it. Loaded before the first frame, or the lock would open on the
        // wallpaper and then flash to the desktop.
        Image {
            x: root.bleed
            y: root.bleed
            width: root.width
            height: root.height
            opacity: 1 - root.dissolve
            visible: opacity > 0 && status === Image.Ready
            source: root.screen ? "file://" + root.lockState.captureFor(root.screen.name) : ""
            asynchronous: false
            cache: false
            fillMode: Image.Stretch
        }
    }

    // The veil: the picture is a place, not something to look at, and the
    // text on it has to hold on any image.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.background, 0.45)
        opacity: root.dissolve
    }

    // A press anywhere on a screen that does not hold the field brings it here.
    TapHandler {
        enabled: !root.active
        onTapped: if (root.screen) root.lockState.active = root.screen.name
    }

    // ---- In front, where the keyboard is -------------------------------------------

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // What the keypad's keys mean with num lock off, read as the figures
    // printed on them.
    readonly property var keypad: ({
        [Qt.Key_Insert]: "0", [Qt.Key_End]: "1", [Qt.Key_Down]: "2",
        [Qt.Key_PageDown]: "3", [Qt.Key_Left]: "4", [Qt.Key_Clear]: "5",
        [Qt.Key_Right]: "6", [Qt.Key_Home]: "7", [Qt.Key_Up]: "8",
        [Qt.Key_PageUp]: "9", [Qt.Key_Delete]: "."
    })

    readonly property string time: {
        const hours = root.lockState.twentyFourHour
                      ? String(clock.hours).padStart(2, "0")
                      : String(clock.hours % 12 === 0 ? 12 : clock.hours % 12);
        return `${hours}:${String(clock.minutes).padStart(2, "0")}`;
    }

    Column {
        id: composition

        anchors.horizontalCenter: parent.horizontalCenter
        // A little above the middle: the eye's centre of a screen is higher
        // than its geometric one.
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.height * 0.06

        visible: root.active
        spacing: 0

        // The time is the clock's, and the clock is a human thing: the
        // expressive voice, with tabular figures so the minute does not move
        // the line.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.arrived(0)
            transform: Translate { y: (1 - root.arrived(0)) * 4 * root.factor }
            text: root.time
            color: Theme.text
            font: Typography.tabular(Qt.font({
                "family": Typography.expressive,
                "pixelSize": Math.round(112 * root.factor),
                "weight": Typography.weightValue
            }))
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.arrived(1)
            transform: Translate { y: (1 - root.arrived(1)) * 4 * root.factor }
            text: clock.date.toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM").toUpperCase()
            color: Theme.textMuted
            font: Qt.font({
                "family": Typography.technical,
                "pixelSize": root.metrics.fontSecondary,
                "weight": Typography.weightLabel,
                "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                     Typography.labelTracking)
            })
        }

        Item { width: 1; height: 72 * root.factor }

        // The avatar as the System cell wears it at rest — the portrait in a
        // round cell of its own, glass and lit rim — at the lock's scale: 30 in
        // 40 there, the same proportion here. The person is the same one the
        // membrane shows (Akusen, 2026-09-27).
        Item {
            id: badge

            readonly property real portrait: 76 * root.factor
            readonly property real radius: width / 2

            anchors.horizontalCenter: parent.horizontalCenter
            width: portrait * (Metrics.cellHeight / 30)
            height: width
            opacity: root.arrived(2)
            transform: Translate { y: (1 - root.arrived(2)) * 4 * root.factor }

            Rectangle {
                anchors.fill: parent
                radius: badge.radius
                color: Qt.alpha(Theme.cell, Config.get("cell.opacity", 0.72))
                antialiasing: true
            }

            Rim {
                anchors.fill: parent
                radius: badge.radius
            }

            Portrait {
                anchors.centerIn: parent
                width: badge.portrait
                height: width
                source: Session.avatar
                available: Session.hasAvatar
                onFailed: Session.avatarFailed()
            }
        }

        Item { width: 1; height: 14 * root.factor }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.arrived(3)
            transform: Translate { y: (1 - root.arrived(3)) * 4 * root.factor }
            text: Session.fullName
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: Math.round(20 * root.factor)
        }

        Item { width: 1; height: 24 * root.factor }

        // ---- The field ---------------------------------------------------------

        Item {
            id: field

            // It grows from its middle to its width, as a capsule opens into
            // a panel: animated in width, never scaled, so the outline and the
            // curve of its caps stay what they are.
            readonly property real grown: root.arrived(4)

            anchors.horizontalCenter: parent.horizontalCenter
            width: height + (300 * root.factor - height) * field.grown
            height: 44 * root.factor

            // Waiting on PAM, the field says so by stepping back rather than
            // by a spinner: nothing here moves without a value behind it.
            opacity: Math.min(field.grown * 2, 1) * (root.lockState.checking ? 0.6 : 1)

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusFor(height, root.metrics)
                antialiasing: true
                color: Qt.alpha(Theme.lift(Theme.background, -0.01), 0.72)
                border.width: Metrics.crisp(1.5, Screen.devicePixelRatio)
                border.color: root.lockState.failed ? Theme.alert
                            : secret.activeFocus ? Theme.primary
                            : Theme.line

                Behavior on border.color { ColorAnimation { duration: Timing.transition } }
            }

            // What is inside comes in once the shape is nearly at size.
            readonly property real inside: Math.max(0, (field.grown - 0.7) / 0.3)

            Text {
                anchors.centerIn: parent
                visible: secret.text.length === 0
                opacity: field.inside
                text: "Password"
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
            }

            TextInput {
                id: secret

                anchors.fill: parent
                opacity: field.inside
                anchors.leftMargin: 20 * root.factor
                anchors.rightMargin: 20 * root.factor
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                clip: true

                echoMode: TextInput.Password
                passwordCharacter: "•"
                color: Theme.text
                selectionColor: Qt.alpha(Theme.primary, 0.35)
                selectedTextColor: Theme.text
                font.family: Typography.expressive
                font.pixelSize: Math.round(16 * root.factor)
                readOnly: root.lockState.checking

                focus: root.active

                onTextEdited: {
                    root.lockState.password = text;
                    root.lockState.failed = false;
                }

                onAccepted: root.lockState.submit()

                // The keypad types figures whether num lock is on or not.
                // niri turns it on only when it starts, and every reload of
                // the keymap — a layout changed from the keyboard cell — turns
                // it off again, so a password with figures in it would
                // otherwise depend on what happened to the keymap since login.
                Keys.onPressed: event => {
                    if (!(event.modifiers & Qt.KeypadModifier))
                        return;
                    const figure = root.keypad[event.key];
                    if (figure === undefined || secret.readOnly)
                        return;
                    if (secret.selectedText.length > 0)
                        secret.remove(secret.selectionStart, secret.selectionEnd);
                    secret.insert(secret.cursorPosition, figure);
                    root.lockState.password = secret.text;
                    root.lockState.failed = false;
                    event.accepted = true;
                }

                // Escape empties the field: the one way back from a password
                // typed wrong, other than typing over it.
                Keys.onEscapePressed: {
                    secret.clear();
                    root.lockState.password = "";
                    root.lockState.failed = false;
                }
            }

            // A wrong password leaves what was typed where it was, selected:
            // the next key replaces it, and nothing had to be typed twice to
            // find out what was wrong.
            Connections {
                target: root.lockState
                function onFailedChanged() {
                    if (root.lockState.failed)
                        secret.selectAll();
                }
            }
        }

        Item { width: 1; height: 10 * root.factor }

        // Errors live where they happened, in a sentence.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.lockState.failed ? 1 : 0
            text: root.lockState.reason
            color: Theme.alert
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary

            Behavior on opacity { NumberAnimation { duration: Timing.transition } }
        }
    }

    // The field on this screen takes the keys whenever this becomes the screen
    // that holds it, and again once the surface is mapped.
    onActiveChanged: if (root.active) secret.forceActiveFocus()
    onVisibleChanged: if (root.visible && root.active) secret.forceActiveFocus()
}
