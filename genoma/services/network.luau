--!strict
-- The network: the wired link, Wi-Fi and whether the internet is reachable
-- (services/Network.qml at 11bb81e), on Genoma's NetworkManager domain.
--
-- A device that is there but not connected is still reported, so the cell
-- can say "cable unplugged" rather than nothing.
local g = require("@genoma")
local nm = require("@genoma/network")

local M = {}

function M.available(): boolean return nm.available end

local devices = g.computed(function(): { any } return nm.devices end)
local networks = g.computed(function(): { any } return nm.networks end)

-- The connected device of a kind first, else the first of that kind.
local function device_of(kind: string): any
    local first = nil
    for _, d in devices.value do
        if d.kind == kind then
            if d.connected then return d end
            first = first or d
        end
    end
    return first
end

-- ---- Wired ----------------------------------------------------------------

local wired = g.computed(function(): any return device_of("ethernet") end)
function M.wired_present(): boolean return wired.value ~= nil end
function M.wired_connected(): boolean local d = wired.value return d ~= nil and d.connected end
function M.wired_has_link(): boolean local d = wired.value return d ~= nil and d.carrier end
function M.wired_interface(): string local d = wired.value return if d then d.interface else "" end
-- The profile in use, which is also what NetworkManager calls the link.
function M.wired_name(): string local d = wired.value return if d then d.connection or "" else "" end
function M.wired_profile(): string return M.wired_name() end
-- Mb/s; 0 when the driver does not say.
function M.wired_speed(): number local d = wired.value return if d then d.speed or 0 else 0 end

-- ---- Wi-Fi ----------------------------------------------------------------

local wifi = g.computed(function(): any return device_of("wifi") end)
function M.wifi_present(): boolean return wifi.value ~= nil end
function M.wifi_enabled(): boolean return nm.wifi_enabled end
function M.wifi_hardware_enabled(): boolean return nm.wifi_hardware end

local active = g.computed(function(): any
    for _, n in networks.value do
        if n.connected then return n end
    end
    return nil
end)
function M.active_wifi(): any return active.value end
function M.wifi_connected(): boolean return active.value ~= nil end
function M.ssid(): string local n = active.value return if n then n.ssid else "" end
function M.signal_strength(): number local n = active.value return if n then n.strength else 0 end
function M.signal_percent(): number return math.floor(M.signal_strength() * 100 + 0.5) end

-- Strength as four steps, the way the glyph draws it.
function M.bars_for(strength: number?): number
    local s = strength or 0
    if s <= 0 then return 0 end
    if s <= 0.25 then return 1 end
    if s <= 0.5 then return 2 end
    if s <= 0.75 then return 3 end
    return 4
end
function M.signal_bars(): number return M.bars_for(M.signal_strength()) end

function M.set_wifi_enabled(on: boolean) nm:set_wifi_enabled(on) end

-- Scanning costs radio time, so it runs only while a list is on screen.
local scanning = g.signal(false)
function M.scanning(): boolean return scanning.value end
function M.set_scanning(on: boolean)
    if g.untracked(function() return scanning.value end) == on then return end
    scanning.value = on
    nm:set_scanning(on)
end

-- One entry per name, the strongest access point standing for it: the
-- connected one first, then those with a saved profile, then by strength.
local visible = g.computed(function(): { any }
    local best: { [string]: any } = {}
    for _, n in networks.value do
        if n.ssid ~= "" then
            local previous = best[n.ssid]
            if not previous or n.connected or n.strength > previous.strength then best[n.ssid] = n end
        end
    end
    local out = {}
    for _, n in best do table.insert(out, n) end
    table.sort(out, function(a, b)
        if a.connected ~= b.connected then return a.connected end
        if a.known ~= b.known then return a.known end
        if a.strength ~= b.strength then return a.strength > b.strength end
        return a.ssid < b.ssid
    end)
    return out
end)
function M.visible_networks(): { any } return visible.value end

function M.is_secured(n: any): boolean return n ~= nil and n.secured == true end
-- A secured network with no saved profile is the only one that asks.
function M.needs_password(n: any): boolean return M.is_secured(n) and not n.known end

-- ---- Joining ------------------------------------------------------------------
--
-- Joining is asynchronous and can fail; the reason is the domain's, kept
-- until the next attempt.
function M.last_error(): string return nm.failure or "" end
function M.join(n: any) if n then nm:join(n.ssid) end end
function M.join_with_password(n: any, password: string) if n then nm:join(n.ssid, password) end end
function M.leave(_: any?) nm:leave() end
function M.forget(n: any) if n then nm:forget(n.ssid) end end

-- ---- Reachability -------------------------------------------------------------
--
-- A link is not the internet: a cable into a dead switch is connected.
function M.can_check_reachability(): boolean return nm.can_check end
function M.reachability(): string return nm.connectivity end
function M.reachability_known(): boolean return nm.can_check and nm.connectivity ~= "unknown" end
function M.online(): boolean return M.reachability_known() and nm.connectivity == "full" end
function M.captive_portal(): boolean return nm.connectivity == "portal" end
function M.check_reachability() if nm.can_check then nm:check_connectivity() end end

function M.connected(): boolean return M.wired_connected() or M.wifi_connected() end

return M
