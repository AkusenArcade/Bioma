--!strict
-- Quick actions: macros somebody writes on the Settings page and runs from
-- the ring that comes to the pointer (services/Actions.qml at 11bb81e).
--
-- The macros are read here, as the ring needs them; running one is the
-- Quickshell shell's while the two run side by side (genoma/PORT.md, "Who
-- acts on the desktop"): a step changes the volume, the settings, a
-- monitor, and those are its. So a chosen macro is handed to it by name,
-- `actions run`, exactly as a key of its own would hand it.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

function M.macros(): { any }
    local list = config.get("actions.macros", {})
    local out = {}
    if type(list) ~= "table" then return out end
    for _, macro in list do
        if type(macro) == "table" and type(macro.name) == "string" then table.insert(out, macro) end
    end
    return out
end

-- As many as the ring holds, and as many as the page makes: one ring, not
-- pages of them (Akusen, 2026-10-24: "eight are enough"). A longer list
-- written by hand is kept, and the rest run from their key.
M.ring_size = 8

function M.ring(): { any }
    local out = {}
    for i, macro in M.macros() do
        if i > M.ring_size then break end
        table.insert(out, macro)
    end
    return out
end

-- Drawn for the actions, in the set's own grammar (docs/design/icons): what
-- a macro is for, not what it does.
M.icons = {
    "action-work", "action-game", "action-stream", "action-music", "action-relax", "action-focus",
    "action-night", "action-call", "action-code", "action-design", "action-home", "action-travel",
}
M.default_icon = "action-work"

function M.icon_of(macro: any): string
    local name = macro and macro.icon
    for _, icon in M.icons do
        if icon == name then return name end
    end
    return M.default_icon
end

local function ask(...: string)
    g.process { command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "actions", ... } }
end

function M.run(name: string) ask("run", name) end

-- With nothing written yet, the ring's one capsule opens Settings on the
-- page where macros are written; Settings is still the Quickshell shell's.
function M.write() ask("write") end

return M
