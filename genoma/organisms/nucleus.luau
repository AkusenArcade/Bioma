--!strict
-- Nucleus: the battery, as the mass at the heart of the cell (organisms/
-- nucleus/NucleusOrganism.qml at 2cafc17). See docs/design/ORGANISMS.md §14.
--
-- The nucleus is as large as the charge: its area is the charge's share of
-- the envelope round it, which is the battery full. Charging, drops come in
-- from outside and melt into it, as often as watts go in; discharging, it
-- beats, as fast as watts go out; full on the mains it is still. Colour is
-- the charge's state. The drops melt in with the cytoplasm's shader. Only a
-- laptop has one; on a desktop it is absent.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local system = require("services/system_monitor")
local stepper = require("components/stepper")

local SOURCE = require("core/paths").root .. "/genoma/organisms/cytoplasm.wgsl"
local P = {
    drops_per_watt = 1 / 20, fewest = 0.3, most = 2.5,
    beats_per_watt = 1 / 12, slowest = 0.2, fastest = 2.0,
    swell = 0.04, drop = 0.13, fall = 260, absorb = 0.25,
}

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function present(): boolean return system.has_battery() end
        local function level(): number return system.battery_level() end
        local function watts(): number return system.battery_watts() end
        local function well(): number return math.min(o.height(), o.width() / 2) end
        local function envelope(): number return well() / 2 - 10 * f() end
        local function mass(): number return math.max(3 * f(), envelope() * 0.92 * math.sqrt(level())) end
        local function tint(): string return theme.state_for(1 - level()) end
        local function drop_rate(): number
            if not (system.charging() and watts() > 0.5) then return 0 end
            return math.clamp(watts() * P.drops_per_watt, P.fewest, P.most)
        end
        local function beat_rate(): number
            if not (system.discharging() and watts() > 0.5) then return 0 end
            return math.clamp(watts() * P.beats_per_watt, P.slowest, P.fastest)
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
            local c = g.untracked(well) / 2
            local beat = math.max(0, math.sin(phase))
            local radius = g.untracked(mass) * (1 + P.swell * beat) + 2.5 * g.untracked(f) * beat
            local out = { c, c, if g.untracked(present) then radius else 0, 0 }
            local env = g.untracked(envelope)
            for i = 1, 3 do
                local d = drops[i]
                if d then
                    local r = env * P.drop * (if d.absorbing >= 0 then 1 - d.absorbing / P.absorb else 1)
                    table.insert(out, c + math.cos(d.angle) * d.distance)
                    table.insert(out, c + math.sin(d.angle) * d.distance)
                    table.insert(out, math.max(0, r))
                    table.insert(out, 0)
                else
                    table.insert(out, c); table.insert(out, c); table.insert(out, 0); table.insert(out, 0)
                end
            end
            for _ = 5, 24 do for _ = 1, 4 do table.insert(out, 0) end end
            shapes.value = out
        end
        g.effect(function()
            local _ = mass(), present()
            g.untracked(draw)
        end)
        g.watch(drop_rate, function(r: number) if r > 0 and until_next <= 0 then until_next = wait() end end)

        local function moving(): boolean
            return present() and (drop_rate() > 0 or beat_rate() > 0)
        end
        local settling = g.signal(false)
        local function step(dt: number)
            local fa = g.untracked(f)
            local beat = g.untracked(beat_rate)
            if beat > 0 then
                phase = (phase + dt * beat * math.pi * 2) % (math.pi * 2)
            elseif phase ~= 0 then
                -- A beat that stops finishes going back to rest.
                phase += dt * P.slowest * math.pi * 2
                if phase >= math.pi then phase = 0 end
            end
            local m_ = g.untracked(mass)
            local env = g.untracked(envelope)
            local busy = phase ~= 0
            for i = 1, 3 do
                local d = drops[i]
                if d then
                    busy = true
                    if d.absorbing >= 0 then
                        d.absorbing += dt
                        if d.absorbing >= P.absorb then drops[i] = false end
                    else
                        d.speed += P.fall * fa * dt
                        d.distance -= d.speed * dt
                        local touching = m_ + env * P.drop * 0.2
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
                            drops[i] = {
                                angle = math.random() * math.pi * 2,
                                distance = math.min(env * 1.08, g.untracked(well) / 2 - env * P.drop - 1),
                                speed = 0, absorbing = -1,
                            }
                            break
                        end
                    end
                    until_next = wait()
                end
            end
            settling.value = busy
            draw()
        end
        stepper.new { running = function() return moving() or settling.value end, step = step }

        local function values(): { number }
            local out = { 0, 0, 0, 0 }
            local function push(hex: string)
                local c = colour.parse(hex)
                table.insert(out, c.r); table.insert(out, c.g); table.insert(out, c.b); table.insert(out, c.a)
            end
            push(theme.text())
            for _ = 1, 6 do push(tint()) end
            for _, v in shapes.value do table.insert(out, v) end
            return out
        end
        local function duration(seconds: number): string
            local minutes = math.round(seconds / 60)
            local h, mm = minutes // 60, minutes % 60
            return if h > 0 then string.format("%d H %02d M", h, mm) else mm .. " M"
        end
        local function flow(): string
            local w = if watts() > 0.05 then string.format(" · %.1f W", watts()) else ""
            if system.charging() then return "CHARGING" .. w end
            if system.discharging() then return "DISCHARGING" .. w end
            return if level() >= 0.995 then "FULL" else "ON MAINS"
        end
        local function remaining(): string
            local s = system.battery_seconds_left()
            if s <= 0 then return "" end
            if system.charging() then return "FULL IN " .. duration(s) end
            if system.discharging() then return duration(s) .. " LEFT" end
            return ""
        end

        return {
            present = present,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    -- The envelope: the battery full, a hairline round the room
                    -- the nucleus could fill.
                    g.capsule {
                        overlay = true,
                        attach = "corner",
                        offset_x = function() return well() / 2 - envelope() end,
                        offset_y = function() return well() / 2 - envelope() end,
                        width = function() return envelope() * 2 end,
                        height = function() return envelope() * 2 end,
                        stroke = function() return 1.5 * f() end,
                        fill = function() return colour.alpha(theme.text(), 0.03) end,
                        rim_top = function() return colour.alpha(theme.text(), 0.22) end,
                        rim_bottom = function() return colour.alpha(theme.text(), 0.22) end,
                    },
                    g.shader {
                        overlay = true,
                        attach = "corner",
                        src = SOURCE,
                        width = well,
                        height = well,
                        values = values,
                        follow = stepper.follow,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not present() end,
                        width = well,
                        height = well,
                        align = "center",
                        justify = "center",
                        g.text { text = "No battery", color = theme.text_faint, font = typography.expressive,
                            size = function() return math.round(14 * f()) end, italic = true },
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = present,
                        offset_x = function() return well() + 14 * f() end,
                        height = o.height,
                        direction = "column",
                        align = "start",
                        justify = "center",
                        gap = function() return 6 * f() end,
                        g.text { text = function() return math.round(level() * 100) .. "%" end,
                            color = function() return theme.gradient_top(tint()) end,
                            color_bottom = function() return theme.gradient_bottom(tint()) end,
                            font = typography.technical, size = function() return math.round(40 * f()) end,
                            weight = typography.weight_value, tabular = true },
                        g.text { text = flow, color = theme.text, font = typography.technical,
                            size = function() return m().font_meta end, weight = typography.weight_label,
                            tracking = typography.label_tracking, tabular = true },
                        g.text { present = function() return remaining() ~= "" end, text = remaining,
                            color = theme.text_muted, font = typography.technical,
                            size = function() return m().font_meta end, tabular = true },
                    },
                }
            end,
        }
    end,
}
