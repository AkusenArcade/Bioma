--!strict
-- What is on the calendar (services/Calendar.qml).
--
-- Two kinds of source, both added from the clock cell: the calendars of an
-- account in GNOME Online Accounts, found over CalDAV (or Microsoft Graph),
-- and an iCalendar address, pasted, kept in the keyring because a secret
-- address is a password. The configuration keeps only what to call them:
--
--   "calendar": {
--       "sources": [{ "goa": "account_…", "href": "https://…/events/", "name": "Family" },
--                   { "id": "…", "name": "Personal" }],
--       "days": 62,
--       "minutes": 15
--   }
--
-- The reading is `scripts/calendar`'s: unfolding, time zones and
-- recurrences are dateutil's work. It runs at the start, every `minutes`, at
-- midnight and when the sources change, through the proxy when one is on,
-- whenever a source is set: what shows the next appointment has to know
-- there is one before it can appear.
--
-- Times are milliseconds since the epoch, as the script gives them.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local proxy = require("services/proxy")

local M = {}

local script = paths.script("calendar")

-- ---- Where ------------------------------------------------------------------------

local function usable(source: any): boolean
    if type(source) ~= "table" then return false end
    if type(source.id) == "string" and #source.id > 0 then return true end
    if type(source.url) == "string" and string.match(source.url, "%S") then return true end
    return type(source.goa) == "string" and type(source.href) == "string"
end

function M.sources(): { any }
    local out = {}
    for _, source in config.get("calendar.sources", {}) or {} do
        if usable(source) then table.insert(out, source) end
    end
    return out
end
function M.active(): boolean return #M.sources() > 0 end

-- How far ahead, from today: the clock's month and the next one.
function M.days(): number return math.max(1, config.get("calendar.days", 62)) end
local function every(): number return math.max(1, config.get("calendar.minutes", 15)) * 60 end

-- ---- Days -------------------------------------------------------------------------

-- The minute the answers below are judged by, aligned to the minute: an
-- appointment at ten is "now" at ten.
local now = g.signal(os.time() * 1000)

-- Luau's os.time reads a table as UTC, so a local wall-clock time is
-- turned into a moment through the offset in force then: asked twice,
-- since the offset at the guess may differ from the one now (summer time).
local function offset_at(seconds: number): number
    return os.time(os.date("*t", seconds) :: any) - seconds
end
local function local_time(fields: { [string]: number }): number
    local wall = os.time(fields :: any)
    local guess = wall - offset_at(wall)
    return wall - offset_at(guess)
end

-- Local midnight of a date, in milliseconds: the month's grid is built
-- from these.
function M.midnight(year: number, month: number, day: number): number
    return local_time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 }) * 1000
end

-- Midnight of the day `ms` falls in, moved by `offset` days. Days, not
-- 24-hour steps: a day with a change of summer time is 23 or 25 hours.
function M.day_start(ms: number, offset: number?): number
    local t = os.date("*t", ms // 1000) :: any
    return local_time({ year = t.year, month = t.month, day = t.day + (offset or 0), hour = 0, min = 0, sec = 0 }) * 1000
end

function M.now(): number return now.value end
-- Changes once a day, however often the minute does.
local today_start = g.computed(function(): number return M.day_start(now.value) end)
function M.today_start(): number return today_start.value end
function M.today_end(): number return M.day_start(today_start.value, 1) end

-- And how far back: to the Monday the clock's month starts its grid on, so
-- the days of this month already gone still show what they held.
local function back(): number
    local today = os.date("*t", M.today_start() // 1000) :: any
    local first = os.date("!*t", os.time({ year = today.year, month = today.month, day = 1, hour = 12 })) :: any
    local lead = (first.wday - 2) % 7 -- wday: Sunday is 1
    return today.day - 1 + lead
end

-- ---- What -------------------------------------------------------------------------

-- [{ uid, calendar, title, location, start, end, allDay }], sorted by start:
-- everything overlapping the window, what began before it and is still on
-- included.
local events = g.signal({})
local problems = g.signal({})
-- When the events were last read; 0 before the first time.
local read_at = g.signal(0)

function M.events(): { any } return events.value end
function M.read_at(): number return read_at.value end
-- [{ index, calendar, message }]: a source that could not be read, by its
-- place in `sources` counted from 0, as the script gives it (-1 for the
-- reading as a whole). Its last copy is used when there is one.
function M.problems(): { any } return problems.value end
function M.problem(): string
    local out = {}
    for _, p in problems.value do table.insert(out, p.message) end
    return table.concat(out, " ")
end
-- What is wrong with source `index`, counted from 1 as M.sources() is.
function M.trouble_of(index: number): string
    for _, p in problems.value do
        if p.index == index - 1 then return p.message end
    end
    return ""
end

-- Events that overlap [from, to).
function M.between(from: number, to: number): { any }
    local out = {}
    for _, e in events.value do
        if e.start < to and (e["end"] > from or (e["end"] == e.start and e.start >= from)) then table.insert(out, e) end
    end
    return out
end

-- Timed events going on right now: an all-day one is a day's context, not
-- something happening at this minute.
function M.ongoing(): { any }
    local t, out = now.value, {}
    for _, e in events.value do
        if not e.allDay and e.start <= t and t < e["end"] then table.insert(out, e) end
    end
    return out
end

-- The next timed event to begin, or nil.
function M.next(): any
    local t = now.value
    for _, e in events.value do
        if not e.allDay and e.start > t then return e end
    end
    return nil
end

-- Today, all-day first, as the events are sorted.
function M.today(): { any } return M.between(M.today_start(), M.today_end()) end

-- The timed events that begin within the next `minutes`.
function M.starting_within(minutes: number): { any }
    local t = now.value
    local limit = t + minutes * 60000
    local out = {}
    for _, e in events.value do
        if not e.allDay and e.start > t and e.start <= limit then table.insert(out, e) end
    end
    return out
end

-- ---- Reading ----------------------------------------------------------------------

local function failure(errors: string): string
    return if string.find(errors, "No module named 'dateutil'", 1, true) then "The calendar needs python-dateutil."
        else "The calendar could not be read."
end

local function merged(a: { [string]: string }, b: { [string]: string }): { [string]: string }
    local out = table.clone(a)
    for k, v in b do out[k] = v end
    return out
end

local reading = false
local again = false

local function read(text: string)
    if text == "" then return end
    local ok, answer = pcall(g.parse_json, text)
    if not ok or type(answer) ~= "table" then
        problems.value = { { index = -1, calendar = "", message = "The calendar could not be read." } }
        return
    end
    g.batch(function()
        events.value = answer.events or {}
        problems.value = answer.problems or {}
        read_at.value = os.time() * 1000
        now.value = os.time() * 1000
    end)
end

local function refresh()
    if not g.untracked(M.active) then return end
    -- Asked again while a reading runs, it reads once more when that one
    -- ends, so the last change of sources is never lost to a busy reader.
    if reading then
        again = true
        return
    end
    reading = true
    local out, errors = {}, {}
    g.process {
        command = { script, "read", tostring(g.untracked(M.days)), tostring(g.untracked(back)) },
        -- The sources travel in the environment, not on the command line,
        -- which every user can read (`ps`).
        env = merged(g.untracked(proxy.environment), { BIOMA_CALENDAR_SOURCES = g.to_json(g.untracked(M.sources)) }),
        on_line = function(line: string) table.insert(out, line) end,
        on_error_line = function(line: string) table.insert(errors, line) end,
        on_exit = function(code: number)
            reading = false
            if code ~= 0 then
                problems.value = { { index = -1, calendar = "", message = failure(table.concat(errors, "\n")) } }
            else
                read(table.concat(out, "\n"))
            end
            if again then
                again = false
                refresh()
            end
        end,
    }
end
M.refresh = refresh

-- Every `minutes`, while there is a source; the first reading at once.
g.effect(function()
    if not M.active() then return end
    local seconds = every()
    g.untracked(refresh)
    g.timer { every = seconds, on_tick = refresh }
end)

-- By value: the list is rebuilt whenever the configuration is, and an
-- unrelated setting is no reason to read the calendars again.
local signature = g.computed(function(): string return g.to_json(M.sources()) end)
local last_signature = g.untracked(function() return signature.value end)
g.watch(function() return signature.value end, function(now_signature: string)
    if now_signature == last_signature then return end
    last_signature = now_signature
    if not g.untracked(M.active) then
        g.batch(function()
            events.value = {}
            read_at.value = 0
            problems.value = {}
        end)
    elseif reading or g.untracked(function() return read_at.value end) > 0 then
        refresh()
    end
end)

-- The minute, while there is a source; past midnight one more day is read.
local minute: any = nil
local function next_minute()
    minute = g.after(60 - os.time() % 60 + 0.05, function()
        now.value = os.time() * 1000
        next_minute()
    end)
end
g.effect(function()
    if minute then
        minute:stop()
        minute = nil
    end
    if M.active() then next_minute() end
end)

local last_day = g.untracked(M.today_start)
g.watch(M.today_start, function(day: number)
    if day == last_day then return end
    last_day = day
    if g.untracked(function() return read_at.value end) > 0 then refresh() end
end)

-- ---- Adding and forgetting ----------------------------------------------------------

local checking = g.signal(false)
local add_problem = g.signal("")
local added_listeners: { (string) -> () } = {}

-- While a pasted address is being read.
function M.checking(): boolean return checking.value end
-- Why the last address pasted was not taken, in a sentence.
function M.add_problem(): string return add_problem.value end
-- A calendar was taken, under the name it gave itself.
function M.on_added(f: (string) -> ()) table.insert(added_listeners, f) end

local function taken(text: string)
    if text == "" then return end
    local ok, answer = pcall(g.parse_json, text)
    if not ok or type(answer) ~= "table" then
        add_problem.value = "The calendar could not be read."
        return
    end
    if answer.error then
        add_problem.value = answer.error
        return
    end
    local sources = table.clone(g.untracked(M.sources))
    table.insert(sources, answer.source)
    config.set("calendar.sources", sources)
    for _, f in added_listeners do f(answer.source.name) end
end

function M.add(address: string)
    local wanted = string.match(address or "", "^%s*(.-)%s*$") or ""
    if wanted == "" or g.untracked(function() return checking.value end) then return end
    add_problem.value = ""
    checking.value = true
    local out, errors = {}, {}
    local p = g.process {
        command = { script, "add" },
        env = g.untracked(proxy.environment),
        on_line = function(line: string) table.insert(out, line) end,
        on_error_line = function(line: string) table.insert(errors, line) end,
        on_exit = function(code: number)
            checking.value = false
            if code ~= 0 then
                add_problem.value = failure(table.concat(errors, "\n"))
            else
                taken(table.concat(out, "\n"))
            end
        end,
    }
    -- The address goes in on stdin and is not held here afterwards.
    p:write(wanted)
    p:close_input()
end

-- ---- The accounts in GNOME Online Accounts ---------------------------------------

-- [{ goa, identity, provider, calendars = [{ href, name }], problem? }].
local accounts = g.signal({})
local accounts_present = g.signal(false)
local discovering = g.signal(false)

function M.accounts(): { any } return accounts.value end
-- Whether GOA answered at all; without it only addresses can be added.
function M.accounts_present(): boolean return accounts_present.value end
function M.discovering(): boolean return discovering.value end

-- Looks again at the accounts: asked whenever the way to a new calendar
-- opens, so an account added a moment ago is there.
function M.discover()
    if g.untracked(function() return discovering.value end) then return end
    discovering.value = true
    local out = {}
    g.process {
        command = { script, "accounts" },
        env = g.untracked(proxy.environment),
        on_line = function(line: string) table.insert(out, line) end,
        on_exit = function()
            discovering.value = false
            local ok, answer = pcall(g.parse_json, table.concat(out, "\n"))
            if ok and type(answer) == "table" then
                g.batch(function()
                    accounts.value = answer.accounts or {}
                    accounts_present.value = answer.present == true
                end)
            end
        end,
    }
end

function M.holds(goa: string, href: string): boolean
    for _, source in M.sources() do
        if source.goa == goa and source.href == href then return true end
    end
    return false
end

-- Switches on one calendar of an account.
function M.add_from_account(goa: string, calendar: any)
    if g.untracked(function() return M.holds(goa, calendar.href) end) then return end
    local sources = table.clone(g.untracked(M.sources))
    table.insert(sources, { goa = goa, href = calendar.href, name = calendar.name })
    config.set("calendar.sources", sources)
end

-- Takes a source out of the configuration, and its address out of the
-- keyring if it had one there.
function M.forget(index: number)
    local sources = g.untracked(M.sources)
    local source = sources[index]
    if not source then return end
    local rest = {}
    for i, s in sources do
        if i ~= index then table.insert(rest, s) end
    end
    config.set("calendar.sources", rest)
    if source.id then g.process { command = { script, "forget", source.id } } end
end

return M
