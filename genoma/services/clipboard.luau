--!strict
-- What was copied, kept (services/Clipboard.qml at 11bb81e).
--
-- The history is kept by Bioma on Quickshell while the two run side by
-- side (genoma/PORT.md, "Who acts on the desktop"): it watches the
-- clipboard and writes history.json and the copies beside it. This reads
-- that file, puts an entry back with wl-copy (which the history then
-- takes as the newest copy, as it always did), and asks Quickshell to drop
-- what is dropped, so the list it holds never brings an entry back.
local g = require("@genoma")
local paths = require("core/paths")

local M = {}

local home = g.env("HOME") or ""
local cache = g.env("XDG_CACHE_HOME") or (home .. "/.cache")
M.directory = cache .. "/bioma/clipboard"

local index = g.file { path = M.directory .. "/history.json" }
local entries = g.computed(function(): { any }
    local text = index.text
    if not text or text == "" then return {} end
    local ok, list = pcall(g.parse_json, text)
    return if ok and type(list) == "table" then list else {}
end)
function M.entries(): { any } return entries.value end

-- A new copy at the head of the list: what the cell pulses on.
local listeners: { () -> () } = {}
function M.on_copied(f: () -> ()) table.insert(listeners, f) end
local newest = ""
g.watch(function()
    local e = entries.value[1]
    return if e then tostring(e.hash) else ""
end, function(hash: string)
    if newest ~= "" and hash ~= "" and hash ~= newest then
        for _, f in listeners do f() end
    end
    newest = hash
end)

function M.restore(entry: any)
    if not entry then return end
    g.process { command = { "sh", "-c", 'wl-copy --type "$1" < "$2"', "restore", entry.mime, entry.file } }
end

local function ask(...: string)
    local command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "clipboard", ... }
    g.process { command = command }
end
function M.remove(entry: any) if entry then ask("remove", tostring(entry.hash)) end end
function M.clear() ask("clear") end

function M.is_image(entry: any): boolean
    return entry ~= nil and string.sub(tostring(entry.mime), 1, 6) == "image/"
end

-- How long ago, in the machine's words: NOW, 5 MIN, 3 H, 2 D.
function M.age(entry: any, now: number): string
    local seconds = math.max(0, math.floor((now - (entry.time or 0) / 1000) + 0.5))
    if seconds < 60 then return "NOW" end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return minutes .. " MIN" end
    local hours = math.floor(minutes / 60 + 0.5)
    if hours < 24 then return hours .. " H" end
    return math.floor(hours / 24 + 0.5) .. " D"
end

return M
