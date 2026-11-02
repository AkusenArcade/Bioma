--!strict
-- The files used lately (services/Recent.qml at 2cafc17): the desktop's own
-- record of them, ~/.local/share/recently-used.xbel, which GTK and Qt
-- applications and file managers keep. Read while something holds it, read
-- again when it changes; directories left out, and what no longer exists.
local g = require("@genoma")

local M = {}

local KEPT = 60
local data = g.env("XDG_DATA_HOME") or ((g.env("HOME") or "") .. "/.local/share")
local PATH = data .. "/recently-used.xbel"

local holders = g.signal(0)
function M.hold(on: boolean)
    holders.value = math.max(0, g.untracked(function() return holders.value end) + (if on then 1 else -1))
end

local files = g.signal({} :: { any })
local loaded = g.signal(false)
function M.files(): { any } return files.value end
function M.loaded(): boolean return loaded.value end

local function entities(text: string): string
    text = string.gsub(text, "&quot;", "\"")
    text = string.gsub(text, "&apos;", "'")
    text = string.gsub(text, "&lt;", "<")
    text = string.gsub(text, "&gt;", ">")
    text = string.gsub(text, "&amp;", "&")
    return text
end
local function decode(s: string): string
    return (string.gsub(s, "%%(%x%x)", function(h: string) return string.char(tonumber(h, 16) :: number) end))
end
-- An ISO 8601 stamp, as UTC seconds.
local function stamp(s: string): number
    local y, mo, d, h, mi, se = string.match(s, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return 0 end
    local t = os.time({ year = tonumber(y) :: number, month = tonumber(mo) :: number, day = tonumber(d) :: number,
        hour = tonumber(h) :: number, min = tonumber(mi) :: number, sec = tonumber(se) :: number })
    -- os.time read the table as local time: the stamp is UTC.
    local offset = os.time(os.date("*t", t) :: any) - os.time(os.date("!*t", t) :: any)
    return t + offset
end

local checking = false
local queued: { any }? = nil
local function check(candidates: { any })
    if checking then
        queued = candidates
        return
    end
    if #candidates == 0 then
        g.batch(function()
            files.value = {}
            loaded.value = true
        end)
        return
    end
    checking = true
    local command = { "sh", "-c", "for f; do [ -e \"$f\" ] && printf '%s\\n' \"$f\"; done", "check" }
    for _, c in candidates do table.insert(command, c.path) end
    local there = {}
    g.process {
        command = command,
        on_line = function(line: string) there[line] = true end,
        on_exit = function()
            checking = false
            local out = {}
            for _, c in candidates do if there[c.path] then table.insert(out, c) end end
            g.batch(function()
                files.value = out
                loaded.value = true
            end)
            if queued then
                local next = queued
                queued = nil
                check(next)
            end
        end,
    }
end

local function read(text: string?)
    if not text then
        g.batch(function()
            files.value = {}
            loaded.value = true
        end)
        return
    end
    local found = {}
    for chunk in string.gmatch(text, "<bookmark (.-)</bookmark>") do
        local href = string.match(chunk, 'href="([^"]*)"')
        local mime = string.match(chunk, 'mime%-type type="([^"]*)"') or ""
        if href and string.sub(href, 1, 7) == "file://" and mime ~= "inode/directory" then
            local head = string.match(chunk, "^[^>]*") or ""
            local at = 0
            for _, key in { "added", "modified", "visited" } do
                local s = string.match(head, key .. '="([^"]*)"')
                if s then at = math.max(at, stamp(s)) end
            end
            local path = decode(string.sub(entities(href), 8))
            table.insert(found, { path = path, name = string.match(path, "([^/]+)$") or path, mime = mime, at = at })
        end
    end
    table.sort(found, function(a: any, b: any) return a.at > b.at end)
    local kept = {}
    for i = 1, math.min(KEPT, #found) do kept[i] = found[i] end
    check(kept)
end

local reader: any = nil
g.effect(function()
    if holders.value <= 0 then return end
    g.untracked(function()
        if not reader then reader = g.file { path = PATH } end
    end)
    local text = reader.text
    g.untracked(function() read(text) end)
end)

return M
