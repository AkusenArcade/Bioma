--!strict
-- The wallpaper and the palette derived from it (cells/theme/ThemeCell.qml
-- at 60ca560). See docs/design/CELLS.md §07.
--
-- At rest this is not an icon that represents the theme: it is the palette,
-- seven chips in a row. Change the wallpaper and the cell changes, which is
-- seen without opening anything: the contracted cell is the data. It moves
-- only when the theme changes, the chips replacing each other a stagger
-- apart, never on a clock.
--
-- Conditional, it is there for a moment after the palette changes, so the
-- change is seen where it is made.
local g = require("@genoma")
local theme = require("core/theme")
local metrics_mod = require("core/metrics")
local expansion = require("cells/theme_expansion")

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function chip_width(): number return 10 * f() end
        local function chip_height(): number return 22 * f() end
        local function chip_gap(): number return 3 * f() end

        -- The destination, not the transit: a chip bound to a colour that is
        -- itself moving would restart its delay on every frame.
        g.watch(function()
            return theme.target("background") .. theme.target("primary") .. theme.target("secondary")
                .. theme.target("text")
        end, function() cell.pulse() end)

        local opened = expansion.new(cell)
        local row: { [any]: any } = { direction = "row", align = "center", gap = chip_gap }
        for i = 1, 7 do
            table.insert(row, g.capsule {
                width = chip_width,
                height = chip_height,
                radius = function() return metrics_mod.shaped(5 * f()) end,
                fill = function() return theme.target_roles()[i] end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                transition = { fill = "chip_" .. i },
            })
        end

        return {
            panel = opened.panel,
            on_key = opened.on_key,
            padding_leading = 16,
            padding_trailing = 16,
            condition = function() return if cell.pulsing() then 1 else 0 end,
            content_width = function() return 7 * chip_width() + 6 * chip_gap() end,
            header_title = "THEME",
            header_mark_size = function() return 22 * f() end,
            header_mark = function(mark: () -> number)
                return g.icon {
                    width = mark,
                    height = mark,
                    icon = "theme",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                }
            end,
            contracted = function() return g.box(row) end,
        }
    end,
}
