import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// Who is logged in, and how to leave.
//
// The smallest cell in the catalogue and the most delicate: it holds the only
// actions that can lose work. At rest it is the avatar and nothing else — no
// name, because a name on the membrane at all times is the shell introducing
// someone who already knows who they are.
//
// See docs/design/CELLS.md §08, PRD §9.8.
Cell {
    id: root

    domain: "session"

    // The avatar is the whole content, and it is round like the window title's
    // icon, so the padding is what makes the cell square around it.
    readonly property real avatarSize: 30 * metrics.factor
    paddingLeading: (metrics.cellHeight - avatarSize) / 2
    paddingTrailing: open ? 16 : paddingLeading

    contentWidth: avatarSize

    // ---- Open ---------------------------------------------------------------

    headerTitle: "SESSION"
    headerMarkSize: 20 * metrics.factor
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "power"
            gradient: true
        }
    }

    replacesContent: true

    // The numbers are part of the design: whoever opens this cell is often
    // already on the keyboard, and the second time round there is nothing left
    // to read. So this cell holds the keys for as long as it is open, unlike
    // vitals, which asks only over its own panel — five rows and a question
    // are a short moment, and while it lasts the window title says which cell
    // has the focus rather than going out.
    wantsKeyboard: open

    // A question left on screen is a question asked again next time. Closing
    // the cell withdraws it.
    onOpenChanged: if (!open) Session.cancel()

    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("SessionExpansion.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
    }

    // ---- Contracted ---------------------------------------------------------

    Portrait {
        anchors.centerIn: parent
        width: root.avatarSize
        height: width
        source: Session.avatar
        available: Session.hasAvatar
        onFailed: Session.avatarFailed()
    }
}
