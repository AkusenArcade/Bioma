pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Performance mode (core/Performance.qml): the switch, what turns it on by
// itself, and what it quietens, one switch a lever.
//
// Akusen asked for it on 2026-10-24, from "Forse: modalità leggera" in the
// vault: on from a key or while a given program runs — a game through
// GameMode, or any application on a list — and every lever a flag of its
// own. Laid out as the Sounds page is, in wells with a line in Spectral
// saying what the current choice does; the application list picks from the
// windows open now, as the Niri page's window rules do, because an app-id is
// read, not guessed.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var cell: null

    readonly property real factor: metrics.factor
    readonly property real inset: 14 * factor
    readonly property real headerHeight: 28 * factor
    readonly property real gap: 10 * factor
    readonly property real chipHeight: 28 * factor

    readonly property font labelFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontSecondary,
        "letterSpacing": Typography.tracking(root.metrics.fontSecondary, Typography.labelTracking)
    })

    readonly property font metaFont: Qt.font({
        "family": Typography.technical,
        "pixelSize": root.metrics.fontMeta,
        "letterSpacing": Typography.tracking(root.metrics.fontMeta, Typography.labelTracking)
    })

    readonly property var patterns: {
        const list = Config.get("performance.apps", []);
        return Array.isArray(list) ? list : [];
    }

    function addPattern(pattern) {
        pattern = String(pattern || "").trim();
        if (pattern.length === 0)
            return;
        if (root.patterns.some(p => p.toLowerCase() === pattern.toLowerCase()))
            return;
        Config.set("performance.apps", root.patterns.concat([pattern]));
    }

    function removePattern(pattern) {
        Config.set("performance.apps", root.patterns.filter(p => p !== pattern));
    }

    property bool adding: false

    readonly property bool gamemode: Config.get("performance.gamemode", true) === true

    // ---- Shapes this page is made of ----------------------------------------------

    // A well: its label, perhaps its control on the same line, then what it
    // means. Everything under the label is the well's own content.
    component Section: Well {
        id: section

        property string label: ""
        property alias trailing: trailingSlot.data
        default property alias content: body.data

        metrics: root.metrics
        width: parent.width
        height: root.inset * 2 + root.headerHeight + body.childrenRect.height
                + (body.childrenRect.height > 0 ? 6 * root.factor : 0)

        Text {
            x: root.inset
            y: root.inset
            height: root.headerHeight
            verticalAlignment: Text.AlignVCenter
            text: section.label
            color: Theme.text
            font: root.labelFont
        }

        Item {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            y: root.inset
            width: childrenRect.width
            height: root.headerHeight
        }

        Column {
            id: body
            x: root.inset
            y: root.inset + root.headerHeight + 6 * root.factor
            width: section.width - root.inset * 2
            spacing: 10 * root.factor
        }
    }

    // One lever: its switch, and what it does on and off.
    component Lever: Section {
        id: lever

        property string key: ""
        property string whenOn: ""
        property string whenOff: ""

        readonly property bool on: Config.get(`performance.suspend.${lever.key}`, true) !== false

        trailing: Switch {
            anchors.verticalCenter: parent.verticalCenter
            factor: root.factor
            on: lever.on
            onToggled: value => Config.set(`performance.suspend.${lever.key}`, value)
        }

        Line {
            text: lever.on ? lever.whenOn : lever.whenOff
        }
    }

    // What a person reads, so the human voice.
    component Line: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        color: Theme.text
        font.family: Typography.expressive
        font.pixelSize: root.metrics.fontSecondary
        lineHeight: 1.15
    }

    // A place for something not there yet, as on the Structure page.
    component Offer: Item {
        id: offer

        property string label: ""
        signal pressed()

        width: offerLabel.implicitWidth + offerPlus.width + 30 * root.factor
        height: root.chipHeight

        readonly property bool navigable: true
        function activate() { offer.pressed(); }

        KeyMark {
            factor: root.factor
            outset: 3 * root.factor
        }

        DashedSlot {
            anchors.fill: parent
            radius: Metrics.radiusFor(parent.height, root.metrics)
            colour: offerHover.hovered ? Theme.primary : Qt.alpha(Theme.line, 0.7)
        }

        Icon {
            id: offerPlus
            anchors.left: parent.left
            anchors.leftMargin: 11 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 9 * root.factor
            height: width
            name: "plus"
            colour: offerLabel.color
        }

        Text {
            id: offerLabel
            anchors.left: offerPlus.right
            anchors.leftMargin: 7 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: offer.label
            color: offerHover.hovered ? Theme.primary : Theme.text
            font: root.metaFont
        }

        HoverHandler { id: offerHover }
        TapHandler { onTapped: offer.activate() }
    }

    // A one-line field, outlined, in the human voice.
    component Field: Rectangle {
        id: field

        property alias text: input.text
        property string placeholder: ""
        signal accepted()

        height: root.chipHeight
        radius: Metrics.radiusFor(height, root.metrics)
        antialiasing: true
        color: "transparent"
        border.width: Metrics.rim(Screen.devicePixelRatio)
        border.color: input.activeFocus ? Theme.primary : Theme.line

        readonly property bool navigable: !input.activeFocus

        function activate() {
            if (root.cell)
                root.cell.fieldKeyed = true;
            Focus.type(input);
        }

        KeyMark {
            factor: root.factor
            outset: 2 * root.factor
        }

        TextInput {
            id: input

            anchors.left: parent.left
            anchors.leftMargin: 14 * root.factor
            anchors.right: parent.right
            anchors.rightMargin: 14 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
            clip: true
            selectByMouse: true
            selectionColor: Qt.alpha(Theme.primary, 0.35)
            selectedTextColor: Theme.text

            onActiveFocusChanged: {
                if (root.cell && activeFocus)
                    root.cell.fieldEngaged = true;
            }
            onAccepted: {
                field.accepted();
                focus = false;
            }

            Text {
                visible: input.text.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                color: Theme.textFaint
                font: input.font
            }
        }
    }

    // An application to choose: its icon, its name, and the app-id that will
    // be written, or OPEN NOW for one with a window.
    component AppRow: Item {
        id: app

        property string icon: ""
        property string name: ""
        property string detail: ""
        property bool hovered: appHover.hovered
        // An offer is chosen by a press on the whole row; a listed one only
        // through its tools.
        property bool chosenOnTap: false
        default property alias trailing: appTrailing.data
        signal chosen()

        width: parent ? parent.width : 0
        height: 30 * root.factor

        readonly property bool navigable: app.chosenOnTap
        function activate() { app.chosen(); }

        KeyMark {
            visible: app.chosenOnTap
            factor: root.factor
        }

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            color: appHover.hovered && app.chosenOnTap ? Qt.alpha(Theme.text, 0.06) : "transparent"
        }

        Image {
            id: appIcon
            x: 8 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * root.factor
            height: width
            sourceSize.width: width * 2
            sourceSize.height: width * 2
            source: app.icon.length > 0 ? Quickshell.iconPath(app.icon, true) : ""
        }

        Icon {
            anchors.fill: appIcon
            visible: appIcon.status !== Image.Ready
            name: "app-fallback"
        }

        Text {
            id: appName
            anchors.left: appIcon.right
            anchors.leftMargin: 10 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, app.width * 0.5)
            text: app.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }

        Text {
            anchors.left: appName.right
            anchors.leftMargin: 10 * root.factor
            anchors.right: appTrailing.left
            anchors.rightMargin: 8 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            text: app.detail
            elide: Text.ElideLeft
            horizontalAlignment: Text.AlignRight
            color: Theme.textMuted
            font: root.metaFont
        }

        Row {
            id: appTrailing
            anchors.right: parent.right
            anchors.rightMargin: 4 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.factor
        }

        HoverHandler { id: appHover }
        TapHandler {
            enabled: app.chosenOnTap
            onTapped: app.chosen()
        }
    }

    // ---- The page -----------------------------------------------------------------

    // The panel is one height for every category; the wells scroll if they
    // are taller than it.
    Scroller {
        flick: page
        factor: root.factor
        x: root.width - width
    }

    Flickable {
        id: page

        anchors.fill: parent
        anchors.rightMargin: 8 * root.factor
        contentHeight: column.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column

            width: page.width
            spacing: root.gap

            Section {
                label: "PERFORMANCE MODE"

                trailing: Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    factor: root.factor
                    on: Performance.active
                    onToggled: value => value ? Performance.on() : Performance.off()
                }

                Line {
                    text: (Performance.manual
                           ? "On by hand: it stays on, across a restart too, until it is turned off. "
                           : Performance.active
                           ? `On ${Performance.reason}: it goes off by itself when that ends. `
                           : Performance.refused
                           ? "Off by hand while something on this page holds it; it comes back with the next one. "
                           : "Off: the shell runs in full. ")
                          + "A key turns it on and off — Mod+Alt+G as shipped, moved on the Keybinds page — and so does the performance cell."
                }
            }

            Section {
                label: "GAMEMODE"

                trailing: Switch {
                    anchors.verticalCenter: parent.verticalCenter
                    factor: root.factor
                    on: root.gamemode
                    onToggled: value => Config.set("performance.gamemode", value)
                }

                Line {
                    text: root.gamemode
                          ? "On while a game is registered with GameMode: started with gamemoderun, or with GameMode switched on in Steam or Lutris."
                            + (Workload.games > 0 ? " One is registered now." : "")
                          : "Games registered with GameMode do not turn it on."
                }
            }

            Section {
                label: "APPLICATIONS"

                Line {
                    text: root.patterns.length === 0
                          ? "None yet. With a window of one of these open, it comes on. * stands for anything: Steam's games are steam_app_* under XWayland and steam_proton under Proton's Wayland driver."
                          : "On while a window of one of these is open. * stands for anything: Steam's games are steam_app_* under XWayland and steam_proton under Proton's Wayland driver."
                }

                Repeater {
                    model: root.patterns

                    delegate: AppRow {
                        id: listed

                        required property string modelData

                        readonly property var entry: modelData.indexOf("*") < 0 ? Apps.entryFor(modelData) : null
                        readonly property bool open: Workload.matchers.length > 0
                            && Object.keys(Niri.windows).some(id => Workload.matcher(listed.modelData).test(Niri.windows[id].appId || ""))

                        icon: entry && entry.icon ? entry.icon : ""
                        name: entry && entry.name ? entry.name : modelData
                        detail: (listed.open ? "OPEN NOW · " : "") + modelData.toUpperCase()

                        RemoveTool {
                            factor: root.factor
                            opacity: listed.hovered || asking ? 1 : 0
                            onConfirmed: root.removePattern(listed.modelData)
                        }
                    }
                }

                Loader {
                    width: parent.width
                    active: root.adding
                    visible: active

                    sourceComponent: Column {
                        id: picker

                        width: parent ? parent.width : 0
                        spacing: 8 * root.factor

                        // The windows open now first — their app-id is what
                        // the list matches, without guessing — then the
                        // installed applications.
                        readonly property var matches: {
                            const query = search.text.trim().toLowerCase();
                            const fits = (...words) => query.length === 0
                                || words.some(word => String(word || "").toLowerCase().indexOf(query) >= 0);
                            const out = [];
                            const seen = {};
                            for (const pattern of root.patterns)
                                seen[pattern.toLowerCase()] = true;

                            for (const id in Niri.windows) {
                                const appId = Niri.windows[id].appId;
                                if (!appId || seen[appId.toLowerCase()])
                                    continue;
                                const entry = Apps.entryFor(appId);
                                if (!fits(appId, entry ? entry.name : ""))
                                    continue;
                                seen[appId.toLowerCase()] = true;
                                out.push({ "appId": appId, "open": true,
                                           "name": entry ? entry.name : appId, "icon": entry ? entry.icon : "" });
                            }

                            const installed = [];
                            for (const entry of Apps.entries) {
                                if (!entry || entry.noDisplay)
                                    continue;
                                const appId = entry.startupClass || entry.id || "";
                                if (!appId || seen[appId.toLowerCase()] || !fits(entry.name, entry.id))
                                    continue;
                                installed.push({ "appId": appId, "open": false,
                                                 "name": entry.name, "icon": entry.icon });
                            }
                            installed.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
                            return out.concat(installed).slice(0, 6);
                        }

                        function take(appId) {
                            root.addPattern(appId);
                            root.adding = false;
                        }

                        Field {
                            id: search
                            width: parent.width
                            placeholder: "Search open windows and applications, or write an app-id"
                            Component.onCompleted: activate()
                            // Enter keeps what was written, so a pattern
                            // like steam_app_* can be given as it is.
                            onAccepted: picker.take(search.text)
                        }

                        Repeater {
                            model: picker.matches

                            delegate: AppRow {
                                id: offered

                                required property var modelData

                                chosenOnTap: true
                                icon: modelData.icon || ""
                                name: modelData.name
                                detail: (modelData.open ? "OPEN NOW · " : "") + modelData.appId.toUpperCase()
                                onChosen: picker.take(offered.modelData.appId)
                            }
                        }
                    }
                }

                Offer {
                    label: "APPLICATION"
                    onPressed: root.adding = !root.adding
                }
            }

            Lever {
                label: "LIVE INDICATORS"
                key: "motion"
                whenOn: "Held still: the vitals keep their colour and level but stop beating, the clock's second hand ticks once a second, the media band and the download threads stop. The alarms still sound. This is most of what the shell costs at rest."
                whenOff: "They keep moving at the rate of what they measure."
            }

            Lever {
                label: "ORGANISMS"
                key: "organisms"
                whenOn: "Put away, surface and all, and back when the mode goes. Placing them brings them back for as long as it lasts."
                whenOff: "They stay on the desktop."
            }

            Lever {
                label: "WALLPAPER"
                key: "wallpaper"
                whenOn: "Only the picture on screen is kept: the blurred copy behind the overview is put away, and the previous picture is let go once the next one is in."
                whenOff: "The overview keeps its blurred backdrop."
            }

            Lever {
                label: "BLUR AND SHADOWS"
                key: "blur"
                whenOn: "None: the glass shows what is behind it unblurred, and nothing casts a shadow."
                whenOff: "The glass keeps its blur and the panels their shadows."
            }

            Lever {
                label: "TRANSITIONS"
                key: "transitions"
                whenOn: "Instant: cells and panels take their size in one frame instead of growing to it."
                whenOff: "Cells and panels grow and shrink as they always do."
            }

            Lever {
                label: "POLLING"
                key: "polling"
                readonly property int every: Math.round(Performance.vitalsInterval / 1000)
                whenOn: `The vitals are read every ${every} seconds instead of every ${Math.round(Config.get("vitals.interval", 2000) / 100) / 10}.`
                whenOff: "The vitals are read as often as ever."
            }
        }
    }
}
