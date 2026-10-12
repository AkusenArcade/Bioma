pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// What is on the calendar.
//
// Two kinds of source, both added from the clock cell.
//
// - **The calendars of an account in GNOME Online Accounts.** GOA holds the
//   sign-in — Google's OAuth, or the password of a WebDAV or Nextcloud
//   account (mailbox.org, Posteo, Fastmail) — and its calendars are found
//   over CalDAV (`discover`), each switched on with a touch. Nothing secret
//   is kept by Bioma. Moving off Google is another account in Online
//   Accounts, not new code (Akusen's choice, 2026-10-12).
// - **An iCalendar address**, pasted (`add`), for what has no account: it is
//   read once to make sure it is a calendar and to learn the name it gives
//   itself, and kept in the keyring, because a secret address is a password.
//
// The configuration keeps only what to call them:
//
//   "calendar": {
//       "sources": [{ "goa": "account_…", "href": "https://…/events/", "name": "Family" },
//                   { "id": "…", "name": "Personal" }],
//       "days": 62,
//       "minutes": 15
//   }
//
// A source written by hand may carry its `url` instead of an `id`; so does
// one added on a machine with no keyring.
//
// The reading is done by `scripts/calendar`: unfolding, time zones and
// recurrences are dateutil's work, and QML has no time zones at all. It runs
// at start, every `minutes`, at midnight and when the sources change, through
// the proxy when one is on. A feed that cannot be reached is replaced by its
// last copy, and named in `problems`.
//
// It runs whenever a source is set, not only while something is on screen:
// what shows the next appointment has to know there is one before it can
// appear.
Singleton {
    id: root

    // ---- Where ------------------------------------------------------------------------

    readonly property var sources: (Config.get("calendar.sources", []) || [])
        .filter(source => source && (typeof source.id === "string" && source.id.length > 0
                                     || typeof source.url === "string" && source.url.trim().length > 0
                                     || typeof source.goa === "string" && typeof source.href === "string"))
    readonly property bool active: root.sources.length > 0

    // How far ahead, from today. Two months by default: the clock's month and
    // the next one, which is where its arrows go first.
    readonly property int days: Math.max(1, Config.get("calendar.days", 62))
    readonly property int every: Math.max(1, Config.get("calendar.minutes", 15)) * 60 * 1000

    // And how far back: to the Monday the clock's month starts its grid on,
    // so the days of this month already gone still show what they held.
    readonly property int back: {
        const today = new Date(root.todayStart);
        const first = new Date(today.getFullYear(), today.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;
        return today.getDate() - 1 + lead;
    }

    // [{ "index", "calendar", "message" }]: a source that could not be read,
    // by its place in `sources`. Its last copy is used when there is one.
    property var problems: []
    readonly property string problem: root.problems.map(p => p.message).join(" ")

    function troubleOf(index) {
        const found = root.problems.find(p => p.index === index);
        return found ? found.message : "";
    }

    // ---- What -------------------------------------------------------------------------

    // [{ "uid", "calendar", "title", "location", "start", "end", "allDay" }],
    // in milliseconds, `end` exclusive, sorted by start: everything that
    // overlaps the window, including what began before it and is still on.
    property var events: []

    // When the events were last read, in milliseconds; 0 before the first time.
    property double readAt: 0

    // The minute the answers below are judged by. Aligned to the minute, so an
    // appointment at ten is "now" at ten, not up to a minute later.
    property double now: Date.now()

    SystemClock {
        id: clock
        enabled: root.active
        precision: SystemClock.Minutes
        onDateChanged: root.now = clock.date.getTime()
    }

    readonly property double todayStart: root.dayStart(root.now)
    readonly property double todayEnd: root.dayStart(root.todayStart, 1)

    // Midnight of the day `ms` falls in, moved by `offset` days. Days, not
    // 24-hour steps: a day with a change of summer time is 23 or 25 hours.
    function dayStart(ms, offset) {
        const date = new Date(ms);
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() + (offset || 0)).getTime();
    }

    // Timed events going on right now. All-day ones are a day's context, not
    // something happening at this minute.
    readonly property var ongoing: root.events.filter(e => !e.allDay && e.start <= root.now && root.now < e.end)

    // The next timed event to begin, or null.
    readonly property var next: root.events.find(e => !e.allDay && e.start > root.now) ?? null

    // Today, all-day first, as the events are sorted.
    readonly property var today: root.between(root.todayStart, root.todayEnd)

    // Events that overlap [from, to).
    function between(from, to) {
        return root.events.filter(e => e.start < to && (e.end > from || (e.end === e.start && e.start >= from)));
    }

    // The timed events that begin within the next `minutes`.
    function startingWithin(minutes) {
        const limit = root.now + minutes * 60000;
        return root.events.filter(e => !e.allDay && e.start > root.now && e.start <= limit);
    }

    // ---- Reading ----------------------------------------------------------------------

    Timer {
        interval: root.every
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // The window moves with the day: past midnight one more day is read.
    onTodayStartChanged: if (root.readAt > 0) root.refresh()

    // By value: the list is rebuilt whenever the configuration is, and an
    // unrelated setting is no reason to read the calendars again. The first
    // reading is the timer's.
    readonly property string signature: JSON.stringify(root.sources)

    onSignatureChanged: {
        if (!root.active) {
            root.events = [];
            root.readAt = 0;
            root.problems = [];
        } else if (reader.running || root.readAt > 0) {
            root.refresh();
        }
    }

    // Asked again while a reading is running, it reads once more when that one
    // ends, so the last change of sources is never lost to a busy reader.
    property bool again: false

    function refresh() {
        if (!root.active)
            return;
        if (reader.running) {
            root.again = true;
            return;
        }
        // The sources travel in the environment, not on the command line,
        // which every user can read (`ps`).
        reader.environment = Object.assign({}, Proxy.environment, {
            "BIOMA_CALENDAR_SOURCES": JSON.stringify(root.sources)
        });
        reader.command = [Quickshell.shellPath("scripts/calendar"), "read", String(root.days), String(root.back)];
        reader.running = true;
    }

    Process {
        id: reader

        stdout: StdioCollector {
            onStreamFinished: root.read(text)
        }

        stderr: StdioCollector {
            id: readerErrors
        }

        onExited: code => {
            if (code !== 0)
                root.problems = [{ "index": -1, "calendar": "", "message": root.failure(readerErrors.text) }];
            if (root.again) {
                root.again = false;
                root.refresh();
            }
        }
    }

    function failure(errors) {
        return errors.indexOf("No module named 'dateutil'") >= 0
            ? "The calendar needs python-dateutil."
            : "The calendar could not be read.";
    }

    function read(text) {
        if (text.length === 0)
            return;
        let answer = null;
        try {
            answer = JSON.parse(text);
        } catch (e) {
            root.problems = [{ "index": -1, "calendar": "", "message": "The calendar could not be read." }];
            return;
        }
        root.events = answer.events || [];
        root.problems = answer.problems || [];
        root.readAt = Date.now();
        root.now = Date.now();
    }

    // ---- Adding and forgetting ----------------------------------------------------------

    // While a pasted address is being read.
    readonly property bool checking: adder.running

    // Why the last address pasted was not taken, in a sentence. Empty while
    // all is well, and again as soon as another is tried.
    property string addProblem: ""

    // A calendar was taken, under the name it gave itself.
    signal added(string name)

    property string pendingAddress: ""

    function add(address) {
        const wanted = (address || "").trim();
        if (wanted.length === 0 || adder.running)
            return;
        root.addProblem = "";
        root.pendingAddress = wanted;
        adder.environment = Proxy.environment;
        adder.running = true;
    }

    Process {
        id: adder

        command: [Quickshell.shellPath("scripts/calendar"), "add"]
        stdinEnabled: true

        // The address goes in on stdin and is not held here afterwards.
        onStarted: {
            adder.write(root.pendingAddress);
            adder.stdinEnabled = false;
            root.pendingAddress = "";
        }

        stdout: StdioCollector {
            onStreamFinished: root.taken(text)
        }

        stderr: StdioCollector {
            id: adderErrors
        }

        onExited: code => {
            if (code !== 0)
                root.addProblem = root.failure(adderErrors.text);
            adder.stdinEnabled = true;
        }
    }

    function taken(text) {
        if (text.length === 0)
            return;
        let answer = null;
        try {
            answer = JSON.parse(text);
        } catch (e) {
            root.addProblem = "The calendar could not be read.";
            return;
        }
        if (answer.error) {
            root.addProblem = answer.error;
            return;
        }
        Config.set("calendar.sources", root.sources.concat([answer.source]));
        root.added(answer.source.name);
    }

    // ---- The accounts in GNOME Online Accounts ---------------------------------------

    // [{ "goa", "identity", "provider", "calendars": [{ "href", "name" }],
    //    "problem"? }]: every account with its calendar on, as last looked at.
    property var accounts: []

    // Whether GOA answered at all; without it only addresses can be added.
    property bool accountsPresent: false

    readonly property bool discovering: discoverer.running

    // Looks again at the accounts and their calendars: asked whenever the
    // way to a new calendar opens, so an account added a moment ago is there.
    function discover() {
        if (discoverer.running)
            return;
        discoverer.environment = Proxy.environment;
        discoverer.running = true;
    }

    Process {
        id: discoverer

        command: [Quickshell.shellPath("scripts/calendar"), "accounts"]

        stdout: StdioCollector {
            onStreamFinished: {
                let answer = null;
                try {
                    answer = JSON.parse(text);
                } catch (e) {
                    return;
                }
                root.accounts = answer.accounts || [];
                root.accountsPresent = answer.present === true;
            }
        }
    }

    function holds(goa, href) {
        return root.sources.some(source => source.goa === goa && source.href === href);
    }

    // Switches on one calendar of an account.
    function addFromAccount(goa, calendar) {
        if (root.holds(goa, calendar.href))
            return;
        Config.set("calendar.sources", root.sources.concat([{
            "goa": goa, "href": calendar.href, "name": calendar.name
        }]));
    }

    // Takes a source out of the configuration, and its address out of the
    // keyring if it had one there.
    function forget(index) {
        const source = root.sources[index];
        if (!source)
            return;
        Config.set("calendar.sources", root.sources.filter((_, i) => i !== index));
        if (source.id)
            Quickshell.execDetached([Quickshell.shellPath("scripts/calendar"), "forget", source.id]);
    }
}
