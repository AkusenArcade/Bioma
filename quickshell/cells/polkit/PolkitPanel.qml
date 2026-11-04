import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The request, and the answer to it.
//
// What is asking comes first: the action's icon in the dark circle every
// third-party icon in the shell sits in, the message polkit was given —
// human language, written by whoever wrote the action — and under it the
// action's own name, which is the machine's. Then the field, as the lock
// screen draws it: the same password, the same capsule, the outline that
// turns to the primary when it has the keys and to the alert when the
// password was refused. What polkit says back stands under it.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property var flow: Polkit.flow

    // Between the press and polkit's answer the field steps back, as the
    // lock's does while PAM is checking: nothing moves without a value.
    property bool checking: false
    readonly property bool failed: root.flow ? root.flow.failed : false

    Connections {
        target: root.flow
        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired)
                root.checking = false;
        }
        function onFailedChanged() {
            root.checking = false;
            if (root.flow.failed) {
                secret.selectAll();
                secret.forceActiveFocus();
            }
        }
    }

    implicitWidth: 380 * factor
    implicitHeight: content.height
    width: implicitWidth
    height: implicitHeight

    function takeCaret() {
        secret.forceActiveFocus();
    }

    function answer() {
        if (!root.flow || !root.flow.isResponseRequired || root.checking)
            return;
        root.checking = true;
        Polkit.submit(secret.text);
    }

    readonly property string iconSource: root.flow && root.flow.iconName
        ? Quickshell.iconPath(root.flow.iconName, true) : ""

    Column {
        id: content
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: Math.max(portrait.height, words.height)

            Rectangle {
                id: portrait
                width: 36 * root.factor
                height: width
                radius: width / 2
                color: Theme.lift(Theme.background, -0.015)
                border.width: Metrics.rim(Screen.devicePixelRatio)
                border.color: Qt.alpha(Theme.text, 0.5)
                antialiasing: true

                Image {
                    anchors.centerIn: parent
                    visible: root.iconSource !== ""
                    width: parent.width * 0.62
                    height: width
                    source: root.iconSource
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: root.iconSource === ""
                    width: parent.width * 0.5
                    height: width
                    name: "lock"
                    colour: Theme.textMuted
                }
            }

            Column {
                id: words
                anchors.left: portrait.right
                anchors.leftMargin: 14 * root.factor
                anchors.right: parent.right
                spacing: 4 * root.factor

                Text {
                    width: parent.width
                    text: root.flow ? root.flow.message : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(15 * root.factor)
                }

                Text {
                    width: parent.width
                    text: root.flow ? root.flow.actionId : ""
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                    color: Theme.textFaint
                    font: Qt.font({
                        "family": Typography.technical,
                        "pixelSize": root.metrics.fontMeta,
                        "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                             Typography.labelTracking)
                    })
                }
            }
        }

        Item { width: 1; height: 16 * root.factor }

        // ---- The field -------------------------------------------------------

        Item {
            id: field

            width: parent.width
            height: 44 * root.factor
            opacity: root.checking ? 0.6 : 1

            Behavior on opacity { NumberAnimation { duration: Timing.transition } }

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusFor(height, root.metrics)
                antialiasing: true
                color: Qt.alpha(Theme.lift(Theme.background, -0.01),
                                Config.get("cell.opacity", 0.72))
                border.width: Metrics.crisp(1.5, Screen.devicePixelRatio)
                border.color: root.failed ? Theme.alert
                            : secret.activeFocus ? Theme.primary
                            : Theme.line

                Behavior on border.color { ColorAnimation { duration: Timing.transition } }
            }

            // polkit's own word for what it wants, without the colon its
            // terminal habit puts after it.
            Text {
                anchors.centerIn: parent
                visible: secret.text.length === 0
                text: root.flow && root.flow.inputPrompt.length > 0
                      ? root.flow.inputPrompt.replace(/[:\s]+$/, "") : "Password"
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
            }

            TextInput {
                id: secret

                anchors.fill: parent
                anchors.leftMargin: 20 * root.factor
                anchors.rightMargin: 20 * root.factor
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                clip: true

                echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                color: Theme.text
                selectionColor: Qt.alpha(Theme.primary, 0.35)
                selectedTextColor: Theme.text
                font.family: Typography.expressive
                font.pixelSize: Math.round(16 * root.factor)
                readOnly: root.checking

                onAccepted: root.answer()
            }
        }

        // What polkit says back — a refusal in the alert colour, anything
        // else in the muted voice — where it happened, in a sentence.
        Item {
            width: parent.width
            height: said.text.length > 0 ? said.height + 10 * root.factor : 0

            Behavior on height { NumberAnimation { duration: Timing.transition } }

            Text {
                id: said
                y: 10 * root.factor
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: {
                    if (!root.flow)
                        return "";
                    if (root.flow.supplementaryMessage.length > 0)
                        return root.flow.supplementaryMessage;
                    return root.failed ? "That password was not accepted" : "";
                }
                color: root.failed || (root.flow && root.flow.supplementaryIsError)
                       ? Theme.alert : Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
            }
        }

        Item { width: 1; height: 16 * root.factor }

        Row {
            anchors.right: parent.right
            spacing: 8 * root.factor

            Choice {
                metrics: root.metrics
                label: "Cancel"
                onActivated: {
                    Polkit.cancel();
                    if (root.cell)
                        root.cell.open = false;
                }
            }

            Choice {
                metrics: root.metrics
                label: "Authenticate"
                kind: "primary"
                dimmed: root.checking || !(root.flow && root.flow.isResponseRequired)
                onActivated: root.answer()
            }
        }
    }
}
