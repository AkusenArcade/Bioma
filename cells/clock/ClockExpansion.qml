pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The clock, opened: the month in the middle, hung from the time it belongs
// to; other places on one side and a timer and an alarm on the other, each on
// its own thread from the month. Once there is a calendar, the day's
// appointments hang from the month on the side away from the cell — the day
// chosen in the month, today until another is.
//
// Human language where it is language — the month's name, a city's name over
// its time, both in Spectral — and the machine's voice where it is counting:
// the days of the month, the offsets, the timer's figure, in Orbitron with
// tabular figures so nothing dances as it changes.
Item {
    id: root

    property Item cell: null
    property var metrics: Metrics.step("normal")

    readonly property real factor: metrics.factor

    readonly property real calendarWidth: 300 * factor
    readonly property real sideWidth: 250 * factor
    readonly property real panelHeight: 320 * factor
    readonly property real gap: metrics.gap
    readonly property real padding: 14 * factor

    readonly property bool upward: root.cell ? !root.cell.opensDown : false

    implicitWidth: sideWidth * 2 + calendarWidth + gap * 2
    implicitHeight: panelHeight + (agendaPlaced ? gap + agendaHeight : 0)
    width: implicitWidth
    height: implicitHeight

    readonly property bool twentyFourHour: root.cell ? root.cell.twentyFourHour : true

    SystemClock {
        id: now
        precision: SystemClock.Minutes
    }

    function hhmm(hours, minutes) {
        const h = root.twentyFourHour ? String(hours).padStart(2, "0")
                                      : String(hours % 12 === 0 ? 12 : hours % 12);
        return `${h}:${String(minutes).padStart(2, "0")}`;
    }

    function technical(size, weight) {
        return Typography.tabular(Qt.font({
            "family": Typography.technical,
            "pixelSize": size,
            "weight": weight === undefined ? Typography.weightLabel : weight,
            "letterSpacing": Typography.tracking(size, Typography.labelTracking)
        }));
    }

    // ---- The cascade --------------------------------------------------------
    //
    // The month grows with the cell; then both threads at once; then the two
    // panels at their ends.

    property real cascade: 0

    function stage(index) {
        return Timing.stage(root.cascade, index, 2);
    }

    Connections {
        target: root.cell
        function onOpenChanged() {
            cascade.stop();
            cascade.to = root.cell.open ? 1 : 0;
            cascade.duration = root.cell.open ? Timing.open : Timing.close;
            cascade.easing.bezierCurve = root.cell.open ? Timing.easeOpenFlat : Timing.easeClose;
            cascade.start();
            if (root.cell.open)
                root.today();
        }
    }

    NumberAnimation {
        id: cascade
        target: root
        property: "cascade"
        to: 1
        duration: Timing.open
        easing.type: Easing.Bezier
        easing.bezierCurve: Timing.easeOpenFlat
    }

    onCellChanged: {
        if (root.cell && root.cell.open) {
            cascade.to = 1;
            cascade.restart();
        }
    }

    // ---- The month ------------------------------------------------------------

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()

    function today() {
        const date = new Date();
        root.viewYear = date.getFullYear();
        root.viewMonth = date.getMonth();
        root.chosenDay = Calendar.dayStart(date.getTime());
    }

    function turn(step) {
        let month = root.viewMonth + step;
        let year = root.viewYear;
        while (month < 0) { month += 12; year--; }
        while (month > 11) { month -= 12; year++; }
        root.viewMonth = month;
        root.viewYear = year;
    }

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
                                       "August", "September", "October", "November", "December"]

    // Six weeks from the Monday on or before the first: every month fits, and
    // the grid does not change height from one month to the next.
    readonly property var days: {
        now.date;   // a new day redraws which one is today
        const first = new Date(root.viewYear, root.viewMonth, 1);
        const lead = (first.getDay() + 6) % 7;
        const start = new Date(root.viewYear, root.viewMonth, 1 - lead);
        const today = new Date();
        const out = [];
        for (let i = 0; i < 42; i++) {
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            out.push({
                "day": day.getDate(),
                "start": day.getTime(),
                "inMonth": day.getMonth() === root.viewMonth,
                "today": day.getFullYear() === today.getFullYear() && day.getMonth() === today.getMonth()
                         && day.getDate() === today.getDate(),
                "busy": root.busyDays[day.getTime()] === true
            });
        }
        return out;
    }

    // The days something is on, by their midnight: every day an event
    // touches, so a trip of three days marks all three.
    readonly property var busyDays: {
        const out = {};
        for (const event of Calendar.events) {
            const last = event.end > event.start ? event.end - 1 : event.start;
            let day = Calendar.dayStart(event.start);
            for (let n = 0; day <= last && n < 62; n++) {
                out[day] = true;
                day = Calendar.dayStart(day, 1);
            }
        }
        return out;
    }

    Panel {
        id: calendar

        metrics: root.metrics
        padding: root.padding
        fixedWidth: root.calendarWidth
        fixedHeight: root.panelHeight
        growth: root.cell ? root.cell.panelGrowth : 0
        contentReady: root.cell ? root.cell.panelReady : false

        anchorX: root.sideWidth + root.gap
        anchorY: root.monthTop
        nodeX: root.width / 2
        nodeY: root.upward ? root.monthTop + root.panelHeight : 0

        Column {
            anchors.fill: parent
            spacing: 8 * root.factor

            // The month and the year, with the way to the next and back. The
            // name itself brings the month of today back.
            Item {
                width: parent.width
                height: 30 * root.factor

                // One stop for the keyboard: Left and Right turn the month,
                // as the chevrons do, and Enter brings today back, as the
                // name does.
                readonly property bool navigable: true

                function adjust(direction) {
                    root.turn(direction);
                }

                function activate() {
                    root.today();
                }

                KeyMark {
                    factor: root.factor
                }

                Chevron {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    pointsLeft: true
                    onPressed: root.turn(-1)
                }

                Text {
                    anchors.centerIn: parent
                    text: `${root.monthNames[root.viewMonth]} ${root.viewYear}`
                    color: Theme.text
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontTitle
                    font.weight: Typography.weightTitle

                    TapHandler { onTapped: root.today() }
                }

                Chevron {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onPressed: root.turn(1)
                }
            }

            Grid {
                id: month

                columns: 7
                readonly property real cellWidth: parent.width / 7
                readonly property real cellHeight: 32 * root.factor

                Repeater {
                    model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

                    delegate: Text {
                        required property string modelData
                        width: month.cellWidth
                        height: 22 * root.factor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: Theme.textFaint
                        font: root.technical(root.metrics.fontMeta)
                    }
                }

                Repeater {
                    model: root.days

                    delegate: Item {
                        id: day

                        required property var modelData

                        width: month.cellWidth
                        height: month.cellHeight

                        readonly property bool chosen: root.agendaShown && !root.addingCalendar
                                                       && day.modelData.start === root.chosenDay

                        // Today is lit the way a chosen control is: the disc
                        // with the light gradient, the figure dark on it.
                        Disc {
                            anchors.centerIn: parent
                            visible: day.modelData.today
                            width: 26 * root.factor
                            height: width
                        }

                        // The day whose appointments hang below, when it is
                        // not today: the rim alone, in the primary.
                        Rectangle {
                            anchors.centerIn: parent
                            visible: day.chosen && !day.modelData.today
                            width: 26 * root.factor
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: Metrics.rim(Screen.devicePixelRatio)
                            border.color: Theme.primary
                            antialiasing: true
                        }

                        Text {
                            anchors.centerIn: parent
                            text: day.modelData.day
                            color: day.modelData.today ? Theme.background
                                 : day.modelData.inMonth ? Theme.text : Theme.textFaint
                            font: root.technical(root.metrics.fontSecondary,
                                                 day.modelData.today ? Typography.weightTitle
                                                                     : Typography.weightLabel)
                        }

                        // Something is on: a point under the figure. Form,
                        // not a count — how many is the agenda's to say.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4 * root.factor
                            visible: day.modelData.busy
                            width: 4 * root.factor
                            height: width
                            radius: width / 2
                            color: day.modelData.today ? Theme.background
                                 : day.modelData.inMonth ? Theme.textMuted : Theme.textFaint
                            antialiasing: true
                        }

                        TapHandler {
                            enabled: root.agendaShown && !root.addingCalendar
                            onTapped: root.chosenDay = day.modelData.start
                        }
                    }
                }
            }

            // With no calendar yet, the way to one: it opens the agenda below,
            // asking for an address. Once there is one, this moves there.
            AddChip {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.agendaShown
                label: "+ Calendar"
                onPressed: root.addingCalendar = true
                onKeyed: {
                    if (root.cell)
                        root.cell.typingKeyed = true;
                    root.addingCalendar = true;
                }
            }
        }
    }

    // ---- The threads ------------------------------------------------------------

    Thread {
        vertical: false
        progress: root.stage(0)
        width: root.gap
        height: implicitHeight
        x: root.sideWidth
        y: root.monthTop + root.panelHeight / 2 - height / 2
    }

    Thread {
        vertical: false
        progress: root.stage(0)
        width: root.gap
        height: implicitHeight
        x: root.sideWidth + root.gap + root.calendarWidth
        y: root.monthTop + root.panelHeight / 2 - height / 2
    }

    // ---- Other places -----------------------------------------------------------

    // Whether the city field is open. The cell asks for the keyboard while it
    // is, and only then.
    property bool adding: false
    onAddingChanged: {
        if (root.cell)
            root.cell.typing = root.adding || root.addingCalendar;
        if (root.adding) {
            root.addingCalendar = false;
            Time.askKnown();
            placeField.text = "";
            placeField.forceActiveFocus();
        }
    }
    Component.onDestruction: if (root.cell) root.cell.typing = false

    readonly property var matches: {
        const wanted = placeField.text.trim().toLowerCase().replace(/ /g, "_");
        if (wanted.length < 2)
            return [];
        return Time.known.filter(zone => zone.toLowerCase().includes(wanted)
                                         && Time.zones.indexOf(zone) < 0).slice(0, 6);
    }

    Panel {
        id: places

        metrics: root.metrics
        padding: root.padding
        fixedWidth: root.sideWidth
        fixedHeight: root.panelHeight
        growth: root.stage(1)
        contentReady: root.stage(1) > 0.999

        anchorX: 0
        anchorY: root.monthTop
        nodeX: root.sideWidth
        nodeY: root.monthTop + root.panelHeight / 2

        Item {
            anchors.fill: parent

            // The places, each with its name above its time and where it
            // stands against UTC beside it.
            Column {
                visible: !root.adding
                width: parent.width
                spacing: 4 * root.factor

                Repeater {
                    model: Time.zones

                    delegate: Item {
                        id: place

                        required property string modelData

                        readonly property var here: {
                            now.minutes;
                            return Time.inZone(place.modelData, new Date());
                        }

                        // A day apart says so: the time alone would be read
                        // as today's.
                        readonly property string dayShift: {
                            if (!place.here)
                                return "";
                            const local = new Date();
                            const a = new Date(local.getFullYear(), local.getMonth(), local.getDate());
                            const b = new Date(place.here.getFullYear(), place.here.getMonth(), place.here.getDate());
                            const difference = Math.round((b - a) / 86400000);
                            return difference > 0 ? "TOMORROW" : difference < 0 ? "YESTERDAY" : "";
                        }

                        width: parent.width
                        height: 52 * root.factor

                        // Reached only to be let go of: Delete is the cross
                        // that shows under the pointer.
                        readonly property bool navigable: true

                        function discard() {
                            Time.removeZone(place.modelData);
                        }

                        KeyMark {
                            factor: root.factor
                            outset: 4 * root.factor
                        }

                        Text {
                            id: city
                            anchors.left: parent.left
                            anchors.leftMargin: 4 * root.factor
                            anchors.top: parent.top
                            anchors.topMargin: 4 * root.factor
                            text: Time.cityOf(place.modelData)
                            color: Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                            font.weight: Typography.weightTitle
                        }

                        Text {
                            anchors.left: city.left
                            anchors.top: city.bottom
                            text: place.here ? root.hhmm(place.here.getHours(), place.here.getMinutes()) : "…"
                            color: Theme.text
                            font: Typography.tabular(Qt.font({
                                "family": Typography.expressive,
                                "pixelSize": root.metrics.fontTitle + 3 * root.factor,
                                "weight": Typography.weightValue
                            }))
                        }

                        Column {
                            anchors.right: remove.left
                            anchors.rightMargin: 6 * root.factor
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.right: parent.right
                                text: Time.utcLabel(place.modelData)
                                color: Theme.textMuted
                                font: root.technical(root.metrics.fontMeta)
                            }

                            Text {
                                anchors.right: parent.right
                                visible: place.dayShift.length > 0
                                text: place.dayShift
                                color: Theme.textFaint
                                font: root.technical(root.metrics.fontMeta)
                            }
                        }

                        Item {
                            id: remove
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * root.factor
                            height: width
                            visible: placeHover.hovered

                            Icon {
                                anchors.centerIn: parent
                                width: 9 * root.factor
                                height: width
                                name: "close"
                                colour: removeHover.hovered ? Theme.text : Theme.textMuted
                            }

                            HoverHandler { id: removeHover }
                            TapHandler { onTapped: Time.removeZone(place.modelData) }
                        }

                        HoverHandler { id: placeHover }
                    }
                }

                Text {
                    visible: Time.zones.length === 0
                    width: parent.width
                    height: 52 * root.factor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "No other places"
                    color: Theme.textFaint
                    font.family: Typography.expressive
                    font.pixelSize: root.metrics.fontSecondary
                }
            }

            // Adding one: a field, and what the system knows that matches.
            Column {
                visible: root.adding
                width: parent.width
                spacing: 4 * root.factor

                Item {
                    width: parent.width
                    height: 34 * root.factor

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusFor(height, root.metrics)
                        color: "transparent"
                        border.width: Metrics.crisp(1.5, Screen.devicePixelRatio)
                        border.color: Theme.primary
                        antialiasing: true
                    }

                    TextInput {
                        id: placeField
                        anchors.left: parent.left
                        anchors.leftMargin: 14 * root.factor
                        anchors.right: parent.right
                        anchors.rightMargin: 14 * root.factor
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontSecondary
                        clip: true

                        Keys.onEscapePressed: root.adding = false
                        onAccepted: {
                            if (root.matches.length > 0) {
                                Time.addZone(root.matches[0]);
                                root.adding = false;
                            }
                        }

                        Text {
                            visible: placeField.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "A city or a zone"
                            color: Theme.textFaint
                            font: placeField.font
                        }
                    }
                }

                Repeater {
                    model: root.matches

                    delegate: Item {
                        id: match

                        required property string modelData

                        width: parent.width
                        height: 30 * root.factor

                        readonly property bool navigable: true

                        function activate() {
                            Time.addZone(match.modelData);
                            root.adding = false;
                        }

                        KeyMark {
                            factor: root.factor
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: Time.cityOf(match.modelData)
                            color: matchHover.hovered ? Theme.primary : Theme.text
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            text: match.modelData.split("/")[0]
                            color: Theme.textFaint
                            font: root.technical(root.metrics.fontMeta)
                        }

                        HoverHandler { id: matchHover }
                        TapHandler {
                            onTapped: {
                                Time.addZone(match.modelData);
                                root.adding = false;
                            }
                        }
                    }
                }
            }

            // The dashed chip adds a place, and is the way back out of the
            // field while it is open.
            Item {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: addLabel.implicitWidth + 28 * root.factor
                height: 26 * root.factor
                visible: root.adding || Time.zones.length < 5

                // From the keyboard the field it opens takes the keys, and
                // the mark lets go so the caret is the one thing that says
                // where typing goes.
                readonly property bool navigable: true

                function activate() {
                    if (!root.adding && root.cell)
                        root.cell.typingKeyed = true;
                    root.adding = !root.adding;
                    if (root.adding)
                        Focus.type(placeField);
                }

                KeyMark {
                    factor: root.factor
                    outset: 3 * root.factor
                }

                DashedSlot {
                    anchors.fill: parent
                    radius: Metrics.radiusFor(parent.height, root.metrics)
                    colour: root.adding ? Theme.primary : Qt.alpha(Theme.line, 0.7)
                }

                Text {
                    id: addLabel
                    anchors.centerIn: parent
                    text: root.adding ? "Cancel" : "+ Place"
                    color: root.adding ? Theme.primary : Theme.textMuted
                    font: root.technical(root.metrics.fontMeta)
                }

                TapHandler { onTapped: root.adding = !root.adding }
            }
        }
    }

    // ---- The day's appointments ---------------------------------------------------
    //
    // Hung from the month, on the side away from the cell, on its own thread:
    // the month feeds it the day. There only once a calendar is set — or while
    // the first is being added, so the field has somewhere to be.

    readonly property real agendaHeight: 236 * factor
    readonly property real eventRow: 34 * factor

    property double chosenDay: Calendar.dayStart(Date.now())

    property bool addingCalendar: false
    onAddingCalendarChanged: {
        if (root.cell)
            root.cell.typing = root.adding || root.addingCalendar;
        if (root.addingCalendar) {
            root.adding = false;
            Calendar.addProblem = "";
            calendarField.text = "";
            Calendar.discover();
            Focus.type(calendarField);
        }
    }

    Connections {
        target: Calendar
        function onAdded(name) {
            root.addingCalendar = false;
            root.today();
        }
    }

    readonly property bool agendaShown: Calendar.active || root.addingCalendar

    // Its own presence, for when a calendar arrives or goes while the clock is
    // open: it grows out of its thread then as it does with the rest.
    property real agendaPresence: root.agendaShown ? 1 : 0
    Behavior on agendaPresence {
        NumberAnimation {
            duration: root.agendaShown ? Timing.open : Timing.close
            easing.type: Easing.Bezier
            easing.bezierCurve: root.agendaShown ? Timing.easeOpenFlat : Timing.easeClose
        }
    }

    readonly property bool agendaPlaced: root.agendaShown || root.agendaPresence > 0

    // Opening upwards the agenda is above the month, and everything else
    // stands that much lower.
    readonly property real monthTop: root.upward && root.agendaPlaced ? root.agendaHeight + root.gap : 0

    readonly property var chosenEvents: Calendar.between(root.chosenDay, Calendar.dayStart(root.chosenDay, 1))

    readonly property var weekdayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    function dayTitle(start) {
        now.date;   // a new day renames them
        const difference = Math.round((start - Calendar.dayStart(Date.now())) / 86400000);
        if (difference === 0)
            return "Today";
        if (difference === 1)
            return "Tomorrow";
        if (difference === -1)
            return "Yesterday";
        const date = new Date(start);
        return `${root.weekdayNames[date.getDay()]} ${date.getDate()} ${root.monthNames[date.getMonth()]}`;
    }

    Thread {
        id: agendaLink

        readonly property real headY: root.upward ? agenda.y + agenda.height : calendar.y + calendar.height
        readonly property real footY: root.upward ? calendar.y : agenda.y

        visible: root.agendaPlaced
        vertical: true
        progress: Math.min(root.stage(0), root.agendaPresence)
        width: implicitWidth
        height: Math.max(0, agendaLink.footY - agendaLink.headY)
        x: root.width / 2 - width / 2
        y: agendaLink.headY
    }

    Panel {
        id: agenda

        metrics: root.metrics
        padding: root.padding
        fixedWidth: root.calendarWidth
        fixedHeight: root.agendaHeight
        growth: Math.min(root.stage(1), root.agendaPresence)
        contentReady: agenda.growth > 0.999

        anchorX: root.sideWidth + root.gap
        anchorY: root.upward ? 0 : root.panelHeight + root.gap
        nodeX: root.width / 2
        nodeY: root.upward ? root.agendaHeight : root.panelHeight + root.gap

        Item {
            anchors.fill: parent

            Text {
                id: agendaTitle
                anchors.left: parent.left
                anchors.right: addCalendar.left
                anchors.rightMargin: 8 * root.factor
                height: 26 * root.factor
                verticalAlignment: Text.AlignVCenter
                text: root.addingCalendar ? "A new calendar" : root.dayTitle(root.chosenDay)
                color: Theme.text
                elide: Text.ElideRight
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
                font.weight: Typography.weightTitle
            }

            // The way to one more, beside the day rather than after the
            // calendars: their row runs out of room at the second name.
            AddChip {
                id: addCalendar
                anchors.right: parent.right
                anchors.top: parent.top
                label: root.addingCalendar ? "Done" : "+ Calendar"
                lit: root.addingCalendar
                onPressed: root.addingCalendar = !root.addingCalendar
                onKeyed: {
                    if (!root.addingCalendar && root.cell)
                        root.cell.typingKeyed = true;
                    root.addingCalendar = !root.addingCalendar;
                }
            }

            // The day: the time in the machine's voice, the title in the
            // human one. What is over is faint; what is on now carries the
            // primary, which is the only state an appointment has.
            Flickable {
                id: dayList

                visible: !root.addingCalendar
                anchors.top: agendaTitle.bottom
                anchors.topMargin: 4 * root.factor
                anchors.bottom: sources.top
                anchors.bottomMargin: 8 * root.factor
                width: parent.width
                clip: true
                contentHeight: dayColumn.height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: dayColumn
                    width: parent.width

                    Repeater {
                        model: root.chosenEvents

                        delegate: Item {
                            id: event

                            required property var modelData

                            readonly property bool over: event.modelData.end <= Calendar.now
                            readonly property bool on: !event.modelData.allDay && event.modelData.start <= Calendar.now
                                                       && Calendar.now < event.modelData.end

                            width: parent.width
                            height: root.eventRow

                            Text {
                                id: when
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 70 * root.factor
                                text: {
                                    if (event.modelData.allDay)
                                        return "ALL DAY";
                                    const start = new Date(Math.max(event.modelData.start, root.chosenDay));
                                    return event.modelData.start < root.chosenDay
                                        ? "…" : root.hhmm(start.getHours(), start.getMinutes());
                                }
                                color: event.on ? Theme.primary : event.over ? Theme.textFaint : Theme.textMuted
                                font: root.technical(root.metrics.fontMeta)
                            }

                            Text {
                                anchors.left: when.right
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: event.modelData.title
                                color: event.over ? Theme.textFaint : Theme.text
                                elide: Text.ElideRight
                                font.family: Typography.expressive
                                font.pixelSize: root.metrics.fontSecondary
                            }
                        }
                    }

                    // A calendar that could not be read says so here, under
                    // what was read from the others.
                    Text {
                        visible: Calendar.problem.length > 0
                        width: parent.width
                        topPadding: 6 * root.factor
                        text: Calendar.problem
                        color: Theme.alert
                        wrapMode: Text.WordWrap
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontMeta
                    }
                }
            }

            Scroller {
                flick: dayList
                factor: root.factor
                x: dayList.width - width
                y: dayList.y
            }

            Text {
                visible: !root.addingCalendar && root.chosenEvents.length === 0 && Calendar.problem.length === 0
                anchors.fill: dayList
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Calendar.readAt > 0 ? "Nothing on the calendar" : "Reading the calendar…"
                color: Theme.textFaint
                font.family: Typography.expressive
                font.pixelSize: root.metrics.fontSecondary
            }

            // A new one. First the calendars of the accounts in Online
            // Accounts, each switched on with a touch — several in a row, so
            // the field stays open until Done. Under the rule, for what has
            // no account, an address pasted and Enter: it is read before it
            // is taken, and the name it gives itself is the one it keeps.
            Flickable {
                id: addingList

                visible: root.addingCalendar
                anchors.top: agendaTitle.bottom
                anchors.topMargin: 6 * root.factor
                anchors.bottom: parent.bottom
                width: parent.width
                clip: true
                contentHeight: addingColumn.height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: addingColumn
                    width: parent.width
                    spacing: 6 * root.factor

                    Text {
                        visible: text.length > 0
                        width: parent.width
                        text: Calendar.discovering && Calendar.accounts.length === 0
                              ? "Looking in Online Accounts…"
                              : !Calendar.discovering && Calendar.accounts.length === 0
                                ? "The calendars of the accounts in Online Accounts appear here."
                                : ""
                        color: Theme.textFaint
                        wrapMode: Text.WordWrap
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontMeta
                    }

                    Repeater {
                        model: Calendar.accounts

                        delegate: Column {
                            id: account

                            required property var modelData

                            width: addingColumn.width
                            spacing: 0

                            Text {
                                width: parent.width
                                height: 22 * root.factor
                                verticalAlignment: Text.AlignVCenter
                                text: `${account.modelData.provider} · ${account.modelData.identity}`
                                color: Theme.textFaint
                                elide: Text.ElideRight
                                font.family: Typography.expressive
                                font.pixelSize: root.metrics.fontMeta
                            }

                            Text {
                                visible: !!account.modelData.problem
                                width: parent.width
                                text: account.modelData.problem || ""
                                color: Theme.alert
                                wrapMode: Text.WordWrap
                                font.family: Typography.expressive
                                font.pixelSize: root.metrics.fontMeta
                            }

                            Repeater {
                                model: account.modelData.calendars

                                delegate: Item {
                                    id: offered

                                    required property var modelData

                                    readonly property bool taken: Calendar.holds(account.modelData.goa, offered.modelData.href)

                                    width: account.width
                                    height: 30 * root.factor

                                    readonly property bool navigable: !offered.taken

                                    function activate() {
                                        Calendar.addFromAccount(account.modelData.goa, offered.modelData);
                                    }

                                    KeyMark {
                                        factor: root.factor
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8 * root.factor
                                        anchors.right: offeredState.left
                                        anchors.rightMargin: 8 * root.factor
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: offered.modelData.name
                                        elide: Text.ElideRight
                                        color: offered.taken ? Theme.textMuted
                                             : offeredHover.hovered ? Theme.primary : Theme.text
                                        font.family: Typography.expressive
                                        font.pixelSize: root.metrics.fontSecondary
                                    }

                                    Text {
                                        id: offeredState
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8 * root.factor
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: offered.taken ? "ADDED" : "ADD"
                                        color: offered.taken ? Theme.textFaint
                                             : offeredHover.hovered ? Theme.primary : Theme.textMuted
                                        font: root.technical(root.metrics.fontMeta)
                                    }

                                    HoverHandler { id: offeredHover }
                                    TapHandler {
                                        enabled: !offered.taken
                                        onTapped: offered.activate()
                                    }
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 2 * root.factor }

                    DashedRule {
                        width: parent.width
                    }

                    Item { width: 1; height: 2 * root.factor }

                    Item {
                        width: parent.width
                        height: 34 * root.factor

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusFor(height, root.metrics)
                            color: "transparent"
                            border.width: Metrics.crisp(1.5, Screen.devicePixelRatio)
                            border.color: Calendar.addProblem.length > 0 ? Theme.alert
                                        : calendarField.activeFocus ? Theme.primary : Theme.line
                            antialiasing: true
                        }

                        TextInput {
                            id: calendarField
                            anchors.left: parent.left
                            anchors.leftMargin: 14 * root.factor
                            anchors.right: parent.right
                            anchors.rightMargin: 14 * root.factor
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text
                            readOnly: Calendar.checking
                            font.family: Typography.expressive
                            font.pixelSize: root.metrics.fontSecondary
                            clip: true

                            onTextChanged: Calendar.addProblem = ""
                            Keys.onEscapePressed: root.addingCalendar = false
                            onAccepted: Calendar.add(text)

                            Text {
                                visible: calendarField.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Or an iCal address"
                                color: Theme.textFaint
                                font: calendarField.font
                            }
                        }
                    }

                    Text {
                        visible: text.length > 0
                        width: parent.width
                        text: Calendar.checking ? "Reading it…" : Calendar.addProblem
                        color: Calendar.checking ? Theme.textMuted : Theme.alert
                        wrapMode: Text.WordWrap
                        font.family: Typography.expressive
                        font.pixelSize: root.metrics.fontMeta
                    }
                }
            }

            Scroller {
                flick: addingList
                factor: root.factor
                x: addingList.width - width
                y: addingList.y
            }

            // The calendars read.
            Row {
                id: sources
                anchors.bottom: parent.bottom
                width: parent.width
                height: 26 * root.factor
                spacing: 6 * root.factor
                clip: true

                Repeater {
                    model: root.addingCalendar ? [] : Calendar.sources

                    delegate: SourceChip {}
                }
            }
        }
    }

    // ---- The timer and the alarm --------------------------------------------------

    function clockFigure(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const rest = seconds % 60;
        const mm = String(minutes).padStart(2, "0");
        const ss = String(rest).padStart(2, "0");
        return hours > 0 ? `${hours}:${mm}:${ss}` : `${mm}:${ss}`;
    }

    Panel {
        id: timers

        metrics: root.metrics
        padding: root.padding
        fixedWidth: root.sideWidth
        fixedHeight: root.panelHeight
        growth: root.stage(1)
        contentReady: root.stage(1) > 0.999

        anchorX: root.sideWidth + root.gap + root.calendarWidth + root.gap
        anchorY: root.monthTop
        nodeX: root.sideWidth + root.gap + root.calendarWidth + root.gap
        nodeY: root.monthTop + root.panelHeight / 2

        Column {
            anchors.fill: parent
            spacing: 10 * root.factor

            Text {
                text: "TIMER"
                color: Theme.textFaint
                font: root.technical(root.metrics.fontMeta)
            }

            // The figure is what the wheel turns while the timer is still:
            // a minute a notch.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.clockFigure(Time.left)
                color: Time.running ? Theme.text : Theme.textMuted
                font: root.technical(root.metrics.fontValue, Typography.weightValue)

                readonly property bool navigable: !Time.running

                function adjust(direction) {
                    Time.setLength(Time.length + direction * 60);
                }

                KeyMark {
                    factor: root.factor
                    outset: 4 * root.factor
                }

                WheelHandler {
                    enabled: !Time.running
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => Time.setLength(Time.length + (event.angleDelta.y > 0 ? 60 : -60))
                }
            }

            // What is left of it: a live value, so it may move.
            Slider {
                width: parent.width
                factor: root.factor
                value: Time.fractionLeft
                dimmed: !Time.running
                enabled: false
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6 * root.factor

                Repeater {
                    model: [5, 10, 25, 60]

                    delegate: Pill {
                        required property int modelData
                        label: modelData < 60 ? `${modelData}` : "1 H"
                        lit: !Time.running && Time.length === modelData * 60
                        onPressed: Time.setLength(modelData * 60)
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8 * root.factor

                Pill {
                    label: Time.running ? "PAUSE" : (Time.paused ? "RESUME" : "START")
                    lit: true
                    onPressed: Time.running ? Time.pause() : Time.start()
                }

                Pill {
                    label: "RESET"
                    onPressed: Time.reset()
                }
            }

            Item { width: 1; height: 6 * root.factor }

            Item {
                width: parent.width
                height: 22 * root.factor

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ALARM"
                    color: Theme.textFaint
                    font: root.technical(root.metrics.fontMeta)
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    factor: root.factor
                    on: Time.alarm.on === true
                    onToggled: on => Time.setAlarm(Time.alarm.hour, Time.alarm.minute, on)
                }
            }

            // The hour and the minute, each turned by the wheel over it.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    text: String(Time.alarm.hour).padStart(2, "0")
                    color: Time.alarm.on ? Theme.text : Theme.textMuted
                    font: root.technical(root.metrics.fontValue, Typography.weightValue)

                    // The keys turn what the wheel turns, by the same steps.
                    readonly property bool navigable: true

                    function adjust(direction) {
                        Time.setAlarm(Time.alarm.hour + direction, Time.alarm.minute, Time.alarm.on);
                    }

                    KeyMark {
                        factor: root.factor
                        outset: 3 * root.factor
                    }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => Time.setAlarm(Time.alarm.hour + (event.angleDelta.y > 0 ? 1 : -1),
                                                        Time.alarm.minute, Time.alarm.on)
                    }
                }

                Text {
                    text: ":"
                    color: Theme.textMuted
                    font: root.technical(root.metrics.fontValue, Typography.weightValue)
                }

                Text {
                    text: String(Time.alarm.minute).padStart(2, "0")
                    color: Time.alarm.on ? Theme.text : Theme.textMuted
                    font: root.technical(root.metrics.fontValue, Typography.weightValue)

                    readonly property bool navigable: true

                    function adjust(direction) {
                        Time.setAlarm(Time.alarm.hour, Time.alarm.minute + direction * 5, Time.alarm.on);
                    }

                    KeyMark {
                        factor: root.factor
                        outset: 3 * root.factor
                    }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => Time.setAlarm(Time.alarm.hour,
                                                        Time.alarm.minute + (event.angleDelta.y > 0 ? 5 : -5),
                                                        Time.alarm.on)
                    }
                }
            }
        }
    }

    // ---- Pieces -------------------------------------------------------------------

    component Chevron: Item {
        id: chevron

        property bool pointsLeft: false
        signal pressed

        width: 24 * root.factor
        height: 24 * root.factor

        Icon {
            anchors.centerIn: parent
            width: 11 * root.factor
            height: width
            rotation: chevron.pointsLeft ? 180 : 0
            name: "chevron-right"
            colour: chevronHover.hovered ? Theme.text : Theme.textMuted
        }

        HoverHandler { id: chevronHover }
        TapHandler { onTapped: chevron.pressed() }
    }

    component Pill: Item {
        id: pill

        property string label: ""
        property bool lit: false
        signal pressed

        width: pillText.implicitWidth + 22 * root.factor
        height: 24 * root.factor

        readonly property bool navigable: true

        function activate() {
            pill.pressed();
        }

        KeyMark {
            factor: root.factor
            outset: 3 * root.factor
        }

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            color: pill.lit ? Qt.alpha(Theme.primary, 0.16) : "transparent"
            border.width: Metrics.rim(Screen.devicePixelRatio)
            border.color: pill.lit ? Theme.primary : pillHover.hovered ? Theme.text : Theme.line
        }

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.lit ? Theme.text : Theme.textMuted
            font: root.technical(root.metrics.fontMeta)
        }

        HoverHandler { id: pillHover }
        TapHandler { onTapped: pill.pressed() }
    }

    // A calendar read: its name, and a cross. The cross asks first — the
    // address behind it was found once, in another application's settings,
    // and should not be lost to a slip — and the second press anywhere on the
    // chip answers; leaving it withdraws the question.
    component SourceChip: Item {
        id: chip

        required property var modelData
        required property int index

        property bool asking: false
        readonly property string trouble: Calendar.troubleOf(chip.index)

        width: Math.min(chipText.implicitWidth, 110 * root.factor) + 36 * root.factor
        height: 26 * root.factor

        readonly property bool navigable: true

        function activate() {
            if (chip.asking)
                Calendar.forget(chip.index);
            else
                chip.asking = true;
        }

        function discard() {
            chip.activate();
        }

        KeyMark {
            factor: root.factor
            outset: 3 * root.factor
        }

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            color: "transparent"
            border.width: Metrics.rim(Screen.devicePixelRatio)
            border.color: chip.asking || chip.trouble.length > 0 ? Theme.alert
                        : chipHover.hovered ? Theme.text : Theme.line
        }

        Text {
            id: chipText
            anchors.left: parent.left
            anchors.leftMargin: 11 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 110 * root.factor)
            text: chip.asking ? "FORGET?" : String(chip.modelData.name || "Calendar").toUpperCase()
            elide: Text.ElideRight
            color: chip.asking || chip.trouble.length > 0 ? Theme.alert : Theme.textMuted
            font: root.technical(root.metrics.fontMeta)
        }

        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.factor
            anchors.verticalCenter: parent.verticalCenter
            width: 9 * root.factor
            height: width
            name: "close"
            colour: chip.asking ? Theme.alert : crossHover.hovered ? Theme.text : Theme.textMuted

            HoverHandler { id: crossHover }
        }

        HoverHandler {
            id: chipHover
            onHoveredChanged: if (!hovered) chip.asking = false
        }

        TapHandler { onTapped: chip.activate() }
    }

    // The dashed chip that adds something, and is the way back out of the
    // field it opened while that is open.
    component AddChip: Item {
        id: addChip

        property string label: ""
        property bool lit: false
        signal pressed
        signal keyed

        width: addChipText.implicitWidth + 28 * root.factor
        height: 26 * root.factor

        // From the keyboard the field it opens takes the keys, and the mark
        // lets go so the caret is the one thing that says where typing goes.
        readonly property bool navigable: true

        function activate() {
            addChip.keyed();
        }

        KeyMark {
            factor: root.factor
            outset: 3 * root.factor
        }

        DashedSlot {
            anchors.fill: parent
            radius: Metrics.radiusFor(parent.height, root.metrics)
            colour: addChip.lit ? Theme.primary : Qt.alpha(Theme.line, 0.7)
        }

        Text {
            id: addChipText
            anchors.centerIn: parent
            text: addChip.label
            color: addChip.lit ? Theme.primary : Theme.textMuted
            font: root.technical(root.metrics.fontMeta)
        }

        TapHandler { onTapped: addChip.pressed() }
    }

    function shapes() {
        const out = [
            { "item": calendar, "radius": calendar.radius },
            { "item": places, "radius": places.radius },
            { "item": timers, "radius": timers.radius }
        ];
        if (root.agendaPlaced)
            out.push({ "item": agenda, "radius": agenda.radius });
        return out;
    }
}
