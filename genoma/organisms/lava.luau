--!strict
-- A lava lamp heated by the processor (organisms/lava/LavaOrganism.qml at
-- 2cafc17). See docs/design/ORGANISMS.md.
--
-- The one place Bioma draws metaballs: an organism is never pressed, and
-- here the union is the point, wax melting together where it meets. Every
-- motion is the temperature. Wax sits on the heater and warms towards it;
-- warm enough, it lets go and rises, cools as it climbs and sinks back. How
-- high it gets is how hot the processor is, and below the start of the
-- scale nothing leaves the bottom, so a cool machine is a still pool. The
-- simulation runs only while something moves (components/stepper.luau).
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local system = require("services/system_monitor")
local stepper = require("components/stepper")

local SOURCE = require("core/paths").root .. "/genoma/organisms/lava.wgsl"

-- Constants of the simulation, not durations: rates per second and
-- fractions of the lamp (tuned offline, 2026-10-05).
local P = {
    release = 0.16, buoyant = 0.12, warming = 1.2, cooling = 0.2,
    lift = 1.2, drag = 2.2, zone = 0.08, sway = 0.10,
}

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function present(): boolean return system.cpu_temperature_known() end
        local function cold(): number return o.entry().cold or 48 end
        local function hot(): number return o.entry().hot or 90 end
        local function heat(): number
            if not present() then return 0 end
            return math.clamp((system.cpu_temperature() - cold()) / math.max(1, hot() - cold()), 0, 1)
        end
        local function themed(): boolean return o.entry().colour == "theme" end
        local function wax(): string return if themed() then theme.primary() else theme.state_for(heat()) end
        local function figures(): boolean return o.entry().figures ~= false end
        local function inset(): number return 18 * f() end
        -- Where it stops rising: under the figure, so the wax never runs
        -- over what it is saying.
        local function cap(): number
            return if figures() and present() then inset() + m().font_label * 1.3 + 2 * f() + m().font_value * 1.3 + inset() / 2 else 0
        end

        -- Seven blobs of different sizes side by side on the heater.
        local blobs = {}
        for i = 0, 6 do
            local spread = ((i * 37) % 7) / 6
            table.insert(blobs, {
                r = 0.07 + 0.05 * spread,
                home = 0.2 + 0.6 * i / 6,
                warming = 0.4 + 1.2 * ((i * 53) % 7) / 6,
                y = 0, vy = 0,
                t = -0.15 * ((i * 29) % 7) / 6,
                phase = i * 1.7,
                pinned = true,
            })
        end
        local function floor_of(b: any): number return b.r * 0.6 * o.width() / math.max(1, o.height()) end
        local function ceiling_of(b: any): number return 1 - (cap() + b.r * 1.1 * o.width()) / math.max(1, o.height()) end

        local shapes = g.signal({} :: { number })
        local moving = g.signal(true)
        local function draw()
            local w, h = g.untracked(o.width), g.untracked(o.height)
            local here = g.untracked(present)
            local out = {}
            for _, b in blobs do
                local x = math.clamp(b.home + P.sway * math.sin(b.phase), b.r, 1 - b.r) * w
                table.insert(out, x)
                table.insert(out, h - b.y * h)
                table.insert(out, if here then b.r * w else 0)
                table.insert(out, 0)
            end
            for _ = #blobs + 1, 10 do for _ = 1, 4 do table.insert(out, 0) end end
            shapes.value = out
        end
        for _, b in blobs do if b.pinned then b.y = floor_of(b) end end
        draw()
        g.watch(heat, function() moving.value = true end)

        local function step(dt: number)
            local hh = g.untracked(heat)
            local free = hh > P.release
            dt *= 0.3 + 1.7 * hh
            local any = false
            for _, b in blobs do
                local floor, ceiling = g.untracked(function() return floor_of(b) end), g.untracked(function() return ceiling_of(b) end)
                if b.y < floor + P.zone then
                    b.t += (hh - b.t) * P.warming * b.warming * dt
                else
                    b.t -= b.t * P.cooling * (1 + 2 * math.max(0, b.y - 0.7)) * dt
                end
                local skip = false
                if b.pinned then
                    if free and b.t > 0.9 * hh then
                        b.pinned = false
                    else
                        if free then any = true end
                        skip = true
                    end
                end
                if not skip then
                    any = true
                    local buoyancy = (b.t - P.buoyant) * P.lift * 0.1 / b.r
                    b.vy += (buoyancy - P.drag * b.vy) * dt
                    b.y += b.vy * dt
                    b.phase += math.abs(b.vy) * 6 * dt
                    if b.y > ceiling then
                        b.y = ceiling
                        b.vy = math.min(0, b.vy)
                    end
                    if b.y < floor then
                        b.y = floor
                        b.vy = 0
                        b.pinned = true
                    end
                end
            end
            moving.value = any
            draw()
        end
        stepper.new { running = function() return moving.value and present() end, step = step }

        local function values(): { number }
            local out = { m().radius_panel, heat(), 0, 0 }
            for _, hex in { wax(), theme.text() } do
                local c = colour.parse(hex)
                table.insert(out, c.r)
                table.insert(out, c.g)
                table.insert(out, c.b)
                table.insert(out, c.a)
            end
            for _, v in shapes.value do table.insert(out, v) end
            return out
        end

        return {
            bleeds = true,
            present = present,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    g.shader {
                        overlay = true,
                        attach = "corner",
                        src = SOURCE,
                        width = o.width,
                        height = o.height,
                        values = values,
                        follow = stepper.follow,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return figures() and present() end,
                        offset_x = inset,
                        offset_y = inset,
                        direction = "column",
                        align = "start",
                        gap = function() return 2 * f() end,
                        g.text {
                            text = "CPU",
                            color = theme.text,
                            font = typography.technical,
                            size = function() return m().font_label end,
                            weight = typography.weight_label,
                            tracking = typography.label_tracking,
                        },
                        g.text {
                            text = function() return math.round(system.cpu_temperature()) .. "°" end,
                            color = function() return theme.gradient_top(wax()) end,
                            color_bottom = function() return theme.gradient_bottom(wax()) end,
                            font = typography.technical,
                            size = function() return m().font_value end,
                            weight = typography.weight_value,
                            tabular = true,
                        },
                    },
                    -- Blank: placed while arranging on a machine that reports
                    -- no temperature.
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not present() end,
                        width = o.width,
                        height = o.height,
                        align = "center",
                        justify = "center",
                        g.text {
                            text = "No temperature sensor",
                            color = theme.text_faint,
                            font = typography.technical,
                            size = function() return m().font_secondary end,
                            wrap = true,
                            text_align = "center",
                            max_width = function() return o.width() - inset() * 2 end,
                        },
                    },
                }
            end,
        }
    end,
}
