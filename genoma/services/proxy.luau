--!strict
-- The proxy (services/Proxy.qml at 11bb81e): the profiles, which one is in
-- force (by hand, or the first whose trigger is met: a VPN up, a Wi-Fi
-- network, a cable), and the environment a program reaching the network is
-- given.
--
-- Not here, on purpose: writing the desktop's own proxy setting
-- (`gsettings`). It stays Bioma on Quickshell's while both run, or the two
-- would write it in turn (genoma/PORT.md, "Who acts on the desktop"); it
-- follows the same configuration this writes.
local g = require("@genoma")
local config = require("core/config")
local network = require("services/network")
local vpn = require("services/vpn")

local M = {}

local function profiles(): { any } return config.get("proxy.profiles", {}) end
local function mode(): string return config.get("proxy.mode", "auto") end
M.profiles = profiles
M.mode = mode

local function profile_for(id: string): any
    for _, p in profiles() do
        if p.id == id then return p end
    end
    return nil
end

local function matches(trigger: any): boolean
    if not trigger then return false end
    if trigger.kind == "vpn" then
        for _, p in vpn.active() do
            if p.uuid == trigger.uuid then return true end
        end
        return false
    end
    if trigger.kind == "wifi" then return network.wifi_connected() and network.ssid() == trigger.ssid end
    if trigger.kind == "wired" then return network.wired_connected() end
    return false
end

local function triggered(profile: any): boolean
    for _, t in profile.triggers or {} do
        if matches(t) then return true end
    end
    return false
end

function M.current(): any
    local m = mode()
    if m == "off" then return nil end
    if m ~= "auto" then return profile_for(m) end
    for _, p in profiles() do
        if triggered(p) then return p end
    end
    return nil
end

function M.on(): boolean return M.current() ~= nil end

local function url_of(profile: any): string
    local scheme = if profile.type == "socks5" then "socks5h" else "http"
    return scheme .. "://" .. tostring(profile.host) .. ":" .. tostring(profile.port)
end

function M.exceptions(): string
    local current = M.current()
    return if current then (current.noProxy or "localhost,127.0.0.1,::1") else ""
end

-- What a program that reaches the network is started with.
function M.environment(): { [string]: string }
    local current = M.current()
    if not current then return {} end
    local url = url_of(current)
    local exceptions = M.exceptions()
    local out = {
        http_proxy = url, HTTP_PROXY = url,
        https_proxy = url, HTTPS_PROXY = url,
        no_proxy = exceptions, NO_PROXY = exceptions,
    }
    if current.type == "socks5" then
        out.all_proxy = url
        out.ALL_PROXY = url
    end
    return out
end

-- ---- Writing the profiles ----------------------------------------------------

function M.set_mode(m: string) config.set("proxy.mode", m) end

function M.save(profile: any)
    local list = table.clone(g.untracked(profiles))
    local at = 0
    for i, p in list do
        if p.id == profile.id then at = i end
    end
    if at > 0 then list[at] = profile else table.insert(list, profile) end
    config.set("proxy.profiles", list)
end

function M.remove(id: string)
    local list = {}
    for _, p in g.untracked(profiles) do
        if p.id ~= id then table.insert(list, p) end
    end
    config.set("proxy.profiles", list)
    if g.untracked(mode) == id then M.set_mode("auto") end
end

-- Base 36 of the time, as Proxy.qml makes them.
function M.new_id(): string
    local n = math.floor(os.time() * 1000 + (g.now() * 1000) % 1000)
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    repeat
        local d = n % 36
        out = string.sub(digits, d + 1, d + 1) .. out
        n = n // 36
    until n == 0
    return "p" .. out
end

function M.describe(trigger: any): string
    if trigger.kind == "vpn" then return trigger.name or "VPN" end
    if trigger.kind == "wifi" then return trigger.ssid or "" end
    if trigger.kind == "wired" then return "Wired" end
    return ""
end

return M
