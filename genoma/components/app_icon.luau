--!strict
-- An application's icon in a launcher's result row: the icon (or, with
-- none, the fallback glyph) clipped to a circle, and the ring round it on
-- the row reached. The circle is the inside of the ring, so a full-bleed
-- square icon keeps its corners within the ring whether it is lit or not,
-- and a round one is left whole.
local g = require("@genoma")
local theme = require("core/theme")

local M = {}

-- `t`: slot() (the box the row lays out), ring() (the ring's diameter),
-- stroke() (its line), icon() and fallback() (the two sizes), source()
-- (an icon file, or ""), picked() (the row reached).
function M.new(t: { [string]: any }): any
    local function inside(): number return t.ring() - t.stroke() * 2 end
    return g.box {
        width = t.slot,
        height = t.slot,
        align = "center",
        justify = "center",
        g.capsule {
            overlay = true,
            present = t.picked,
            width = t.ring,
            height = t.ring,
            stroke = t.stroke,
            rim_top = theme.primary,
            rim_bottom = theme.primary,
        },
        -- The icon and the circle it is shown through, apart from the ring
        -- so the mask does not take the ring with it.
        g.box {
            width = t.slot,
            height = t.slot,
            align = "center",
            justify = "center",
            g.icon {
                present = function() return t.source() ~= "" end,
                width = t.icon,
                height = t.icon,
                icon = t.source,
            },
            g.icon {
                present = function() return t.source() == "" end,
                width = t.fallback,
                height = t.fallback,
                icon = "app-fallback",
                color = theme.text_muted,
            },
            g.capsule {
                mask = true,
                overlay = true,
                width = inside,
                height = inside,
                fill = "#ffffffff",
                rim_top = "#00000000",
                rim_bottom = "#00000000",
            },
        },
    }
end

return M
