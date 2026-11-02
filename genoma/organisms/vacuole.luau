--!strict
-- Vacuole: the notifications nobody has read yet, stored in a sac
-- (organisms/vacuole/VacuoleOrganism.qml at 2cafc17). See
-- docs/design/ORGANISMS.md §12.
--
-- Each application is one body in the sac and each of its unread
-- notifications a drop of it: the drops of one application melt together,
-- two applications never do. A notification arrives unread and stays so
-- until it is read (Akusen, 2026-10-07); read, its drop is taken back in.
-- Nothing moves but that. With nothing unread there is no vacuole. A body
-- is primary; one holding a critical notification is alert.
--
-- Not yet: the shadow under the names (MultiEffect).
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")
local notifications = require("services/notifications")
local stepper = require("components/stepper")

local SOURCE = require("core/paths").root .. "/genoma/organisms/cytoplasm.wgsl"
local P = { drop = 0.2, ceiling = 0.45, growth = 3.0, nesting = 0.6, gap = 2, pull = 0.6, inset = 6, membrane = 1.5 }
local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function present(): boolean return #notifications.unread() > 0 end
        local function figures(): boolean return o.entry().figures ~= false end
        local function labels(): boolean return o.entry().labels ~= false end
        local function gap(): number return 14 * f() end
        local function caption_height(): number return m().font_label * 1.3 end
        local function sac(): number
            return math.max(0, math.min(o.width(), o.height() - (if figures() then gap() + caption_height() else 0)))
        end
        local function sac_x(): number return (o.width() - sac()) / 2 end

        -- Unread, by application, most first.
        local function apps(): { any }
            local by, order = {}, {}
            for _, e in notifications.unread() do
                local key = if e.app_name ~= "" then e.app_name else "?"
                if not by[key] then
                    by[key] = { key = key, name = if e.app_name ~= "" then e.app_name else "Unknown", count = 0, critical = false }
                    table.insert(order, by[key])
                end
                by[key].count += 1
                by[key].critical = by[key].critical or e.critical
            end
            table.sort(order, function(a: any, b: any) return a.count > b.count end)
            return order
        end

        local function empty_slot(i: number): any
            local angle = (i - 1) / 6 * math.pi * 2
            local s = g.untracked(sac)
            return {
                key = "", name = "", count = 0, critical = false, leaving = true,
                x = s / 2 + math.cos(angle) * s * 0.2, y = s / 2 + math.sin(angle) * s * 0.2,
                radii = { 0, 0, 0, 0 }, targets = { 0, 0, 0, 0 },
                -- Fixed per slot, so the sac does not turn while nothing arrives.
                angle = (i - 1) * 1.3 - math.pi / 2, extent = 0,
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
        local function place(slot: any)
            local c = g.untracked(sac) / 2
            local best, best_room = { x = c, y = c }, -math.huge
            for i = 0, 23 do
                local angle = i * 2.39996
                local distance = c * 0.55 * math.sqrt((i + 0.5) / 24)
                local x, y = c + math.cos(angle) * distance, c + math.sin(angle) * distance
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
            local show = g.untracked(labels)
            local fa = g.untracked(f)
            local out, list = {}, {}
            for i, slot in slots do
                for _, l in lobes_of(slot) do
                    table.insert(out, l.x); table.insert(out, l.y); table.insert(out, if here then l.r else 0); table.insert(out, 0)
                end
                table.insert(list, { index = i, x = slot.x, y = slot.y, name = slot.name, figure = tostring(slot.count),
                    extent = slot.extent,
                    shown = show and not slot.leaving and slot.radii[1] > 0 and slot.extent >= 22 * fa })
            end
            shapes.value = out
            tags.value = list
        end
        local function ingest()
            local list = apps()
            local s = sac()
            if s <= 0 then return end
            g.untracked(function()
                local fa = f()
                local inner = s / 2 - P.membrane * fa - P.inset * fa
                local drop_area = math.pi * (P.drop * inner) ^ 2
                local drops = 0
                for i = 1, math.min(6, #list) do drops += list[i].count end
                local room = P.ceiling * math.pi * inner * inner
                local scale = if drops * drop_area > room then room / (drops * drop_area) else 1
                local wanted = {}
                for i = 1, math.min(6, #list) do wanted[list[i].key] = list[i] end
                for _, slot in slots do
                    if slot.key ~= "" and not wanted[slot.key] then slot.leaving = true end
                end
                for i = 1, math.min(6, #list) do
                    local a = list[i]
                    local slot = nil
                    for _, sl in slots do if sl.key == a.key then slot = sl end end
                    if not slot then
                        for j, sl in slots do
                            if sl.leaving and sl.radii[1] < 0.5 and sl.radii[2] < 0.5 and sl.radii[3] < 0.5 and sl.radii[4] < 0.5 then
                                slot = empty_slot(j)
                                slots[j] = slot
                                slot.key = a.key
                                place(slot)
                                break
                            end
                        end
                    end
                    if slot then
                        slot.leaving = false
                        slot.name, slot.count, slot.critical = a.name, a.count, a.critical
                        -- The drops dealt round the four lobes.
                        for k = 0, 3 do
                            local share = if a.count > k then (a.count - k + 3) // 4 else 0
                            slot.targets[k + 1] = math.sqrt(share * drop_area * scale / math.pi)
                        end
                    end
                end
                for _, slot in slots do
                    if slot.leaving then slot.targets = { 0, 0, 0, 0 } end
                end
                local t = {}
                for i, slot in slots do t[i] = if slot.critical then theme.alert() else theme.primary() end
                tints.value = t
                moving.value = true
                draw()
            end)
        end
        g.effect(ingest)
        g.watch(present, function() draw() end)

        local function step(dt: number)
            local fa = g.untracked(f)
            local c = g.untracked(sac) / 2
            local any = false
            for _, slot in slots do
                for i = 1, 4 do
                    local d = slot.targets[i] - slot.radii[i]
                    if math.abs(d) > 0.2 then
                        slot.radii[i] += d * math.min(1, P.growth * dt)
                        any = true
                    else
                        slot.radii[i] = slot.targets[i]
                    end
                end
                local extent = 0
                if slot.radii[1] > 0 then
                    for _, l in lobes_of(slot) do
                        extent = math.max(extent, math.sqrt((l.x - slot.x) ^ 2 + (l.y - slot.y) ^ 2) + l.r)
                    end
                end
                slot.extent = extent
            end
            local live = {}
            for _, slot in slots do if slot.extent > 0.5 then table.insert(live, slot) end end
            for _, slot in live do
                slot.x += (c - slot.x) * P.pull * dt
                slot.y += (c - slot.y) * P.pull * dt
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
                    live[a].x -= px * push; live[a].y -= py * push
                    live[b].x += px * push; live[b].y += py * push
                    if math.sqrt(px * px + py * py) * push > 0.05 then any = true end
                end
            end
            local inner = c - (P.membrane + P.inset) * fa
            for _, slot in live do
                local reach = math.max(0, inner - slot.extent)
                local dx, dy = slot.x - c, slot.y - c
                local d = math.sqrt(dx * dx + dy * dy)
                if d > reach and d > 0 then
                    slot.x, slot.y = c + dx / d * reach, c + dy / d * reach
                end
            end
            moving.value = any
            draw()
        end
        stepper.new { running = function() return moving.value end, step = step }

        local function values(): { number }
            local out = { sac() / 2, 0, 0, 0 }
            local function push(hex: string)
                local cc = colour.parse(hex)
                table.insert(out, cc.r); table.insert(out, cc.g); table.insert(out, cc.b); table.insert(out, cc.a)
            end
            push(theme.text())
            local t = tints.value
            for i = 1, 6 do push(t[i] or theme.primary()) end
            for _, v in shapes.value do table.insert(out, v) end
            return out
        end
        local function since(at: number): string
            local d, now = os.date("*t", at) :: any, os.date("*t") :: any
            local time = string.format("%02d:%02d", d.hour, d.min)
            if d.year == now.year and d.yday == now.yday then return time end
            return d.day .. " " .. MONTHS[d.month] .. " " .. time
        end
        local function meta(text: () -> string, weight: number, alpha: number): any
            return g.text { text = text, color = function() return colour.alpha(theme.text(), alpha) end,
                font = typography.technical, size = function() return m().font_meta end, weight = weight,
                tracking = typography.label_tracking, tabular = true }
        end
        local function tag(item: () -> any): any
            local function named(): boolean
                local width = g.text_width { text = string.upper(item().name), font = typography.technical(),
                    size = m().font_meta, tracking = typography.label_tracking }
                return width <= 2 * item().extent + 6 * f()
            end
            return g.box {
                overlay = true,
                attach = "corner",
                offset_x = function() return sac_x() + item().x - 60 * f() end,
                offset_y = function() return item().y - m().font_meta * (if named() then 1.3 else 0.65) end,
                width = function() return 120 * f() end,
                direction = "column",
                align = "center",
                opacity = function() return if item().shown then 1 else 0 end,
                transition = { opacity = "content_fade", offset_x = "step", offset_y = "step" },
                g.box { present = named, meta(function() return string.upper(item().name) end, typography.weight_label, 1) },
                meta(function() return item().figure end, typography.weight_secondary, 0.8),
            }
        end

        return {
            present = present,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    g.capsule {
                        overlay = true,
                        attach = "corner",
                        offset_x = sac_x,
                        width = sac,
                        height = sac,
                        stroke = function() return P.membrane * f() end,
                        fill = function() return colour.alpha(theme.text(), 0.03) end,
                        rim_top = function() return colour.alpha(theme.text(), 0.22) end,
                        rim_bottom = function() return colour.alpha(theme.text(), 0.22) end,
                    },
                    g.shader {
                        overlay = true,
                        attach = "corner",
                        offset_x = sac_x,
                        src = SOURCE,
                        width = sac,
                        height = sac,
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
                        offset_x = sac_x,
                        width = sac,
                        height = sac,
                        align = "center",
                        justify = "center",
                        g.text { text = "Nothing unread", color = theme.text_faint, font = typography.expressive,
                            size = function() return math.round(14 * f()) end, italic = true },
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return figures() and present() end,
                        offset_x = sac_x,
                        offset_y = function() return sac() + gap() end,
                        width = sac,
                        direction = "row",
                        align = "center",
                        justify = "between",
                        g.box {
                            direction = "row",
                            align = "end",
                            gap = function() return 8 * f() end,
                            meta(function() return "UNREAD" end, typography.weight_label, 1),
                            g.text { text = function() return tostring(#notifications.unread()) end,
                                color = function() return theme.gradient_top(theme.primary()) end,
                                color_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                                font = typography.technical, size = function() return m().font_label end,
                                weight = typography.weight_value, tabular = true },
                        },
                        g.text {
                            text = function()
                                local list = notifications.unread()
                                return if #list > 0 then "SINCE " .. since(list[1].at) else ""
                            end,
                            color = theme.text_muted, font = typography.technical,
                            size = function() return m().font_meta end, tabular = true,
                        },
                    },
                }
            end,
        }
    end,
}
