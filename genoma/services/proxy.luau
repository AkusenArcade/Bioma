--!strict
-- The proxy (services/Proxy.qml at 11bb81e): the profiles, which one is in
-- force (by hand, or the first whose trigger is met: a VPN up, a Wi-Fi
-- network, a cable), and the environment a program reaching the network is
-- given.
--
-- The desktop's own proxy setting (`gsettings`) is written by `start`,
-- once the switch is made (M6 step 7a); beside Quickshell, Quickshell
-- writes it, or the two would write it in turn (genoma/PORT.md, "Who acts
-- on the desktop").
local g = require("@genoma")
local config = require("core/config")
local timing = require("core/timing")
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
    local list = g.array()
    for _, p in g.untracked(profiles) do table.insert(list, p) end
    local at = 0
    for i, p in list do
        if p.id == profile.id then at = i end
    end
    if at > 0 then list[at] = profile else table.insert(list, profile) end
    config.set("proxy.profiles", list)
end

function M.remove(id: string)
    local list = g.array()
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

-- ---- The desktop's setting ---------------------------------------------------
--
-- Written when what is on changes, and not while the shell is starting: the
-- networks fill in a moment after start, and writing "none" for that moment
-- would drop a proxy somebody's browser is using. With no profiles the
-- desktop's setting is somebody else's, unless the shell set it and then
-- lost its last profile: then it undoes what it did, once.
local touched = false
local writing, again = false, false

local function clean(text: string): string return (string.gsub(text, "['\"\\$`]", "")) end

local function apply()
    local empty = #g.untracked(profiles) == 0
    if empty and not touched then return end
    touched = not empty
    if writing then
        again = true
        return
    end
    local schema = "org.gnome.system.proxy"
    local sets: { { string } } = {}
    local function set(key: string, name: string, value: string) table.insert(sets, { key, name, value }) end
    local profile = if empty then nil else g.untracked(M.current)
    if not profile then
        set(schema, "mode", "none")
    else
        -- A string, as GVariant wants it: `'proxy.example'`.
        local host = "'" .. clean(tostring(profile.host or "")) .. "'"
        local port = tostring(math.max(0, math.floor(tonumber(profile.port) or 0)))
        local ignored = {}
        for h in string.gmatch(g.untracked(M.exceptions), "[^,]+") do
            local trimmed = string.match(h, "^%s*(.-)%s*$") or ""
            if trimmed ~= "" then table.insert(ignored, "'" .. clean(trimmed) .. "'") end
        end
        set(schema, "ignore-hosts", "[" .. table.concat(ignored, ", ") .. "]")
        if profile.type == "socks5" then
            set(schema .. ".socks", "host", host)
            set(schema .. ".socks", "port", port)
            set(schema .. ".http", "host", "''")
            set(schema .. ".https", "host", "''")
        else
            set(schema .. ".http", "host", host)
            set(schema .. ".http", "port", port)
            set(schema .. ".https", "host", host)
            set(schema .. ".https", "port", port)
            set(schema .. ".socks", "host", "''")
        end
        set(schema, "mode", "manual")
    end
    -- One after the other, as one change: no shell between them, so nothing
    -- is quoted twice.
    writing = true
    local i = 0
    local function next_set()
        i += 1
        local s = sets[i]
        if not s then
            writing = false
            if again then
                again = false
                apply()
            end
            return
        end
        local said = {}
        g.process {
            command = { "gsettings", "set", s[1], s[2], s[3] },
            on_error_line = function(line: string) table.insert(said, line) end,
            on_exit = function(code: number)
                if code ~= 0 then print("Bioma: the proxy setting was not written — " .. table.concat(said, " ")) end
                next_set()
            end,
        }
    end
    next_set()
end

local started = false
function M.start()
    if started then return end
    started = true
    local settled = false
    g.after(timing.seconds.settle, function()
        settled = true
        apply()
    end)
    g.watch(function(): string
        local p = M.current()
        if not p then return "none" end
        return table.concat({ tostring(p.type), tostring(p.host), tostring(p.port), M.exceptions() }, "\n")
    end, function() if settled then apply() end end)
    g.watch(function() return #profiles() end, function(count: number)
        if settled and count == 0 and touched then apply() end
    end)
end

return M
