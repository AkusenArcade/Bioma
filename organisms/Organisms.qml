pragma Singleton

import QtQuick
import Quickshell
import qs.core
import qs.services

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
        "calendar": "calendar/CalendarOrganism.qml",
        "weather": "weather/WeatherOrganism.qml",
        "note": "note/NoteOrganism.qml",
        "lava": "lava/LavaOrganism.qml",
        "cytoplasm": "cytoplasm/CytoplasmOrganism.qml",
        "rings": "rings/RingsOrganism.qml",
        "osmosis": "osmosis/OsmosisOrganism.qml",
        "photoperiod": "photoperiod/PhotoperiodOrganism.qml",
        "vacuole": "vacuole/VacuoleOrganism.qml",
        "sediment": "sediment/SedimentOrganism.qml",
        "nucleus": "nucleus/NucleusOrganism.qml",
        "adipose": "adipose/AdiposeOrganism.qml"
    })

    // What an organism is called when it is spoken about rather than drawn.
    readonly property var names: ({
        "clock": "Clock",
        "media": "Media",
        "vitals": "Vitals",
        "calendar": "Calendar",
        "weather": "Weather",
        "note": "Note",
        "lava": "Lava lamp",
        "cytoplasm": "Cytoplasm",
        "rings": "Growth rings",
        "osmosis": "Osmosis",
        "photoperiod": "Photoperiod",
        "vacuole": "Vacuole",
        "sediment": "Sediment",
        "nucleus": "Nucleus",
        "adipose": "Adipose"
    })

    // How many units of the grid each one covers, across and down
    // (Metrics.organismUnit, the shape gap between them): one size per kind,
    // so they fall into tidy clusters (Akusen, 2026-10-07). The body is laid
    // out in what the template gives it, never the other way round.
    readonly property var templates: ({
        "clock": [2, 1],
        "media": [2, 2],
        "vitals": [2, 1],
        "calendar": [2, 2],
        "weather": [2, 1],
        "note": [2, 2],
        "lava": [1, 2],
        "cytoplasm": [2, 1],
        "rings": [2, 2],
        "osmosis": [1, 2],
        "photoperiod": [2, 1],
        "vacuole": [2, 2],
        "sediment": [2, 2],
        "nucleus": [2, 1],
        "adipose": [2, 1]
    })

    // The template of one block. Where an organism already has an option for
    // its shape, the option chooses among templates: a note is one, two or
    // three units tall, the vitals a row or a square. A row of four vitals is
    // a unit wider, because a figure cut short is not a figure.
    function template(entry) {
        const type = entry.type || "";
        if (type === "note")
            return [2, entry.height === "short" ? 1 : entry.height === "tall" ? 3 : 2];
        if (type === "vitals") {
            if (entry.layout === "square")
                return [2, 2];
            const domains = 2 + (SystemMonitor.gpuPresent ? 1 : 0) + (SystemMonitor.hasBattery ? 1 : 0);
            return [domains > 3 ? 3 : 2, 1];
        }
        return root.templates[type] || [1, 1];
    }

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
