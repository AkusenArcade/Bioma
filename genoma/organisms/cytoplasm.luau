--!strict
-- The applications that are running, drawn as cells pressed together in a
-- cytoplasm (organisms/cytoplasm/CytoplasmOrganism.qml at 2cafc17). See
-- docs/design/ORGANISMS.md §08.
--
-- Each application is one cell and each of its heaviest processes a lobe of
-- it. Lobes of one application fuse; two applications never do: they press
-- against each other and keep the seam. Size is memory: a cell's area is its
-- share of the machine's memory, scaled down together past 45% of the
-- panel. Motion is processor: lobes circle their cell at a rate proportional
-- to the application's load, so an idle one is still and a busy one turns.
-- The grouping of processes into applications is AppLoad's.
--
-- Not yet: the shadow under the names (MultiEffect), which Genoma lacks.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local system = require("services/system_monitor")
local app_load = require("services/app_load")
local stepper = require("components/stepper")

local SOURCE = require("core/paths").root .. "/genoma/organisms/cytoplasm.wgsl"

-- Constants of the simulation: rates per second and pixels at factor 1.
local P = {
    fill = 1.0, ceiling = 0.45, growth = 3.0, streaming = 0.03, fastest = 3.0,
    nesting = 0.6, smallest = 0.08, gap = 2, pull = 0.6, inset = 10,
}

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        app_load.hold(true)
        local function present(): boolean return #app_load.apps() > 0 end
        local function count(): number return math.clamp(o.entry().count or 6, 1, 6) end
        local function themed(): boolean return o.entry().colour == "theme" end
        local function labels(): boolean return o.entry().labels ~= false end

        -- Six slots, each one application or empty: an application keeps its
        -- slot while it is drawn, so it keeps its place and its colour.
        local function empty_slot(i: number): any
            local angle = (i - 1) / 6 * math.pi * 2
            local w, h = g.untracked(o.width), g.untracked(o.height)
            return {
                key = "", name = "", ram = 0, leaving = true,
                x = w / 2 + math.cos(angle) * w * 0.25, y = h / 2 + math.sin(angle) * h * 0.25,
                radii = { 0, 0, 0, 0 }, targets = { 0, 0, 0, 0 }, angle = (i - 1) * 1.3, cpu = 0, extent = 0,
            }
        end
        local slots = {}
        for i = 1, 6 do slots[i] = empty_slot(i) end
        local tints = g.signal({} :: { string })
        local tags = g.signal({} :: { any })
        local shapes = g.signal({} :: { number })
        local moving = g.signal(false)

        local function lobes_of(slot: any): { any }
            local r = slot.radii
            local out = { { x = slot.x, y = slot.y, r = r[1] } }
            for i = 2, 4 do
                local angle = slot.angle + (i - 2) * math.pi * 2 / 3
                local distance = P.nesting * (r[1] + r[i])
                table.insert(out, { x = slot.x + math.cos(angle) * distance, y = slot.y + math.sin(angle) * distance, r = r[i] })
            end
            return out
        end

        -- A new cell starts where there is most room.
        local function place(slot: any)
            local w, h = g.untracked(o.width), g.untracked(o.height)
            local best, best_room = { x = w / 2, y = h / 2 }, -1
            for i = 0, 23 do
                local x = w * (0.2 + 0.6 * ((i * 7) % 24) / 23)
                local y = h * (0.2 + 0.6 * ((i * 11) % 24) / 23)
                local room = math.huge
                for _, other in slots do
                    if other ~= slot and other.key ~= "" and not other.leaving then
                        room = math.min(room, math.sqrt((other.x - x) ^ 2 + (other.y - y) ^ 2) - other.extent)
                    end
                end
                if room > best_room then best_room, best = room, { x = x, y = y } end
            end
            slot.x, slot.y = best.x, best.y
        end

        local function draw()
            local here = g.untracked(present)
            local out, tag_list = {}, {}
            local show = g.untracked(labels)
            local labelled = 24 * g.untracked(f)
            for i, slot in slots do
                for _, l in lobes_of(slot) do
                    table.insert(out, l.x); table.insert(out, l.y); table.insert(out, if here then l.r else 0); table.insert(out, 0)
                end
                table.insert(tag_list, {
                    index = i, x = slot.x, y = slot.y, name = slot.name,
                    figure = if slot.ram >= 1024 then string.format("%.1f GB", slot.ram / 1024) else math.round(slot.ram) .. " MB",
                    shown = show and not slot.leaving and slot.radii[1] > 0 and slot.extent >= labelled,
                })
            end
            shapes.value = out
            tags.value = tag_list
        end

        local function ingest()
            local list = app_load.apps()
            local ram_total = system.ram_total()
            if ram_total <= 0 then return end
            local shown_apps = {}
            for i = 1, math.min(count(), #list) do shown_apps[i] = list[i] end
            local area = o.width() * o.height() * P.fill
            local shown = 0
            for _, a in shown_apps do shown += a.ram end
            shown /= ram_total
            local scale = if shown > P.ceiling then P.ceiling / shown else 1
            g.untracked(function()
                local wanted = {}
                for _, a in shown_apps do wanted[a.key] = a end
                for _, slot in slots do
                    if slot.key ~= "" and not wanted[slot.key] then slot.leaving = true end
                end
                for _, a in shown_apps do
                    local slot = nil
                    for _, s in slots do if s.key == a.key then slot = s end end
                    if not slot then
                        for i, s in slots do
                            if s.leaving and s.radii[1] < 0.5 and s.radii[2] < 0.5 and s.radii[3] < 0.5 and s.radii[4] < 0.5 then
                                slot = empty_slot(i)
                                slots[i] = slot
                                slot.key = a.key
                                place(slot)
                                break
                            end
                        end
                    end
                    if slot then
                        slot.leaving = false
                        slot.name, slot.ram, slot.cpu = a.name, a.ram, a.cpu
                        -- The heaviest three processes and the rest, each a lobe
                        -- whose area is its share of the cell's; a share too small
                        -- to be more than a speck joins the body.
                        local cell_area = a.ram / ram_total * area * scale
                        local least = a.ram * P.smallest
                        local shares = {}
                        for i = 1, 3 do shares[i] = if a.processes[i] then a.processes[i].ram else 0 end
                        local rest = 0
                        for i = 4, #a.processes do rest += a.processes[i].ram end
                        shares[4] = rest
                        for i = 2, 4 do
                            if shares[i] < least then
                                shares[1] += shares[i]
                                shares[i] = 0
                            end
                        end
                        for i = 1, 4 do
                            slot.targets[i] = if a.ram > 0 then math.sqrt(shares[i] / a.ram * cell_area / math.pi) else 0
                        end
                    end
                end
                for _, slot in slots do
                    if slot.leaving then slot.targets = { 0, 0, 0, 0 } end
                end
                local t = {}
                for i, slot in slots do
                    t[i] = if themed() then theme.primary() else theme.state_for(math.min(1, (slot.cpu or 0) / 100))
                end
                tints.value = t
                moving.value = true
                draw()
            end)
        end
        g.effect(ingest)

        local function step(dt: number)
            local fa = g.untracked(f)
            local w, h = g.untracked(o.width), g.untracked(o.height)
            local any = false
            for _, slot in slots do
                for i = 1, 4 do
                    local gap = slot.targets[i] - slot.radii[i]
                    if math.abs(gap) > 0.2 then
                        slot.radii[i] += gap * math.min(1, P.growth * dt)
                        any = true
                    else
                        slot.radii[i] = slot.targets[i]
                    end
                end
                local spin = math.min(P.fastest, P.streaming * (slot.cpu or 0))
                if spin > 0.005 and slot.radii[1] > 0.5 then
                    slot.angle += spin * dt
                    any = true
                end
                local extent = 0
                if slot.radii[1] > 0 then
                    for _, l in lobes_of(slot) do
                        extent = math.max(extent, math.sqrt((l.x - slot.x) ^ 2 + (l.y - slot.y) ^ 2) + l.r)
                    end
                end
                slot.extent = extent
            end
            -- Cells pressed together: each pulled to the centre, pushed apart
            -- lobe against lobe where two would overlap, held inside the glass.
            local live = {}
            for _, slot in slots do if slot.extent > 0.5 then table.insert(live, slot) end end
            for _, slot in live do
                slot.x += (w / 2 - slot.x) * P.pull * dt
                slot.y += (h / 2 - slot.y) * P.pull * dt
            end
            local lobes = {}
            for i, slot in live do
                lobes[i] = {}
                for _, l in lobes_of(slot) do if l.r > 0.5 then table.insert(lobes[i], l) end end
            end
            for a = 1, #live do
                for b = a + 1, #live do
                    local px, py = 0, 0
                    for _, one in lobes[a] do
                        for _, two in lobes[b] do
                            local dx, dy = two.x - one.x, two.y - one.y
                            local d = math.sqrt(dx * dx + dy * dy)
                            if d < 0.01 then dx, dy, d = 1, 0, 1 end
                            local overlap = one.r + two.r + P.gap * fa - d
                            if overlap > 0 then
                                px += dx / d * overlap
                                py += dy / d * overlap
                            end
                        end
                    end
                    local push = math.min(1, 10 * dt) / 2
                    live[a].x -= px * push
                    live[a].y -= py * push
                    live[b].x += px * push
                    live[b].y += py * push
                    if math.sqrt(px * px + py * py) * push > 0.05 then any = true end
                end
            end
            local inset = P.inset * fa
            for _, slot in live do
                local reach = math.min(slot.extent + inset, math.min(w, h) / 2)
                slot.x = math.clamp(slot.x, reach, math.max(reach, w - reach))
                slot.y = math.clamp(slot.y, reach, math.max(reach, h - reach))
            end
            moving.value = any
            draw()
        end
        stepper.new { running = function() return moving.value and present() end, step = step }

        local function values(): { number }
            local out = { m().radius_panel, 0, 0, 0 }
            local function push(hex: string)
                local c = colour.parse(hex)
                table.insert(out, c.r); table.insert(out, c.g); table.insert(out, c.b); table.insert(out, c.a)
            end
            push(theme.text())
            local t = tints.value
            for i = 1, 6 do push(t[i] or theme.primary()) end
            for _, v in shapes.value do table.insert(out, v) end
            return out
        end

        local function tag(item: () -> any): any
            local function meta(text: () -> string, weight: number, alpha: number): any
                return g.text { text = text, color = function() return colour.alpha(theme.text(), alpha) end,
                    font = typography.technical, size = function() return m().font_meta end, weight = weight,
                    tracking = typography.label_tracking, tabular = true }
            end
            return g.box {
                overlay = true,
                attach = "corner",
                offset_x = function() return item().x - 60 * f() end,
                offset_y = function() return item().y - m().font_meta * 1.3 end,
                width = function() return 120 * f() end,
                direction = "column",
                align = "center",
                opacity = function() return if item().shown then 1 else 0 end,
                transition = { opacity = "content_fade", offset_x = "step", offset_y = "step" },
                meta(function() return string.upper(item().name) end, typography.weight_label, 1),
                meta(function() return item().figure end, typography.weight_secondary, 0.8),
            }
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
                    g.each {
                        overlay = true,
                        attach = "corner",
                        items = function() return tags.value end,
                        key = function(t: any) return tostring(t.index) end,
                        row = tag,
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not present() end,
                        width = o.width,
                        height = o.height,
                        align = "center",
                        justify = "center",
                        g.text { text = "No applications", color = theme.text_faint, font = typography.technical,
                            size = function() return m().font_secondary end },
                    },
                }
            end,
        }
    end,
}
