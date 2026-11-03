--!strict
-- What was copied, kept (services/Clipboard.qml at 8ed8892).
--
-- One `wl-paste --watch` runs `scripts/clip` on every copy, which writes
-- the copy into a private directory and prints a line describing it; this
-- keeps the list (newest first, `clipboard.history` long, a copy made again
-- moved to the top) in history.json beside the copies.
--
-- Bioma on Genoma alone keeps it (M6 step 7a, `start`). Beside Quickshell,
-- Quickshell keeps it: this reads history.json, puts an entry back with
-- wl-copy (which the history then takes as the newest copy), and asks
-- Quickshell to drop what is dropped, so the list it holds never brings an
-- entry back.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local runtime = require("core/runtime")
local timing = require("core/timing")

local M = {}

local home = g.env("HOME") or ""
local cache = g.env("XDG_CACHE_HOME") or (home .. "/.cache")
M.directory = cache .. "/bioma/clipboard"

local index = g.file { path = M.directory .. "/history.json" }
local function parsed(text: string?): { any }
    if not text or text == "" then return {} end
    local ok, list = pcall(g.parse_json, text)
    return if ok and type(list) == "table" then list else {}
end
-- The list as this shell keeps it, once it keeps it; until then the file.
local kept = g.signal(nil :: { any }?)
local entries = g.computed(function(): { any }
    local own = kept.value
    if own then return own end
    return parsed(index.text)
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

-- ---- Keeping it ----------------------------------------------------------------

local function forget(files: { string })
    if #files == 0 then return end
    local command = { "rm", "-f", "--" }
    for _, f in files do table.insert(command, f) end
    g.process { command = command }
end

-- One copy can reach the watcher twice (wl-paste reports the offer and the
-- selection a millisecond apart), and the second file is never in the
-- list: what the list does not name is swept a moment after it settles.
local sweeping: any = nil
local function sweep_soon()
    if sweeping then sweeping:stop() end
    sweeping = g.after(timing.seconds.debounce, function()
        sweeping = nil
        local command = { "sh", "-c",
            'cd "$1" || exit 0; shift; for f in [0-9]*; do [ -e "$f" ] || continue; keep=0; '
            .. 'for k in "$@"; do [ "$k" = "$f" ] && keep=1 && break; done; '
            .. '[ $keep = 1 ] || rm -f -- "$f"; done', "sweep", M.directory }
        for _, e in g.untracked(function() return entries.value end) do
            local parts = string.split(tostring(e.file), "/")
            table.insert(command, parts[#parts])
        end
        g.process { command = command }
    end)
end

local function save(list: { any })
    kept.value = list
    index:write(g.to_json(g.array(list)))
    sweep_soon()
end

local function take(entry: any)
    if type(entry) ~= "table" or not entry.file then return end
    local doomed, list = {}, { entry }
    for _, old in g.untracked(function() return entries.value end) do
        if old.hash == entry.hash then table.insert(doomed, old.file) else table.insert(list, old) end
    end
    local keep = config.get("clipboard.history", 50)
    while #list > keep do table.insert(doomed, table.remove(list).file) end
    forget(doomed)
    save(list)
end

local function ask(...: string)
    local command = { paths.script("ipc"), "clipboard", ... }
    g.process { command = command }
end

function M.remove(entry: any)
    if not entry then return end
    if not g.untracked(function() return kept.value end) then
        ask("remove", tostring(entry.hash))
        return
    end
    local list = {}
    for _, e in g.untracked(function() return entries.value end) do
        if e.hash ~= entry.hash then table.insert(list, e) end
    end
    forget({ entry.file })
    save(list)
end

function M.clear()
    if not g.untracked(function() return kept.value end) then
        ask("clear")
        return
    end
    local files = {}
    for _, e in g.untracked(function() return entries.value end) do table.insert(files, e.file) end
    forget(files)
    save({})
end

-- One watcher for the life of the shell, dying with it; if it dies first
-- (the compositor restarted, say), it comes back.
local function watch()
    g.process {
        command = { "wl-paste", "--watch", paths.script("clip"), "store", M.directory },
        on_line = function(line: string)
            local ok, entry = pcall(g.parse_json, line)
            if ok then take(entry) end
        end,
        on_exit = function() g.after(3, watch) end,
    }
end

local started = false
function M.start()
    if started or not runtime.alone() then return end
    started = true
    -- What an earlier session kept, then this one's; a first run makes the
    -- directory private before anything is in it.
    kept.value = parsed(index.text)
    g.process {
        command = { "sh", "-c", 'mkdir -p "$1" && chmod 700 "$1"', "mkdir", M.directory },
        on_exit = function()
            watch()
            sweep_soon()
        end,
    }
end

return M
