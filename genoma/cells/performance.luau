--!strict
-- Performance mode, while it is on: the shell has stepped back, and this
-- is the one thing left saying so (cells/performance/PerformanceCell.qml
-- and PerformancePanel.qml at 11bb81e). See docs/design/CELLS.md §21.
--
-- At rest the glyph alone, a dial with its needle all the way over, in the
-- primary gradient; kept by an `always` visibility while the mode is off,
-- dim. Opened, why it is on, what it has quietened, and the switch.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local performance = require("core/performance")
local switch = require("components/switch")

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 20 * f() end
        local function inset(): number return 14 * f() end
        local function inner(): number return 340 * f() - 20 * f() - inset() * 2 end

        local function levers(): { any }
            return {
                { key = "motion", words = "LIVE INDICATORS STILL" },
                { key = "organisms", words = "ORGANISMS PUT AWAY" },
                { key = "wallpaper", words = "ONE PICTURE KEPT" },
                { key = "blur", words = "NO BLUR, NO SHADOWS" },
                { key = "transitions", words = "INSTANT TRANSITIONS" },
                { key = "polling", words = "VITALS EVERY " .. math.floor(performance.vitals_interval() / 1000 + 0.5) .. " S" },
            }
        end
        local function quietened(): { any }
            local out = {}
            for _, l in levers() do
                if config.get("performance.suspend." .. l.key, true) ~= false then table.insert(out, l) end
            end
            return out
        end
        local function said(): string
            if performance.manual() then return "On by hand. It stays on, across a restart too, until it is turned off." end
            if performance.active() then return "On " .. performance.reason() .. ". It goes off by itself when that ends." end
            if performance.refused() then return "Off by hand while a trigger holds it. It comes back with the next one." end
            return "Off. The shell runs in full."
        end
        local function mark(size: () -> number): any
            return g.icon {
                width = size,
                height = size,
                icon = "performance",
                gradient_top = function() return if performance.active() then theme.gradient_top(theme.primary()) else theme.line() end,
                gradient_bottom = function() return if performance.active() then theme.gradient_bottom(theme.primary()) else theme.line() end,
            }
        end
        local function technical(text: any, size: () -> number, colour_of: any): any
            return g.text {
                text = text,
                color = colour_of,
                font = typography.technical,
                size = size,
                tracking = typography.label_tracking,
            }
        end
        local function prose_lines(): number
            local w = g.text_width { text = said(), font = typography.expressive(), size = m().font_secondary }
            return math.max(1, math.ceil(w / inner()))
        end
        local function content_height(): number
            local line = m().font_secondary * 1.4
            return 28 * f() + 10 * f() + prose_lines() * line
                + (if #quietened() > 0 then 10 * f() + #quietened() * (m().font_meta * 1.4 + 4 * f()) else 0)
                + 10 * f() + 2 * m().font_meta * 1.4
        end

        local function content(): any
            return g.capsule {
                width = function() return 340 * f() - 20 * f() end,
                padding = inset,
                direction = "column",
                align = "start",
                gap = function() return 10 * f() end,
                radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                g.box {
                    width = inner,
                    height = function() return 28 * f() end,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    technical("PERFORMANCE MODE", function() return m().font_secondary end, theme.text),
                    switch.new { on = performance.active, factor = f,
                        on_toggle = function(on: boolean) if on then performance.on() else performance.off() end end },
                },
                g.text {
                    text = said,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    max_width = inner,
                    wrap = true,
                },
                g.each {
                    direction = "column",
                    align = "start",
                    gap = function() return 4 * f() end,
                    present = function() return #quietened() > 0 end,
                    items = quietened,
                    key = function(l: any) return l.key end,
                    row = function(l: () -> any)
                        return technical(function() return l().words end, function() return m().font_meta end,
                            function() return if performance.active() then theme.text_muted() else theme.text_faint() end)
                    end,
                },
                g.text {
                    text = "What it quietens, and what turns it on by itself, is chosen in Settings, under Performance.",
                    color = theme.text_muted,
                    font = typography.expressive,
                    size = function() return m().font_meta end,
                    max_width = inner,
                    wrap = true,
                },
            }
        end

        return {
            panel = {
                width = function() return 340 * f() end,
                height = function() return content_height() + inset() * 2 + 20 * f() end,
                content = content,
            },
            padding_leading = function() return (m().cell_height - glyph()) / 2 end,
            padding_trailing = function() return (m().cell_height - glyph()) / 2 end,
            condition = function() return if performance.active() then 1 else 0 end,
            content_width = glyph,
            header_title = "PERFORMANCE",
            header_mark_size = glyph,
            header_mark = mark,
            contracted = function() return mark(glyph) end,
        }
    end,
}
