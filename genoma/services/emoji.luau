--!strict
-- Emoji: the set, searching it, and sending one where the keyboard points
-- (services/Emoji.qml at 11bb81e). The set is assets/emoji/emoji.json,
-- read the first time it is wanted; the text goes through `scripts/paste`,
-- as dictation's does, left on the clipboard when nothing can take it.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local timing = require("core/timing")
local niri = require("services/niri")
local dictation = require("services/dictation")

local M = {}

local wanted = g.signal(false)
local data = g.signal({ loaded = false, groups = {}, all = {}, by_character = {} } :: { [string]: any })

function M.want() wanted.value = true end

g.effect(function()
    if not wanted.value then return end
    g.untracked(function()
        local file = g.file { path = paths.root .. "/assets/emoji/emoji.json" }
        g.effect(function()
            local text = file.text
            if not text then return end
            local ok, parsed = pcall(g.parse_json, text)
            if not ok or type(parsed) ~= "table" then
                print("Emoji: the set does not parse")
                return
            end
            local rows, index = {}, {}
            for _, row in parsed.emoji do
                local name = row[2]
                local name_words = {}
                for w in string.gmatch(string.lower(name), "[%w\128-\255'+#*%-]+") do table.insert(name_words, w) end
                local key_words = {}
                for w in string.gmatch(row[3] or "", "%S+") do table.insert(key_words, w) end
                local entry = { character = row[1], name = name, group = row[4], tones = row[5],
                    name_words = name_words, key_words = key_words }
                table.insert(rows, entry)
                index[entry.character] = #rows
            end
            g.untracked(function()
                data.value = { loaded = true, groups = parsed.groups, all = rows, by_character = index }
            end)
            print("Emoji: " .. #rows .. " emoji, Unicode " .. tostring(parsed.version))
        end)
    end)
end)

function M.loaded(): boolean return data.value.loaded end
function M.groups(): { string } return data.value.groups end
function M.all(): { any } return data.value.all end

function M.tone(): number return math.clamp(config.get("emoji.tone", 0), 0, 5) end
function M.set_tone(value: number) config.set("emoji.tone", math.clamp(value, 0, 5)) end
function M.shown(entry: any): string
    local t = M.tone()
    if t > 0 and type(entry.tones) == "table" and entry.tones[t] then return entry.tones[t] end
    return entry.character
end

local function recent_count(): number return config.get("emoji.recent_count", 20) end
function M.recent_entries(): { any }
    local d = data.value
    local out = {}
    for _, c in config.get("emoji.recent", {}) do
        local at = d.by_character[c]
        if at then table.insert(out, d.all[at]) end
    end
    return out
end
local function remember(entry: any)
    local next = g.array({ entry.character })
    for _, c in g.untracked(function() return config.get("emoji.recent", {}) end) do
        if c ~= entry.character and #next < g.untracked(recent_count) then table.insert(next, c) end
    end
    config.set("emoji.recent", next)
end

-- Every term must be found: a whole name word scores most, the start of
-- one less, a keyword less again; shorter names and recent use rank up.
function M.search(query: string): { any }
    local terms = {}
    for t in string.gmatch(string.lower(query), "%S+") do table.insert(terms, t) end
    if #terms == 0 then return {} end
    local lately = {}
    local n = recent_count()
    for i, c in config.get("emoji.recent", {}) do lately[c] = 3 * (1 - (i - 1) / n) end
    local found = {}
    for i, entry in data.value.all do
        local score, missed = 0, false
        for _, term in terms do
            local best = 0
            for _, w in entry.name_words do
                if w == term then best = 8 break end
                if best < 4 and string.sub(w, 1, #term) == term then best = 4 end
            end
            if best < 5 then
                for _, w in entry.key_words do
                    if w == term then best = 5 break end
                    if best < 2 and string.sub(w, 1, #term) == term then best = 2 end
                end
            end
            if best == 0 then missed = true break end
            score += best
        end
        if not missed then
            score -= math.max(0, #entry.name_words - #terms) * 0.5
            score += lately[entry.character] or 0
            table.insert(found, { entry = entry, score = score, order = i })
        end
    end
    table.sort(found, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    local out = {}
    for _, f in found do table.insert(out, f.entry) end
    return out
end

-- ---- Sending -------------------------------------------------------------------
--
-- The paster runs while the cell is open, so it is ready when the choice
-- comes; the text is handed over once the cell has closed and the focus
-- is back with the window it is for.
local paster: any = nil
local can_paste = false
local in_flight = false
local held_open = false

local function stop()
    if paster and not in_flight and not held_open then
        local p = paster
        paster = nil
        p:stop()
    end
end

function M.ready(on: boolean)
    held_open = on
    if on and not paster then
        can_paste = false
        paster = g.process {
            command = { paths.script("paste") },
            on_line = function(line: string)
                if line == "ready" then
                    can_paste = true
                elseif line == "no-uinput" then
                    can_paste = false
                    print("Emoji: /dev/uinput is not writable; the emoji will be left on the clipboard")
                elseif line == "pasted" or line == "copied" then
                    in_flight = false
                    stop()
                end
            end,
            on_exit = function()
                paster = nil
                in_flight = false
            end,
        }
    else
        stop()
    end
end

function M.send(entry: any)
    if not entry then return end
    remember(entry)
    local text = g.untracked(function() return M.shown(entry) end)
    in_flight = true
    if not paster then M.ready(true) end
    g.after(timing.seconds.close, function()
        local p = paster
        if not p then
            in_flight = false
            return
        end
        local window = g.untracked(niri.focused_window)
        p:write(g.to_json({
            text = text,
            terminal = dictation.is_terminal(g.untracked(niri.focused_app_id)),
            copyOnly = window == nil or not can_paste,
        }) .. "\n")
    end)
end

return M
