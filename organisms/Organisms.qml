pragma Singleton

import QtQuick
import Quickshell
import qs.core

// Which file is which organism.
//
// Adding an organism costs one config block and one line here — never a
// structural change anywhere else. A type nobody registered is a warning and
// an organism that does not appear.
Singleton {
    id: root

    readonly property var files: ({
        "clock": "clock/ClockOrganism.qml",
        "media": "media/MediaOrganism.qml",
        "vitals": "vitals/VitalsOrganism.qml",
        "calendar": "calendar/CalendarOrganism.qml"
    })

    // What an organism is called when it is spoken about rather than drawn.
    readonly property var names: ({
        "clock": "Clock",
        "media": "Media",
        "vitals": "Vitals",
        "calendar": "Calendar"
    })

    function fileFor(type) {
        return root.files[type] || "";
    }

    // An option of the first cell of `type` anywhere in the layout. An
    // organism that shares a domain with a cell speaks the way that cell was
    // told to — the clock organism in the clock cell's 12 or 24 hours — rather
    // than asking the same question twice.
    function cellOption(type, key, fallback) {
        const blocks = [];
        for (const membrane of Config.get("membranes", []))
            for (const tissue of membrane.tissues || [])
                for (const cell of tissue.cells || [])
                    blocks.push(cell);
        for (const tissue of Config.get("floating", []))
            for (const cell of tissue.cells || [])
                blocks.push(cell);
        for (const cell of blocks)
            if (cell.type === type && cell.options && cell.options[key] !== undefined)
                return cell.options[key];
        return fallback;
    }
}
