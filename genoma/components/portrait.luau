--!strict
-- A person's picture in a ring (components/Portrait.qml at 11bb81e), or,
-- with none, the silhouette: a head and shoulders in the rim's light, the
-- place where a picture would be rather than an initial standing in for it.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")

local M = {}

-- `t`: size(), source() (a file, or "").
function M.new(t: { [string]: any }): any
    local function unit(): number return t.size() / 64 end
    local function bare(): boolean return t.source() == "" end
    local CLEAR = "#00000000"
    return g.capsule {
        width = t.size,
        height = t.size,
        fill = function() return theme.lift(theme.background(), -0.015) end,
        rim_top = function() return colour.alpha(theme.text(), 0.5) end,
        rim_bottom = function() return colour.alpha(theme.text(), 0.5) end,
        g.image {
            overlay = true,
            present = function() return not bare() end,
            src = t.source,
            width = t.size,
            height = t.size,
            fit = "cover",
            radius = function() return t.size() / 2 end,
        },
        -- The head.
        g.capsule {
            overlay = true,
            attach = "corner",
            present = bare,
            offset_x = function() return (32 - 11) * unit() end,
            offset_y = function() return (25 - 11) * unit() end,
            width = function() return 22 * unit() end,
            height = function() return 22 * unit() end,
            fill = function() return colour.alpha(theme.rim(), 0.55) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
        },
        -- The shoulders: the top half of a disc.
        g.box {
            overlay = true,
            attach = "corner",
            present = bare,
            offset_x = function() return (32 - 21) * unit() end,
            offset_y = function() return (58 - 21) * unit() end,
            width = function() return 42 * unit() end,
            height = function() return 21 * unit() end,
            clip = true,
            g.capsule {
                overlay = true,
                attach = "corner",
                width = function() return 42 * unit() end,
                height = function() return 42 * unit() end,
                fill = function() return colour.alpha(theme.rim(), 0.45) end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
            },
        },
    }
end

return M
