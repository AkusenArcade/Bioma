--!strict
-- The session: who is here and how the session ends (cells/system/
-- SystemCell.qml at 11bb81e). At rest the person's picture; opened, the
-- identity, the five actions, the machine and its power profile.
--
-- Conditional, it is there while a restart is due: the kernel running has
-- been replaced by an upgrade.
local g = require("@genoma")
local theme = require("core/theme")
local session = require("services/session")
local portrait = require("components/portrait")
local expansion = require("cells/system_expansion")

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function avatar(): number return 30 * f() end
        local opened = expansion.new(cell)
        g.watch(function() return cell.open.value end, function(open: boolean)
            if not open then session.cancel() end
        end)
        return {
            panel = opened.panel,
            on_key = opened.on_key,
            padding_leading = function() return (cell.metrics().cell_height - avatar()) / 2 end,
            padding_trailing = function() return (cell.metrics().cell_height - avatar()) / 2 end,
            condition = function() return if session.restart_due() then 1 else 0 end,
            content_width = avatar,
            header_title = "SYSTEM",
            header_mark_size = function() return 20 * f() end,
            header_mark = function(mark: () -> number)
                return g.icon {
                    width = mark,
                    height = mark,
                    icon = "power",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                }
            end,
            contracted = function() return portrait.new { size = avatar, source = session.avatar } end,
        }
    end,
}
