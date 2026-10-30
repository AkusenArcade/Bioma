--!strict
-- What the machine has to say on someone else's behalf
-- (services/Notifications.qml at 11bb81e). See docs/design/CELLS.md §10,
-- PRD §9.10.
--
-- The server is Genoma's (`@genoma/notifications`); everything above it is
-- Bioma's: urgency, a dwell that obeys it, a queue with a cap, a hover that
-- stops the clock, and a history that outlives the popup.
--
-- One owner per session. While another shell holds
-- `org.freedesktop.Notifications` (Bioma on Quickshell, while the two run
-- side by side) this server acquires nothing and the cells stay empty:
-- that is not a failure state to draw, it is the shell not being the shell
-- yet. Notifications move last (genoma/PORT.md).
--
-- Not yet: Bioma's notification sound (no Genoma cell plays sounds); the
-- unread list the vacuole organism holds (organisms are not ported); an
-- image a sender gives only as pixels, which the scene cannot draw yet:
-- such a notification takes its icon, or the bell.
local g = require("@genoma")
local config = require("core/config")
local apps = require("core/apps")

local M = {}

local server = require("@genoma/notifications")

function M.serving(): boolean return server.serving == true end

-- Said once: another server is not a failure of Bioma's, but it means this
-- one will never be told anything.
g.after(5, function()
    if not g.untracked(M.serving) then
        print("Bioma: another notification server holds this session (" .. tostring(server.error) .. ")")
    end
end)

-- What the server holds, by id: a replacement updates the one already
-- there, and what is drawn follows it.
local by_id = g.computed(function(): { [number]: any }
    local out = {}
    for _, n in server.list do out[n.id] = n end
    return out
end)
local function find(id: number?): any
    if not id then return nil end
    return g.untracked(function() return by_id.value end)[id]
end
function M.get(id: number?): any
    if not id then return nil end
    return by_id.value[id]
end

-- ---- Do not disturb -----------------------------------------------------
--
-- It lives with the history rather than in settings (CELLS §10): people look
-- for it while notifications are bothering them. Quiet is not deaf:
-- everything still arrives and everything is kept; what stops is the
-- appearing.
function M.quiet(): boolean return config.get("notifications.quiet", false) == true end
function M.set_quiet(on: boolean) config.set("notifications.quiet", on) end

-- ---- How long one stays ---------------------------------------------------
--
-- Four seconds for low, eight for ordinary, and a critical one does not
-- leave by itself. A sender that asks for a particular time gets it, except
-- a critical one, where the convention outranks the request.
local function low_dwell(): number return config.get("notifications.dwell_low", 4000) / 1000 end
local function normal_dwell(): number return config.get("notifications.dwell_normal", 8000) / 1000 end

function M.is_critical(n: any): boolean return n ~= nil and n.urgency == 2 end

-- Seconds; 0 for no clock.
local function dwell_for(n: any): number
    if not n then return g.untracked(normal_dwell) end
    if n.urgency == 2 then return 0 end
    if (n.expire_timeout or -1) > 0 then return n.expire_timeout / 1000 end
    return if n.urgency == 0 then g.untracked(low_dwell) else g.untracked(normal_dwell)
end

-- ---- The queue ----------------------------------------------------------------
--
-- Notifications arriving together queue, and past a cap they stop queueing
-- and become a number: twenty in ten seconds is a system update. A
-- critical one never counts towards the cap and is never collapsed into it.
local function cap(): number return config.get("notifications.queue_cap", 20) end
local function burst_window(): number return config.get("notifications.burst_window", 10000) / 1000 end

local arrivals: { number } = {}
local collapsed = g.signal(0)
function M.collapsed(): number return collapsed.value end
function M.flooding(): boolean return collapsed.value > 0 end

local function crowding(): boolean
    local now = g.now()
    local recent = {}
    for _, at in arrivals do
        if now - at < g.untracked(burst_window) then table.insert(recent, at) end
    end
    table.insert(recent, now)
    arrivals = recent
    return #recent > g.untracked(cap)
end

-- Two queues, because one of them has no clock. A critical notification held
-- on the head of the only queue would stop every other one for as long as
-- it went unanswered; with an urgent queue it sits on top and the others go
-- past it. A cell may show `"urgent"`, `"ordinary"` or `"all"`.
local queue = g.signal({} :: { number })
local urgent = g.signal({} :: { number })

function M.urgent_head(): number? return urgent.value[1] end
function M.ordinary_head(): number? return queue.value[1] end
-- What a cell showing everything shows. Urgency wins it.
function M.current(): number? return urgent.value[1] or queue.value[1] end
local function held(): boolean return #urgent.value > 0 end

-- How many cells show the ordinary queue on their own. With one, the
-- ordinary ones are seen going past an urgent one, so they keep queueing and
-- their clock keeps running.
local ordinary_cells = g.signal(0)
function M.count_ordinary(delta: number) ordinary_cells.value += delta end
local function ordinary_visible(): boolean return ordinary_cells.value > 0 or not held() end

-- Set by the cell showing the ordinary head while the pointer is on it. Time
-- does not run while somebody is reading, and on exit it resumes where it
-- stopped, never from the start (PRD §5.2).
local holding = g.signal(false)
function M.hold(on: boolean) holding.value = on end

-- The head's clock: seconds left, the whole of it, and when it last
-- started. `left()` is what remains as a fraction, read continuously.
local remaining = 0
local lifetime = g.signal(0)
local started_at = g.signal(-1)
local stood = g.signal(0) -- the fraction left while the clock stands still
local life: any = nil

function M.lifetime(): number return lifetime.value end
function M.left(): number
    local l = lifetime.value
    if l <= 0 then return 0 end
    local at = started_at.value
    if at < 0 then return stood.value end
    return math.clamp((remaining - (g.now() - at)) / l, 0, 1)
end
-- Whether the clock is running now: a face drawing `left` asks for frames
-- only then.
function M.running(): boolean return started_at.value >= 0 end

local expire: () -> ()

local function pace()
    local head = g.untracked(function() return queue.value[1] end)
    local run = head ~= nil and g.untracked(ordinary_visible) and not g.untracked(function() return holding.value end)
        and remaining > 0
    local at = g.untracked(function() return started_at.value end)
    if run and at < 0 then
        started_at.value = g.now()
        life = g.after(remaining, function() life = nil expire() end)
    elseif not run and at >= 0 then
        remaining = math.max(0, remaining - (g.now() - at))
        if life then life:stop() life = nil end
        started_at.value = -1
        local l = g.untracked(function() return lifetime.value end)
        stood.value = if l > 0 then remaining / l else 0
    end
end

local function begin()
    if life then life:stop() life = nil end
    local head = g.untracked(function() return queue.value[1] end)
    remaining = if head then dwell_for(find(head)) else 0
    g.batch(function()
        started_at.value = -1
        lifetime.value = remaining
        stood.value = if remaining > 0 then 1 else 0
    end)
    pace()
end

g.watch(function() return holding.value end, function() pace() end)
g.watch(ordinary_visible, function() pace() end)

local function without(list: { number }, id: number?): { number }
    local out = {}
    for _, n in list do
        if n ~= id and find(n) ~= nil then table.insert(out, n) end
    end
    return out
end

-- Take one off whichever queue holds it, and anything the server has
-- already let go with it. A new head starts its own clock.
local function advance(id: number?)
    local head = g.untracked(function() return queue.value[1] end)
    local u = without(g.untracked(function() return urgent.value end), id)
    if #u ~= #g.untracked(function() return urgent.value end) then urgent.value = u end
    local q = without(g.untracked(function() return queue.value end), id)
    if #q ~= #g.untracked(function() return queue.value end) then
        queue.value = q
        if q[1] ~= head then begin() end
    end
    if #q == 0 then collapsed.value = 0 end
end

-- Leaving by itself is not being dismissed: the sender is told it expired,
-- and only the ordinary head expires.
expire = function()
    local head = g.untracked(function() return queue.value[1] end)
    advance(head)
    if head and find(head) then server:close(head, "expired") end
end

-- The one named, or what a cell showing everything shows. A count is
-- dismissed too: the flood is what the cell is saying.
function M.dismiss(id: number?)
    local which = id or g.untracked(M.current)
    if not which then
        collapsed.value = 0
        return
    end
    advance(which)
    if find(which) then server:close(which, "dismissed") end
end

-- An action; the server dismisses it after, unless it is resident.
function M.invoke(id: number, key: string)
    advance(id)
    server:invoke(id, key)
end

-- ---- The history ----------------------------------------------------------------
--
-- What the cell shows when it opens, grouped by application, most recent
-- first. In memory: a shell that wrote every notification to disk would be
-- keeping a diary nobody asked it to keep.
local history = g.signal({} :: { any })
function M.history(): { any } return history.value end

local function remember(n: any)
    local keep = g.untracked(function() return config.get("notifications.history", 100) end)
    local out = { {
        id = n.id, app_name = n.app_name, summary = n.summary, body = n.body,
        image_path = n.image_path, app_icon = n.app_icon, desktop_entry = n.desktop_entry,
        urgency = n.urgency, at = g.now(),
    } }
    for _, e in g.untracked(function() return history.value end) do
        if #out >= keep then break end
        table.insert(out, e)
    end
    history.value = out
end

function M.forget() history.value = {} end

-- Grouped for the history panel: one block per application, in the order
-- the history has them.
function M.grouped(): { any }
    local order, by_app = {}, {}
    for _, e in history.value do
        local name = e.app_name or ""
        if not by_app[name] then
            by_app[name] = { app_name = name, entries = {} }
            table.insert(order, by_app[name])
        end
        table.insert(by_app[name].entries, e)
    end
    return order
end

-- "two minutes ago" is a measurement, written in the technical voice.
function M.since(at: number, now: number): string
    local seconds = math.max(0, math.floor(now - at + 0.5))
    if seconds < 60 then return "now" end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return minutes .. "m" end
    local hours = math.floor(minutes / 60 + 0.5)
    if hours < 24 then return hours .. "h" end
    return math.floor(hours / 24 + 0.5) .. "d"
end

-- ---- Arriving ---------------------------------------------------------------------

-- Something to say: no title, no text and no sender would be a bell in an
-- empty pill.
local function says(n: any): boolean
    return ((n.summary or "") .. (n.body or "") .. (n.app_name or "")) ~= ""
end

local function receive(n: any)
    if not says(n) then return end
    remember(n)
    -- What went while nobody was looking, gone before this one queues.
    advance(nil)
    if M.is_critical(n) then
        local u = table.clone(g.untracked(function() return urgent.value end))
        table.insert(u, n.id)
        urgent.value = u
        return
    end
    if g.untracked(M.quiet) then return end
    if crowding() then
        collapsed.value += 1
        return
    end
    -- Nobody would see it queue: it is kept, and it is in the history.
    if not g.untracked(ordinary_visible) then return end
    local q = table.clone(g.untracked(function() return queue.value end))
    table.insert(q, n.id)
    queue.value = q
    if #q == 1 then begin() end
end

-- New ids are arrivals; ids gone are notifications closed, by the user, by
-- their sender or by the server: off the queues whoever closed them.
local seen: { [number]: boolean } = {}
local started = false
g.watch(function() return by_id.value end, function(now: { [number]: any })
    local gone = false
    for id in seen do
        if not now[id] then
            seen[id] = nil
            gone = true
        end
    end
    if gone then advance(nil) end
    local fresh = {}
    for id, n in now do
        if not seen[id] then
            seen[id] = true
            table.insert(fresh, n)
        end
    end
    table.sort(fresh, function(a, b) return a.id < b.id end)
    -- What the server kept across a reload is on screen already: it is
    -- taken back, not announced again.
    if not started then
        started = true
        for _, n in fresh do
            if says(n) then
                if M.is_critical(n) then
                    local u = table.clone(g.untracked(function() return urgent.value end))
                    table.insert(u, n.id)
                    urgent.value = u
                else
                    local q = table.clone(g.untracked(function() return queue.value end))
                    table.insert(q, n.id)
                    queue.value = q
                end
            end
        end
        begin()
        return
    end
    for _, n in fresh do receive(n) end
end)

-- ---- Where it is drawn ------------------------------------------------------------

-- In the order the sender gave them, and never a guess: a free-form
-- application name resolved the way a window's is would put somebody
-- else's logo on somebody else's message. Where nothing resolves, the cell
-- draws its own glyph.
local function path_of(name: string?): string
    if not name or name == "" then return "" end
    if string.sub(name, 1, 7) == "file://" then return string.sub(name, 8) end
    if string.sub(name, 1, 1) == "/" then return name end
    return g.icon_path(name) or ""
end

function M.icon_for(n: any): string
    if not n then return "" end
    local image = path_of(n.image_path)
    if image ~= "" then return image end
    local icon = path_of(n.app_icon)
    if icon ~= "" then return icon end
    -- A desktop entry is an identifier, not a name: a lookup, not a search.
    local wanted = n.desktop_entry or ""
    if wanted == "" then return "" end
    for _, e in apps.entries() do
        if e.id == wanted or e.id == wanted .. ".desktop" then
            return if e.icon ~= "" then (g.icon_path(e.icon) or "") else ""
        end
    end
    return ""
end

return M
