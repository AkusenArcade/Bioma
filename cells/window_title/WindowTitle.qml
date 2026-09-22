import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// What has the focus. The second of the two exceptions to the silence rule:
// without a name a window cannot be recognised, so the text is always there.
//
// Usually that is a window. Sometimes it is one of Bioma's own cells: a cell
// with a field to type in takes the keyboard, and the compositor takes it off
// the window to give it. The focus did not go nowhere, so neither does this
// cell — it names the cell instead, in the machine's voice with the cell's own
// glyph, and hands the window back the moment the window has it back. Akusen's
// call, 2026-09-22: before it, the title went out and came back as the pointer
// crossed the membrane, which is the shell blinking at its own doing.
//
// It exists only while something has focus, it is elastic between a minimum
// that stops a title change from making the tissue dance and a cap past which
// the text elides, and clicking it centres the window.
//
// See docs/design/CELLS.md §01.
Cell {
    id: root

    domain: "window_title"

    // The icon is round and sits against the leading cap, concentric with it;
    // the text keeps the full margin on the other side.
    paddingLeading: 5
    paddingTrailing: 16

    // The shell has the focus, and a cell is what has it. Both halves matter:
    // a cell holding the keyboard while the window keeps the focus — which is
    // what happens until the compositor actually moves it — is still a window
    // with the focus, and this cell says so.
    readonly property bool onCell: Focus.holdsKeyboard && !Niri.focusedWindow
    readonly property Item subject: root.onCell ? Focus.cell : null

    readonly property string cellName: root.subject
        ? (root.subject.headerTitle.length > 0
           ? root.subject.headerTitle
           : root.subject.domain.toUpperCase())
        : ""

    // Conditional: it exists while something has the focus, whichever of the
    // two it is. A boolean condition against a threshold of one.
    condition: (Niri.focusedWindow || root.onCell) ? 1 : 0

    // It has no expansion and it still answers: a press centres the window.
    interactive: true

    readonly property real iconSize: 30 * metrics.factor
    readonly property real spacing: 10 * metrics.factor
    readonly property real titleSize: metrics.fontTitle

    // The width the content would like, before eliding — see Cell.contentWidth.
    // `implicitWidth` is the unconstrained width of the string; `contentWidth`
    // is what it actually occupies once elided, and binding the label's width
    // to that would make the two chase each other down to nothing.
    readonly property real loaderSize: 16 * metrics.factor

    contentWidth: iconSize + spacing + (root.waiting ? loaderSize + spacing : 0) + label.implicitWidth

    readonly property real available: Math.max(0, width - paddingLeading - paddingTrailing - iconSize - spacing
                                                 - (root.waiting ? loaderSize + spacing : 0))

    // ---- Icon --------------------------------------------------------------
    //
    // Application icons are third-party and stylistically unrelated: the dark
    // circle with a thin outline is what makes them a family. The icon is the
    // only element in the shell that does not follow the palette, because it
    // belongs to the application. The fallback does follow it.

    readonly property string iconSource: Apps.iconFor(Niri.focusedAppId)

    // ---- Title -------------------------------------------------------------
    //
    // Browsers rewrite the title on every tab. The text waits out the debounce
    // and then crosses over; it is never swapped abruptly.

    // A window that is working says so in its own title: a terminal, a browser
    // tab, an editor indexing. They all do it the same way — a spinner glyph in
    // front of the name, rewritten several times a second — and the shell has
    // its own way of saying it. So the glyph is taken out of the string and
    // shown as the loader instead: one drawing for "working", whichever
    // application asked.
    //
    // It also settles the title. A spinner rewrites faster than the debounce,
    // so a cell that watched the raw string was never looking at a title that
    // had stopped changing.
    function spins(code) {
        return (code >= 0x25D0 && code <= 0x25D3)      // half-filled circles
            || (code >= 0x25F4 && code <= 0x25F7)      // quartered circles
            || (code >= 0x2800 && code <= 0x28FF)      // braille, the usual dots
            || (code >= 0x1F550 && code <= 0x1F55B)    // clock faces
            || (code >= 0x1F311 && code <= 0x1F318);   // moon phases
    }

    function settled(title) {
        if (!title || title.length === 0)
            return { "waiting": false, "text": "" };

        const first = title.codePointAt(0);
        if (!root.spins(first))
            return { "waiting": false, "text": title };

        const rest = title.slice(String.fromCodePoint(first).length);
        return { "waiting": true, "text": rest.replace(/^[\s\u00a0]+/, "") };
    }

    readonly property var reading: root.settled(Niri.focusedTitle)
    readonly property string incoming: root.onCell ? root.cellName : root.reading.text

    // Late in, immediate out. A wait under a moment must show nothing — a
    // loader that flashes is worse than a moment of stillness — but the moment
    // the work finishes the loader is wrong, and waiting for a cycle to end
    // would be the shell lying about the state of the machine.
    // Only a window works at something; a cell is never waiting.
    readonly property bool spinning: !root.onCell && root.reading.waiting
    property bool waiting: false

    onSpinningChanged: {
        if (root.spinning) {
            appear.restart();
        } else {
            appear.stop();
            root.waiting = false;
        }
    }

    Timer {
        id: appear
        interval: Timing.debounce
        onTriggered: root.waiting = true
    }

    // A cell that has nothing on it yet has nothing to cross-fade from, and a
    // title that never settles — a terminal with a spinner in it rewrites faster
    // than the debounce — would otherwise leave the cell permanently empty.
    onIncomingChanged: {
        if (label.text === "") {
            label.text = root.incoming;
            root.technical = root.onCell;
        } else {
            debounce.restart();
        }
    }

    Timer {
        id: debounce
        interval: Timing.debounce
        onTriggered: {
            if (label.text !== root.incoming)
                crossfade.restart();
        }
    }

    // A window's name is human language and a cell's name is the machine's own
    // word, and the two voices never swap. The switch travels with the text
    // through the cross-fade rather than on the focus change, or the outgoing
    // string spends the fade in the wrong face.
    property bool technical: false

    SequentialAnimation {
        id: crossfade
        NumberAnimation { target: label; property: "opacity"; to: 0; duration: Timing.contentFade }
        ScriptAction {
            script: {
                label.text = root.incoming;
                root.technical = root.onCell;
            }
        }
        NumberAnimation { target: label; property: "opacity"; to: 1; duration: Timing.contentFade }
    }

    Component.onCompleted: {
        label.text = root.incoming;
        root.technical = root.onCell;
    }

    // Click centres the window on screen, through niri's own action. With a
    // cell in the title there is no window to centre, and the press does
    // nothing rather than acting on whichever window used to be there.
    TapHandler {
        enabled: !root.onCell
        onTapped: Niri.centerFocusedWindow()
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: root.iconSize
            radius: width / 2
            color: Theme.lift(Theme.background, -0.015)
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: Qt.alpha(Theme.text, 0.5)
            antialiasing: true

            // The cell's own mark, built by the cell that holds the focus —
            // the audio dial is still live in here, which is the point of
            // taking the mark rather than drawing a second one.
            Loader {
                anchors.centerIn: parent
                width: parent.width * 0.62
                height: width
                active: root.onCell
                sourceComponent: root.subject ? root.subject.headerMark : null
            }

            Image {
                id: appIcon
                anchors.centerIn: parent
                width: parent.width * 0.62
                height: width
                visible: !root.onCell && root.iconSource !== ""
                source: root.iconSource
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            // Never another application's logo: an unresolved icon gets the
            // neutral glyph, and that one does follow the palette.
            Icon {
                anchors.centerIn: parent
                width: parent.width * 0.62
                height: width
                visible: !root.onCell && root.iconSource === ""
                name: "app-fallback"
                colour: Theme.textMuted
            }
        }

        // Beside the name, never in place of the application's icon: replacing
        // the glyph would make the row jump twice, once when the wait starts
        // and once when it ends.
        Sweep {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.waiting
            width: root.loaderSize
            height: width
            running: root.waiting
            colour: Theme.textMuted
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: root.available
            // Ellipsis goes on the text, never on the cell: clipping the cell
            // eats the rim.
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.text
            font.family: root.technical ? Typography.technical : Typography.expressive
            font.pixelSize: root.titleSize
            font.weight: root.technical ? Typography.weightLabel : Font.Normal
            font.letterSpacing: root.technical
                ? Typography.tracking(root.titleSize, Typography.labelTracking) : 0
        }
    }
}
