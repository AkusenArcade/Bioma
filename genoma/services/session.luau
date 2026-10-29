--!strict
-- The session: who is logged in, the machine's end-of-session actions, and
-- whether a restart is due (services/Session.qml at 11bb81e).
--
-- Not here, on purpose: suspending after idle minutes. It acts on the
-- machine and stays Bioma on Quickshell's while both run (genoma/PORT.md,
-- "Who acts on the desktop"); an action pressed here is a choice, and runs.
local g = require("@genoma")
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

local person = g.signal({ name = login, uid = -1 })
local passwd = g.file { path = "/etc/passwd" }
g.effect(function()
    local text = passwd.text or ""
    for line in string.gmatch(text, "[^\n]+") do
        local fields = string.split(line, ":")
        if fields[1] == login then
            local gecos = string.match(string.split(fields[5] or "", ",")[1] or "", "^%s*(.-)%s*$") or ""
            person.value = { name = if gecos ~= "" then gecos else login, uid = tonumber(fields[3]) or -1 }
            return
        end
    end
end)
function M.full_name(): string return person.value.name end
function M.uid(): number return person.value.uid end

-- The picture, from where the desktop keeps it: AccountsService's, then the
-- old dotfiles. The first that can be read.
local avatar = g.signal("")
local function find_avatar()
    local found = ""
    g.process {
        command = { "sh", "-c", 'for f; do [ -r "$f" ] && [ -s "$f" ] && { echo "$f"; exit; }; done', "avatar",
            "/var/lib/AccountsService/icons/" .. login, home .. "/.face", home .. "/.face.icon" },
        on_line = function(line: string) found = line end,
        on_exit = function() avatar.value = found end,
    }
end
find_avatar()
function M.avatar(): string return avatar.value end
function M.has_avatar(): boolean return avatar.value ~= "" end

-- A new picture, through AccountsService, which copies it where the greeter
-- and the lock read it too.
local last_error = g.signal("")
function M.last_error(): string return last_error.value end
function M.set_avatar(path: string)
    local uid = g.untracked(M.uid)
    if path == "" or uid < 0 then return end
    last_error.value = ""
    g.dbus.call {
        bus = "system",
        destination = "org.freedesktop.Accounts",
        path = "/org/freedesktop/Accounts/User" .. uid,
        interface = "org.freedesktop.Accounts.User",
        method = "SetIconFile",
        signature = "s",
        args = { path },
        reply = function(ok: boolean, why: any)
            if ok then
                find_avatar()
            else
                last_error.value = tostring(why)
                print("Bioma: the avatar was not changed — " .. tostring(why))
            end
        end,
    }
end

-- ---- The end of the session ----------------------------------------------------------

local commands = {
    lock = function() return config.get("session.lock", { "loginctl", "lock-session" }) end,
    suspend = function() return config.get("session.suspend", { "systemctl", "suspend" }) end,
    restart = function() return config.get("session.restart", { "systemctl", "reboot" }) end,
    shutdown = function() return config.get("session.shutdown", { "systemctl", "poweroff" }) end,
    logout = function() return config.get("session.logout", { "niri", "msg", "action", "quit", "-s" }) end,
}

function M.available(action: string): boolean
    local c = commands[action]
    return c ~= nil and #c() > 0
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
    if #command == 0 then
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

return M
