--!strict
-- The cell registry (cells/Registry.qml): old names and retired cells, how
-- wide each cell is, when it is there, and what the settings cell says
-- about it.
local M = {}

-- `session` became `system` on 2026-09-23; `sinestesia` became `media` on
-- 2026-10-07. A block with the old name still works.
M.aliases = { session = "system", sinestesia = "media" }

-- Folded into another cell: `recording` joined `utility` on 2026-09-27.
M.retired = { recording = true }

function M.canonical(kind: string): string
    return M.aliases[kind] or kind
end

-- The cells written on Genoma so far, every one of which answers to its
-- name; and those that are the engine's own, never offered to a keybind.
M.ported = { "window_title", "workspaces", "vitals", "clock", "media", "theme", "utility", "audio", "connectivity", "system", "dock", "tray", "download", "privacy", "timer", "keyboard", "drives", "performance", "clipboard", "emoji", "actions", "notifications", "settings", "launcher" } :: { string }
-- The polkit cell comes when polkit asks for a password, never by a key.
M.internal = { probe = true, polkit = true }

-- Placed nowhere and never in the middle: a cell that comes to the point
-- the hand is at (Registry.comesToPointer). The quick actions are a ring
-- around that point, and a ring has no place on a strip.
M.pointer = { actions = true }
function M.comes_to_pointer(kind: string): boolean
    return M.pointer[M.canonical(kind)] == true
end

-- Each key a block leaves out is the domain's (Registry.widthOf).
M.widths = {
    window_title = { elastic = true, max_percent = 28 },
    media = { elastic = true, max_percent = 22 },
    workspaces = { max = 220 },
    notifications = { max = 300 },
}
function M.width_of(kind: string): { [string]: any }
    return M.widths[M.canonical(kind)] or {}
end

-- The narrowest a cell can be and still be itself, logical units at the
-- normal step; a block may raise it with `min_width`.
M.minimums = {
    clock = 72, window_title = 0, workspaces = 96, vitals = 90, media = 81, audio = 40,
    utility = 40, theme = 120, system = 40, dock = 52, notifications = 220, connectivity = 64,
    launcher = 40, settings = 40, tray = 40, clipboard = 40, keyboard = 76, privacy = 64,
    timer = 40, download = 90, drives = 40, emoji = 40, actions = 40, performance = 40,
}
function M.minimum_of(kind: string): number
    return M.minimums[M.canonical(kind)] or 24
end

-- What a domain's condition means when its block does not say: the figures
-- config/default.json ships (Akusen's, 2026-09-23). Confirm and dwell in ms.
M.grammar = {
    clock = { enter = 1, exit = 1, confirm = 0, dwell = 0 },
    workspaces = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    vitals = { enter = 0.8, exit = 0.75, confirm = 1000, dwell = 3000 },
    audio = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    theme = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    utility = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    system = { enter = 1, exit = 1, confirm = 0, dwell = 0 },
    window_title = { enter = 1, exit = 1, confirm = 0, dwell = 200 },
    media = { enter = 0.02, exit = 0.005, confirm = 200, dwell = 4000 },
    connectivity = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    dock = { enter = 1, exit = 1, confirm = 0, dwell = 400 },
    notifications = { enter = 1, exit = 1, confirm = 0, dwell = 400 },
    tray = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    clipboard = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    keyboard = { enter = 1, exit = 1, confirm = 0, dwell = 5000 },
    privacy = { enter = 1, exit = 1, confirm = 0, dwell = 2000 },
    timer = { enter = 1, exit = 1, confirm = 0, dwell = 0 },
    download = { enter = 1, exit = 1, confirm = 0, dwell = 3000 },
    drives = { enter = 1, exit = 1, confirm = 0, dwell = 0 },
    performance = { enter = 1, exit = 1, confirm = 0, dwell = 0 },
}
M.default_grammar = { enter = 1, exit = 1, confirm = 0, dwell = 2000 }
function M.grammar_of(kind: string): { [string]: number }
    return M.grammar[M.canonical(kind)] or M.default_grammar
end

-- What a band must grant to hold these blocks at their narrowest.
function M.room_for(cells: { any }?, m: { [string]: any }): number
    local metrics = require("core/metrics")
    local wanted = {}
    for _, entry in cells or {} do
        if type(entry) == "table" and entry.enabled ~= false and not M.retired[entry.type] then
            local declared = if entry.min_width and entry.min_width.value then entry.min_width.value else M.minimum_of(entry.type)
            table.insert(wanted, declared)
        end
    end
    return metrics.room_for(wanted, m)
end

-- The cell type for a domain: `cells/<domain>.luau`, or nil while it is not
-- ported yet (the tissue then leaves it out, as QML leaves out a block it
-- cannot build).
local types: { [string]: any } = {}
function M.type_of(kind: string): any
    kind = M.canonical(kind)
    if types[kind] == nil then
        local ok, module = pcall(require, "cells/" .. kind)
        types[kind] = if ok then module else false
        if not ok and not string.find(tostring(module), "No such file") then
            print("Bioma: cell " .. kind .. " failed to load — " .. tostring(module))
        end
    end
    return types[kind] or nil
end

-- ---- What the settings cell says about each cell -------------------------------

-- What a cell is called when it is spoken about rather than drawn, in the
-- catalogue's order: the order the cells were built in, read as a tour of
-- the shell rather than an alphabet.
M.catalogue = {
    { "clock", "Clock" }, { "window_title", "Window title" }, { "workspaces", "Workspaces" },
    { "vitals", "Vitals" }, { "media", "Media" }, { "audio", "Audio" }, { "utility", "Utility" },
    { "theme", "Theme" }, { "system", "System" }, { "dock", "Dock" }, { "notifications", "Notifications" },
    { "connectivity", "Connectivity" }, { "launcher", "Launcher" }, { "settings", "Settings" },
    { "tray", "Tray" }, { "clipboard", "Clipboard" }, { "keyboard", "Keyboard" }, { "privacy", "Privacy" },
    { "timer", "Timer" }, { "download", "Downloads" }, { "drives", "Drives" }, { "emoji", "Emoji" },
    { "actions", "Quick actions" }, { "performance", "Performance" },
} :: { { string } }

function M.name_of(kind: string): string
    kind = M.canonical(kind)
    for _, pair in M.catalogue do
        if pair[1] == kind then return pair[2] end
    end
    return kind
end

-- When each cell is there by itself, said the way the Cells page explains
-- it. What the condition is lives in the cell; this is the sentence about
-- it, kept beside the name so a new cell brings both in one line of work.
M.conditions = {
    clock = "When the hour strikes, for that minute.",
    window_title = "While a window has the focus. With none, there is no title to show.",
    workspaces = "For five seconds after the workspace changes.",
    vitals = "While the processor, the memory, the graphics card or the battery is past its alert level, and three seconds after it comes back.",
    media = "While sound is playing, and four seconds after it stops.",
    audio = "For five seconds after the volume changes or the sound is muted.",
    utility = "For five seconds after a screenshot, and for as long as a recording runs and waits to be kept.",
    theme = "For five seconds after the palette changes.",
    system = "While a restart is due: the kernel was updated and the one running is no longer installed.",
    dock = "While the desktop is showing (no windows on this monitor's workspace) and it has something to hold.",
    notifications = "When a notification arrives, and while many arrive at once.",
    connectivity = "For five seconds after something connects: the wire, a Wi-Fi network, a Bluetooth device, a VPN, or a print starting.",
    launcher = "Never by itself: it comes when its keybind asks for it.",
    settings = "Never by itself: it comes when its keybind asks for it.",
    tray = "From the moment an application's icon changes state until the pointer has been over it, then five seconds.",
    clipboard = "For five seconds after something is copied.",
    keyboard = "For five seconds after the keyboard layout changes.",
    privacy = "While the microphone, a camera or the screen is being taken, and two seconds after.",
    timer = "While a timer runs, or waits, paused, to be resumed.",
    download = "While a browser is downloading into the downloads folder, and until a minute after it stalls.",
    drives = "While a removable drive is attached: a stick, a card, a disk on a cable.",
    emoji = "Never by itself: it comes when its keybind asks for it.",
    actions = "Never by itself: it comes to the pointer when its keybind asks for it.",
    performance = "While performance mode is on: turned on by its key, or by a game or an application on its list.",
} :: { [string]: string }

function M.condition_of(kind: string): string
    return M.conditions[M.canonical(kind)] or ""
end

-- Which visibilities a cell can wear. Every cell can be invoked, so this
-- is about whether it exists without being: a window title with no window
-- has nothing to say. The Cells page shows the ones it cannot have dimmed
-- rather than hidden, which is how the shell explains itself.
M.visibilities = {
    clock = { "always", "conditional" }, window_title = { "conditional" },
    workspaces = { "always", "conditional" }, vitals = { "always", "conditional" },
    media = { "conditional" }, audio = { "always", "conditional", "invoked" },
    utility = { "always", "conditional" }, theme = { "always", "conditional" },
    system = { "always", "conditional" }, dock = { "always", "conditional" },
    notifications = { "always", "conditional" }, connectivity = { "always", "conditional" },
    launcher = { "always", "invoked" }, settings = { "always", "invoked" },
    tray = { "conditional", "always" }, clipboard = { "always", "conditional" },
    keyboard = { "always", "conditional" }, privacy = { "conditional" }, timer = { "conditional" },
    download = { "conditional" }, drives = { "conditional" }, polkit = { "invoked" },
    emoji = { "always", "invoked" }, actions = { "invoked" }, performance = { "conditional", "always" },
} :: { [string]: { string } }

function M.allows(kind: string, visibility: string): boolean
    local list = M.visibilities[M.canonical(kind)]
    return list == nil or table.find(list, visibility) ~= nil
end

-- A cell whose form changes when it floats, and its visibility with it:
-- floating, the launcher is the panel, and a panel always open would hold
-- the keyboard for good.
M.floating_visibility = { launcher = "invoked" } :: { [string]: string }

function M.fixed_when_floating(kind: string): string
    return M.floating_visibility[M.canonical(kind)] or ""
end

function M.allows_in(kind: string, visibility: string, floating: boolean): boolean
    local fixed = if floating then M.fixed_when_floating(kind) else ""
    return if fixed ~= "" then visibility == fixed else M.allows(kind, visibility)
end

-- A membrane or floating list with old names replaced and retired cells
-- dropped, in place.
function M.renamed(list: { any }?): { any }
    local g = require("@genoma")
    local function walk(cells: { any }?): { any }
        -- A list, empty or not: a tissue with no cells is written `[]`.
        local kept = g.array({})
        for _, entry in cells or {} do
            if type(entry) == "table" and entry.type then
                entry.type = M.canonical(entry.type)
            end
            if not (type(entry) == "table" and M.retired[entry.type]) then
                table.insert(kept, entry)
            end
        end
        return kept
    end
    for _, block in list or {} do
        if block.cells then block.cells = walk(block.cells) end
        for _, tissue in block.tissues or {} do
            if tissue.cells then tissue.cells = walk(tissue.cells) end
        end
    end
    return list or {}
end

return M
