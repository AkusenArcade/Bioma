--!strict
-- One vital sign (components/Vital.qml): a ring, and inside it a shape
-- that moves.
--
-- Colour says state, form says domain. The ring is the same for all of
-- them, and what happens inside says which part is speaking: a beating dot
-- is the processor, a liquid the memory, a satellite the graphics card, a
-- charge filling sideways the battery. Colour says only how hard that part
-- is working. Every movement carries a live value in its rate; one with
-- nothing to report is still.
--
-- The geometry is the design's 64 grid. Qt's curve renderer antialiases a
-- small disc about half a pixel wider on each side than an exact distance
-- field does (measured on the satellite, 2026-10-28): a pixel more of
-- diameter draws Bioma's disc.
--
-- Not yet: the battery's drops while it charges and the bolt cut out of it
-- full on the mains (they wait for a battery to be checked against, on the
-- laptop); performance mode's resting poses, with its service.
local g = require("@genoma")
local performance = require("core/performance")
local theme = require("core/theme")

local M = {}

local QT_AA = 1

-- `t`: kind ("cpu" | "ram" | "gpu" | "battery"), size(), load() (0…1, the
-- colour and nothing else), rate() (0…1, the rhythm), level() (0…1, how
-- full), present().
function M.new(t: { [string]: any }): any
    local kind = t.kind
    local function unit(): number return t.size() / 64 end
    local function radius(): number return 24 * unit() end
    local function stroke(): number return math.max(1, 1.5 * unit()) end
    local function vessel(): number return (radius() - stroke()) * 2 end
    local function base(): string return theme.state_for(t.load()) end
    local function top(): string return theme.gradient_top(base()) end
    local function bottom(): string return theme.gradient_bottom(base()) end
    -- An indicator not drawn (a battery on a desktop reads as empty) raises
    -- no alarm.
    local function shown(): boolean return t.present == nil or t.present() end
    local function critical(): boolean return shown() and t.load() >= theme.threshold_alert end
    local function level(): number return if t.level then t.level() else 0 end
    -- The memory reaching the top is the one case where the ring itself
    -- goes: a full disc, not a dot inside a ring, which is what a critical
    -- processor looks like.
    local function ram_full(): boolean return kind == "ram" and shown() and level() >= 0.995 end

    local inner = {}

    if kind == "cpu" then
        -- The beat is the clock, on the service's moving average: 45 a
        -- minute at idle, 140 at full speed. It pulses and then waits, the
        -- way a heart does.
        table.insert(inner, g.capsule {
            width = function() return 16 * unit() + QT_AA end,
            height = function() return 16 * unit() + QT_AA end,
            fill = top,
            fill_bottom = bottom,
            pulse = function() return if performance.still() then 0 else 45 + t.rate() * 95 end,
            transition = { fill = "theme", fill_bottom = "theme" },
        })
    elseif kind == "ram" then
        -- The level is the memory in use: it moves when the machine
        -- allocates, not when time passes. The wave on top is the only part
        -- on a clock, one period per cycle so the travel closes on itself.
        table.insert(inner, g.capsule {
            width = vessel,
            height = vessel,
            present = function() return not ram_full() end,
            fill = top,
            fill_bottom = bottom,
            level = level,
            -- Quadratic arcs with their control 6 above and below reach half
            -- of it: the crest stands 3 off the level.
            wave = function() return 3 * unit() end,
            wave_period = function() return 46 * unit() end,
            wave_time = 2.4,
            transition = { level = "reflow", fill = "theme", fill_bottom = "theme" },
        })
    elseif kind == "gpu" then
        -- Utilisation and clock diverge, so they are said by two properties
        -- of one shape: the orbit is the clock, the colour the load. A card
        -- at idle still has a clock, so the satellite never stops.
        table.insert(inner, g.capsule {
            width = function() return 12 * unit() + QT_AA end,
            height = function() return 12 * unit() + QT_AA end,
            fill = top,
            fill_bottom = bottom,
            orbit = function() return if performance.still() then 0 else 1 / (6 - t.rate() * 4.8) end,
            orbit_radius = radius,
            transition = { fill = "theme", fill_bottom = "theme" },
        })
    elseif kind == "battery" then
        -- Left to right, so it cannot be taken for the memory's liquid,
        -- which rises from the bottom.
        table.insert(inner, g.capsule {
            width = vessel,
            height = vessel,
            fill = base,
            level = level,
            level_left = true,
            transition = { level = "reflow", fill = "theme" },
        })
    end

    -- Past the threshold the ring emits a wave: it expands and fades.
    local spread = g.signal(0)
    local halo_opacity = g.signal(0)
    local halo_moving = g.signal(false)
    local function emit()
        halo_moving.value = false
        spread.value = 0
        halo_opacity.value = 0.5
        g.after(0, function()
            halo_moving.value = true
            spread.value = 8 * g.untracked(unit)
            halo_opacity.value = 0
        end)
    end
    g.effect(function()
        if not critical() then return end
        g.untracked(emit)
        g.timer { every = 0.9, on_tick = emit }
    end)

    -- Memory at the top: a full disc in the alert colour, pulsing.
    local full_small = g.signal(false)
    g.effect(function()
        if not ram_full() then return end
        g.timer { every = 0.45, on_tick = function() full_small.value = not g.untracked(function() return full_small.value end) end }
    end)

    local ring: { [any]: any } = {
        overlay = true,
        width = function() return 2 * radius() + stroke() end,
        height = function() return 2 * radius() + stroke() end,
        present = function() return not ram_full() end,
        stroke = stroke,
        rim_top = top,
        rim_bottom = bottom,
        transition = { rim_top = "theme", rim_bottom = "theme" },
    }
    for i, child in inner do ring[i] = child end

    return g.box {
        width = t.size,
        height = t.size,
        present = t.present,
        justify = "center",
        align = "center",
        g.capsule {
            overlay = true,
            present = critical,
            width = function() return 2 * (radius() + spread.value) + stroke() end,
            height = function() return 2 * (radius() + spread.value) + stroke() end,
            stroke = stroke,
            rim_top = theme.alert,
            rim_bottom = theme.alert,
            opacity = function() return halo_opacity.value end,
            transition = {
                width = function() return if halo_moving.value then "alarm" else "instant" end,
                height = function() return if halo_moving.value then "alarm" else "instant" end,
                opacity = function() return if halo_moving.value then "alarm_fade" else "instant" end,
            },
        },
        g.capsule(ring),
        g.capsule {
            overlay = true,
            present = ram_full,
            width = function() return (radius() + stroke() / 2) * 2 * (if full_small.value then 0.88 else 1) end,
            height = function() return (radius() + stroke() / 2) * 2 * (if full_small.value then 0.88 else 1) end,
            fill = function() return theme.gradient_top(theme.alert()) end,
            fill_bottom = function() return theme.gradient_bottom(theme.alert()) end,
            transition = { width = "full_pulse", height = "full_pulse" },
        },
    }
end

return M
