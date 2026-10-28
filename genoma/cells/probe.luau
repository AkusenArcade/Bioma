--!strict
-- A cell for testing the layout engine, and nothing else: a label (longer
-- at each press, back at the fifth), and with `blink` a condition that comes
-- and goes every so many seconds. It is no domain of Bioma's and is never
-- offered anywhere.
local g = require("@genoma")
local theme = require("core/theme")
local typography = require("core/typography")

return {
    new = function(cell: any)
        local base = cell.option("label", "probe")
        local label = g.signal(base)
        local on = g.signal(1)
        local every = cell.option("blink", 0)
        if every > 0 then
            g.timer { every = every, on_tick = function() on.value = 1 - on.value end }
        end
        local function size(): number return cell.metrics().font_label end
        return {
            contracted = function()
                return g.text {
                    font = typography.expressive(),
                    size = size(),
                    color = theme.text,
                    text = function() return label.value end,
                    max_width = cell.room,
                }
            end,
            content_width = function()
                return g.text_width { text = label.value, font = typography.expressive(), size = size() }
            end,
            condition = function() return on.value end,
            interactive = true,
            on_click = function()
                label.value = if #label.value < #base + 28 then label.value .. " longer" else base
            end,
        }
    end,
}
