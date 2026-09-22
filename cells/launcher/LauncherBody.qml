import QtQuick
import Quickshell
import qs.core
import qs.components

// The launcher's own body: a field and the results under it.
//
// It is a file of its own because the launcher is two things wearing one set
// of clothes — the whole panel in the middle of the screen when it is asked
// for by name, and a panel hanging off a button when somebody has put it on a
// membrane. What changes is where it is born; what it *is* does not, which is
// the same sentence CELLS §05 uses about the audio cell.
//
// Everything it knows it asks the cell for: the query, the results, which one
// is chosen, and what to do about it.
//
// See docs/design/CELLS.md §13.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    // The cell arrives a moment after the body does: a Loader builds its item
    // first and hands it the cell in `onLoaded`, so every measurement taken
    // from the cell is read through one of these. Without them the first frame
    // is a page of "cannot read property of null" — harmless, and exactly the
    // kind of noise a real error hides in.
    readonly property real fieldHeight: root.cell ? root.cell.fieldHeight : 0
    readonly property real resultHeight: root.cell ? root.cell.resultHeight : 0
    readonly property real listGap: root.cell ? root.cell.listGap : 0
    readonly property int shownRows: root.cell ? root.cell.shownRows : 0
    readonly property string query: root.cell ? root.cell.query : ""
    readonly property var results: root.cell ? root.cell.results : []
    readonly property int chosen: root.cell ? root.cell.chosen : 0

    // It measures itself from what it was given rather than from the cell:
    // the cell is a panel in one form and a twenty-pixel button in the other,
    // and its content width is the button's.
    function takeCaret() {
        field.forceActiveFocus();
    }

    // The chosen row is kept in view by whoever draws the rows, not by
    // whoever counts them: the cell moves the choice and the list follows.
    Connections {
        target: root.cell
        function onChosenChanged() {
            list.positionViewAtIndex(root.cell.chosen, ListView.Contain);
        }
    }

    Item {
        id: search

        width: root.width
        height: root.fieldHeight
        y: 0

        Icon {
            id: lens
            anchors.left: parent.left
            anchors.leftMargin: 6 * root.metrics.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.metrics.factor
            height: width
            name: "search"
            gradient: true
        }

        TextInput {
            id: field

            anchors.left: lens.right
            anchors.leftMargin: 12 * root.metrics.factor
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.metrics.factor
            anchors.verticalCenter: parent.verticalCenter

            text: root.query
            onTextChanged: if (root.cell) root.cell.query = text

            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: 16 * root.metrics.factor
            selectByMouse: true
            cursorVisible: true

            // Arrows move, Enter launches, Escape closes. The first result is
            // already chosen: two letters and Enter has to be enough.
            Keys.onDownPressed: cell.move(1)
            Keys.onUpPressed: cell.move(-1)
            Keys.onReturnPressed: cell.launch(cell.chosen)
            Keys.onEnterPressed: cell.launch(cell.chosen)
            Keys.onEscapePressed: cell.dismiss()

            Text {
                anchors.fill: parent
                visible: field.text.length === 0
                text: "Search"
                color: Theme.textFaint
                font: field.font
            }
        }
    }

    // ---- The results ---------------------------------------------------------

    // Nothing found is one line, and the field does not move: a panel that
    // collapsed under the fingers would take the field with it.
    Text {
        y: search.height + root.listGap
        width: root.width
        height: root.resultHeight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        visible: root.query.length > 0 && root.results.length === 0
        text: "Nothing answers to that"
        color: Theme.textMuted
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontTitle
    }

    Scroller {
        flick: list
        factor: root.metrics.factor
        x: root.width - width
    }

    ListView {
        id: list

        y: search.height + root.listGap
        width: root.width - 8 * root.metrics.factor
        height: root.shownRows * root.resultHeight
        visible: root.results.length > 0

        model: root.results
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        delegate: Item {
            id: result

            required property var modelData
            required property int index

            readonly property bool picked: root.chosen === result.index

            width: ListView.view.width
            height: root.resultHeight

            // Selection is a fill and never an outline: the lit outline means
            // "surface" in this shell, and a row wearing one would read as a
            // cell inside a cell.
            Rectangle {
                anchors.fill: parent
                anchors.rightMargin: 2 * root.metrics.factor
                radius: Metrics.shaped(14 * root.metrics.factor)
                color: Qt.alpha(Theme.primary, 0.12)
                visible: result.picked
                antialiasing: true
            }

            Item {
                id: portrait

                anchors.left: parent.left
                anchors.leftMargin: 8 * root.metrics.factor
                anchors.verticalCenter: parent.verticalCenter
                width: 36 * root.metrics.factor
                height: width

                readonly property string source: result.modelData.entry.icon
                    ? Quickshell.iconPath(result.modelData.entry.icon, true) : ""

                Ring {
                    anchors.fill: parent
                    visible: result.picked
                    radius: width / 2
                    thickness: Metrics.crisp(1.5 * root.metrics.factor, Screen.devicePixelRatio)
                    colour: Theme.primary
                }

                Image {
                    anchors.centerIn: parent
                    visible: portrait.source !== ""
                    width: parent.width * 0.7
                    height: width
                    source: portrait.source
                    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: portrait.source === ""
                    width: parent.width * 0.6
                    height: width
                    name: "app-fallback"
                    colour: Theme.textMuted
                }
            }

            // The name, with the letters the search matched lit. A name is
            // human language; the category under it is the system's own word
            // for what the thing is, and takes the other voice.
            Text {
                id: name

                anchors.left: portrait.right
                anchors.leftMargin: 14 * root.metrics.factor
                anchors.right: parent.right
                anchors.rightMargin: 14 * root.metrics.factor
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: category.text.length > 0 ? 0 : -name.height / 2

                text: root.cell.lit(result.modelData.name, result.modelData.at)
                textFormat: Text.StyledText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: 15 * root.metrics.factor
            }

            Text {
                id: category

                anchors.left: name.left
                anchors.right: name.right
                anchors.top: parent.verticalCenter
                anchors.topMargin: 2 * root.metrics.factor
                visible: category.text.length > 0 && name.anchors.bottomMargin === 0

                text: {
                    const list = result.modelData.entry.categories || [];
                    return list.length > 0 ? String(list[0]).toUpperCase() : "";
                }
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.textFaint
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontMeta,
                    "letterSpacing": Typography.tracking(root.metrics.fontMeta,
                                                         Typography.labelTracking)
                })
            }

            HoverHandler {
                onHoveredChanged: if (hovered) cell.chosen = result.index
            }

            TapHandler {
                onTapped: cell.launch(result.index)
            }
        }
    }
}
