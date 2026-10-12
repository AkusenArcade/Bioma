pragma ComponentBehavior: Bound

import QtQuick
import qs.core
import qs.components
import qs.organisms
import qs.services

// What is coming, on the wall.
//
// The calendars the clock cell reads (services/Calendar.qml), from now on:
// the appointment on now or the next one large in a well at the top, then
// the days after it, a line each, as many as the panel holds. Read-only, as
// every organism: nothing here opens an event or adds a calendar — that is
// the clock cell's.
//
// The one thing that moves is the appointment going on: a thread filling as
// it runs, a minute at a time. An appointment is not a machine, so the only
// colour it takes is the primary, and only while it is on.
//
// It is always there. With no calendar it is blank and says where one is
// added; with nothing ahead it says so.
//
// See docs/design/ORGANISMS.md §16.
Item {
    id: root

    property var metrics: Metrics.step("normal")
    property var entry: ({})
    property var organism: null

    readonly property real factor: root.metrics.factor

    readonly property bool present: true
    readonly property bool blank: !Calendar.active

    // What is still to come or still going: anything that has not ended.
    readonly property var ahead: Calendar.events.filter(e => e.end > Calendar.now
                                                         || (e.end === e.start && e.start >= Calendar.now))

    // The well's: a timed appointment on now, or else the first thing to
    // come, so the list under it never goes back in time. Today's all-day
    // events are the day's context, not what comes next — a holiday would
    // otherwise hold the well all day over the meeting at three — and stay
    // in the list under Today.
    readonly property var lead: {
        if (Calendar.ongoing.length > 0)
            return Calendar.ongoing[0];
        return root.ahead.find(e => e.allDay ? e.start >= Calendar.todayEnd : e.start > Calendar.now) ?? null;
    }
    readonly property bool leadOn: root.lead !== null && !root.lead.allDay && root.lead.start <= Calendar.now

    function technical(size, weight) {
        return Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": size,
            "weight": weight === undefined ? Typography.weightSecondary : weight,
            "letterSpacing": Typography.tracking(size, Typography.labelTracking)
        }));
    }

    // Hours as the clock cell was told to give them.
    readonly property bool twentyFourHour: Organisms.cellOption("clock", "format", "24h") === "24h"

    function hhmm(ms) {
        const date = new Date(ms);
        const hours = date.getHours();
        const h = root.twentyFourHour ? String(hours).padStart(2, "0") : String(hours % 12 === 0 ? 12 : hours % 12);
        return `${h}:${String(date.getMinutes()).padStart(2, "0")}`;
    }

    readonly property var weekdayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
                                       "August", "September", "October", "November", "December"]

    function dayName(start) {
        const difference = Math.round((start - Calendar.todayStart) / 86400000);
        if (difference === 0)
            return "Today";
        if (difference === 1)
            return "Tomorrow";
        const date = new Date(start);
        return `${root.weekdayNames[date.getDay()]} ${date.getDate()} ${root.monthNames[date.getMonth()]}`;
    }

    // How far off, in the machine's voice: `IN 25 MIN`, `IN 2 H 10`, or the
    // day when it is not today.
    function until(start) {
        const minutes = Math.max(0, Math.round((start - Calendar.now) / 60000));
        if (start >= Calendar.todayEnd)
            return root.dayName(Calendar.dayStart(start)).toUpperCase();
        if (minutes < 60)
            return `IN ${minutes} MIN`;
        const hours = Math.floor(minutes / 60);
        const rest = minutes % 60;
        return rest > 0 ? `IN ${hours} H ${String(rest).padStart(2, "0")}` : `IN ${hours} H`;
    }

    // `ALL DAY`, or how many days when it is more than one.
    function allDaySpan(event) {
        const days = Math.round((Calendar.dayStart(event.end) - Calendar.dayStart(event.start)) / 86400000);
        return days > 1 ? `${days} DAYS` : "ALL DAY";
    }

    // ---- The well -------------------------------------------------------------------

    Well {
        id: well

        metrics: root.metrics
        inset: 10 * root.factor
        width: parent.width
        height: 118 * root.factor

        // Blank: where a calendar comes from.
        Column {
            visible: root.blank || root.lead === null
            anchors.centerIn: parent
            width: parent.width - 28 * root.factor
            spacing: 4 * root.factor

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.blank ? "No calendar" : "Nothing coming up"
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: Math.round(19 * root.factor)
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.blank ? "Add one from the clock: open it, then + Calendar."
                                 : `Nothing in the next ${Calendar.days} days.`
                color: Theme.textMuted
                font.family: Typography.expressive
                font.pixelSize: Math.round(14 * root.factor)
                font.italic: true
            }
        }

        Item {
            visible: !root.blank && root.lead !== null
            anchors.fill: parent
            anchors.margins: 16 * root.factor

            // NOW, or how far off.
            Text {
                id: leadWhen
                text: root.lead === null ? "" : root.leadOn ? "NOW" : root.until(root.lead.start)
                color: root.leadOn ? Theme.primary : Theme.textMuted
                font: root.technical(Math.round(11 * root.factor))
            }

            Text {
                id: leadTitle
                anchors.top: leadWhen.bottom
                anchors.topMargin: 4 * root.factor
                width: parent.width
                text: root.lead ? root.lead.title : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.text
                font.family: Typography.expressive
                font.pixelSize: Math.round(22 * root.factor)
                font.weight: Font.Bold
            }

            Row {
                anchors.top: leadTitle.bottom
                anchors.topMargin: 4 * root.factor
                width: parent.width
                spacing: 12 * root.factor

                LitText {
                    id: leadTime
                    anchors.verticalCenter: parent.verticalCenter
                    text: !root.lead ? ""
                        : root.lead.allDay ? root.allDaySpan(root.lead)
                        : `${root.hhmm(root.lead.start)} – ${root.hhmm(root.lead.end)}`
                    font: root.technical(Math.round(17 * root.factor), Typography.weightValue)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - leadTime.width - parent.spacing
                    text: root.lead ? (root.lead.location.split("\n")[0] || root.lead.calendar) : ""
                    elide: Text.ElideRight
                    color: Theme.textFaint
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(14 * root.factor)
                }
            }

            // While it is on, how much of it has gone: the one movement here,
            // a minute at a time.
            Item {
                visible: root.leadOn
                anchors.bottom: parent.bottom
                width: parent.width
                height: 3 * root.factor

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(Theme.line, 0.6)
                }

                Rectangle {
                    width: root.lead && root.leadOn
                           ? parent.width * Math.min(1, (Calendar.now - root.lead.start)
                                                        / Math.max(60000, root.lead.end - root.lead.start))
                           : 0
                    height: parent.height
                    radius: height / 2
                    color: Theme.primary
                }
            }
        }
    }

    // ---- The days after it --------------------------------------------------------------

    readonly property real dayHeight: 26 * root.factor
    readonly property real rowHeight: 28 * root.factor
    readonly property real listTop: well.height + 14 * root.factor

    // Day headings and rows, cut where the panel ends: a whole row or none,
    // and never a day with no row under it.
    readonly property var lines: {
        if (root.blank)
            return [];
        const room = root.height - root.listTop;
        const out = [];
        let used = 0;
        let day = -1;
        for (const event of root.ahead) {
            if (root.lead && event.uid === root.lead.uid && event.start === root.lead.start)
                continue;
            const start = Math.max(Calendar.dayStart(event.start), Calendar.todayStart);
            const heading = start !== day;
            const needed = root.rowHeight + (heading ? root.dayHeight : 0);
            if (used + needed > room)
                break;
            if (heading) {
                out.push({ "kind": "day", "start": start });
                day = start;
            }
            out.push({ "kind": "event", "event": event });
            used += needed;
        }
        return out;
    }

    Column {
        y: root.listTop
        width: parent.width

        Repeater {
            model: root.lines

            delegate: Item {
                id: line

                required property var modelData

                readonly property bool isDay: line.modelData.kind === "day"
                readonly property var event: line.isDay ? null : line.modelData.event

                width: parent.width
                height: line.isDay ? root.dayHeight : root.rowHeight

                Text {
                    visible: line.isDay
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4 * root.factor
                    text: line.isDay ? root.dayName(line.modelData.start) : ""
                    color: Theme.textMuted
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(13 * root.factor)
                    font.weight: Font.Bold
                }

                Text {
                    id: when
                    visible: !line.isDay
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76 * root.factor
                    text: !line.event ? ""
                        : line.event.allDay ? "ALL DAY"
                        : line.event.start < Calendar.todayStart ? "…"
                        : root.hhmm(line.event.start)
                    color: line.event && !line.event.allDay && line.event.start <= Calendar.now
                           ? Theme.primary : Theme.textMuted
                    font: root.technical(Math.round((line.event && line.event.allDay ? 11 : 13) * root.factor))
                }

                Text {
                    visible: !line.isDay
                    anchors.left: when.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: line.event ? line.event.title : ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: Math.round(15 * root.factor)
                }
            }
        }
    }
}
