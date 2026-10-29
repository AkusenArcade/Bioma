--!strict
-- Performance mode (core/Performance.qml at 11bb81e): the shell stepping
-- back, by hand or while something that wants the machine runs.
--
-- By hand is the configuration's `performance.manual`, shared with Bioma on
-- Quickshell, so the two step back together. Turned off by hand while a
-- trigger holds it, it stays off until that trigger ends. Each lever is
-- chosen in Settings (`performance.suspend.<lever>`); the ones that have
-- something to act on here are read where they act: motion (timing and
-- the live indicators), blur, transitions, polling. The organisms and the
-- wallpaper are still Quickshell's.
local g = require("@genoma")
local config = require("core/config")
local workload = require("services/workload")

local M = {}

function M.manual(): boolean return config.get("performance.manual", false) == true end
function M.triggers(): { any } return workload.triggers() end
function M.triggered(): boolean return #workload.triggers() > 0 end

local refused = g.signal(false)
g.watch(M.triggered, function(on: boolean) if not on then refused.value = false end end)
function M.refused(): boolean return refused.value end

function M.active(): boolean return M.manual() or (M.triggered() and not refused.value) end

function M.lever(name: string): boolean
    return M.active() and config.get("performance.suspend." .. name, true) ~= false
end
function M.still(): boolean return M.lever("motion") end
function M.flat(): boolean return M.lever("blur") end
function M.instant(): boolean return M.lever("transitions") end
function M.sparse(): boolean return M.lever("polling") end
-- What a shape blurs behind it: the configuration's choice, unless the
-- blur lever is pulled.
function M.blurred(): boolean return config.get("cell.blur", true) == true and not M.flat() end
function M.vitals_interval(): number return math.max(2000, config.get("performance.vitals_interval", 10000)) end

function M.on()
    refused.value = false
    if not g.untracked(M.manual) and not g.untracked(M.triggered) then config.set("performance.manual", true) end
end
function M.off()
    if g.untracked(M.manual) then config.set("performance.manual", false) end
    if g.untracked(M.triggered) then refused.value = true end
end
function M.toggle() if g.untracked(M.active) then M.off() else M.on() end end

function M.reason(): string
    if not M.active() then return "" end
    if M.manual() then return "by hand" end
    local games, names = false, {}
    for _, t in M.triggers() do
        if t.kind == "game" then games = true elseif t.kind == "app" then table.insert(names, t.name) end
    end
    local parts = {}
    if games then table.insert(parts, "a game runs") end
    if #names > 0 then table.insert(parts, table.concat(names, ", ") .. (if #names == 1 then " is" else " are") .. " open") end
    return if #parts > 0 then "while " .. table.concat(parts, " and ") else ""
end

return M
