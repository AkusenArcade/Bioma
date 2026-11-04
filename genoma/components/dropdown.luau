--!strict
-- A dropdown on a settings page (the media effect on the Cells page, the
-- presets on the Structure page): always the same width, only what it says
-- changes; pressed, its list is born from its bottom edge, over the page.
--
-- The list is the dropdown's own overlay, `raised`: drawn after the rows it
-- covers, with what lies under its glass erased first, as Quickshell cut
-- the page under it so the sharp rows did not show through the blur. The
-- choice is exclusive, so the mark may be a dot.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local performance = require("core/performance")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")

local M = {}

local CLEAR = "#00000000"

-- `t`: metrics(), width(), options() ({ { key, label } }), current(),
-- on_choose(key), and optionally height(). Returns the node and a handle:
-- open (a signal), close().
function M.new(t: { [string]: any }): (any, any)
    local function m(): any return t.metrics() end
    local function f(): number return m().factor end
    local function height(): number return if t.height then t.height() else 22 * f() end
    local function padding(): number return 6 * f() end
    local function row(): number return m().row_height end
    local function font_control(): number return math.round(12 * f()) end
    local open = g.signal(false)
    local hovered = g.signal(false)
    -- There while it grows and while it goes, gone once it has: a list at
    -- no size would still take the presses over the rows under it.
    local out = g.signal(false)
    local putting_away: any = nil
    g.watch(function() return open.value end, function(on: boolean)
        if putting_away then putting_away:stop() end
        putting_away = nil
        if on then
            out.value = true
        else
            putting_away = g.after(timing.seconds.close + timing.seconds.content_fade, function()
                out.value = false
            end)
        end
    end)

    local function label(): string
        for _, o in t.options() do
            if o.key == t.current() then return o.label end
        end
        return ""
    end
    local function list_height(): number return #t.options() * row() + padding() * 2 end
    local function choose(key: string)
        open.value = false
        if key ~= g.untracked(t.current) then t.on_choose(key) end
    end

    local function option_row(option: () -> any, index: () -> number): any
        local over = g.signal(false)
        local function current(): boolean return option().key == t.current() end
        return g.capsule {
            role = "button",
            overlay = true,
            attach = "corner",
            offset_y = function() return (index() - 1) * row() end,
            width = function() return t.width() - padding() * 2 end,
            height = row,
            direction = "row",
            align = "center",
            justify = "between",
            padding_x = function() return 10 * f() end,
            radius = function() return metrics_mod.radius_for(row(), m()) end,
            fill = function() return if over.value then colour.alpha(theme.text(), 0.06) else CLEAR end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            on_hover = function(on: boolean) over.value = on end,
            on_click = function() choose(g.untracked(option).key) end,
            g.text {
                text = function() return option().label end,
                color = function() return if current() then theme.text() else theme.text_muted() end,
                font = typography.technical,
                size = font_control,
                weight = typography.weight_label,
                tracking = 0.04,
                max_width = function() return t.width() - padding() * 2 - 34 * f() end,
            },
            g.capsule {
                opacity = function() return if current() then 1 else 0 end,
                width = function() return 6 * f() end,
                height = function() return 6 * f() end,
                fill = theme.primary,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
            },
        }
    end

    local function edge(): string
        if open.value then return theme.primary() end
        return if hovered.value then theme.text() else theme.control_edge()
    end

    local node = g.capsule {
        role = "button",
        width = t.width,
        height = height,
        direction = "row",
        align = "center",
        justify = "between",
        padding_left = function() return 10 * f() end,
        padding_right = function() return 10 * f() end,
        radius = function() return metrics_mod.radius_for(height(), m()) end,
        fill = CLEAR,
        rim_top = edge,
        rim_bottom = edge,
        on_hover = function(on: boolean) hovered.value = on end,
        on_click = function() open.value = not g.untracked(function() return open.value end) end,
        g.text {
            text = label,
            color = theme.text,
            font = typography.technical,
            size = function() return m().font_meta end,
            weight = typography.weight_label,
            tracking = 0.04,
            max_width = function() return t.width() - 35 * f() end,
        },
        g.icon {
            width = function() return 9 * f() end,
            height = function() return 9 * f() end,
            icon = "chevron-down",
            color = function() return colour.alpha(theme.text(), 0.6) end,
        },
        g.capsule {
            name = "list",
            role = "group",
            overlay = true,
            attach = "corner",
            raised = true,
            present = function() return out.value end,
            offset_y = function() return height() + 6 * f() end,
            width = t.width,
            height = list_height,
            radius = function() return m().radius_well end,
            growth = function() return if open.value then 1 else 0 end,
            transition = { growth = function() return if open.value then "grow" else "close" end },
            blur = performance.blurred,
            fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            -- Glass over the page: what is under it does not answer.
            on_press = function() end,
            on_click = function() end,
            g.box {
                overlay = true,
                attach = "corner",
                offset_x = padding,
                offset_y = padding,
                width = function() return t.width() - padding() * 2 end,
                height = function() return list_height() - padding() * 2 end,
                opacity = function() return if open.value then 1 else 0 end,
                transition = { opacity = function() return if open.value then "content_enter" else "content_leave" end },
                g.each {
                    overlay = true,
                    attach = "corner",
                    items = t.options,
                    key = function(o: any) return o.key end,
                    row = option_row,
                },
            },
        },
    }
    return node, { open = open, close = function() open.value = false end }
end

return M
