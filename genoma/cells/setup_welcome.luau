--!strict
-- The setup's first page (cells/settings/SetupWelcome.qml at 2cafc17): what
-- this is, before anything is asked. See docs/design/SETUP.md, step 0.
--
-- The greeter's welcome, set inside the panel rather than over the screen:
-- a splash of its own would appear from nowhere, and the mark belongs to
-- the settings cell alone. "Welcome to", then the mark, the name and the
-- line, one after the next at the welcome's own pace, each let in from just
-- above; then what the steps are for. It runs once, as the page arrives.
local g = require("@genoma")
local theme = require("core/theme")
local typography = require("core/typography")

local M = {}

-- `t`: metrics(), width(), height().
function M.new(t: { [string]: any }): any
    local function f(): number return t.metrics().factor end
    local here = g.signal(false)
    g.after(0, function() here.value = true end)

    -- One line of the greeting: in after `index` staggers, from above.
    local function greeted(index: number, node: { [any]: any }): any
        node.opacity = function() return if here.value then 1 else 0 end
        node.offset_y = function() return if here.value then 0 else -4 * f() end
        node.transition = { opacity = "welcome_" .. index, offset_y = "welcome_" .. index }
        return node
    end
    local function spacer(h: number): any return g.box { height = function() return h * f() end } end
    local function unit(): number return math.round(96 * f()) end

    return g.box {
        width = t.width,
        height = t.height,
        direction = "column",
        align = "center",
        justify = "center",
        g.text(greeted(1, {
            text = "Welcome to",
            color = theme.text_muted,
            font = typography.expressive,
            size = function() return math.round(18 * f()) end,
        })),
        spacer(20),
        -- The logotype (components/Logotype.qml): the mark, the name in
        -- Orbitron and the line under it in Spectral, in units of the mark.
        g.icon(greeted(2, {
            width = unit,
            height = unit,
            icon = "mark",
            gradient_top = function() return theme.gradient_top(theme.primary()) end,
            gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
        })),
        spacer(10),
        g.text(greeted(3, {
            text = "BIOMA",
            color = theme.text,
            font = typography.technical,
            size = function() return math.round(0.18 * unit() / 0.72) end,
            tracking = 0.02,
        })),
        spacer(4),
        g.text(greeted(4, {
            text = "A Living Shell",
            color = theme.text_muted,
            font = typography.expressive,
            size = function() return math.round(0.094 * unit() / 0.66) end,
        })),
        spacer(36),
        g.text(greeted(5, {
            text = "A few steps put the desktop together: where things go, how it looks, its keys in niri, "
                .. "and the login screen. Every answer can be changed later, and any step can be skipped.",
            color = theme.text,
            font = typography.expressive,
            size = function() return t.metrics().font_secondary end,
            wrap = true,
            text_align = "center",
            max_width = function() return t.width() - 48 * f() end,
        })),
    }
end

return M
