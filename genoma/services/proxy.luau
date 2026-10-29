--!strict
-- The proxy (services/Proxy.qml), the part read so far: which profile is in
-- force and the environment a program reaching the network is given.
--
-- Not yet, and on purpose: the triggers (a VPN up, a Wi-Fi network, a cable)
-- wait for the VPN and network services, and so an `auto` mode with
-- triggers chooses none; and writing the desktop's own proxy setting
-- (`gsettings`) stays Bioma on Quickshell's while both run, or the two
-- would write it in turn.
local config = require("core/config")

local M = {}

local function profiles(): { any } return config.get("proxy.profiles", {}) end
local function mode(): string return config.get("proxy.mode", "auto") end

local function profile_for(id: string): any
    for _, p in profiles() do
        if p.id == id then return p end
    end
    return nil
end

-- A trigger is met when its link is: none can be told yet.
local function triggered(_profile: any): boolean return false end

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

return M
