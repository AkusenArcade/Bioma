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
-- The entries are read at the load and again whenever a file comes into or
-- leaves one of the folders they are read from, so an application installed
-- since is in the launcher without a restart.
local g = require("@genoma")
local paths = require("core/paths")

local M = {}

-- The list itself is kept outside a signal, which does not take it; the
-- signal counts the readings, so a binding that reads the list follows it.
local entries = g.desktop_entries()
local read = g.signal(0)
function M.entries(): { any }
    local _ = read.value
    return entries
end

local cache: { [string]: any } = {}

-- The folders g.desktop_entries reads, in its order: the user's data
-- folder, then the system's.
local function application_folders(): { string }
    local home = g.env("HOME") or ""
    local data_home = g.env("XDG_DATA_HOME")
    local out = { (if data_home and data_home ~= "" then data_home else home .. "/.local/share") .. "/applications" }
    local system = g.env("XDG_DATA_DIRS")
    if not system or system == "" then system = "/usr/local/share:/usr/share" end
    for _, dir in string.split(system, ":") do
        if dir ~= "" then
            local folder = string.gsub(dir, "/$", "") .. "/applications"
            if not table.find(out, folder) then table.insert(out, folder) end
        end
    end
    return out
end

-- A package manager writes its files one after another: read once they
-- have stopped coming. A folder that does not exist yet is not followed.
-- The load's, whoever requires this first.
local first = true
local settle: any = nil
g.lasting(function()
    local folders = {}
    for _, path in application_folders() do table.insert(folders, g.folder { path = path }) end
    g.effect(function()
        for _, folder in folders do
            for _, e in folder.entries do local _ = e.name end
        end
        if first then
            first = false
            return
        end
        g.untracked(function()
            if settle then settle:stop() end
            settle = g.lasting(function()
                -- Required here: core/timing reaches back to this module
                -- (performance → workload → apps).
                return g.after(require("core/timing").seconds.debounce, function()
                    settle = nil
                    cache = {}
                    entries = g.desktop_entries()
                    read.value += 1
                end)
            end)
        end)
    end)
end)

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
    -- A Steam game's window is `steam_app_<id>`, and Steam writes the game a
    -- desktop file that starts `steam://rungameid/<id>`. Without this the
    -- search below found "steam" inside the name and drew Steam's logo on
    -- the game (Akusen, 2026-11-02).
    local game = string.match(wanted, "^steam_app_(%d+)$")
    if game then
        local url = "steam://rungameid/" .. game
        for _, e in entries do
            if table.find(M.command_of(e), url) then return e end
        end
        return nil
    end
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
-- The command an entry runs, its field codes gone; with `files` (paths),
-- %f and %u take the first and %F and %U them all, as the desktop entry
-- specification allows (a local file may be given as a path for a URL).
function M.command_of(entry: any, files: { string }?): { string }
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
        elseif files and #files > 0 and (w == "%f" or w == "%u") then
            table.insert(out, files[1])
        elseif files and (w == "%F" or w == "%U") then
            for _, f in files do table.insert(out, f) end
        elseif not string.match(w, "^%%[fFuUdDnNickvm]$") then
            table.insert(out, (string.gsub(w, "%%%%", "%%")))
        end
    end
    return out
end

-- The desktop's terminal, asked the way the freedesktop proposal asks it
-- (`xdg-terminal-exec`), else $TERMINAL, else the first of the usual ones;
-- each of those takes the command after `-e`.
local IN_TERMINAL = 'if command -v xdg-terminal-exec >/dev/null 2>&1; then exec xdg-terminal-exec "$@"; fi; '
    .. 'for t in "$TERMINAL" kitty alacritty foot ghostty wezterm konsole xterm; do '
    .. '[ -n "$t" ] && command -v "$t" >/dev/null 2>&1 && exec "$t" -e "$@"; done; '
    .. 'echo "no terminal for $1" >&2; exit 1'

-- Whether an entry opens files or links given to it (its Exec has %f, %F,
-- %u or %U): what a file dropped on its dock icon needs.
function M.takes_files(entry: any): boolean
    local exec = if entry then entry.exec or "" else ""
    return string.find(exec, "%%[fFuU]") ~= nil
end

-- Start an application, with whatever the shell adds to its environment
-- (the proxy, while one is on), and `files` for it to open. Not as the
-- shell's child: `scripts/launch` makes it a user service of its own, out
-- of the shell's scheduling and cgroup. One that runs in a terminal is
-- started inside the desktop's. Where Genoma gives activation tokens, the
-- press that asked gets one, and the application's window the focus (one
-- already running is raised).
function M.run(entry: any, environment: { [string]: string }?, files: { string }?)
    if not entry then return end
    local command = M.command_of(entry, files)
    if #command == 0 then return end
    local function start(token: string?)
        local launch = { paths.script("launch"), "--id", entry.id or "" }
        if entry.path and entry.path ~= "" then
            table.insert(launch, "--dir")
            table.insert(launch, entry.path)
        end
        if token then
            table.insert(launch, "--token")
            table.insert(launch, token)
        end
        table.insert(launch, "--")
        if entry.terminal then
            for _, w in { "bash", "-c", IN_TERMINAL, "terminal" } do table.insert(launch, w) end
        end
        for _, w in command do table.insert(launch, w) end
        g.process { command = launch, env = environment or {} }
    end
    local ask = (g :: any).activation_token
    if ask then
        ask { app_id = entry.id, on_token = start }
    else
        start(nil)
    end
end

return M
