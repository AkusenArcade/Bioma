--!strict
-- What both launchers know: the applications and how a query finds them,
-- what a result is called, and what launching one does. The simple
-- launcher (cells/launcher.luau) lists the results; the organic one
-- (cells/launcher_organic.luau) gathers them into clusters round its field.
-- One search, so the two always answer the same thing.
local g = require("@genoma")
local config = require("core/config")
local apps = require("core/apps")
local files = require("services/files")
local calculator = require("services/calculator")
local proxy = require("services/proxy")

local M = {}

function M.letters_of(s: string): { string }
    local out = {}
    local ok = pcall(function()
        for _, code in utf8.codes(s) do table.insert(out, utf8.char(code)) end
    end)
    if not ok then
        out = {}
        for i = 1, #s do table.insert(out, string.sub(s, i, i)) end
    end
    return out
end

-- The applications, with their names already split into lower-case
-- letters: the search runs over them on every key.
local entries = {}
for _, e in apps.entries() do
    local name = if e.name ~= "" then e.name else e.id
    table.insert(entries, { entry = e, name = name, letters = M.letters_of(string.lower(name)) })
end

-- A subsequence match, and it says **where** it matched: the letters the
-- search found are coloured in the result, the one place in this shell
-- where colour enters a word. It shows the reasoning, so a wrong answer is
-- visibly wrong rather than broken. A run of letters together, and a match
-- at the start of a word, are worth more than the same letters scattered.
function M.match(letters: { string }, wanted: { string }): (boolean, { number }, number)
    if #wanted == 0 then return true, {}, 0 end
    local at, index, run, score = {}, 1, 0, 0
    for _, letter in wanted do
        local found = nil
        for i = index, #letters do
            if letters[i] == letter then
                found = i
                break
            end
        end
        if not found then return false, {}, 0 end
        run = if found == index then run + 1 else 0
        score += run * 2 + (if found == 1 or letters[found - 1] == " " then 3 else 0)
        table.insert(at, found)
        index = found + 1
    end
    return true, at, score
end

-- How often each application was launched from here, by desktop id.
function M.uses(): { [string]: number }
    local u = config.get("launcher.uses", {})
    return if type(u) == "table" then u else {}
end

-- The freedesktop main categories an application may name, and the word
-- the organic launcher gathers it under. The first main category in its
-- list decides; an application that names none is OTHER.
local MAIN = {
    AudioVideo = "media", Audio = "media", Video = "media",
    Development = "development", Education = "science", Science = "science",
    Game = "games", Graphics = "graphics", Network = "internet",
    Office = "office", Settings = "system", System = "system", Utility = "utilities",
}
M.group_labels = {
    media = "MEDIA", development = "DEVELOPMENT", science = "SCIENCE", games = "GAMES",
    graphics = "GRAPHICS", internet = "INTERNET", office = "OFFICE", system = "SYSTEM",
    utilities = "UTILITIES", other = "OTHER", files = "FILES", sum = "CALCULATOR",
}
function M.group_of(entry: any): string
    for _, c in entry.categories or {} do
        local main = MAIN[tostring(c)]
        if main then return main end
    end
    return "other"
end

-- The applications answering `wanted`, best first: by how well they
-- match, then by how often they were launched, then by name. At most `cap`.
function M.applications(wanted: { string }, cap: number): { any }
    local counts = M.uses()
    local out = {}
    for _, item in entries do
        local hit, at, score = M.match(item.letters, wanted)
        if hit then
            local categories = item.entry.categories or {}
            table.insert(out, {
                kind = "app",
                group = "",
                entry = item.entry,
                name = item.name,
                at = at,
                icon = item.entry.icon or "",
                detail = if #categories > 0 then string.upper(tostring(categories[1])) else "",
                score = score,
                used = counts[item.entry.id] or 0,
            })
        end
    end
    table.sort(out, function(a: any, b: any)
        if #wanted > 0 and a.score ~= b.score then return a.score > b.score end
        if a.used ~= b.used then return a.used > b.used end
        return string.lower(a.name) < string.lower(b.name)
    end)
    local kept = {}
    for i = 1, math.min(cap, #out) do kept[i] = out[i] end
    return kept
end

-- A result's identity, stable while it stays among the results.
function M.key_of(r: any): string
    if r.kind == "file" then return "file:" .. r.file.path end
    if r.kind == "app" then return "app:" .. r.entry.id end
    return r.kind
end

-- A sum is copied; a file is opened by whatever opens it, or with `reveal`
-- shown where it lives; an application is run and counted.
function M.launch(r: any, reveal: boolean)
    local environment = g.untracked(proxy.environment)
    if r.kind == "sum" then
        calculator.copy()
    elseif r.kind == "file" then
        if reveal then files.reveal(r.file.path, environment) else files.open(r.file.path, environment) end
    else
        local counted = table.clone(g.untracked(M.uses))
        counted[r.entry.id] = (counted[r.entry.id] or 0) + 1
        config.set("launcher.uses", counted)
        apps.run(r.entry, environment)
    end
end

return M
