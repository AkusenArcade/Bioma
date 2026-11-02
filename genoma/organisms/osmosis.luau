--!strict
-- The network, as osmosis (organisms/osmosis/OsmosisOrganism.qml at
-- 2cafc17). See docs/design/ORGANISMS.md.
--
-- A membrane above, a pool below. What comes in falls from the membrane as
-- drops into the pool; what goes out rises from the pool into the membrane.
-- A drop crosses in about a second whatever the traffic: how many cross is
-- what the traffic says, on a logarithmic scale from an idle link to a
-- gigabit one, and drops come at that rate on average, never on a beat.
--
-- Not yet: the figures lit by the water's gradient (LitText).
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local system = require("services/system_monitor")
local stepper = require("components/stepper")

local SOURCE = require("core/paths").root .. "/genoma/organisms/osmosis.wgsl"
local SLOTS = 20
local P = { gravity = 2.2, gather = 0.35, absorb = 0.18 }

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function present(): boolean return system.net_known() end
        local function quiet(): number return (o.entry().quiet or 4) * 1024 end
        local function ceiling(): number return (o.entry().ceiling or 100000) * 1024 end
        local function drops_per_second(bytes: number): number
            if not present() or bytes < quiet() then return 0 end
            local along = math.clamp(math.log(bytes / quiet()) / math.log(ceiling() / quiet()), 0, 1)
            return 0.4 + (6 - 0.4) * along
        end
        local function in_rate(): number return drops_per_second(system.net_in()) end
        local function out_rate(): number return drops_per_second(system.net_out()) end
        local function figures(): boolean return o.entry().figures ~= false end
        local function inset(): number return 18 * f() end
        local function thickness(): number return 6 * f() end
        -- The membrane runs under the figures, so no drop crosses them.
        local function membrane(): number
            local caption = if figures() and present() then inset() + 2 * (m().font_value * 1.3) + 2 * f() + inset() * 0.6 else inset()
            return caption + thickness() / 2
        end
        local function pool(): number return o.height() * 0.8 end

        -- Each drop keeps its slot while it lives: the shader eases its
        -- numbers, and a drop given another's slot would slide into it.
        local slots: { any } = {}
        for i = 1, SLOTS do slots[i] = false end
        local next_in, next_out = math.huge, math.huge
        local function wait(rate: number): number
            return if rate > 0 then -math.log(1 - math.random()) / rate else math.huge
        end
        g.watch(in_rate, function(r: number)
            if r <= 0 then next_in = math.huge elseif next_in == math.huge then next_in = wait(r) end
        end)
        g.watch(out_rate, function(r: number)
            if r <= 0 then next_out = math.huge elseif next_out == math.huge then next_out = wait(r) end
        end)
        next_in = wait(g.untracked(in_rate))
        next_out = wait(g.untracked(out_rate))

        local shapes = g.signal({} :: { number })
        local live = g.signal(false)
        local function draw()
            local out = {}
            for _, d in slots do
                if d then
                    table.insert(out, d.x); table.insert(out, d.y); table.insert(out, d.r * d.size); table.insert(out, 0)
                else
                    for _ = 1, 4 do table.insert(out, 0) end
                end
            end
            shapes.value = out
        end
        draw()

        local function bud(up: boolean)
            for i = 1, SLOTS do
                if not slots[i] then
                    local w = g.untracked(o.width)
                    local r = (0.045 + 0.025 * math.random()) * w
                    local x = r * 1.5 + math.random() * (w - r * 3)
                    slots[i] = {
                        x = x, r = r, size = 0, vy = 0, up = up, stage = "gather",
                        -- Half in the water it comes from, so it grows out of it.
                        y = if up then g.untracked(pool) + r * 0.1 else g.untracked(membrane) + g.untracked(thickness) / 2 - r * 0.1,
                    }
                    return
                end
            end
        end

        local function step(dt: number)
            next_in -= dt
            next_out -= dt
            if next_in <= 0 then
                bud(false)
                next_in = wait(g.untracked(in_rate))
            end
            if next_out <= 0 then
                bud(true)
                next_out = wait(g.untracked(out_rate))
            end
            local top = g.untracked(membrane) + g.untracked(thickness) / 2
            local surface = g.untracked(pool)
            local span = math.max(1, surface - top)
            local any = false
            for i, d in slots do
                if d then
                    any = true
                    if d.stage == "gather" then
                        d.size = math.min(1, d.size + dt / P.gather)
                        local hang = d.r * (d.size - 0.1)
                        d.y = if d.up then surface - hang else top + hang
                        if d.size >= 1 then d.stage = "travel" end
                    elseif d.stage == "travel" then
                        d.vy += P.gravity * span * dt
                        d.y += (if d.up then -d.vy else d.vy) * dt
                        local arrived = if d.up then d.y <= top + d.r * 0.4 else d.y >= surface + d.r * 0.4
                        if arrived then d.stage = "absorb" end
                    else
                        -- Taken in where it touched, shrinking into the water.
                        d.size -= dt / P.absorb
                    end
                    if d.size <= 0 then slots[i] = false end
                end
            end
            live.value = any
            draw()
        end
        stepper.new {
            running = function() return present() and (live.value or in_rate() > 0 or out_rate() > 0) end,
            step = step,
        }

        local function values(): { number }
            local out = { m().radius_panel, membrane(), thickness(), pool() }
            for _, hex in { theme.primary(), theme.text() } do
                local c = colour.parse(hex)
                table.insert(out, c.r); table.insert(out, c.g); table.insert(out, c.b); table.insert(out, c.a)
            end
            for _, v in shapes.value do table.insert(out, v) end
            return out
        end

        local function rate(bytes: number): string
            if bytes < 1024 then return math.round(bytes) .. " B/s" end
            if bytes < 1024 * 1024 then return math.round(bytes / 1024) .. " KB/s" end
            local mb = bytes / (1024 * 1024)
            return if mb < 10 then string.format("%.1f MB/s", mb) else math.round(mb) .. " MB/s"
        end
        local function label(text: string): any
            return g.box {
                width = function() return 40 * f() end,
                g.text { text = text, color = theme.text, font = typography.technical,
                    size = function() return m().font_label end, weight = typography.weight_label, tracking = typography.label_tracking },
            }
        end
        local function figure(read: () -> number): any
            return g.text { text = function() return rate(read()) end, color = theme.primary, font = typography.technical,
                size = function() return m().font_value end, weight = typography.weight_value, tabular = true }
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
                        present = present,
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
                        g.box { direction = "row", align = "center", gap = function() return 10 * f() end,
                            label("IN"), figure(system.net_in) },
                        g.box { direction = "row", align = "center", gap = function() return 10 * f() end,
                            label("OUT"), figure(system.net_out) },
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not present() end,
                        width = o.width,
                        height = o.height,
                        align = "center",
                        justify = "center",
                        g.text {
                            text = "No network link",
                            color = theme.text_faint,
                            font = typography.technical,
                            size = function() return m().font_secondary end,
                        },
                    },
                }
            end,
        }
    end,
}
