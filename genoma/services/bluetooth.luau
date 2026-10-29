--!strict
-- Bluetooth: the adapter and its devices (services/Bluetooth.qml at
-- 11bb81e), on Genoma's BlueZ domain.
--
-- Discovery runs only while something asks for it (a list on screen): an
-- adapter that is always discovering spends radio and battery to show a
-- list nobody is looking at.
local g = require("@genoma")
local bluez = require("@genoma/bluetooth")

local M = {}

local adapter = g.computed(function(): any return bluez.adapter end)
local devices = g.computed(function(): { any } return bluez.devices end)

function M.available(): boolean return adapter.value ~= nil end
function M.adapter_name(): string local a = adapter.value return if a then a.name else "" end
function M.enabled(): boolean local a = adapter.value return a ~= nil and a.powered end

-- Between asking for power and BlueZ reporting it, the switch is settling:
-- a second press then would undo the first.
local wanted = g.signal(nil :: boolean?)
function M.settling(): boolean
    local w = wanted.value
    return w ~= nil and w ~= M.enabled()
end
g.watch(M.enabled, function(on: boolean)
    if g.untracked(function() return wanted.value end) == on then wanted.value = nil end
end)
function M.set_enabled(on: boolean)
    if not g.untracked(M.available) then return end
    wanted.value = on
    bluez:set_powered(on)
end

local discovering = g.signal(false)
function M.discovering(): boolean return discovering.value end
function M.set_discovering(on: boolean)
    if g.untracked(function() return discovering.value end) == on then return end
    discovering.value = on
    bluez:set_discovering(on)
end
-- What the adapter itself reports, which is what the glyph shows.
function M.scanning(): boolean local a = adapter.value return a ~= nil and a.discovering end

local function where(test: (any) -> boolean): { any }
    local out = {}
    for _, d in devices.value do
        if test(d) then table.insert(out, d) end
    end
    return out
end
local connected = g.computed(function() return where(function(d) return d.connected end) end)
local paired = g.computed(function() return where(function(d) return d.paired end) end)
-- Discovered and unpaired, named: a bare address is a device that has not
-- said what it is, and a list of MAC addresses is noise.
local found = g.computed(function()
    return where(function(d)
        if d.paired then return false end
        local name = if d.name ~= "" then d.name else d.device_name or ""
        return name ~= "" and not string.match(name, "^%x%x[-:]%x%x[-:]%x%x[-:]%x%x[-:]%x%x[-:]%x%x$")
    end)
end)
function M.connected_devices(): { any } return connected.value end
function M.paired_devices(): { any } return paired.value end
function M.found_devices(): { any } return found.value end
function M.any_connected(): boolean return #connected.value > 0 end
function M.primary(): any return connected.value[1] end

-- Genoma names the call in flight ("pairing", "connecting"…), or "".
function M.is_busy(d: any): boolean return d ~= nil and (d.busy or "") ~= "" end
function M.is_pairing(d: any): boolean return d ~= nil and d.busy == "pairing" end
function M.describe(d: any): string
    if not d then return "" end
    if d.name ~= "" then return d.name end
    if (d.device_name or "") ~= "" then return d.device_name end
    return d.address or ""
end
function M.icon(d: any): string return if d then d.icon or "" else "" end
function M.has_battery(d: any): boolean return d ~= nil and d.battery ~= nil end
function M.battery_percent(d: any): number
    local v = if d and d.battery then d.battery else 0
    return math.floor((if v <= 1 then v * 100 else v) + 0.5)
end

function M.connect_device(d: any) if d then bluez:connect(d.address) end end
function M.disconnect_device(d: any) if d then bluez:disconnect(d.address) end end
function M.forget(d: any) if d then bluez:forget(d.address) end end
function M.set_trusted(d: any, on: boolean) if d then bluez:set_trusted(d.address, on) end end
function M.cancel_pair(d: any) if d then bluez:cancel_pair(d.address) end end

-- Pairing, then trusting, then connecting: what a person means by pressing
-- a device they have never used. The address of one that failed is kept,
-- so its row can say so.
local pending = g.signal("")
local failed = g.signal("")
function M.failed_address(): string return failed.value end
function M.pair_and_connect(d: any)
    if not d then return end
    failed.value = ""
    pending.value = d.address
    bluez:pair(d.address)
end
g.watch(function()
    local address = pending.value
    if address == "" then return nil end
    for _, d in devices.value do
        if d.address == address then return { address = address, paired = d.paired, busy = M.is_busy(d) } end
    end
    return nil
end, function(state: any)
    if not state then return end
    if state.paired then
        bluez:set_trusted(state.address, true)
        bluez:connect(state.address)
        pending.value = ""
    elseif not state.busy then
        -- Not paired and no longer pairing: it failed, or was refused.
        local f = g.untracked(function() return bluez.failure end)
        if f and f.address == state.address then
            failed.value = state.address
            pending.value = ""
        end
    end
end)

return M
