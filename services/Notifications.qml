pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.core

// What the machine has to say on someone else's behalf.
//
// The server is Prisma's — twenty lines of it — and everything above it is new:
// urgency, a dwell that obeys it, a queue with a cap, a hover that stops the
// clock, and a history that outlives the popup. Prisma dismissed every
// notification after four seconds, critical ones included, which is precisely
// the freedesktop convention Bioma commits to keeping.
//
// One owner per session. While another shell holds
// `org.freedesktop.Notifications` this server acquires nothing and the cell
// stays empty — that is not a failure state to draw, it is the shell not being
// the shell yet.
//
// See docs/design/CELLS.md §10, PRD §9.10.
Singleton {
    id: root

    // ── The server ───────────────────────────────────────────────────────

    NotificationServer {
        id: server

        // A reload must not lose what is on screen: the shell restarts far
        // more often than a notification lives.
        keepOnReload: true

        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        inlineReplySupported: false

        onNotification: notification => root.receive(notification)
    }

    readonly property var tracked: server.trackedNotifications?.values ?? []

    // ── Do not disturb ───────────────────────────────────────────────────
    //
    // It lives with the history rather than in settings (CELLS §10, decided
    // against the PRD): people look for it while notifications are bothering
    // them, which is when they are looking at this cell.
    //
    // Quiet is not deaf. Everything still arrives and everything is kept —
    // what stops is the appearing.
    property bool quiet: Config.get("notifications.quiet", false)

    function setQuiet(value) {
        root.quiet = value;
        Config.set("notifications.quiet", value);
    }

    // ── How long one stays ───────────────────────────────────────────────
    //
    // The convention, and the design's own figures: four seconds for low,
    // eight for ordinary, and a critical one does not leave by itself. A
    // sender that asks for a particular time gets it, because it knows
    // something about its own message that the shell does not — except a
    // critical one, where the convention outranks the request.

    readonly property int lowDwell: Config.get("notifications.dwell_low", 4000)
    readonly property int normalDwell: Config.get("notifications.dwell_normal", 8000)

    function dwellFor(notification) {
        if (!notification)
            return root.normalDwell;
        if (notification.urgency === NotificationUrgency.Critical)
            return 0;
        if (notification.expireTimeout > 0)
            return notification.expireTimeout;
        return notification.urgency === NotificationUrgency.Low
            ? root.lowDwell : root.normalDwell;
    }

    function isCritical(notification) {
        return notification?.urgency === NotificationUrgency.Critical;
    }

    // ── The queue ────────────────────────────────────────────────────────
    //
    // Notifications arriving together queue, and past a cap they stop queuing
    // and become a number: twenty in ten seconds is a system update, and
    // without a cap the cell would be occupied for minutes saying things
    // nobody is reading. A critical one never counts towards the cap and is
    // never collapsed into it — it is the one that has to be read.

    readonly property int cap: Config.get("notifications.queue_cap", 20)
    readonly property int burstWindow: Config.get("notifications.burst_window", 10000)

    property var arrivals: []
    property int collapsed: 0

    readonly property bool flooding: root.collapsed > 0

    function crowding() {
        const now = Date.now();
        const recent = root.arrivals.filter(at => now - at < root.burstWindow);
        recent.push(now);
        root.arrivals = recent;
        return recent.length > root.cap;
    }

    // ── What is on screen ────────────────────────────────────────────────

    // Two queues, because one of them has no clock.
    //
    // A critical notification does not leave by itself, and one cell can show
    // one thing — so held on the head of the ordinary queue it would stop
    // every other notification for as long as it went unanswered, which is
    // the one thing CELLS §10 says must not happen: the others keep going
    // past it. They cannot go past it *visibly* until this cell can be a
    // column of cells, which is the vertical tissue's next job; until then
    // they go to the history rather than into a queue that is not moving.
    //
    // Urgency wins the cell: what is critical is what is on screen.
    property var queue: []
    property var urgent: []

    readonly property var current: root.urgent.length > 0 ? root.urgent[0]
                                 : (root.queue.length > 0 ? root.queue[0] : null)
    readonly property int waiting: Math.max(0, root.queue.length - 1) + root.urgent.length

    readonly property bool held: root.urgent.length > 0

    readonly property bool present: root.current !== null || root.flooding

    // Set by the cell while the pointer is on it. Time does not run while
    // somebody is reading, and on exit it resumes where it stopped — never
    // from the start, or a distracted hover would keep a notification alive
    // for ever (PRD §5.2, mandatory here).
    property bool holding: false

    property real remaining: 0
    property real startedAt: 0

    function receive(notification) {
        notification.tracked = true;

        root.remember(notification);

        if (root.isCritical(notification)) {
            root.urgent = root.urgent.concat([notification]);
            life.stop();
            return;
        }

        if (root.quiet)
            return;

        if (root.crowding()) {
            root.collapsed = root.collapsed + 1;
            return;
        }

        // While something urgent is on the cell the ordinary ones do not
        // queue behind it: they are kept and they are in the history, and
        // what is in front of somebody is the thing that matters.
        if (root.held)
            return;

        root.queue = root.queue.concat([notification]);
        if (root.queue.length === 1)
            root.begin();
    }

    // The head of the queue starts its own clock. A critical one has none.
    function begin() {
        life.stop();
        root.remaining = root.dwellFor(root.current);
        if (root.remaining <= 0)
            return;
        root.startedAt = Date.now();
        life.interval = root.remaining;
        life.start();
    }

    function advance() {
        life.stop();
        if (root.urgent.length > 0)
            root.urgent = root.urgent.slice(1);
        else
            root.queue = root.queue.slice(1);

        if (root.current !== null)
            root.begin();
        else
            root.collapsed = 0;
    }

    // Leaving by itself is not the same as being dismissed: a notification
    // that expires stays in the history and the sender is told it expired,
    // while one the user closes is closed.
    function expire() {
        const notification = root.current;
        root.advance();
        if (notification)
            notification.expire();
    }

    function dismiss() {
        const notification = root.current;
        root.advance();
        if (notification)
            notification.dismiss();
    }

    function invoke(action) {
        action?.invoke();
        root.dismiss();
    }

    Timer {
        id: life
        onTriggered: root.expire()
    }

    onHoldingChanged: {
        if (!root.current)
            return;
        if (root.holding) {
            if (life.running) {
                root.remaining = Math.max(0, life.interval - (Date.now() - root.startedAt));
                life.stop();
            }
            return;
        }
        if (root.remaining > 0) {
            root.startedAt = Date.now();
            life.interval = root.remaining;
            life.start();
        }
    }

    // ── The history ──────────────────────────────────────────────────────
    //
    // What the cell shows when it opens, grouped by application, most recent
    // first — people come back looking for "that browser thing", not "that
    // 14:32 thing". It is in memory: the freedesktop server owns no store, and
    // a shell that wrote every notification to disk would be keeping a diary
    // nobody asked it to keep.

    readonly property int keep: Config.get("notifications.history", 100)

    property var history: []

    function remember(notification) {
        const entry = {
            "id": notification.id,
            "appName": notification.appName,
            "summary": notification.summary,
            "body": notification.body,
            "image": notification.image,
            "appIcon": notification.appIcon,
            "desktopEntry": notification.desktopEntry,
            "urgency": notification.urgency,
            "at": Date.now()
        };
        root.history = [entry].concat(root.history).slice(0, root.keep);
    }

    function forget() {
        root.history = [];
    }

    // Grouped for the history panel: one block per application, each in the
    // order the notifications arrived in.
    readonly property var grouped: {
        const order = [];
        const byApp = ({});
        for (const entry of root.history) {
            const name = entry.appName || "";
            if (byApp[name] === undefined) {
                byApp[name] = { "appName": name, "entries": [] };
                order.push(byApp[name]);
            }
            byApp[name].entries.push(entry);
        }
        return order;
    }

    // "two minutes ago" is a measurement, and the cell writes it in the
    // technical voice — so it is given as a short string rather than a date.
    function since(at) {
        const seconds = Math.max(0, Math.round((Date.now() - at) / 1000));
        if (seconds < 60)
            return "now";
        const minutes = Math.round(seconds / 60);
        if (minutes < 60)
            return `${minutes}m`;
        const hours = Math.round(minutes / 60);
        if (hours < 24)
            return `${hours}h`;
        return `${Math.round(hours / 24)}d`;
    }

    // ── Where it is drawn ────────────────────────────────────────────────

    // In the order the sender gave them, and **never a guess**. A notification
    // carries a free-form application name, and resolving that name the way
    // the window title resolves a window's would put somebody else's logo on
    // somebody else's message — `systemd` matched something with a broken
    // icon, and what was drawn was a missing-texture chequerboard. Where
    // nothing resolves, the cell draws its own glyph, which is honest.
    function iconFor(entry) {
        if (!entry)
            return "";

        const image = entry.image ?? "";

        // Quickshell hands the sender's icon over as `image://icon/<name>`,
        // and its provider answers a name it cannot find with a chequerboard
        // rather than with nothing — which is how `dialog-warning`, a name
        // this icon theme does not carry, ended up drawn as a missing
        // texture on the membrane. So a named icon is checked before it is
        // believed, and the cell's own glyph takes over when it is not there.
        if (image.startsWith("image://icon/")) {
            const named = Quickshell.iconPath(image.slice("image://icon/".length), true);
            if (named.length > 0)
                return named;
        } else if (image.length > 0) {
            return image;
        }

        if (entry.appIcon && entry.appIcon.length > 0) {
            const named = Quickshell.iconPath(entry.appIcon, true);
            if (named.length > 0)
                return named;
        }
        // A desktop entry is an identifier and not a name, so this one is a
        // lookup rather than a search.
        const declared = entry.desktopEntry ? DesktopEntries.byId(entry.desktopEntry) : null;
        return declared && declared.icon ? Quickshell.iconPath(declared.icon, true) : "";
    }
}
