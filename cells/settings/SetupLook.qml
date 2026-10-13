import QtQuick
import Qt5Compat.GraphicalEffects
import qs.core
import qs.components
import qs.services

// The setup's second step: the palette, the wallpaper, and whether other
// applications wear them.
//
// Everything here is the theme cell's, offered once in the order a newcomer
// decides it; the theme is an animated singleton, so the desktop retints while
// the choice is made. Other applications are off until asked for — their
// configurations are somebody's own — and one switch here turns on every
// target the theme cell lists for what is installed.
//
// See docs/design/SETUP.md, step 2.
Item {
    id: root

    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor
    readonly property bool fromWallpaper: Theme.source === "matugen"

    function summarise() {
        Setup.note("look", root.fromWallpaper
            ? `From the wallpaper, ${Matugen.variant}`
            : Theme.paletteName);
    }

    // What is on screen already counts as an answer: the step's capsule says
    // it as soon as the step has been seen.
    Component.onCompleted: root.summarise()

    // The applications a switch here would colour: installed, and not niri,
    // which is on from the start.
    readonly property var apps: Templates.catalogue.filter(entry => entry.installed && entry.id !== "niri")
    readonly property bool appsOn: root.apps.length > 0 && root.apps.every(entry => Templates.isOn(entry.id))

    function setApps(on) {
        for (const entry of root.apps)
            Templates.setOn(entry.id, on);
    }

    Column {
        anchors.fill: parent
        spacing: 10 * root.factor

        SetupSection {
            metrics: root.metrics
            label: "PALETTE"

            trailing: Segmented {
                anchors.verticalCenter: parent.verticalCenter
                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                options: [
                    { "key": "manual", "label": "Bioma" },
                    { "key": "matugen", "label": "Wallpaper" }
                ]
                current: Theme.source
                onChose: key => {
                    Config.set("theme.source", key);
                    root.summarise();
                }
            }

            Segmented {
                visible: !root.fromWallpaper
                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                options: Theme.palettes.map(palette => ({ "key": palette.file, "label": palette.name }))
                current: Theme.manualPalette
                onChose: key => {
                    Config.set("theme.palette", key);
                    root.summarise();
                }
            }

            Segmented {
                visible: root.fromWallpaper
                metrics: root.metrics
                fontSize: root.metrics.fontMeta
                options: [
                    { "key": "dark", "label": "Dark" },
                    { "key": "light", "label": "Light" }
                ]
                current: Matugen.variant
                onChose: key => {
                    Config.set("theme.matugen.variant", key);
                    root.summarise();
                }
            }

            SetupLine {
                metrics: root.metrics
                text: root.fromWallpaper
                      ? "The colours are taken from the wallpaper, and change with it."
                      : "One of Bioma's palettes, the same whatever the wallpaper."
            }
        }

        SetupSection {
            metrics: root.metrics
            label: "WALLPAPER"

            trailing: Choice {
                anchors.verticalCenter: parent.verticalCenter
                metrics: root.metrics
                label: Wallpaper.picking ? "CHOOSING" : "FOLDER"
                dimmed: Wallpaper.picking
                onActivated: Wallpaper.pickFolder()
            }

            // The folder's pictures, the one on screen in the middle. A press
            // on another puts it on the desktop.
            Row {
                spacing: 8 * root.factor

                Repeater {
                    model: [-2, -1, 0, 1, 2]

                    delegate: Item {
                        id: thumb

                        required property int modelData

                        readonly property string path: Wallpaper.neighbour(thumb.modelData)
                        readonly property bool here: thumb.modelData === 0

                        width: 76 * root.factor
                        height: 48 * root.factor
                        visible: thumb.path.length > 0 && (thumb.here || Wallpaper.entries.length > 1)

                        readonly property bool navigable: !thumb.here

                        function activate() {
                            Wallpaper.step(thumb.modelData);
                            root.summarise();
                        }

                        KeyMark {
                            factor: root.factor
                        }

                        Component.onCompleted: if (thumb.path.length > 0) Wallpaper.prepare(thumb.path)
                        onPathChanged: if (thumb.path.length > 0) Wallpaper.prepare(thumb.path)

                        // Rounded as the theme cell's carousel is: through a
                        // mask, never a clip, which would square the corners.
                        // Both halves carry their own layer and are hidden with
                        // opacity, never `visible` (CLAUDE.md).
                        Image {
                            id: picture
                            anchors.fill: parent
                            source: thumb.path.length > 0 ? `file://${Wallpaper.thumbnail(thumb.path)}` : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            sourceSize.width: Math.round(76 * 2 * Screen.devicePixelRatio)
                            opacity: 0
                            layer.enabled: true
                        }

                        Rectangle {
                            id: shape
                            anchors.fill: parent
                            radius: 6 * root.factor
                            antialiasing: true
                            opacity: 0
                            layer.enabled: true
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: picture
                            maskSource: shape
                            opacity: thumb.here ? 1 : 0.55
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 6 * root.factor
                            color: "transparent"
                            border.width: Metrics.rim(Screen.devicePixelRatio)
                            border.color: thumb.here ? Theme.primary : Qt.alpha(Theme.line, 0.7)
                            antialiasing: true
                        }

                        TapHandler {
                            onTapped: thumb.activate()
                        }
                    }
                }
            }

            SetupLine {
                metrics: root.metrics
                color: Wallpaper.folderError.length > 0 ? Theme.alert : Theme.text
                text: Wallpaper.folderError.length > 0 ? Wallpaper.folderError
                    : Wallpaper.entries.length === 0 ? "No pictures in this folder yet. Bioma's own is on the desktop."
                    : `From ${Wallpaper.folder.replace(/^\/home\/[^/]+/, "~")}. The theme cell has the rest of them.`
            }
        }

        SetupSection {
            metrics: root.metrics
            label: "OTHER APPLICATIONS"
            visible: root.apps.length > 0

            trailing: Switch {
                anchors.verticalCenter: parent.verticalCenter
                factor: root.factor
                on: root.appsOn
                onToggled: value => root.setApps(value)
            }

            SetupLine {
                metrics: root.metrics
                text: root.appsOn
                      ? `The palette reaches ${root.apps.map(entry => entry.name).join(", ")}. Each is switched on or off on its own under APPS in the theme cell (Mod+Alt+T).`
                      : "Off: other applications keep their own colours. Switched on, the palette is written into their configurations — each one can be turned back off in the theme cell."
            }
        }
    }
}
