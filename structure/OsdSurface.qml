import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.services

// The on-screen display, one per monitor: the volume, the brightness or the
// keyboard's layout, said for a moment after it changes where no cell says it
// already (`Osd`).
//
// It is the audio cell's summoned form — dial, figure, slider in one capsule —
// because it says the same thing, and the brightness wears the same capsule
// with the sun in the middle of its dial: the arc is the travel, the glyph is
// the domain. The layout has no travel, so it has no dial: it wears the
// keyboard cell's face instead — glyph and code — with the layout's full name
// beside it, and the capsule is as wide as that. It grows from its own centre, low in the middle of the screen,
// and takes no input: it answers a key, it is not a control.
PanelWindow {
    id: root

    required property var screenItem

    screen: screenItem
    color: "transparent"
    exclusiveZone: -1

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bioma-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property var metrics: Metrics.step("normal")
    readonly property real factor: metrics.factor

    readonly property bool here: Osd.kind.length > 0 && root.screenItem
                                 && Osd.output === root.screenItem.name

    // What it is saying, kept while it leaves: the kind is cleared the moment
    // the display is done, and the capsule has to shrink wearing what it wore.
    property string kind: "volume"
    onHereChanged: if (root.here) root.kind = Osd.kind
    Connections {
        target: Osd
        function onKindChanged() { if (root.here) root.kind = Osd.kind; }
    }

    property real growth: root.here ? 1 : 0

    Behavior on growth {
        NumberAnimation {
            duration: root.here ? Timing.open : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.here ? Timing.easeOpen : Timing.easeClose
        }
    }

    visible: root.growth > 0

    readonly property real capsuleHeight: 88 * factor
    readonly property real dialSize: 56 * factor
    readonly property real figureWidth: 62 * factor
    readonly property real sliderWidth: 168 * factor
    readonly property real gap: 20 * factor
    readonly property real side: 23 * factor
    readonly property real glyphSize: 28 * factor

    readonly property bool layout: root.kind === "layout"
    readonly property real capsuleWidth: root.layout
        ? root.side * 2 + root.glyphSize + root.gap + layoutCode.implicitWidth
          + root.gap + layoutName.implicitWidth
        : root.side * 2 + root.dialSize + root.figureWidth + root.sliderWidth + root.gap * 2

    readonly property real fraction: root.kind === "brightness" ? Brightness.brightness
                                                                : Math.min(1, Audio.volume)
    readonly property real overflow: root.kind === "brightness" ? 0 : Math.max(0, Audio.volume - 1)
    readonly property bool silenced: root.kind === "volume" && Audio.muted
    readonly property int percent: root.kind === "brightness" ? Math.round(Brightness.brightness * 100)
                                                              : Audio.volumePercent

    // Low in the middle: under the eye's line, clear of any membrane.
    readonly property real centreX: width / 2
    readonly property real centreY: height - 3 * metrics.cellHeight - capsuleHeight / 2

    OuterShadow {
        anchors.fill: capsule
        radius: capsule.radius
        blur: 44
        offsetY: 22
        color: Theme.shadowFloat
        opacity: Timing.shadowFor(root.growth)
    }

    Panel {
        id: capsule

        metrics: root.metrics
        radius: Metrics.radiusFor(root.capsuleHeight, root.metrics)
        padding: root.side
        fixedWidth: root.capsuleWidth
        fixedHeight: root.capsuleHeight
        growth: root.growth
        contentReady: root.growth > 0.999

        anchorX: root.centreX - root.capsuleWidth / 2
        anchorY: root.centreY - root.capsuleHeight / 2
        nodeX: root.centreX
        nodeY: root.centreY

        Item {
            anchors.fill: parent
            visible: !root.layout

            Gauge {
                id: dial
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.dialSize
                height: width
                trackUnits: 1.5
                nodeUnits: 4
                fraction: root.fraction
                overflow: root.overflow
                muted: root.silenced

                Icon {
                    anchors.centerIn: parent
                    visible: root.kind === "brightness"
                    width: 22 * root.factor
                    height: width
                    name: "brightness"
                    gradient: true
                }
            }

            Text {
                id: reading
                anchors.left: dial.right
                anchors.leftMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                width: root.figureWidth
                text: `${root.percent}%`
                color: Theme.text
                opacity: root.silenced ? 0.45 : 1
                font: Typography.tabular(Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontValue,
                    "weight": Typography.weightValue
                }))
            }

            Slider {
                anchors.left: reading.right
                anchors.leftMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                width: root.sliderWidth
                factor: root.factor
                value: root.fraction
                dimmed: root.silenced
                enabled: false
            }
        }

        Item {
            anchors.fill: parent
            visible: root.layout

            Icon {
                id: layoutGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.glyphSize
                height: width
                name: "keyboard"
                gradient: true
            }

            Text {
                id: layoutCode
                anchors.left: layoutGlyph.right
                anchors.leftMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                text: Keyboard.currentCode
                color: Theme.text
                font: Qt.font({
                    "family": Typography.technical,
                    "pixelSize": root.metrics.fontValue,
                    "weight": Typography.weightValue,
                    "letterSpacing": Typography.tracking(root.metrics.fontValue, Typography.labelTracking)
                })
            }

            Text {
                id: layoutName
                anchors.left: layoutCode.right
                anchors.leftMargin: root.gap
                anchors.verticalCenter: parent.verticalCenter
                text: Keyboard.current
                color: Theme.textMuted
                font: Qt.font({
                    "family": Typography.expressive,
                    "pixelSize": root.metrics.fontLabel,
                    "weight": Typography.weightSecondary
                })
            }
        }
    }

    // It takes nothing: a press anywhere goes to what is under it.
    Region { id: nothing }
    mask: nothing

    // And it is glass like every other shape, blurred as a shape.
    property var blurRegion: null
    BackgroundEffect.blurRegion: blurRegion

    function refreshBlur() {
        root.blurRegion = Regions.rebind(root, root.blurRegion,
                                         [{ "item": capsule, "radius": capsule.radius }]);
    }

    onGrowthChanged: root.refreshBlur()
    Component.onCompleted: root.refreshBlur()
}
