--!strict
-- Two voices (core/Typography.qml): if the system measured it, technical —
-- Orbitron; if it came from a human, expressive — Spectral. Sizes follow the
-- density step and live in metrics.step().
local config = require("core/config")

local M = {}

function M.expressive(): string return config.get("fonts.expressive", "Spectral") end
function M.technical(): string return config.get("fonts.technical", "Orbitron") end

-- 700 is for titles only; values and metadata stay at their scale weights.
M.weight_value = 500
M.weight_label = 500
M.weight_secondary = 400
M.weight_title = 700

-- Labels are uppercase and tracked out, in em.
M.label_tracking = 0.06

-- In logical units, as Qt's letterSpacing takes it. Genoma's text takes
-- tracking in em: pass `label_tracking` itself there, not this.
function M.tracking(pixel_size: number, em: number): number
    return pixel_size * em
end

return M
