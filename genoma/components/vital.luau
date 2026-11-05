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
-- The battery is the nucleus organism in small (organisms/nucleus.luau,
-- ORGANISMS §14), Akusen's choice of 2026-11-05 over the charge that
-- filled sideways: a mass whose area is the charge's share of the inside
-- of the ring. Charging, drops come in from the ring and melt into it, as
-- often as watts go in; discharging, it swells, as fast as watts go out;
-- full on the mains it is still, and a bolt is cut out of it.
local g = require("@genoma")
local colour = require("core/colour")
local paths = require("core/paths")
local performance = require("core/performance")
local theme = require("core/theme")
local stepper = require("components/stepper")

local M = {}

local QT_AA = 1

local NUCLEUS = paths.root .. "/genoma/components/nucleus.wgsl"
-- The nucleus organism's constants. Its fall, 260 px/s² over a 70 px
-- envelope, is taken in envelopes; its mass fills a little less of the
-- room, so that a drop near the full charge still has a wall to come from;
-- its swell, 4 % and 2.5 px at that scale, would be a third of a pixel
-- here, so the fixed part is two units of the 64 grid.
local N = {
    drops_per_watt = 1 / 20, fewest = 0.3, most = 2.5,
    beats_per_watt = 1 / 12, slowest = 0.2, fastest = 2.0,
    mass = 0.86, drop = 0.13, fall = 260 / 70, absorb = 0.25,
    swell = 0.04, swell_grid = 2,
}

-- The battery's nucleus: a shader the size of the ring, inside it.
local function nucleus(t: { [string]: any }, unit: () -> number, radius: () -> number, stroke: () -> number,
    vessel: () -> number, base: () -> string, shown: () -> boolean, level: () -> number): any
    local function size(): number return 2 * radius() + stroke() end
    local function envelope(): number return vessel() / 2 end
    local function mass(): number return math.max(3 * unit(), envelope() * N.mass * math.sqrt(level())) end
    local function drop_radius(): number return radius() * N.drop end
    local function active(): boolean return shown() and (t.active == nil or t.active()) end
    local function inflow(): number return if t.inflow then t.inflow() else 0 end
    local function outflow(): number return if t.outflow then t.outflow() else 0 end
    local function mains_full(): boolean return t.mains_full ~= nil and t.mains_full() end
    local function drop_rate(): number
        if not active() or performance.still() or inflow() <= 0.5 then return 0 end
        return math.clamp(inflow() * N.drops_per_watt, N.fewest, N.most)
    end
    local function beat_rate(): number
        if not active() or performance.still() or outflow() <= 0.5 then return 0 end
        return math.clamp(outflow() * N.beats_per_watt, N.slowest, N.fastest)
    end

    -- Three drops in flight at most, each keeping its slot.
    local drops: { any } = { false, false, false }
    local phase = 0
    local until_next = 0
    local function wait(): number
        local r = g.untracked(drop_rate)
        return if r > 0 then -math.log(1 - math.random()) / r else 0
    end
    local shapes = g.signal({} :: { number })
    local function draw()
        local c = g.untracked(size) / 2
        local beat = math.max(0, math.sin(phase))
        local m = g.untracked(mass)
        local r = m * (1 + N.swell * beat) + N.swell_grid * g.untracked(unit) * beat
        local out = { c, c, r, 0 }
        local dr = g.untracked(drop_radius)
        for i = 1, 3 do
            local d = drops[i]
            if d then
                local k = if d.absorbing >= 0 then 1 - d.absorbing / N.absorb else 1
                table.insert(out, c + math.cos(d.angle) * d.distance)
                table.insert(out, c + math.sin(d.angle) * d.distance)
                table.insert(out, math.max(0, dr * k))
                table.insert(out, 0)
            else
                table.insert(out, c); table.insert(out, c); table.insert(out, 0); table.insert(out, 0)
            end
        end
        shapes.value = out
    end
    g.effect(function()
        local _ = mass(), size()
        g.untracked(draw)
    end)
    g.watch(drop_rate, function(r: number) if r > 0 and until_next <= 0 then until_next = wait() end end)

    local settling = g.signal(false)
    local function step(dt: number)
        local beat = g.untracked(beat_rate)
        if beat > 0 then
            phase = (phase + dt * beat * math.pi * 2) % (math.pi * 2)
        elseif phase ~= 0 then
            -- A beat that stops finishes going back to rest.
            phase += dt * N.slowest * math.pi * 2
            if phase >= math.pi then phase = 0 end
        end
        local m = g.untracked(mass)
        local env = g.untracked(envelope)
        local dr = g.untracked(drop_radius)
        local busy = phase ~= 0
        for i = 1, 3 do
            local d = drops[i]
            if d then
                busy = true
                if d.absorbing >= 0 then
                    d.absorbing += dt
                    if d.absorbing >= N.absorb then drops[i] = false end
                else
                    d.speed += N.fall * env * dt
                    d.distance -= d.speed * dt
                    local touching = m + dr * 0.2
                    if d.distance <= touching then
                        d.distance = touching
                        d.absorbing = 0
                    end
                end
            end
        end
        if g.untracked(drop_rate) > 0 then
            until_next -= dt
            if until_next <= 0 then
                for i = 1, 3 do
                    if not drops[i] then
                        -- Born against the inside of the ring: nothing is
                        -- drawn outside it.
                        drops[i] = { angle = math.random() * math.pi * 2, distance = env - dr, speed = 0, absorbing = -1 }
                        break
                    end
                end
                until_next = wait()
            end
        end
        settling.value = busy
        draw()
    end
    stepper.new {
        running = function() return drop_rate() > 0 or beat_rate() > 0 or settling.value end,
        step = step,
    }

    local function push(out: { number }, hex: string)
        local c = colour.parse(hex)
        table.insert(out, c.r); table.insert(out, c.g); table.insert(out, c.b); table.insert(out, c.a)
    end
    return g.shader {
        src = NUCLEUS,
        width = size,
        height = size,
        values = function(): { number }
            if not shown() then return {} end
            -- The cytoplasm's unit is its panel over 360; the nucleus's
            -- envelope is 70 of a 160 well, so its unit is the envelope
            -- over 157.5.
            local out = { envelope() / 157.5, if mains_full() then 1 else 0, unit(), envelope() }
            push(out, theme.text())
            push(out, base())
            for _, v in shapes.value do table.insert(out, v) end
            return out
        end,
        follow = stepper.follow,
    }
end

-- `t`: kind ("cpu" | "ram" | "gpu" | "battery"), size(), load() (0…1, the
-- colour and nothing else), rate() (0…1, the rhythm), level() (0…1, how
-- full), present(); for the battery, inflow() and outflow() (watts going
-- in and out), mains_full(), and active() (false while it is not seen: a
-- closed expansion's pod steps nothing).
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
        table.insert(inner, nucleus(t, unit, radius, stroke, vessel, base, shown, level))
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
