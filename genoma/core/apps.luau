--!strict
-- Which application a name belongs to (core/Apps.qml).
--
-- Two callers need this and neither gets a clean answer from the system: a
-- compositor reports an `app_id` that may be a class name, and `ps` an
-- executable cut to fifteen characters (`xwayland-satell`, `steamwebhelp`,
-- `zen-bin`). So: the obvious lookups first, then the obvious variants,
-- then a look through the desktop files for one that recognises the name.
-- Answers are cached, misses included, because the process list asks the
-- same sixty questions every few seconds.
--
-- The entries are read at the load; an application installed since is
-- found at the next one.
local g = require("@genoma")
local paths = require("core/paths")

local M = {}

local entries = g.desktop_entries()
function M.entries(): { any } return entries end

local cache: { [string]: any } = {}

-- Wrappers and packaging leave these behind.
local function normalise(name: string): string
    local out = string.lower(name or "")
    for _, suffix in { "%.exe$", "%.bin$", "%.sh$", "%.py$" } do out = string.gsub(out, suffix, "") end
    for _, suffix in { "bin", "wrapped", "real", "desktop", "gtk", "qt", "electron" } do
        out = string.gsub(out, "[-_]" .. suffix .. "$", "")
    end
    return out
end

-- Quickshell's heuristicLookup: the id, the reverse-DNS id's last part, the
-- window class, the name, compared without case.
local function heuristic(name: string): any
    local wanted = string.lower(name)
    for _, e in entries do
        local id = string.lower(e.id)
        if id == wanted or string.sub(id, -(#wanted + 1)) == "." .. wanted then return e end
    end
    for _, e in entries do
        if string.lower(e.startup_class) == wanted then return e end
    end
    for _, e in entries do
        if string.lower(e.name) == wanted then return e end
    end
    return nil
end

local function search(name: string): any
    local wanted = normalise(name)
    if #wanted < 2 then return nil end
    local direct = heuristic(name) or heuristic(wanted)
    if direct then return direct end
    -- A cut executable is a prefix of the real thing, so the match goes both
    -- ways, but never on a fragment short enough to match half the menu: a
    -- short label inside a longer name (Vim in nvim) is somebody else's icon.
    for _, e in entries do
        local id, label, startup = string.lower(e.id), string.lower(e.name), string.lower(e.startup_class)
        if id == wanted or label == wanted or startup == wanted then return e end
        if #wanted >= 4 and (string.find(id, wanted, 1, true) or string.find(startup, wanted, 1, true)
            or string.find(label, wanted, 1, true) or (#label >= 4 and string.find(wanted, label, 1, true))) then
            return e
        end
    end
    return nil
end

function M.entry_for(name: string?): any
    if not name or name == "" then return nil end
    local found = cache[name]
    if found == nil then
        found = search(name) or false
        cache[name] = found
    end
    return found or nil
end

-- The file to draw, or "" when nothing answers: the caller then draws the
-- neutral glyph rather than somebody else's logo.
function M.icon_for(name: string?): string
    local entry = M.entry_for(name)
    if not entry or entry.icon == "" then return "" end
    return g.icon_path(entry.icon) or ""
end

-- `Exec=` as words: quoting undone, field codes (%f, %U, …) dropped.
function M.command_of(entry: any): { string }
    local words, word, quoted, i = {}, {}, false, 1
    local exec = entry.exec or ""
    while i <= #exec do
        local c = string.sub(exec, i, i)
        if c == '"' then
            quoted = not quoted
        elseif c == "\\" and quoted and i < #exec then
            i += 1
            table.insert(word, string.sub(exec, i, i))
        elseif c == " " and not quoted then
            if #word > 0 then
                table.insert(words, table.concat(word))
                word = {}
            end
        else
            table.insert(word, c)
        end
        i += 1
    end
    if #word > 0 then table.insert(words, table.concat(word)) end
    local out = {}
    for _, w in words do
        if w == "%%" then
            table.insert(out, "%")
        elseif not string.match(w, "^%%[fFuUdDnNickvm]$") then
            table.insert(out, (string.gsub(w, "%%%%", "%%")))
        end
    end
    return out
end

-- Start an application, with whatever the shell adds to its environment
-- (the proxy, while one is on). Not as the shell's child: `scripts/launch`
-- makes it a user service of its own, out of the shell's scheduling and
-- cgroup. One that runs in a terminal is started by the terminal the
-- launcher service knows, which comes with it.
function M.run(entry: any, environment: { [string]: string }?)
    if not entry then return end
    if entry.terminal then
        print("apps: " .. entry.id .. " runs in a terminal, which comes with the launcher")
        return
    end
    local command = M.command_of(entry)
    if #command == 0 then return end
    local launch = { paths.script("launch"), "--id", entry.id or "" }
    if entry.path and entry.path ~= "" then
        table.insert(launch, "--dir")
        table.insert(launch, entry.path)
    end
    table.insert(launch, "--")
    for _, w in command do table.insert(launch, w) end
    g.process { command = launch, env = environment or {} }
end

return M
