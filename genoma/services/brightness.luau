--!strict
-- Display brightness (services/Brightness.qml at 8ed8892), on Genoma's
-- `@genoma/brightness` since Genoma 0.1.16.
--
-- Two backends and, above all, a capability check:
--   backlight  /sys/class/backlight, written through logind: laptops and
--              any panel the kernel drives directly; of several, the one
--              under a connected DRM connector (Genoma ranks them as this
--              file did: a hybrid laptop's `nvidia_0` took every write while
--              the panel stayed where it was, 2026-11-04);
--   ddc        DDC/CI through ddcutil on a thread of Genoma's: external
--              monitors, each by its own bus, writes coalesced so a dragged
--              control never queues.
-- With neither, `available` is false and every control does nothing: a
-- control that cannot change anything is not offered.
--
-- What is Bioma's: which backend is in use (`brightness.backend`), which
-- monitor the bare `brightness` and `set` mean (`brightness.display`), and
-- how a monitor is named.
local g = require("@genoma")
local config = require("core/config")
local native = require("@genoma/brightness")

local M = {}

-- auto | backlight | ddc | off
local function configured(): string return config.get("brightness.backend", "auto") end

function M.error(): string return native.error end

local function of_kind(kind: string): { any }
    local out = {}
    for _, d in native.displays do
        if d.kind == kind then table.insert(out, d) end
    end
    return out
end

local function backlight(): any return of_kind("backlight")[1] end

function M.backend(): string
    local c = configured()
    if c == "off" then return "off" end
    if backlight() and (c == "auto" or c == "backlight") then return "backlight" end
    if #of_kind("ddc") > 0 and (c == "auto" or c == "ddc") then return "ddc" end
    return "none"
end
function M.available(): boolean
    local b = M.backend()
    return b == "backlight" or b == "ddc"
end
-- The monitors DDC found: { connector, model, value (0…1 or nil), max }.
function M.displays(): { any } return of_kind("ddc") end

local function display_for(connector: string): any
    for _, d in of_kind("ddc") do if d.connector == connector then return d end end
    return nil
end
-- Which display the bare `brightness` and `set` mean: the configured
-- connector, else the first.
function M.display(): any
    local wanted = config.get("brightness.display", "")
    if wanted ~= "" then
        local chosen = display_for(wanted)
        if chosen then return chosen end
    end
    return of_kind("ddc")[1]
end

-- A monitor's own words for itself; the connector always exists.
function M.describe(entry: any): string
    if not entry then return "" end
    return if entry.model and entry.model ~= "" then entry.model .. " (" .. entry.connector .. ")" else entry.connector
end

function M.brightness(): number
    local b = M.backend()
    if b == "backlight" then
        local l = backlight()
        return if l and l.value then l.value else 0
    end
    local d = M.display()
    if b == "ddc" and d and d.value then return d.value end
    return 0
end
-- Whether `brightness` is a reading yet: over DDC the first answer comes
-- seconds after start, and going from nothing to what it is is not a change.
function M.known(): boolean
    local b = M.backend()
    if b == "backlight" then
        local l = backlight()
        return l ~= nil and l.value ~= nil
    end
    if b == "ddc" then
        local d = M.display()
        return d ~= nil and d.value ~= nil
    end
    return false
end
-- -1 while that display has not answered, which is not 0.
function M.brightness_for(connector: string): number
    local d = display_for(connector)
    return if d and d.value then d.value else -1
end

-- Writes read what they need untracked: called from an effect, they must
-- not make it depend on the brightness they change.
function M.set_for(connector: string, fraction: number)
    if g.untracked(M.backend) ~= "ddc" then return end
    native:set(math.clamp(fraction, 0, 1), connector)
end

function M.set(fraction: number)
    local b = g.untracked(M.backend)
    if b == "backlight" then
        -- Never quite off: a panel at 0 is a screen that looks broken.
        local l = g.untracked(backlight)
        if l then native:set(math.clamp(fraction, 0.01, 1), l.connector) end
    elseif b == "ddc" then
        local d = g.untracked(M.display)
        if d then M.set_for(d.connector, fraction) end
    end
end

function M.step(delta: number) M.set(math.clamp(g.untracked(M.brightness) + delta, 0, 1)) end

return M
