--!strict
-- The wallpaper: which image, and how (services/Wallpaper.qml).
--
-- This owns the choice and the library; it draws nothing. The choice is
-- kept out of the configuration layers on purpose: the theme cell rewrites
-- it every time an image is tried, and that churn does not belong in a
-- file a human edits. It lives in `wallpaper.json`, which Bioma on
-- Quickshell watches too: until the switch (genoma/PORT.md, "Who acts on
-- the desktop") a choice made here is written there, and Quickshell is the
-- one that draws it and runs matugen on it.
--
-- Not yet: making thumbnails. The ones
-- Quickshell has made are read, by the same name; without one the image
-- itself is shown, which an image node fits off the frame anyway.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

local home = g.env("HOME") or ""
local config_home = g.env("XDG_CONFIG_HOME") or (home .. "/.config")
local cache_home = g.env("XDG_CACHE_HOME") or (home .. "/.cache")

-- fill (cover each monitor), fit (contain), span (one image over the box of
-- every monitor, each showing its part), per_monitor (an image each).
M.modes = { "fill", "fit", "span", "per_monitor" }

-- Written by a human, so it may carry a `~` or a `$HOME`.
function M.expand(candidate: string): string
    if candidate == "~" then return home end
    if string.sub(candidate, 1, 2) == "~/" then return home .. string.sub(candidate, 2) end
    if string.sub(candidate, 1, 5) == "$HOME" then return home .. string.sub(candidate, 6) end
    return candidate
end

-- ---- The choice -----------------------------------------------------------

M.state_path = config_home .. "/bioma/wallpaper.json"
local state_file = g.file { path = M.state_path }

local state = g.computed(function(): { [string]: any }
    local text = state_file.text
    local out = { path = "", mode = "fill", per_monitor = {}, loaded = true }
    if not text or string.match(text, "^%s*$") then return out end
    local ok, saved = pcall(g.parse_json, text)
    if not ok or type(saved) ~= "table" then
        print("Wallpaper: state file is not valid JSON")
        return out
    end
    if type(saved.path) == "string" then out.path = M.expand(saved.path) end
    if type(saved.mode) == "string" and table.find(M.modes, saved.mode) then out.mode = saved.mode end
    if type(saved.perMonitorPaths) == "table" then out.per_monitor = saved.perMonitorPaths end
    return out
end)

M.shipped_folder = paths.root .. "/assets/wallpapers"
-- Shown until an image is chosen, so a first session opens on a picture;
-- never written into the state.
M.fallback = M.shipped_folder .. "/bioma-forest.jpg"

function M.path(): string return state.value.path end
function M.mode(): string return state.value.mode end
function M.current(): string
    local p = state.value.path
    return if p ~= "" then p else M.fallback
end
function M.path_for(output: string): string
    local s = state.value
    if s.mode == "per_monitor" and type(s.per_monitor[output]) == "string" then return s.per_monitor[output] end
    return M.current()
end

local function save(path: string, mode: string, per_monitor: { [string]: string })
    local text = g.json_set("{}", {
        { "path", path },
        { "mode", mode },
        { "perMonitorPaths", per_monitor },
    })
    state_file:write(text)
end

-- The writes Quickshell reads: the image, the mode.
function M.set_path(path: string)
    local s = g.untracked(function() return state.value end)
    if s.path == path then return end
    save(path, s.mode, s.per_monitor)
end
function M.set_mode(mode: string)
    local s = g.untracked(function() return state.value end)
    if s.mode == mode or not table.find(M.modes, mode) then return end
    save(s.path, mode, s.per_monitor)
end

-- ---- The library ------------------------------------------------------------
--
-- Bioma's own images first, then the folder's, in name order, the favourites
-- before both: the ones somebody comes back to are at the top of the grid and
-- beside each other in the carousel.

function M.folder(): string return M.expand(config.get("wallpaper.folder", "$HOME/Pictures/Wallpapers")) end

local function images(list: { any }, extensions: { [string]: boolean }): { string }
    local out = {}
    for _, e in list do
        local ext = string.lower(string.match(e.name, "%.(%w+)$") or "")
        if not e.dir and extensions[ext] then table.insert(out, e.path) end
    end
    return out
end

local shipped_kinds = { jpg = true, jpeg = true, png = true, webp = true }
local folder_kinds = { jpg = true, jpeg = true, png = true, webp = true, bmp = true, avif = true }
local shipped = g.folder { path = M.shipped_folder }
-- The folder watched follows the configuration: what an effect makes, its
-- next run disposes, so the old watch goes with the old folder.
local library = g.signal({})
g.effect(function()
    local folder = g.folder { path = M.folder() }
    g.effect(function()
        local list = images(folder.entries, folder_kinds)
        g.untracked(function() library.value = list end)
    end)
end)

function M.favourites(): { string } return config.get("wallpaper.favourites", {}) end
function M.is_favourite(path: string): boolean return table.find(M.favourites(), path) ~= nil end

local entries = g.computed(function(): { string }
    local out = images(shipped.entries, shipped_kinds)
    -- A folder pointed at assets/wallpapers would offer each image twice.
    for _, p in library.value do
        if not table.find(out, p) then table.insert(out, p) end
    end
    local liked, rest = {}, {}
    for _, p in out do
        table.insert(if M.is_favourite(p) then liked else rest, p)
    end
    for _, p in rest do table.insert(liked, p) end
    return liked
end)

function M.entries(): { string } return entries.value end
-- Of what is on screen, the fallback included: it is in the list.
function M.index(): number return table.find(entries.value, M.current()) or 0 end

-- The carousel's whole interaction, and it wraps: a folder of wallpapers has
-- no first and no last.
function M.step(delta: number)
    local list = g.untracked(M.entries)
    if #list == 0 then return end
    local from = g.untracked(M.index)
    if from == 0 then from = 1 end
    M.set_path(list[(from - 1 + delta) % #list + 1])
end

-- The image `offset` places along from the current one.
function M.neighbour(offset: number): string
    local list = entries.value
    if #list == 0 then return "" end
    if #list == 1 then return if offset == 0 then list[1] else "" end
    local from = M.index()
    if from == 0 then from = 1 end
    return list[(from - 1 + offset) % #list + 1]
end

function M.favour(path: string, on: boolean)
    if path == "" or on == g.untracked(function() return M.is_favourite(path) end) then return end
    local now = g.untracked(M.favourites)
    local next_list = {}
    for _, p in now do
        if p ~= path then table.insert(next_list, p) end
    end
    if on then table.insert(next_list, path) end
    config.set("wallpaper.favourites", next_list)
end

-- ---- The folder ---------------------------------------------------------------
--
-- Chosen in a GTK folder picker rather than typed: a path is found by
-- looking, and a picker cannot return a folder that is not there. Written
-- the short way, `~/…`. `folder_error` names what went wrong.

local folder_error = g.signal("")
local picking = g.signal(false)
function M.folder_error(): string return folder_error.value end
function M.picking(): boolean return picking.value end

function M.set_folder(path: string)
    local wanted = string.gsub(path, "^%s+", "")
    wanted = string.gsub(wanted, "%s+$", "")
    while #wanted > 1 and string.sub(wanted, -1) == "/" do wanted = string.sub(wanted, 1, -2) end
    if string.sub(wanted, 1, 1) ~= "/" then return end
    if home ~= "" and (wanted == home or string.sub(wanted, 1, #home + 1) == home .. "/") then
        wanted = "~" .. string.sub(wanted, #home + 1)
    end
    config.set("wallpaper.folder", wanted)
end

function M.pick_folder()
    if g.untracked(function() return picking.value end) then return end
    folder_error.value = ""
    picking.value = true
    local chosen = ""
    -- 127 is the shell's answer for a command it cannot find, told apart
    -- from a picker that was cancelled (1).
    g.process {
        command = { "sh", "-c", 'command -v zenity >/dev/null || exit 127; '
            .. 'exec zenity --file-selection --directory --title="Wallpaper folder" --filename="$1/"',
            "sh", g.untracked(M.folder) },
        on_line = function(line: string) chosen = line end,
        on_exit = function(code: number)
            picking.value = false
            if code == 0 then M.set_folder(chosen)
            elseif code == 127 then folder_error.value = "ZENITY MISSING" end
        end,
    }
end

-- ---- Thumbnails ---------------------------------------------------------------
--
-- Quickshell's names: FNV-1a over the path's UTF-16 code units, in base 36,
-- so the cache it made serves both.

local function fingerprint(text: string): string
    local hash = 0x811c9dc5
    local function mix(unit: number)
        hash = bit32.bxor(hash, unit)
        -- × 0x01000193 is × 2^24 + × 0x193, each exact in a double.
        hash = (hash * 0x193 + bit32.lshift(hash, 24)) % 4294967296
    end
    for _, code in utf8.codes(text) do
        if code >= 0x10000 then
            local v = code - 0x10000
            mix(0xD800 + bit32.rshift(v, 10))
            mix(0xDC00 + bit32.band(v, 0x3FF))
        else
            mix(code)
        end
    end
    local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    if hash == 0 then return "0" end
    local out = ""
    while hash > 0 do
        local d = hash % 36
        out = string.sub(digits, d + 1, d + 1) .. out
        hash = hash // 36
    end
    return out
end
M.fingerprint = fingerprint

M.cache_folder = cache_home .. "/bioma/thumbnails"
local cache = g.folder { path = M.cache_folder }
local cached = g.computed(function(): { [string]: boolean }
    local out = {}
    for _, e in cache.entries do out[e.name] = true end
    return out
end)

-- The thumbnail where Quickshell made one, the image itself where not.
function M.thumbnail(path: string): string
    if path == "" or not config.get("wallpaper.thumbnails", true) then return path end
    local name = fingerprint(path) .. ".jpg"
    return if cached.value[name] then M.cache_folder .. "/" .. name else path
end

return M
