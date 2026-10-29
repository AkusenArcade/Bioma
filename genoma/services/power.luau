--!strict
-- The power profile (services/Power.qml at 11bb81e), on Genoma's
-- power-profiles domain.
--
-- Not here, on purpose: following the mains (a profile on battery, another
-- on the plug). It acts on the machine and stays Bioma on Quickshell's while
-- both run (genoma/PORT.md, "Who acts on the desktop"); a profile chosen by
-- hand here is a choice, and is set.
local power = require("@genoma/power")

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

return M
