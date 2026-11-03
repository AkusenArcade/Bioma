--!strict
-- Which runtime a part of Bioma belongs to (genoma/PORT.md, "Who draws
-- what"). Beside Quickshell, block by block: a membrane, a floating tissue
-- or an organism marked `"runtime": "genoma"`, the wallpaper by
-- `wallpaper.runtime`, the lock and the greeter by their own key. Alone,
-- after the switch: a top-level `"runtime": "genoma"` in the configuration
-- gives Genoma everything, and `scripts/bioma` starts Genoma instead of
-- Quickshell (Akusen, 2026-11-03).
local config = require("core/config")

local M = {}

-- Bioma on Genoma alone: the switch is made.
function M.alone(): boolean
    return config.get("runtime", "quickshell") == "genoma"
end

-- Whether a configuration block is Genoma's to draw.
function M.ours(entry: any): boolean
    if M.alone() then return true end
    return type(entry) == "table" and entry.runtime == "genoma"
end

-- Whether a part with a key of its own (`wallpaper`, `lock`, `greeter`) is.
function M.part(key: string): boolean
    return M.alone() or config.get(key .. ".runtime", "quickshell") == "genoma"
end

return M
