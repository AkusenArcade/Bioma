--!strict
-- The power profile (services/Power.qml at 11bb81e), on Genoma's
-- power-profiles domain.
--
-- Following the mains (a profile on battery, another on the plug) acts on
-- the machine: `start` runs it once the switch is made (M6 step 7a);
-- beside Quickshell it is Quickshell's (genoma/PORT.md, "Who acts on the
-- desktop"). A profile chosen by hand here is a choice, and is set.
local g = require("@genoma")
local power = require("@genoma/power")
local config = require("core/config")

local M = {}

-- Without the daemon there is no profile to show.
function M.present(): boolean return power.profile ~= "" end

-- "saver", "balanced", "performance", Bioma's names for the daemon's.
function M.profile(): string
    local p = power.profile
    if p == "power-saver" then return "saver" end
    if p == "performance" then return "performance" end
    return "balanced"
end

function M.performance_available(): boolean
    return table.find(power.profiles, "performance") ~= nil
end

function M.held_back(): string
    if M.profile() ~= "performance" then return "" end
    local d = power.degraded
    if d == "lap-detected" then return "Held back: the machine is on a lap" end
    if d == "high-operator-temperature" then return "Held back: the machine is running hot" end
    return ""
end

function M.set(key: string)
    if not M.present() then return end
    if key == "saver" then power:set_profile("power-saver")
    elseif key == "performance" and M.performance_available() then power:set_profile("performance")
    elseif key == "balanced" then power:set_profile("balanced") end
end

-- ---- Following the power source ------------------------------------------
--
-- On a machine with a battery, `power.on_battery` and `power.on_mains`, each
-- a profile or `keep`. A moment after the source changes: short enough that
-- nobody waits for it, long enough to let UPower finish answering, and a
-- plug that is wiggled sets the profile once, not four times.
--
-- The source reads the profile itself (through `present`) and the whole
-- battery, so it re-runs when a profile is chosen by hand and each time the
-- charge moves. g.watch calls the handler on every re-run, not only on a
-- change, so the handler acts only when what is wanted is different —
-- otherwise the hand-chosen profile is put straight back.
local started = false
function M.start()
    if started then return end
    started = true
    local follow: any = nil
    local last = ""
    g.watch(function(): string
        local b = power.battery
        local settled = M.present() and b.laptop and b.present
        if not settled then return "" end
        local source = if power.on_battery then "battery" else "mains"
        return source .. ":" .. config.get("power.on_" .. source, "keep")
    end, function(key: string)
        if key == last then return end
        last = key
        local wanted = string.match(key, ":(.*)$") or ""
        if follow then follow:stop() end
        follow = g.after(0.4, function()
            follow = nil
            if wanted ~= "" and wanted ~= "keep" then M.set(wanted) end
        end)
    end)
end

return M
