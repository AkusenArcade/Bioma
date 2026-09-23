import QtQuick
import QtQuick.Dialogs
import Quickshell
import qs.core
import qs.components
import qs.services

// The system, opened: who is logged in above, the five ways to leave below in
// increasing order of gravity, and beside them, on a thread, what the machine
// is — its name, what it runs, what it is made of, how long it has been up.
// The machine's description opens toward the middle of the screen, away from
// the edge the cell sits at.
//
// The confirmation is the row. No dialog arrives from outside and nothing is
// covered: the row that was pressed becomes the question, and the alert colour
// appears there and nowhere else. Colouring `SHUT DOWN` red at all times would
// make it invisible exactly when it matters.
//
// Only the three that close programs ask. Lock and suspend undo themselves
// with a movement of the mouse, and confirming everything teaches people to
// press twice without reading — which is the fastest way to make the
// confirmation that matters useless.
//
// See docs/design/CELLS.md §08.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property real capsuleWidth: 300 * factor
    readonly property real capsuleHeight: 108 * factor
    readonly property real avatarSize: 88 * factor

    readonly property real panelWidth: 300 * factor
    readonly property real panelPadding: 10 * factor
    readonly property real rowHeight: 44 * factor
    readonly property real gap: metrics.gap

    // The order is the order of gravity, and the numbers follow it: whoever
    // learns that shutting down is four has learnt something that stays true.
    readonly property var actions: [
        { "key": "lock", "label": "LOCK", "glyph": "lock" },
        { "key": "suspend", "label": "SUSPEND", "glyph": "suspend" },
        { "key": "restart", "label": "RESTART", "glyph": "restart" },
        { "key": "shutdown", "label": "SHUT DOWN", "glyph": "power" },
        { "key": "logout", "label": "LOG OUT", "glyph": "logout" }
    ]

    readonly property real panelHeight: panelPadding * 2 + actions.length * rowHeight

    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    readonly property real capsuleY: upward ? panelHeight + gap : 0
    readonly property real panelY: upward ? 0 : capsuleHeight + gap
    readonly property real capsuleNear: upward ? capsuleY + capsuleHeight : capsuleY

    // The machine, beside the commands.
    readonly property real infoWidth: 340 * factor
    readonly property bool infoLeft: root.cell ? root.cell.origin === "end" : false
    readonly property real columnX: root.infoLeft ? root.infoWidth + root.gap : 0
    readonly property real infoX: root.infoLeft ? 0 : root.panelWidth + root.gap
    readonly property real columnCentre: root.columnX + root.capsuleWidth / 2

    implicitWidth: Math.max(capsuleWidth, panelWidth) + gap + infoWidth
    implicitHeight: capsuleHeight + gap + panelHeight

    width: implicitWidth
    height: implicitHeight

    // ---- The cascade --------------------------------------------------------

    property real cascade: 0

    function stage(index) {
        return Timing.stage(root.cascade, index, 4);
    }

    readonly property real linkProgress: stage(0)
    readonly property real panelProgress: stage(1)
    readonly property real sideProgress: stage(2)
    readonly property real infoProgress: stage(3)

    Connections {
        target: root.cell
        function onOpenChanged() {
            cascade.stop();
            cascade.to = root.cell.open ? 1 : 0;
            cascade.duration = root.cell.open ? Timing.open : Timing.close;
            // The opening curve run backwards is not a closing curve: it
            // starts fast and ends slow, so the shapes fell out of the
            // composition in the first fifty milliseconds and then crawled the
            // rest of the way. Closing takes the closing curve — it opens
            // calmly and closes quickly.
            cascade.easing.bezierCurve = root.cell.open ? Timing.easeOpenFlat
                                                     : Timing.easeClose;
            cascade.start();
            if (root.cell.open)
                keys.forceActiveFocus();
        }
    }

    NumberAnimation {
        id: cascade
        target: root
        property: "cascade"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    // The expansion is made when the cell is already open and handed the cell
    // after that, so this — not the opening — is where it starts: the cascade,
    // the keys, and asking the machine what it is.
    onCellChanged: {
        if (root.cell && root.cell.open) {
            cascade.to = 1;
            cascade.restart();
            keys.forceActiveFocus();
            Machine.ask();
            Machine.watching = true;
        }
    }

    // ---- The keyboard -------------------------------------------------------
    //
    // One to five run the matching command, and the ones that ask still ask:
    // a number is a shorter way to reach a row, not a way around the question.
    // Enter answers the question that is open, Escape withdraws it.

    Item {
        id: keys
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (Session.pending.length > 0)
                    Session.cancel();
                else if (root.cell)
                    root.cell.open = false;
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (Session.pending.length > 0) {
                    Session.confirm();
                    event.accepted = true;
                }
                return;
            }

            const index = event.key - Qt.Key_1;
            if (index >= 0 && index < root.actions.length) {
                Session.ask(root.actions[index].key);
                event.accepted = true;
            }
        }
    }

    // ---- Who ----------------------------------------------------------------

    Panel {
        id: identity

        metrics: root.metrics
        radius: Metrics.radiusFor(root.capsuleHeight, root.metrics)
        padding: 10 * root.factor
        targetWidth: root.capsuleWidth
        targetHeight: root.capsuleHeight
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        anchorX: root.columnX
        anchorY: root.capsuleY
        nodeX: root.columnCentre
        nodeY: root.capsuleNear

        Item {
            anchors.fill: parent

            Portrait {
                id: face
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.avatarSize
                height: width
                source: Session.avatar
                available: Session.hasAvatar
                onFailed: Session.avatarFailed()

                // The one action in this cell that is not about the session
                // but about identity, which is why it sits on the face rather
                // than in the list of commands. It opens the system's own file
                // picker; the daemon does the rest.
                Item {
                    id: change

                    width: 26 * root.factor
                    height: width
                    x: face.width - width
                    y: face.height - height

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        antialiasing: true

                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.gradientTop(Theme.primary) }
                            GradientStop { position: 1; color: Theme.gradientBottom(Theme.primary) }
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        width: 12 * root.factor
                        height: width
                        name: "plus"
                        colour: Theme.background
                    }

                    TapHandler {
                        onTapped: picker.open()
                    }
                }
            }

            // The system's own picker, through Qt: with the portal platform
            // theme this is the desktop's file chooser, and without one Qt
            // draws its own — which works and looks like nothing else on the
            // screen. `scripts/bioma` is what sets the theme; the README says
            // why. It is a window of its own, so the cell is dismissed under
            // it the moment it takes the pointer, and the write does not need
            // the cell to still be open.
            FileDialog {
                id: picker
                title: "Choose a picture"
                nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
                onAccepted: Session.setAvatar(picker.selectedFile)
            }

            // The person's name is human language; the login is the machine's
            // name for them. The two voices never swap, and here they sit one
            // above the other to say exactly that.
            Text {
                id: person
                anchors.left: face.right
                anchors.leftMargin: 18 * root.factor
                anchors.right: parent.right
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: 2 * root.factor
                text: Session.fullName
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontValue
            }

            Text {
                anchors.left: person.left
                anchors.right: parent.right
                anchors.top: parent.verticalCenter
                anchors.topMargin: 4 * root.factor
                text: Session.login
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.textMuted
                font.family: Typography.technical
                font.pixelSize: root.metrics.fontSecondary
            }
        }
    }

    // The thread between the two shapes, its ends on the shapes themselves.
    Thread {
        id: descent

        readonly property real headY: root.upward ? commands.y + commands.height
                                                  : identity.y + identity.height
        readonly property real footY: root.upward ? identity.y : commands.y

        vertical: true
        progress: root.linkProgress
        width: implicitWidth
        height: Math.max(0, descent.footY - descent.headY)
        x: root.columnCentre - width / 2
        y: descent.headY
    }

    // ---- The five -----------------------------------------------------------

    Panel {
        id: commands

        metrics: root.metrics
        padding: root.panelPadding
        targetWidth: root.panelWidth
        targetHeight: root.panelHeight
        growth: root.panelProgress
        contentReady: root.panelProgress > 0.999

        anchorX: root.columnX
        anchorY: root.panelY
        nodeX: root.columnCentre
        nodeY: root.upward ? commands.anchorY + root.panelHeight : commands.anchorY

        Column {
            anchors.fill: parent

            Repeater {
                model: root.actions

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property bool asking: Session.pending === row.modelData.key

                    width: commands.width - root.panelPadding * 2
                    height: root.rowHeight

                    // The command, standing down while its own question is up.
                    Item {
                        anchors.fill: parent
                        opacity: row.asking ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }

                        Icon {
                            id: glyph
                            anchors.left: parent.left
                            anchors.leftMargin: 6 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20 * root.factor
                            height: width
                            name: row.modelData.glyph
                            gradient: true
                        }

                        // A command is not human language: it is the word the
                        // machine answers to, so it takes the technical voice.
                        Text {
                            anchors.left: glyph.right
                            anchors.leftMargin: 16 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label
                            color: Theme.text
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontSecondary,
                                "weight": Typography.weightValue,
                                "letterSpacing": Typography.tracking(root.metrics.fontSecondary,
                                                                     0.04)
                            })
                        }

                        // The machine wants this one: the kernel it runs has
                        // been replaced on disk. Said beside the command it
                        // asks for, which is also why the cell appeared.
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 40 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.key === "restart" && Session.restartDue
                            text: "DUE"
                            color: Theme.primary
                            font: Qt.font({
                                "family": Typography.technical,
                                "pixelSize": root.metrics.fontMeta,
                                "weight": Typography.weightValue,
                                "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                     Typography.labelTracking)
                            })
                        }

                        // The number that runs it, in a box: a key, drawn as
                        // a key.
                        Item {
                            anchors.right: parent.right
                            anchors.rightMargin: 6 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22 * root.factor
                            height: 22 * root.factor

                            Rectangle {
                                anchors.fill: parent
                                radius: Metrics.shaped(6 * root.factor)
                                color: "transparent"
                                border.width: Metrics.crisp(Metrics.rimWidth,
                                                            Screen.devicePixelRatio)
                                border.color: Theme.line
                                antialiasing: true
                            }

                            Text {
                                anchors.centerIn: parent
                                text: `${row.index + 1}`
                                color: Theme.textMuted
                                font: Typography.tabular(Qt.font({
                                    "family": Typography.technical,
                                    "pixelSize": root.metrics.fontMeta
                                }))
                            }
                        }

                        TapHandler {
                            onTapped: Session.ask(row.modelData.key)
                        }
                    }

                    // The question, in the row's own place. It grows there
                    // rather than arriving from somewhere else — the same
                    // grammar as killing a process in vitals and as keeping a
                    // recording.
                    Item {
                        anchors.fill: parent
                        opacity: row.asking ? 1 : 0
                        visible: opacity > 0
                        scale: row.asking ? 1 : 0.96

                        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
                        Behavior on scale {
                            NumberAnimation { duration: Timing.contentFade; easing.type: Easing.OutQuad }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            color: "transparent"
                            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
                            border.color: Theme.alert
                            antialiasing: true
                        }

                        // The question is asked in human language, because it
                        // is addressed to a person.
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${row.modelData.label.charAt(0)}${row.modelData.label.slice(1).toLowerCase()}?`
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 6 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * root.factor

                            Item {
                                width: cancelText.implicitWidth + 24 * root.factor
                                height: 26 * root.factor

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Metrics.radiusFor(height, root.metrics)
                                    color: "transparent"
                                    border.width: Metrics.crisp(Metrics.rimWidth,
                                                                Screen.devicePixelRatio)
                                    border.color: Theme.line
                                    antialiasing: true
                                }

                                Text {
                                    id: cancelText
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    color: Theme.text
                                    font.family: Typography.expressive
                                    font.pixelSize: root.metrics.fontSecondary
                                }

                                TapHandler {
                                    onTapped: Session.cancel()
                                }
                            }

                            // The one filled surface in the shell that is not
                            // primary. It is filled because it is the thing
                            // that acts, and it is alert because of what it
                            // does — and it is the only place either is true.
                            Item {
                                width: actText.implicitWidth + 24 * root.factor
                                height: 26 * root.factor

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Metrics.radiusFor(height, root.metrics)
                                    antialiasing: true

                                    gradient: Gradient {
                                        GradientStop { position: 0; color: Theme.gradientTop(Theme.alert) }
                                        GradientStop { position: 1; color: Theme.gradientBottom(Theme.alert) }
                                    }
                                }

                                Text {
                                    id: actText
                                    anchors.centerIn: parent
                                    text: `${row.modelData.label.charAt(0)}${row.modelData.label.slice(1).toLowerCase()}`
                                    color: Theme.background
                                    font: Qt.font({
                                        "family": Typography.expressive,
                                        "pixelSize": root.metrics.fontSecondary,
                                        "weight": Typography.weightTitle
                                    })
                                }

                                TapHandler {
                                    onTapped: Session.confirm()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- The machine ---------------------------------------------------------

    Connections {
        target: root.cell
        function onOpenChanged() {
            if (root.cell.open)
                Machine.ask();
            Machine.watching = root.cell.open;
        }
    }

    Component.onDestruction: Machine.watching = false

    Thread {
        vertical: false
        progress: root.sideProgress
        width: root.gap
        height: implicitHeight
        x: root.infoLeft ? root.infoWidth : root.panelWidth
        y: root.panelY + root.panelHeight / 2 - height / 2
    }

    Panel {
        id: machine

        metrics: root.metrics
        padding: root.panelPadding + 4 * root.factor
        targetWidth: root.infoWidth
        targetHeight: root.panelHeight
        growth: root.infoProgress
        contentReady: root.infoProgress > 0.999

        anchorX: root.infoX
        anchorY: root.panelY
        nodeX: root.infoLeft ? root.infoWidth : root.infoX
        nodeY: root.panelY + root.panelHeight / 2

        Column {
            anchors.fill: parent
            anchors.topMargin: 2 * root.factor

            Repeater {
                model: Machine.rows

                delegate: Item {
                    id: fact

                    required property var modelData

                    width: parent.width
                    height: Math.min(24 * root.factor,
                                     (machine.height - (root.panelPadding + 4 * root.factor) * 2)
                                     / Math.max(1, Machine.rows.length))

                    // What it is, in the machine's voice; its value in the
                    // voice it is written in — a name is language, a figure
                    // is the machine counting.
                    Text {
                        id: factLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70 * root.factor
                        text: fact.modelData.label
                        color: Theme.textFaint
                        font: Qt.font({
                            "family": Typography.technical,
                            "pixelSize": root.metrics.fontMeta,
                            "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                 Typography.labelTracking)
                        })
                    }

                    Text {
                        anchors.left: factLabel.right
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: fact.modelData.value
                        color: Theme.text
                        font: fact.modelData.human
                              ? Qt.font({ "family": Typography.expressive,
                                          "pixelSize": root.metrics.fontSecondary })
                              : Typography.tabular(Qt.font({
                                    "family": Typography.technical,
                                    "pixelSize": root.metrics.fontMeta,
                                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                                         Typography.labelTracking)
                                }))
                    }
                }
            }
        }
    }

    // What the membrane has to mask and blur: the surfaces, never the threads.
    function shapes() {
        return [
            { "item": identity, "radius": identity.radius },
            { "item": commands, "radius": commands.radius },
            { "item": machine, "radius": machine.radius }
        ];
    }
}
