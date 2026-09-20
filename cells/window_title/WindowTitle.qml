import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Which window has focus. The second of the two exceptions to the silence rule:
// without a name a window cannot be recognised, so the text is always there.
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

    // Conditional: it exists only while a window has focus. A boolean condition
    // against a threshold of one.
    condition: Niri.focusedWindow ? 1 : 0

    readonly property real iconSize: 30 * metrics.factor
    readonly property real spacing: 10 * metrics.factor
    readonly property real titleSize: metrics.fontTitle

    // The width the content would like, before eliding — see Cell.contentWidth.
    // `implicitWidth` is the unconstrained width of the string; `contentWidth`
    // is what it actually occupies once elided, and binding the label's width
    // to that would make the two chase each other down to nothing.
    contentWidth: iconSize + spacing + label.implicitWidth

    readonly property real available: Math.max(0, width - paddingLeading - paddingTrailing - iconSize - spacing)

    // ---- Icon --------------------------------------------------------------
    //
    // Application icons are third-party and stylistically unrelated: the dark
    // circle with a thin outline is what makes them a family. The icon is the
    // only element in the shell that does not follow the palette, because it
    // belongs to the application. The fallback does follow it.

    readonly property var entry: Niri.focusedAppId ? DesktopEntries.heuristicLookup(Niri.focusedAppId) : null
    readonly property string iconSource: entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""

    // ---- Title -------------------------------------------------------------
    //
    // Browsers rewrite the title on every tab. The text waits out the debounce
    // and then crosses over; it is never swapped abruptly.

    readonly property string incoming: Niri.focusedTitle

    // A cell that has nothing on it yet has nothing to cross-fade from, and a
    // title that never settles — a terminal with a spinner in it rewrites faster
    // than the debounce — would otherwise leave the cell permanently empty.
    onIncomingChanged: {
        if (label.text === "")
            label.text = root.incoming;
        else
            debounce.restart();
    }

    Timer {
        id: debounce
        interval: Timing.debounce
        onTriggered: {
            if (label.text !== root.incoming)
                crossfade.restart();
        }
    }

    SequentialAnimation {
        id: crossfade
        NumberAnimation { target: label; property: "opacity"; to: 0; duration: Timing.contentFade }
        ScriptAction { script: label.text = root.incoming }
        NumberAnimation { target: label; property: "opacity"; to: 1; duration: Timing.contentFade }
    }

    Component.onCompleted: label.text = root.incoming

    // Click centres the window on screen, through niri's own action.
    TapHandler {
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

            Image {
                id: appIcon
                anchors.centerIn: parent
                width: parent.width * 0.62
                height: width
                visible: root.iconSource !== ""
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
                visible: root.iconSource === ""
                name: "app-fallback"
                colour: Theme.textMuted
            }
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
            font.family: Typography.expressive
            font.pixelSize: root.titleSize
        }
    }
}
