--!strict
-- A level the user sets by hand (components/Slider.qml at 11bb81e): a thin
-- track, the travel in the gradient, a handle at its head. A press puts the
-- value where it landed, a drag carries it.
--
-- Not yet: Left and Right, with the keyboard's travel inside an open cell.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")

local M = {}

-- `t`: width(), factor(), value() (0…1), dimmed(), on_move(value).
function M.new(t: { [string]: any }): any
    local function track_height(): number return 3 * t.factor() end
    local function handle(): number return 14 * t.factor() end
    local function travel(): number return math.clamp(t.value(), 0, 1) end
    local function top(): string return theme.gradient_top(theme.primary()) end
    local function bottom(): string return theme.gradient_bottom(theme.primary()) end
    local function report(x: number)
        t.on_move(math.clamp(x / math.max(1, g.untracked(t.width)), 0, 1))
    end
    local held = false

    return g.box {
        role = "slider",
        width = t.width,
        height = handle,
        justify = "start",
        align = "center",
        opacity = function() return if t.dimmed() then 0.45 else 1 end,
        transition = { opacity = "transition" },
        on_press = function(button: number, x: number)
            if button ~= 272 then return end
            held = true
            report(x)
        end,
        on_drag = function(x: number) if held then report(x) end end,
        on_release = function() held = false end,
        -- The press is the slider's: it must not reach the cell under it.
        on_click = function() end,
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_y = function() return (handle() - track_height()) / 2 end,
            width = t.width,
            height = track_height,
            radius = function() return metrics_mod.shaped(track_height() / 2) end,
            fill = function() return colour.alpha(theme.line(), 0.55) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_y = function() return (handle() - track_height()) / 2 end,
            width = function() return t.width() * travel() end,
            height = track_height,
            radius = function() return metrics_mod.shaped(track_height() / 2) end,
            fill = top,
            fill_bottom = bottom,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() return t.width() * travel() - handle() / 2 end,
            width = handle,
            height = handle,
            radius = function() return metrics_mod.shaped(handle() / 2) end,
            fill = top,
            fill_bottom = bottom,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
    }
end

return M
