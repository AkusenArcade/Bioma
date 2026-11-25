--!strict
-- What keeps the session awake besides the compositor's own inhibitors: the
-- freedesktop screen saver interface, `org.freedesktop.ScreenSaver`, served
-- here for the programs that ask there first (Firefox and what is made of
-- it, Chromium, Electron, SDL games, VLC).
--
-- Without it a video did not keep the screens lit: Firefox tries this name,
-- then the portal, which answers that all is well with nobody behind it to
-- hold anything, and so never comes to the Wayland inhibitor that does
-- (Akusen, 2026-11-25). The portal's own backend comes here too.
--
-- What is held is held by its caller: it goes when the caller lets it go,
-- or leaves the bus. Kept in a file of the runtime directory, so a reload or
-- a restart of the shell in the middle of a film forgets nothing.
local g = require("@genoma")
local idle = require("@genoma/idle")

local M = {}

type Held = { app: string, reason: string, sender: string }

-- By cookie, as text: JSON's keys.
local held = g.signal({} :: { [string]: Held })
function M.held(): boolean return next(held.value) ~= nil end

local file = g.file {
    path = `$XDG_RUNTIME_DIR/bioma-awake-{g.env("WAYLAND_DISPLAY") or "none"}.json`,
    watch = false,
}

local function now(): { [string]: Held } return g.untracked(function() return held.value end) end

local function keep(all: { [string]: Held })
    held.value = all
    file:write(g.to_json(all), { mode = "600" })
end

local function release(gone: (cookie: string, h: Held) -> boolean)
    local left, any = {}, false
    for cookie, h in now() do
        if gone(cookie, h) then any = true else left[cookie] = h end
    end
    if any then keep(left) end
end

-- Whether a name idle for `seconds()` is idle, nothing holding it back. Held,
-- it is not counted at all, and counted from the start once let go: the
-- screens do not go dark on the last frame of the film. What is idle already
-- stays so until somebody comes back: a tab that starts playing by itself
-- lights no screen.
function M.after(name: string, seconds: () -> number): () -> boolean
    g.effect(function()
        local wanted = seconds()
        if M.held() and not idle:is_idle(name) then wanted = 0 end
        g.untracked(function() idle:watch(name, wanted) end)
    end)
    return function() return idle:is_idle(name) end
end

-- ---- The service -------------------------------------------------------------

local NAME = "org.freedesktop.ScreenSaver"
local BUS = "org.freedesktop.DBus"

local function inhibit(app: string, reason: string, sender: string): number
    local all = table.clone(now())
    local cookie
    repeat cookie = math.random(1, 2 ^ 31 - 1) until all[tostring(cookie)] == nil
    all[tostring(cookie)] = { app = app, reason = reason, sender = sender }
    keep(all)
    return cookie
end

-- Who is still on the bus: the shell may have been away when they left.
local function ask(sender: string)
    g.dbus.call {
        destination = BUS,
        path = "/org/freedesktop/DBus",
        interface = BUS,
        method = "NameHasOwner",
        signature = "s",
        args = { sender },
        reply = function(ok: boolean, here: any)
            if ok and here == false then release(function(_, h) return h.sender == sender end) end
        end,
    }
end

local started = false
function M.start()
    if started then return end
    started = true
    local ok, before = pcall(g.parse_json, file.text or "{}")
    if ok and type(before) == "table" then held.value = before end

    -- Heard only while somebody holds it: names come and go on the bus all
    -- the time.
    g.effect(function()
        if not M.held() then return end
        g.untracked(function()
            g.dbus.watch {
                sender = BUS,
                path = "/org/freedesktop/DBus",
                interface = BUS,
                member = "NameOwnerChanged",
                on_signal = function(name: any, _old: any, new: any)
                    if new == "" then release(function(_, h) return h.sender == name end) end
                end,
            }
            local asked = {}
            for _, h in now() do
                if not asked[h.sender] then
                    asked[h.sender] = true
                    ask(h.sender)
                end
            end
        end)
    end)

    -- A Genoma older than 0.1.25 serves one path and does not say who
    -- calls: as without it then, rather than half of it.
    local served, problem = pcall(function()
        return g.dbus.serve {
            name = NAME,
            queue = true,
            -- The specification's, and the one programs used before it.
            path = { "/org/freedesktop/ScreenSaver", "/ScreenSaver" },
            interfaces = {
                [NAME] = {
                    methods = {
                        Inhibit = { args = "ss", returns = "u", call = inhibit },
                        UnInhibit = {
                            args = "u",
                            call = function(cookie: number)
                                local key = string.format("%d", cookie)
                                release(function(c) return c == key end)
                            end,
                        },
                        Lock = { call = function() require("services/locker").lock() end },
                        SimulateUserActivity = { call = function() end },
                        GetActive = { returns = "b", call = function() return require("services/locker").locked() end },
                    },
                    signals = { ActiveChanged = "b" },
                },
            },
            on_error = function(message: string) print("Bioma: " .. message) end,
        }
    end)
    if not served then print("Bioma: the screen saver interface — " .. tostring(problem)) end
end

return M
