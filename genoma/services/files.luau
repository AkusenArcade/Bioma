--!strict
-- Files in the home, found by name (services/Files.qml at 2cafc17).
--
-- No index of its own and none of the system's: plocate's daily database
-- leaves out `/home` wherever it is a subvolume of its own (it is on
-- Akusen's), and an index kept here would be memory spent all day for a few
-- searches. `fd` walks the home instead, every time: it skips what is
-- hidden and what a `.gitignore` excludes, and an `.ignore` or `.fdignore`
-- in the home tunes it further (Akusen's choice, 2026-10-04).
--
-- One search at a time. A newer query does not wait for the older one: the
-- older is stopped and what it had found is thrown away.
local g = require("@genoma")
local paths = require("core/paths")
local timing = require("core/timing")

local M = {}

local home = g.env("HOME") or ""

-- How many fd may hand back before it stops walking: the best are chosen
-- from these. How many are kept after ranking. Below `shortest` letters a
-- search over a whole home is a list of everything, and two letters and
-- Enter belong to applications.
local GATHERED = 300
local KEPT = 20
local SHORTEST = 3

local query = g.signal("")
local answered = g.signal("")
-- { path, name, folder, dir, at (characters, from 1), icon }, best first.
local results = g.signal({} :: { any })

local function words_of(text: string): { string }
    local out = {}
    for word in string.gmatch(string.lower(text), "%S+") do table.insert(out, word) end
    return if #table.concat(out, " ") >= SHORTEST then out else {}
end

function M.results(): { any } return results.value end
-- Between asking and the answer: a launcher that said "nothing" while fd
-- was still walking would say it too early.
function M.searching(): boolean
    return #words_of(query.value) > 0 and answered.value ~= query.value
end

-- The theme's own icon for the kind of file, by the name it ends in: only
-- the generic names every icon theme carries.
local KINDS: { [string]: string } = {}
for icon, list in {
    ["application-pdf"] = { "pdf" },
    ["image-x-generic"] = { "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tif", "tiff", "heic", "avif", "kra", "xcf", "psd" },
    ["audio-x-generic"] = { "mp3", "flac", "ogg", "opus", "wav", "m4a", "aac" },
    ["video-x-generic"] = { "mp4", "mkv", "webm", "mov", "avi" },
    ["package-x-generic"] = { "zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2" },
    ["x-office-document"] = { "odt", "doc", "docx", "rtf" },
    ["x-office-spreadsheet"] = { "ods", "xls", "xlsx", "csv" },
    ["x-office-presentation"] = { "odp", "ppt", "pptx" },
    ["text-html"] = { "html", "htm" },
    ["text-x-script"] = { "sh", "py", "fish" },
} do
    for _, ext in list do KINDS[ext] = icon end
end
local function icon_for(lowered: string, dir: boolean): string
    if dir then return "folder" end
    local ext = string.match(lowered, "%.([^.]+)$")
    return (ext and KINDS[ext]) or "text-x-generic"
end

-- fd says only that a name matches. The order here is the one a person
-- expects: the name that starts with what was typed, then the one where a
-- word does, then the nearest to the home.
local function describe(line: string, words: { string }): any
    local dir = string.sub(line, -1) == "/"
    local path = if dir then string.sub(line, 1, -2) else line
    local cut = string.match(path, "^.*()/") or 0
    local name = string.sub(path, cut + 1)
    local lowered = string.lower(name)

    local at, from, score = {}, 1, 0
    for _, word in words do
        local found = string.find(lowered, word, from, true)
        if not found then return nil end
        -- Counted in characters, as a text's marks are.
        local before = utf8.len(string.sub(lowered, 1, found - 1)) or (found - 1)
        for i = 1, utf8.len(word) or #word do table.insert(at, before + i) end
        if found == 1 then
            score += 8
        elseif string.find(string.sub(lowered, found - 1, found - 1), "[%s%._%-]") then
            score += 4
        end
        from = found + #word
    end

    local stem = if dir then lowered else (string.gsub(lowered, "%.[^.]+$", ""))
    if stem == table.concat(words, " ") then score += 10 end

    local below = #string.split(string.sub(path, #home + 1), "/") - 2
    score -= below * 0.75
    score -= #name * 0.02

    local folder = string.sub(path, 1, cut - 1)
    if string.sub(folder, 1, #home) == home then folder = "~" .. string.sub(folder, #home + 1) end
    return { path = path, name = name, folder = folder, dir = dir, at = at, icon = icon_for(lowered, dir), score = score }
end

local walking: any = nil
local settle: any = nil
local function stop_walking()
    if walking then walking:kill() end
    walking = nil
end

local function walk()
    stop_walking()
    local asked = g.untracked(function() return query.value end)
    local words = words_of(asked)
    if #words == 0 then return end
    -- The words in the order typed, each where it falls in the name.
    local parts = {}
    for _, w in words do table.insert(parts, (string.gsub(w, "[%.%*%+%?%^%$%{%}%(%)%|%[%]\\]", "\\%0"))) end
    local lines = {}
    walking = g.process {
        command = { "fd", "--color", "never", "--ignore-case", "--absolute-path",
            "--max-results", tostring(GATHERED), "--", table.concat(parts, ".*"), home },
        on_line = function(line: string) if line ~= "" then table.insert(lines, line) end end,
        on_exit = function()
            if g.untracked(function() return query.value end) ~= asked then return end
            local found = {}
            for _, line in lines do
                local entry = describe(line, words)
                if entry then table.insert(found, entry) end
            end
            table.sort(found, function(a: any, b: any)
                if a.score ~= b.score then return a.score > b.score end
                return a.name < b.name
            end)
            local kept = {}
            for i = 1, math.min(KEPT, #found) do kept[i] = found[i] end
            g.batch(function()
                results.value = kept
                answered.value = asked
            end)
            walking = nil
        end,
    }
end

-- A walk per keystroke would start and kill fd six times for one word.
function M.ask(text: string)
    query.value = text
    if settle then settle:stop() end
    settle = nil
    if #words_of(text) == 0 then
        stop_walking()
        g.batch(function()
            results.value = {}
            answered.value = text
        end)
        return
    end
    settle = g.after(timing.seconds.search, function()
        settle = nil
        walk()
    end)
end

-- Opened by whatever the desktop says opens it, started the way the
-- launcher starts an application: as a user service of its own.
function M.open(path: string, environment: { [string]: string }?)
    g.process { command = { paths.script("launch"), "--id", "xdg-open", "--", "xdg-open", path }, env = environment or {} }
end

-- Shown where it lives, selected, by whichever file manager answers the
-- freedesktop call; the folder opened plainly when none does. The path
-- travels as a URI inside a GVariant string literal, so every byte that
-- could end it is percent-encoded.
function M.reveal(path: string, environment: { [string]: string }?)
    local uri = "file://" .. string.gsub(path, "[^%w/%-%._~]", function(c: string)
        return string.format("%%%02X", string.byte(c))
    end)
    local folder = string.match(path, "^(.*)/[^/]*$") or "/"
    if folder == "" then folder = "/" end
    g.process {
        command = { "bash", "-c",
            "gdbus call --session --dest org.freedesktop.FileManager1 "
            .. "--object-path /org/freedesktop/FileManager1 "
            .. "--method org.freedesktop.FileManager1.ShowItems \"['$1']\" \"\" >/dev/null 2>&1 "
            .. "|| exec \"$2\" --id xdg-open -- xdg-open \"$3\"",
            "reveal", uri, paths.script("launch"), folder },
        env = environment or {},
    }
end

return M
