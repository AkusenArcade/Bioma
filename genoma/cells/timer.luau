--!strict
-- A timer, while one runs: a ring that empties at the speed of time
-- (cells/timer/TimerCell.qml and TimerPanel.qml at 11bb81e). See
-- docs/design/CELLS.md §15.
--
-- At rest the dial and nothing else, the disc on the rim with the lit
-- trail behind it, full when the timer starts and back at twelve when it
-- ends (Akusen, 2026-09-27); paused, it dims and stops where it is. The
-- timer is the clock's own (services/time.luau). Opened: what is left, the
-- presets while it is still, START, PAUSE or RESUME, and STOP.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local time = require("services/time")
local dial = require("components/dial")
local choice = require("components/choice")

local PRESETS = { 5, 10, 25, 60 }

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function dial_size(): number return 22 * f() end

        -- What is left from the moment it ends, not from the last counted
        -- second, read again whenever it has half a pixel to move: a long
        -- timer costs a frame every few seconds, a short one moves smoothly.
        local remaining = g.signal(g.untracked(time.fraction_left))
        local function measure()
            remaining.value = if time.running() and time.length() > 0
                then math.clamp((time.ends_at() - (os.time() + g.now() % 1)) / time.length(), 0, 1)
                else time.fraction_left()
        end
        local ticking: any = nil
        g.effect(function()
            if ticking then ticking:stop() end
            ticking = nil
            local running, placed = time.running(), cell.placed.value
            local _ = time.left()
            g.untracked(measure)
            if running and placed then
                local circumference = math.pi * dial_size() * 0.75
                local every = math.max(0.016, time.length() / math.max(1, circumference * 2))
                ticking = g.timer { every = every, on_tick = function() g.untracked(measure) end }
            end
        end)
        -- Whole is drawn just short of whole: at 1 the rim wraps to empty.
        local function orbit(): number return math.min(remaining.value, 0.9999) end
        local function face(size: () -> number): any
            return g.box {
                opacity = function() return if time.paused() then 0.45 else 1 end,
                transition = { opacity = "content_fade" },
                dial.new { size = size, fraction = function() return 0 end, orbit = orbit, still = true },
            }
        end

        local function figure(seconds: number): string
            local h, mm, ss = seconds // 3600, (seconds % 3600) // 60, seconds % 60
            return if h > 0 then string.format("%d:%02d:%02d", h, mm, ss) else string.format("%02d:%02d", mm, ss)
        end
        local function still(): boolean return not time.running() and not time.paused() end

        local function preset(minutes: number): any
            local hovered = g.signal(false)
            local function lit(): boolean return time.length() == minutes * 60 end
            local function edge(): string
                return if lit() then theme.primary() elseif hovered.value then theme.text() else theme.line()
            end
            return g.capsule {
                role = "button",
                name = "Preset",
                height = function() return 24 * f() end,
                padding_x = function() return 11 * f() end,
                align = "center",
                justify = "center",
                radius = function() return metrics_mod.radius_for(24 * f(), m()) end,
                fill = function() return if lit() then colour.alpha(theme.primary(), 0.16) else "#00000000" end,
                rim_top = edge,
                rim_bottom = edge,
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function() time.set_length(minutes * 60) end,
                g.text {
                    text = if minutes < 60 then minutes .. " M" else "1 H",
                    color = function() return if lit() then theme.text() else theme.text_muted() end,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    weight = typography.weight_secondary,
                    tabular = true,
                },
            }
        end

        local function content(): any
            local presets: { [any]: any } = { direction = "row", gap = function() return 6 * f() end, present = still }
            for _, p in PRESETS do table.insert(presets, preset(p)) end
            return g.capsule {
                width = function() return 280 * f() - 20 * f() end,
                padding = function() return 14 * f() end,
                direction = "column",
                align = "center",
                gap = function() return 12 * f() end,
                radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                -- The figure the wheel turns while the timer is still, a
                -- minute a notch.
                g.box {
                    on_wheel = function(_: number, dy: number)
                        if not g.untracked(still) then return end
                        time.set_length(g.untracked(time.length) + (if dy < 0 then 60 else -60))
                    end,
                    g.text {
                        text = function() return figure(time.left()) end,
                        color = theme.text,
                        font = typography.technical,
                        size = function() return math.floor(34 * f() + 0.5) end,
                        weight = typography.weight_value,
                        tabular = true,
                        opacity = function() return if time.running() then 1 else 0.6 end,
                    },
                },
                g.box(presets),
                g.box {
                    direction = "row",
                    gap = function() return 8 * f() end,
                    choice.new {
                        metrics = m,
                        kind = "primary",
                        label = function() return if time.running() then "PAUSE" elseif time.paused() then "RESUME" else "START" end,
                        on_click = function() if g.untracked(time.running) then time.pause() else time.start() end end,
                    },
                    g.box {
                        present = function() return time.running() or time.paused() end,
                        choice.new { metrics = m, label = "STOP", on_click = time.reset },
                    },
                },
            }
        end

        return {
            panel = {
                width = function() return 280 * f() end,
                height = function()
                    local inner = 14 * f() * 2 + math.floor(34 * f() + 0.5) * 1.25 + 12 * f() + 26 * f()
                        + (if still() then 12 * f() + 24 * f() else 0)
                    return inner + 20 * f()
                end,
                content = content,
            },
            padding_leading = function() return (m().cell_height - dial_size()) / 2 end,
            padding_trailing = function() return (m().cell_height - dial_size()) / 2 end,
            condition = function() return if time.running() or time.paused() then 1 else 0 end,
            content_width = dial_size,
            header_title = "TIMER",
            header_mark_size = dial_size,
            header_mark = function(mark: () -> number) return face(mark) end,
            contracted = function() return face(dial_size) end,
        }
    end,
}
