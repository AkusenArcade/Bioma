--!strict
-- A button's name, under it, for a button that has no words: the trash, a
-- pencil, a cross, a step up or down (Akusen, 2026-11-04, Piano UI 10).
-- At rest the interface does not speak, so the name comes only once the
-- pointer has rested on the button a moment, and goes with it: the value
-- arriving under the hand, as STYLE_GUIDE §1 has it. It is the command's
-- name, so in the technical voice, upper case, as on a button.
--
-- Drawn raised, over whatever lies below the button (the next row, the
-- panel's edge), and it takes no pointer.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")

local M = {}

-- `t`: text (string or function), over() (the pointer is on the button),
-- factor(), and optionally quiet() (true while the button says something
-- itself, as the trash asking REMOVE?). Returns the node to put inside the
-- button, as its last child.
function M.new(t: { [string]: any }): any
    local function f(): number return t.factor() end
    local shown = g.signal(false)
    local waiting: any = nil
    g.watch(function() return t.over() end, function(on: boolean)
        if waiting then waiting:stop() end
        waiting = nil
        if not on then
            shown.value = false
            return
        end
        waiting = g.after(timing.seconds.hint, function()
            waiting = nil
            if g.untracked(t.over) then shown.value = true end
        end)
    end)
    local function text(): string
        local s = if type(t.text) == "function" then t.text() else t.text
        return string.upper(s or "")
    end
    local function visible(): boolean
        return shown.value and not (t.quiet and t.quiet())
    end
    return g.capsule {
        overlay = true,
        attach = "below-center",
        raised = true,
        present = function() return shown.value end,
        offset_y = function() return 6 * f() end,
        height = function() return 22 * f() end,
        padding_x = function() return 9 * f() end,
        align = "center",
        justify = "center",
        radius = function() return 11 * f() end,
        fill = function() return colour.alpha(theme.cell(), math.max(0.92, config.get("cell.opacity", 0.72))) end,
        rim_top = theme.rim,
        rim_bottom = theme.line,
        opacity = function() return if visible() then 1 else 0 end,
        transition = { opacity = "content_fade" },
        g.text {
            text = text,
            color = theme.text,
            font = typography.technical,
            size = function() return math.round(10 * f()) end,
            weight = typography.weight_label,
            tracking = typography.label_tracking,
        },
    }
end

return M
