--!strict
-- CUPS, for the connectivity cell (services/Printers.qml at 11bb81e): the
-- queues, the default and the jobs, through `scripts/printers`; changes come
-- from CUPS's own D-Bus notifications (`printers watch`), nothing polls.
--
-- Not here, on purpose: making the only queue the default by itself. It
-- acts on the desktop, and stays Bioma on Quickshell's while both run
-- (genoma/PORT.md, "Who acts on the desktop"); a default chosen by hand in
-- the panel is a choice, and is made.
local g = require("@genoma")
local timing = require("core/timing")
local paths = require("core/paths")

local M = {}

local script = paths.script("printers")

local state = g.signal({ available = false, printers = {}, jobs = {}, default = "" })
local found = g.signal({})
local searching = g.signal(false)
local working = g.signal("")
local error_text = g.signal("")

function M.available(): boolean return state.value.available end
function M.printers(): { any } return state.value.printers end
function M.jobs(): { any } return state.value.jobs end
function M.default_queue(): string return state.value.default end
function M.found(): { any } return found.value end
function M.searching(): boolean return searching.value end
function M.working(): string return working.value end
function M.error(): string return error_text.value end

-- A queue printing is one with a job and not stopped: a job held by a
-- stopped printer is going nowhere.
function M.printing_queues(): { string }
    local s = state.value
    local out = {}
    for _, job in s.jobs do
        for _, p in s.printers do
            if p.queue == job.queue and p.state ~= "stopped" and not table.find(out, job.queue) then
                table.insert(out, job.queue)
            end
        end
    end
    return out
end
function M.printing(): boolean return #M.printing_queues() > 0 end

-- Where a printer is, the same however the URI spells it, so one already
-- added is not offered again.
local function where(uri: string): string
    local s = string.gsub(uri, "^%a+://", "")
    s = string.gsub(s, "%.?:631/", "/")
    return string.lower(s)
end
local function unknown(list: { any }): { any }
    local known = {}
    for _, p in g.untracked(function() return state.value.printers end) do known[where(p.uri)] = true end
    local out = {}
    for _, f in list do
        if not known[where(f.uri)] then table.insert(out, f) end
    end
    return out
end

local function split(line: string): { string }
    local out = {}
    for field in string.gmatch(line .. "\t", "([^\t]*)\t") do table.insert(out, field) end
    return out
end

local reading: any = nil
local again: any = nil
local function later()
    if again then again:stop() end
    again = g.after(timing.seconds.debounce, M.refresh)
end

function M.refresh()
    if reading and reading.running then later() return end
    local lines = {}
    reading = g.process {
        command = { script, "state" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function(code: number)
            if code ~= 0 then
                state.value = { available = false, printers = {}, jobs = {}, default = "" }
                return
            end
            local fallback, printers, jobs = "", {}, {}
            for _, line in lines do
                local f = split(line)
                if f[1] == "default" and #f >= 2 then
                    fallback = f[2]
                elseif f[1] == "printer" and #f >= 5 then
                    table.insert(printers, { queue = f[2], state = f[3], name = if f[4] ~= "" then f[4] else f[2], uri = f[5] })
                elseif f[1] == "job" and #f >= 3 then
                    table.insert(jobs, { id = f[2], queue = f[3] })
                end
            end
            for _, p in printers do
                p.is_default = p.queue == fallback
                p.jobs = 0
                for _, j in jobs do
                    if j.queue == p.queue then p.jobs += 1 end
                end
            end
            table.sort(printers, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
            state.value = { available = true, printers = printers, jobs = jobs, default = fallback }
            found.value = unknown(g.untracked(function() return found.value end))
        end,
    }
end

-- The watch is restarted when it ends: soon after a long life, backing off
-- when it dies at once (no CUPS).
local backoff = 5
local function watch()
    local started = g.now()
    g.process {
        command = { script, "watch" },
        on_line = later,
        on_exit = function()
            backoff = if g.now() - started > 60 then 5 else math.min(backoff * 2, 600)
            g.after(backoff, watch)
        end,
    }
end
watch()
M.refresh()

local finder: any = nil
function M.search()
    if g.untracked(function() return searching.value end) then return end
    error_text.value = ""
    found.value = {}
    searching.value = true
    local out = {}
    finder = g.process {
        command = { script, "find", "5" },
        on_line = function(line: string)
            local f = split(line)
            if f[1] == "found" and #f >= 3 then
                table.insert(out, { uri = f[2], name = if f[3] ~= "" then f[3] else f[2], uuid = f[4] or "" })
            end
        end,
        on_exit = function()
            searching.value = false
            finder = nil
            found.value = unknown(out)
        end,
    }
end
function M.stop_searching()
    if finder then finder:stop() end
    finder = nil
    searching.value = false
end
function M.clear_found() found.value = {} end

-- CUPS's last line, without its program's name.
local function reason(lines: { string }): string
    local last = ""
    for _, l in lines do
        local t = string.match(l, "^%s*(.-)%s*$") or ""
        if t ~= "" then last = t end
    end
    local r = string.gsub(last, "^%l+:%s*", "")
    return if r ~= "" then r else "CUPS refused it."
end

local function act(key: string, command: { string })
    if g.untracked(function() return working.value end) ~= "" then return end
    error_text.value = ""
    working.value = key
    local complaint = {}
    g.process {
        command = command,
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function(code: number)
            if code ~= 0 then error_text.value = reason(complaint) end
            working.value = ""
            M.refresh()
        end,
    }
end

function M.add(p: any) if p then act(p.uri, { script, "add", p.uri, p.name }) end end
function M.remove(p: any) if p then act(p.queue, { script, "remove", p.queue }) end end
function M.make_default(p: any)
    if p and not p.is_default then act(p.queue, { script, "default", p.queue }) end
end

return M
