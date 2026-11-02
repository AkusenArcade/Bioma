--!strict
-- The time spent at this machine, day by day (services/Activity.qml at
-- 2cafc17): minutes present, kept in ~/.config/bioma/activity.json, which
-- the growth rings organism draws.
--
-- Counted by Bioma on Quickshell while the two run side by side: being
-- present is knowing the user is idle or not, and only one of the two may
-- write the file (genoma/PORT.md, "Who acts on the desktop"). Here it is
-- read, and read again when it changes.
local g = require("@genoma")

local M = {}

local home = g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")
local PATH = home .. "/bioma/activity.json"

local holders = g.signal(0)
function M.hold(on: boolean)
    holders.value = math.max(0, g.untracked(function() return holders.value end) + (if on then 1 else -1))
end

-- Read from the load, not from inside the effect below: made there, it
-- would be the effect's, and go with its next run.
local file = g.file { path = PATH }
local days = g.signal({} :: { [string]: number })
local loaded = g.signal(false)
g.effect(function()
    if holders.value <= 0 then return end
    local text = file.text
    g.untracked(function()
        local ok, data = pcall(g.parse_json, text or "")
        days.value = if ok and type(data) == "table" and type(data.days) == "table" then data.days else {}
        loaded.value = true
    end)
end)

function M.days(): { [string]: number } return days.value end
function M.loaded(): boolean return loaded.value end
function M.date_key(seconds: number): string return os.date("%Y-%m-%d", seconds) :: string end
function M.today(): string
    local _ = require("@genoma/clock").hour
    return M.date_key(os.time())
end
function M.today_minutes(): number return days.value[M.today()] or 0 end

return M
