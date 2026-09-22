import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.structure
import qs.services

// The applications: the ones kept, and the ones running.
//
// **One cell, not a tissue.** The row of icons is its content the way digits
// are the clock's content — if every application were a cell, the membrane
// would be ten glowing outlines in a row and would stop being a membrane.
//
// It does not open. Everything it has to say it already says: which
// applications are there, and which of them are running. The ring says
// running, and it says it once however many windows there are — a number of
// windows is not what anybody reads a dock for.
//
// See docs/design/CELLS.md §09, PRD §9.9.
Cell {
    id: root

    domain: "dock"

    readonly property real iconSize: 28 * metrics.factor
    readonly property real pitch: 10 * metrics.factor
    readonly property real dividerWidth: Metrics.crisp(1, Screen.devicePixelRatio)
    readonly property real dividerRoom: dividerWidth + 12 * metrics.factor

    paddingLeading: 12 * metrics.factor
    paddingTrailing: 12 * metrics.factor

    // ---- What it holds -------------------------------------------------------

    // Kept by hand, in the configuration, and written back when they are
    // reordered. A dock with nothing pinned is a window list, which is a
    // legitimate way to use it.
    readonly property var pinned: Config.get("dock.pinned", [])

    // One entry per application, not per window. Two windows of the same
    // application are one icon, and the click cycles through them.
    readonly property var running: {
        const seen = ({});
        const out = [];
        for (const id in Niri.windows) {
            const window = Niri.windows[id];
            const appId = window.appId;
            if (!appId || appId.length === 0)
                continue;
            if (seen[appId] === undefined) {
                seen[appId] = out.length;
                out.push({ "appId": appId, "windows": [window] });
            } else {
                out[seen[appId]].windows.push(window);
            }
        }
        return out;
    }

    function isPinned(appId) {
        for (const id of root.pinned)
            if (root.sameApp(id, appId))
                return true;
        return false;
    }

    // A pinned entry is a desktop file id and a window reports an `app_id`,
    // and the two agree more often than not — but not always, and not on
    // case. Both go through the same resolution the icons go through, so a
    // pinned Firefox and a running `firefox` are one application.
    function sameApp(a, b) {
        if (!a || !b)
            return false;
        if (a.toLowerCase() === b.toLowerCase())
            return true;
        const left = Apps.entryFor(a);
        const right = Apps.entryFor(b);
        return left !== null && right !== null && left === right;
    }

    function windowsOf(appId) {
        for (const group of root.running)
            if (root.sameApp(group.appId, appId))
                return group.windows;
        return [];
    }

    // The right-hand group: what is running and is not kept. A pinned
    // application that is running says so on its own icon rather than
    // appearing twice.
    readonly property var loose: root.running.filter(group => !root.isPinned(group.appId))

    readonly property bool divided: root.pinned.length > 0 && root.loose.length > 0
    readonly property int count: root.pinned.length + root.loose.length

    // A cell exists when it has something to say: with nothing kept and
    // nothing running there is no dock, and the tissue closes over it.
    condition: root.count

    contentWidth: root.count > 0
        ? root.count * iconSize + (root.count - 1) * pitch + (root.divided ? dividerRoom : 0)
        : iconSize

    // ---- Doing things --------------------------------------------------------

    // Which window of an application the next press goes to. A dock that
    // always raised the first window would make the second one unreachable.
    property var rounds: ({})

    function activate(appId) {
        const windows = root.windowsOf(appId);
        if (windows.length === 0) {
            root.launch(appId);
            return;
        }

        const next = ((root.rounds[appId] ?? -1) + 1) % windows.length;
        const rounds = Object.assign({}, root.rounds);
        rounds[appId] = next;
        root.rounds = rounds;

        Niri.focusWindow(windows[next].id);
    }

    // Keeping one, and letting one go. The design gives the dock no gesture
    // for this and the settings cell is phases away, so it lives on the
    // right button: one press, one effect, and the sign that it worked is the
    // icon moving to the other side of the divider.
    //
    // What is written is the desktop entry's own id where one resolves, so the
    // list stays in the vocabulary the configuration is read in rather than in
    // whatever a compositor happened to call the window.
    function keep(appId) {
        const entry = Apps.entryFor(appId);
        const id = entry && entry.id ? entry.id : appId;
        if (root.isPinned(id))
            return;
        Config.set("dock.pinned", root.pinned.concat([id]));
    }

    function unkeep(appId) {
        Config.set("dock.pinned", root.pinned.filter(id => !root.sameApp(id, appId)));
    }

    function launch(appId) {
        const entry = Apps.entryFor(appId);
        if (!entry) {
            console.info(`Bioma: the dock has no desktop entry for "${appId}"`);
            return;
        }
        entry.execute();
    }

    // ---- The row -------------------------------------------------------------

    // What the pointer is on, and what it is called. The name arrives above
    // the icon rather than inside the row: a row that grew to hold a name
    // would move every icon in it, and the one being pointed at would move out
    // from under the pointer.
    property string named: ""
    property real namedCentre: 0

    function name(label, item, centre) {
        root.named = label;
        root.namedCentre = item.mapToItem(root, centre, 0).x;
    }

    function unname(label) {
        if (root.named === label)
            root.named = "";
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pitch

        Repeater {
            model: root.pinned

            delegate: DockIcon {
                id: kept

                required property string modelData

                size: root.iconSize
                factor: root.metrics.factor
                appId: kept.modelData
                running: root.windowsOf(kept.modelData).length > 0

                onEntered: (label, centre) => root.name(label, kept, centre)
                onExited: label => root.unname(label)
                onActivated: root.activate(kept.modelData)
                onLaunched: root.launch(kept.modelData)
                onToggled: root.unkeep(kept.modelData)
            }
        }

        // A line that does not separate two groups is decoration.
        Item {
            width: root.dividerRoom - root.pitch
            height: root.iconSize
            visible: root.divided

            Rectangle {
                anchors.centerIn: parent
                width: root.dividerWidth
                height: 22 * root.metrics.factor
                color: Theme.line
                antialiasing: true
            }
        }

        Repeater {
            model: root.loose

            delegate: DockIcon {
                id: live

                required property var modelData

                size: root.iconSize
                factor: root.metrics.factor
                appId: live.modelData.appId
                running: true

                onEntered: (label, centre) => root.name(label, live, centre)
                onExited: label => root.unname(label)
                onActivated: root.activate(live.modelData.appId)
                onLaunched: root.launch(live.modelData.appId)
                onToggled: root.keep(live.modelData.appId)
            }
        }
    }

    // One icon: the application's own picture in the shell's own well, and the
    // ring that says it is running.
    component DockIcon: Item {
        id: icon

        property string appId: ""
        property bool running: false
        property real size: 28
        property real factor: 1

        readonly property string source: Apps.iconFor(icon.appId)
        readonly property string label: {
            const entry = Apps.entryFor(icon.appId);
            return entry && entry.name ? entry.name : icon.appId;
        }

        width: icon.size
        height: icon.size

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.lift(Theme.background, -0.015)
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
            border.color: Qt.alpha(Theme.text, 0.35)
            antialiasing: true
        }

        // Flat primary, never the gradient: it is a thin state line and not a
        // surface, and keeping the two apart is what stops a running icon from
        // looking like a cell inside a cell. It sits inside the footprint, so
        // nothing moves when it appears.
        Rectangle {
            anchors.fill: parent
            visible: icon.running
            radius: width / 2
            color: "transparent"
            border.width: Metrics.crisp(1.5 * icon.factor, Screen.devicePixelRatio)
            border.color: Theme.primary
            antialiasing: true
        }

        // The application's picture belongs to the application: never tinted,
        // and never replaced by another application's logo when it does not
        // resolve.
        Image {
            anchors.centerIn: parent
            visible: icon.source !== ""
            width: parent.width * 0.62
            height: width
            source: icon.source
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Icon {
            anchors.centerIn: parent
            visible: icon.source === ""
            width: parent.width * 0.58
            height: width
            name: "app-fallback"
            colour: Theme.textMuted
        }

        // Not `left`: an Item declares that final — it is one of its own
        // anchor lines — and a signal of that name does not compile. The same
        // trap `components/Band.qml` hit with `left` and `right`.
        signal entered(string label, real centre)
        signal exited(string label)
        signal activated
        signal launched
        signal toggled

        HoverHandler {
            onHoveredChanged: {
                if (hovered)
                    icon.entered(icon.label, icon.width / 2);
                else
                    icon.exited(icon.label);
            }
        }

        // A press raises the application, or starts it. The middle button
        // starts another one whatever is already running — the one way to ask
        // for a second window of something that would otherwise just raise the
        // first.
        TapHandler {
            onTapped: icon.activated()
        }

        TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: icon.launched()
        }

        // The right button keeps it, or lets it go.
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: icon.toggled()
        }
    }

    // The name of what the pointer is on, above the icon and outside the row.
    // One at a time, because the pointer is one.
    Item {
        id: nameplate

        readonly property real pad: 10 * root.metrics.factor

        visible: opacity > 0
        opacity: root.named.length > 0 ? 1 : 0
        scale: root.named.length > 0 ? 1 : 0.94
        transformOrigin: root.opensDown ? Item.Top : Item.Bottom

        width: nameText.implicitWidth + nameplate.pad * 2
        height: 26 * root.metrics.factor
        x: Math.max(0, Math.min(root.width - width, root.namedCentre - width / 2))
        y: root.opensDown ? root.height + root.gap : -root.gap - height

        Behavior on opacity { NumberAnimation { duration: Timing.contentFade } }
        Behavior on scale {
            NumberAnimation { duration: Timing.contentFade; easing.type: Easing.OutQuad }
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.alpha(Theme.lift(Theme.background, -0.01), 0.92)
            antialiasing: true
        }

        // An application's name is what a person called it.
        Text {
            id: nameText
            anchors.centerIn: parent
            text: root.named
            color: Theme.text
            font.family: Typography.expressive
            font.pixelSize: root.metrics.fontSecondary
        }
    }
}
