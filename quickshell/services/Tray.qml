pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray as Sni

// The tray: what other programs put on the shell.
//
// It is the one domain where the content is **not ours**. An application
// registers a StatusNotifierItem over D-Bus and hands over an icon drawn in its
// own style, a title, a status, and usually a menu — and the shell's job is to
// carry them without pretending they belong to it. PRD §6.4 says as much about
// the icons: they stay in third-party styles whatever we do.
//
// The protocol allows several hosts on one watcher, so this coexists with
// another shell's tray — unlike notifications, where the bus has one owner.
// That is what makes it safe to build while Noctalia can still be started.
//
// `SystemTray.items` is an `ObjectModel`: read `.values`, and bind it before
// reading it or it answers empty (§9.4).
Singleton {
    id: root

    readonly property var model: Sni.SystemTray.items
    readonly property var live: root.model ? root.model.values : []

    // Sorted, and by something that does not move: the order items register in
    // is the order the applications happened to start, and a row that reorders
    // itself when something restarts is a row nobody can aim at. Category
    // first — hardware, then communications, then the rest — then the id.
    readonly property var items: {
        const out = [];
        for (const item of root.live)
            if (item)
                out.push(item);

        out.sort((a, b) => (root.rank(a) - root.rank(b))
                        || String(a.id).localeCompare(String(b.id)));
        return out;
    }

    readonly property int count: root.items.length
    readonly property bool populated: root.count > 0

    function rank(item) {
        switch (item.category) {
        case Sni.Category.Hardware: return 0;
        case Sni.Category.Communications: return 1;
        case Sni.Category.SystemServices: return 2;
        default: return 3;
        }
    }

    // ── What each one is saying ──────────────────────────────────────────
    //
    // Three states in the protocol, and only one of them is an event: an item
    // that needs attention is the only thing here the shell may say out loud.
    // `Passive` is the protocol's way of saying "I am here but idle" — it does
    // **not** mean hidden, and hiding it is a policy the person did not ask
    // for, so it is carried like any other.

    function attending(item) {
        return item && item.status === Sni.Status.NeedsAttention;
    }

    readonly property bool attention: {
        for (const item of root.items)
            if (root.attending(item))
                return true;
        return false;
    }

    // The name under the icon, for the places that name things. The title is
    // the application's own word for itself; the id is what it registered as,
    // and is all there is when the title is empty.
    function nameOf(item) {
        if (!item)
            return "";
        const title = item.title || "";
        return title.length > 0 ? title : String(item.id || "");
    }

    // The tooltip, as one string. Two fields in the protocol and they are
    // usually a heading and a line under it.
    function tooltipOf(item) {
        if (!item)
            return "";
        const head = item.tooltipTitle || "";
        const body = item.tooltipDescription || "";
        if (head.length > 0 && body.length > 0)
            return `${head} — ${body}`;
        return head.length > 0 ? head : body;
    }

    // ── The icon, which is theirs ────────────────────────────────────────
    //
    // Quickshell hands over a ready URL — `image://icon/<name>`, sometimes
    // with a `?path=` for an application that ships its own directory. The
    // provider paints a **chequerboard** for a name it cannot find rather than
    // failing, which is the trap the notification cell already fell into: a
    // name that resolves to nothing has to be caught before it is drawn, not
    // after. A URL carrying its own path is trusted as it stands; a bare name
    // is asked for by `Quickshell.iconPath`, which answers empty when the
    // theme has nothing.
    function iconFor(item) {
        if (!item || !item.icon)
            return "";

        const url = String(item.icon);
        if (url.indexOf("image://icon/") !== 0)
            return url;

        const rest = url.slice("image://icon/".length);
        if (rest.indexOf("?") >= 0)
            return url;

        return Quickshell.iconPath(rest, true).length > 0 ? url : "";
    }

    // ── Doing what they offer ────────────────────────────────────────────
    //
    // An item declares what it answers to. `onlyMenu` means the primary
    // gesture is not an activation at all — pressing it is asking for the
    // menu — and a shell that called `activate` anyway would be pressing a
    // button the application says it does not have.

    function opens(item) {
        return item && item.hasMenu && (item.onlyMenu || !root.acts(item));
    }

    function acts(item) {
        return item && !item.onlyMenu;
    }

    function activate(item) {
        if (root.acts(item))
            item.activate();
    }

    function secondary(item) {
        if (item && !item.onlyMenu)
            item.secondaryActivate();
    }

    // The protocol's scroll carries a delta and an axis. The shell's wheel
    // gesture is steps, so one step is one notch of the usual fifteen degrees.
    function scroll(item, steps) {
        if (item)
            item.scroll(steps * 120, false);
    }
}
