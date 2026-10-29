--!strict
-- What turns performance mode on by itself (services/Workload.qml at
-- 11bb81e): a game under GameMode, or an open window whose app id matches
-- one of `performance.apps` (`*` a wildcard).
--
-- GameMode's ClientCount is read once and again on every change it
-- announces; nothing polls.
local g = require("@genoma")
local config = require("core/config")
local apps = require("core/apps")
local niri = require("services/niri")

local M = {}

local games = g.signal(0)
local function watches_games(): boolean return config.get("performance.gamemode", true) == true end

local function count()
    g.dbus.get {
        bus = "session",
        destination = "com.feralinteractive.GameMode",
        path = "/com/feralinteractive/GameMode",
        interface = "com.feralinteractive.GameMode",
        property = "ClientCount",
        reply = function(ok: boolean, value: any)
            games.value = if ok and g.untracked(watches_games) then tonumber(value) or 0 else 0
        end,
    }
end
g.effect(function()
    if not watches_games() then
        g.untracked(function() games.value = 0 end)
        return
    end
    g.untracked(function()
        g.dbus.watch {
            bus = "session",
            sender = "com.feralinteractive.GameMode",
            path = "/com/feralinteractive/GameMode",
            on_signal = function() count() end,
        }
        count()
    end)
end)

-- `*` is any run of characters; the rest is matched as written, without
-- regard to case.
local function matcher(pattern: string): (string) -> boolean
    local escaped = string.gsub(string.lower(pattern), "[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
    escaped = string.gsub(escaped, "%*", ".*")
    local whole = "^" .. escaped .. "$"
    return function(id: string) return string.match(string.lower(id), whole) ~= nil end
end

local matchers = g.computed(function(): { (string) -> boolean }
    local out = {}
    local patterns = config.get("performance.apps", {})
    if type(patterns) ~= "table" then return out end
    for _, p in patterns do
        local s = string.match(tostring(p), "^%s*(.-)%s*$") or ""
        if s ~= "" then table.insert(out, matcher(s)) end
    end
    return out
end)

local function matched_apps(): { string }
    local out = {}
    if #matchers.value == 0 then return out end
    for _, w in niri.windows() do
        local id = w.app_id
        if id ~= "" then
            for _, test in matchers.value do
                if test(id) then
                    local entry = apps.entry_for(id)
                    local name = if entry and entry.name ~= "" then entry.name else id
                    if not table.find(out, name) then table.insert(out, name) end
                    break
                end
            end
        end
    end
    return out
end

function M.triggers(): { any }
    local out = {}
    if games.value > 0 then table.insert(out, { kind = "game", name = "GameMode" }) end
    for _, name in matched_apps() do table.insert(out, { kind = "app", name = name }) end
    return out
end

return M
