--!strict
-- The session: who is logged in, the machine's end-of-session actions, and
-- whether a restart is due (services/Session.qml at 11bb81e).
--
-- Suspending after idle minutes acts on the machine: `start` runs it once
-- the switch is made (M6 step 7a); beside Quickshell it is Quickshell's
-- (genoma/PORT.md, "Who acts on the desktop"). An action pressed here is a
-- choice, and runs.
local g = require("@genoma")
local idle = require("@genoma/idle")
local compositor = require("@genoma/compositor")
local config = require("core/config")

local M = {}

local login = g.env("USER") or ""
local home = g.env("HOME") or ""
function M.login(): string return login end

-- ---- A restart is due ----------------------------------------------------------
--
-- The kernel running is no longer installed: an upgrade has replaced its
-- modules, and the next driver to load will fail. pacman removes the old
-- release's directory, so its absence is the sign.
local release = g.signal("")
g.process {
    command = { "uname", "-r" },
    on_line = function(line: string) release.value = line end,
}
local modules = g.folder { path = "/usr/lib/modules" }
function M.restart_due(): boolean
    local r = release.value
    if r == "" then return false end
    local entries = modules.entries
    if not entries or #entries == 0 then return false end
    for _, e in entries do
        if e.name == r then return false end
    end
    return true
end

-- ---- Who ------------------------------------------------------------------------
--
-- From Genoma's `@genoma/accounts` (AccountsService, `/etc/passwd` without
-- it): the real name or the login, the uid, and the picture the desktop
-- keeps (AccountsService's, else `~/.face`), followed as it changes.

local accounts = require("@genoma/accounts")

function M.full_name(): string
    local me = accounts.me
    return if me and (me.name or "") ~= "" then me.name else login
end
function M.uid(): number
    local me = accounts.me
    return if me then me.uid else -1
end
function M.avatar(): string
    local me = accounts.me
    return if me and me.icon then me.icon else ""
end
function M.has_avatar(): boolean return M.avatar() ~= "" end

-- A new picture, through AccountsService, which copies it where the greeter
-- and the lock read it too.
function M.last_error(): string return accounts.error end
function M.set_avatar(path: string)
    if path == "" then return end
    accounts:set_icon(path)
end

-- ---- The end of the session ----------------------------------------------------------

local commands = {
    lock = function() return config.get("session.lock", { "loginctl", "lock-session" }) end,
    suspend = function() return config.get("session.suspend", { "systemctl", "suspend" }) end,
    restart = function() return config.get("session.restart", { "systemctl", "reboot" }) end,
    shutdown = function() return config.get("session.shutdown", { "systemctl", "poweroff" }) end,
    -- "compositor": whichever runs is asked to quit (niri, Hyprland,
    -- Umbriel), the default; a list is a command of the person's own.
    logout = function() return config.get("session.logout", "compositor") end,
}

local function quits(): boolean
    local ok, can = pcall(function() return compositor.name ~= "wayland" and compositor.quit ~= nil end)
    return ok and can == true
end

function M.available(action: string): boolean
    local c = commands[action]
    if not c then return false end
    local command = c()
    if command == "compositor" then return quits() end
    return type(command) == "table" and #command > 0
end

-- The three that end the session ask first; lock and suspend leave it
-- where it was.
function M.confirms(action: string): boolean
    return action == "restart" or action == "shutdown" or action == "logout"
end

local pending = g.signal("")
function M.pending(): string return pending.value end

-- Detached: the shell is not the action's parent. A lock screen that died
-- with the shell's next reload would unlock the session.
function M.run(action: string)
    local c = commands[action]
    local command = if c then g.untracked(c) else {}
    pending.value = ""
    if command == "compositor" then
        local ok, problem = pcall(function() compositor:quit() end)
        if not ok then print('Bioma: session action "' .. action .. '": ' .. tostring(problem)) end
        return
    end
    if type(command) ~= "table" or #command == 0 then
        print('Bioma: session action "' .. action .. '" has no command configured')
        return
    end
    local detached = { "setsid", "-f" }
    for _, word in command do table.insert(detached, word) end
    g.process { command = detached }
end

function M.ask(action: string)
    if not M.available(action) then return end
    if not M.confirms(action) then
        M.run(action)
        return
    end
    pending.value = if g.untracked(function() return pending.value end) == action then "" else action
end
function M.confirm()
    local p = g.untracked(function() return pending.value end)
    if p ~= "" then M.run(p) end
end
function M.cancel() pending.value = "" end

-- ---- Monitors off ---------------------------------------------------------------
--
-- Through the compositor, whichever it is (niri, Hyprland, Umbriel); the
-- standard protocols have no way, and a Genoma older than 0.1.22 no call.
function M.can_blank(): boolean
    local ok, can = pcall(function() return compositor.can_power_monitors end)
    return ok and can == true
end

-- ---- Sleep after a time idle -------------------------------------------------
--
-- Minutes without input before the machine suspends, `sleep.idle_minutes`,
-- with the same suspend command the System cell runs, so a machine whose
-- suspend is not `systemctl` sleeps its own way; the lock before a suspend
-- (services/locker.luau) covers it like any other. Respecting inhibitors:
-- a video playing full screen is not somebody who walked away.
local started = false
function M.start()
    if started then return end
    started = true
    g.effect(function()
        local minutes = config.get("sleep.idle_minutes", 0)
        local seconds = if minutes > 0 and M.available("suspend") then math.max(1, minutes) * 60 else 0
        g.untracked(function() idle:watch("sleep", seconds) end)
    end)
    local was = false
    g.watch(function() return idle:is_idle("sleep") end, function(on: boolean)
        local began = on and not was
        was = on
        if began then g.process { command = { "setsid", "-f", table.unpack(commands.suspend()) } } end
    end)

    -- The monitors off after a time idle, `blank.idle_minutes`, and back on
    -- at the first input. Apart from the lock: it may come before it or
    -- after. Inhibitors hold it back like the others: a video playing
    -- keeps the screens lit.
    g.effect(function()
        local minutes = config.get("blank.idle_minutes", 0)
        local seconds = if minutes > 0 and M.can_blank() then math.max(1, minutes) * 60 else 0
        g.untracked(function() idle:watch("blank", seconds) end)
    end)
    local blank = false
    g.watch(function() return idle:is_idle("blank") end, function(on: boolean)
        if on == blank then return end
        blank = on
        local ok, problem = pcall(function() compositor:power_monitors(not on) end)
        if not ok then print("Bioma: monitors " .. (if on then "off" else "on") .. " — " .. tostring(problem)) end
    end)
end

return M
