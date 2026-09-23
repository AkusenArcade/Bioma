import QtQuick
import Quickshell
import qs.components
import qs.core
import qs.structure
import qs.services

// The wallpaper and the palette derived from it.
//
// At rest this is not an icon that *represents* the theme: it is the palette
// itself, seven chips in a row inside a pill. Change the wallpaper and the cell
// changes, which is visible without opening anything — the contracted cell
// **is** the data.
//
// It does not animate except when the theme changes. That closes PRD §9.7
// against continuous motion: an animation with no live value behind it is
// decoration, and this datum changes once a day.
//
// The file is not called `Theme.qml`: `core/Theme.qml` owns that name, and a
// singleton shadowed by a component is the same trap that cost `Scale` its
// name.
//
// See docs/design/CELLS.md §07.
Cell {
    id: root

    domain: "theme"

    // The chips take the full margin on both sides. Open, the header leads
    // with a round glyph concentric with the cap, and that margin is the
    // engine's to work out.
    paddingLeading: 16
    paddingTrailing: 16

    readonly property real chipWidth: 10 * metrics.factor
    readonly property real chipHeight: 22 * metrics.factor
    readonly property real chipGap: 3 * metrics.factor
    readonly property real chipRadius: Metrics.shaped(5 * metrics.factor)

    // Seven, always — even when two of them are nearly the same colour. The
    // number of roles is fixed, and it is part of what the cell says.
    readonly property var roles: Theme.targetRoles

    // Open, the cell stops being the palette and becomes the title of what it
    // opened, like every other cell with an expansion: the glyph of its domain
    // and its name, in the technical voice. The palette is still on screen —
    // the second capsule holds the same seven roles, larger.
    // Conditional, it is there for a moment after the palette changes — a new
    // wallpaper coloured by matugen, a palette chosen — so the change is seen
    // where it is made. The targets, not the animated roles: those move on
    // every frame of the crossing.
    readonly property string paletteSignature: [Theme.backgroundTarget, Theme.primaryTarget,
                                                 Theme.secondaryTarget, Theme.textTarget].join()
    onPaletteSignatureChanged: root.pulse()
    condition: root.pulsing ? 1 : 0

    headerTitle: "THEME"
    headerMark: Component {
        Icon {
            anchors.fill: parent
            name: "theme"
            gradient: true
        }
    }

    contentWidth: roles.length * chipWidth + (roles.length - 1) * chipGap

    replacesContent: true

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.chipGap

        Repeater {
            model: root.roles

            delegate: Rectangle {
                id: chip

                required property var modelData
                required property int index

                width: root.chipWidth
                height: root.chipHeight
                radius: root.chipRadius
                antialiasing: true
                color: chip.modelData

                // The only movement this cell has, and it runs on a change of
                // theme and never otherwise. The chips replace each other one
                // at a time rather than all together — the shell's own surfaces
                // cross in one transition, and a row that did the same would be
                // a second copy of it rather than a reading of it.
                //
                // They follow the palette's destination, not the shell's
                // transition: a chip bound to a colour that is itself animating
                // would restart its own delay on every frame and arrive late
                // and all at once.
                Behavior on color {
                    SequentialAnimation {
                        PauseAnimation { duration: chip.index * Timing.stagger }
                        ColorAnimation { duration: Timing.theme; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }
    }

    // ---- Open ---------------------------------------------------------------

    // The expansion is a composition — a carousel, two capsules and the threads
    // between them — so it lives in its own file beside this one and arrives
    // through a Loader: a cell's directory is not a QML module.
    expansion: Component {
        Loader {
            id: expansionLoader
            source: Qt.resolvedUrl("ThemeExpansion.qml")
            onLoaded: {
                item.cell = root;
                item.metrics = Qt.binding(() => root.metrics);
            }

            function shapes() {
                return expansionLoader.item ? expansionLoader.item.shapes() : [];
            }
        }
    }
}
