pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// The clock, opened: the month in the middle, hung from the time it belongs
// to; other places on one side and a timer and an alarm on the other, each on
// its own thread from the month.
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
    implicitHeight: panelHeight
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
                "inMonth": day.getMonth() === root.viewMonth,
                "today": day.getFullYear() === today.getFullYear() && day.getMonth() === today.getMonth()
                         && day.getDate() === today.getDate()
            });
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
        anchorY: 0
        nodeX: root.width / 2
        nodeY: root.upward ? root.panelHeight : 0

        Column {
            anchors.fill: parent
            spacing: 8 * root.factor

            // The month and the year, with the way to the next and back. The
            // name itself brings the month of today back.
            Item {
                width: parent.width
                height: 30 * root.factor

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

                        // Today is lit the way a chosen control is: the disc
                        // with the light gradient, the figure dark on it.
                        Disc {
                            anchors.centerIn: parent
                            visible: day.modelData.today
                            width: 26 * root.factor
                            height: width
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
                    }
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
        y: root.panelHeight / 2 - height / 2
    }

    Thread {
        vertical: false
        progress: root.stage(0)
        width: root.gap
        height: implicitHeight
        x: root.sideWidth + root.gap + root.calendarWidth
        y: root.panelHeight / 2 - height / 2
    }

    // ---- Other places -----------------------------------------------------------

    // Whether the city field is open. The cell asks for the keyboard while it
    // is, and only then.
    property bool adding: false
    onAddingChanged: {
        if (root.cell)
            root.cell.typing = root.adding;
        if (root.adding) {
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
        anchorY: 0
        nodeX: root.sideWidth
        nodeY: root.panelHeight / 2

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
        anchorY: 0
        nodeX: root.sideWidth + root.gap + root.calendarWidth + root.gap
        nodeY: root.panelHeight / 2

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

        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusFor(height, root.metrics)
            antialiasing: true
            color: pill.lit ? Qt.alpha(Theme.primary, 0.16) : "transparent"
            border.width: Metrics.crisp(Metrics.rimWidth, Screen.devicePixelRatio)
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

    function shapes() {
        return [
            { "item": calendar, "radius": calendar.radius },
            { "item": places, "radius": places.radius },
            { "item": timers, "radius": timers.radius }
        ];
    }
}
