--!strict
-- The cell registry (cells/Registry.qml), the part the configuration needs
-- now: old names and retired cells. The rest comes with the cells.
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
M.ported = {} :: { string }
M.internal = { probe = true }

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

-- A membrane or floating list with old names replaced and retired cells
-- dropped, in place.
function M.renamed(list: { any }?): { any }
    local function walk(cells: { any }?): { any }
        local kept = {}
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
