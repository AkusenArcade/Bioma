--!strict
-- Settings → Monitors (cells/settings/SettingsMonitors.qml at 11bb81e):
-- where the monitors are, relative to each other.
--
-- Each output is a rectangle drawn to scale, with its name and its mode on
-- two lines in the middle. Dragged and snapped, one below the other too:
-- while a rectangle moves, the edges and centres it could line up with
-- pull it in, and the line it has snapped to is drawn across the area (the
-- guide is the snap, there only while something is snapping). Let go and
-- the layout is written, the top-left monitor at the origin; the
-- rectangles are then drawn from what niri reports, not from where the
-- hand left them. Two monitors may not overlap, so a drop that overlaps
-- goes back.
--
-- Below the area, the chosen monitor: its name, whether it is on, whether
-- it is the one niri focuses at startup (niri's only notion of a primary
-- output) and its scale; on a second line its variable refresh, offered
-- only where niri says the monitor can. On demand waits for a window rule
-- that asks for it, and the line says so while none does; GAMES puts
-- Bioma's own rule for games in place, or takes it back. A monitor
-- switched off stays in the drawing as an outline, and is not dragged.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local segmented = require("components/segmented")
local switch = require("components/switch")
local monitors = require("services/monitors")
local place = require("cells/settings_place")

local M = {}

local CLEAR = "#00000000"

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local function m(): any return t.metrics() end
    local function f(): number return m().factor end
    local function line_height(): number return 44 * f() end
    local function footer_height(): number return 2 * line_height() end
    -- Between the area and the controls under it: they belong to the
    -- chosen monitor, not to the drawing.
    local function footer_gap(): number return 14 * f() end
    local function margin(): number return 36 * f() end
    local function snap_distance(): number return 12 * f() end
    local function area_width(): number return t.width() end
    local function area_height(): number return t.height() - footer_height() - footer_gap() end

    -- The ones that are on, which are the layout, and every one, which is
    -- what is drawn.
    local function all(): { any }
        local out = table.clone(monitors.outputs())
        for _, o in monitors.off() do table.insert(out, o) end
        return out
    end

    local function chosen(): string
        local wanted = place.monitor.value
        local list = all()
        for _, o in list do
            if o.name == wanted then return wanted end
        end
        return if #list > 0 then list[1].name else ""
    end
    local function chosen_output(): any return monitors.output_of(chosen()) end
    local function choose(name: string) place.monitor.value = name end

    monitors.refresh()

    -- ---- The layout, as drawn ------------------------------------------------

    -- Where each monitor is while the hand has it, in logical units; empty
    -- otherwise: at rest, everything is drawn from what niri reports.
    local moving = g.signal({} :: { [string]: { x: number, y: number } })
    local held = g.signal("")
    local refusal = g.signal("")

    local function position_of(o: any): (number, number)
        local moved = moving.value[o.name]
        if moved then return moved.x, moved.y end
        return o.x, o.y
    end

    -- The scale and offset from logical units to the area. Frozen while
    -- something is carried: a canvas that refits itself under the pointer
    -- moves the very thing being aimed at.
    local frozen = g.signal(nil :: any)
    local fit = g.computed(function(): any
        if frozen.value then return frozen.value end
        local list = all()
        if #list == 0 or area_width() <= 0 then return { scale = 1, x = 0, y = 0, min_x = 0, min_y = 0 } end
        local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
        for _, o in list do
            min_x = math.min(min_x, o.x)
            min_y = math.min(min_y, o.y)
            max_x = math.max(max_x, o.x + o.width)
            max_y = math.max(max_y, o.y + o.height)
        end
        local w, h = max_x - min_x, max_y - min_y
        local scale = math.min((area_width() - 2 * margin()) / w, (area_height() - 2 * margin()) / h)
        return {
            scale = scale,
            x = (area_width() - w * scale) / 2,
            y = (area_height() - h * scale) / 2,
            min_x = min_x,
            min_y = min_y,
        }
    end)
    local function to_area(x: number, y: number): (number, number)
        local q = fit.value
        return q.x + (x - q.min_x) * q.scale, q.y + (y - q.min_y) * q.scale
    end
    local function to_logical(x: number, y: number): (number, number)
        local q = g.untracked(function() return fit.value end)
        return (x - q.x) / q.scale + q.min_x, (y - q.y) / q.scale + q.min_y
    end

    -- ---- Snapping ----------------------------------------------------------------
    --
    -- Per axis, the nearest of: this edge against that edge, this edge in
    -- line with that edge, centre in line with centre. Within reach it
    -- wins; the guide is where it snapped.
    local guide_x = g.signal(nil :: number?)
    local guide_y = g.signal(nil :: number?)

    local function snapped(name: string, x: number, y: number): (number, number)
        local on = g.untracked(monitors.outputs)
        local me = nil
        for _, o in on do if o.name == name then me = o end end
        if not me then return math.round(x), math.round(y) end
        local reach = g.untracked(snap_distance) / g.untracked(function() return fit.value end).scale
        local best_x, best_y = nil :: any, nil :: any
        local function consider(best: any, value: number, target: number): any
            local d = target - value
            if math.abs(d) <= reach and (best == nil or math.abs(d) < math.abs(best.delta)) then
                return { delta = d, line = target }
            end
            return best
        end
        for _, other in on do
            if other.name ~= name then
                local left, right, middle = other.x, other.x + other.width, other.x + other.width / 2
                local top, bottom, centre = other.y, other.y + other.height, other.y + other.height / 2
                best_x = consider(best_x, x, right)
                best_x = consider(best_x, x + me.width, left)
                best_x = consider(best_x, x, left)
                best_x = consider(best_x, x + me.width, right)
                best_x = consider(best_x, x + me.width / 2, middle)
                best_y = consider(best_y, y, bottom)
                best_y = consider(best_y, y + me.height, top)
                best_y = consider(best_y, y, top)
                best_y = consider(best_y, y + me.height, bottom)
                best_y = consider(best_y, y + me.height / 2, centre)
            end
        end
        guide_x.value = if best_x then best_x.line else nil
        guide_y.value = if best_y then best_y.line else nil
        return math.round(x + (if best_x then best_x.delta else 0)), math.round(y + (if best_y then best_y.delta else 0))
    end

    local function overlaps(positions: { [string]: any }): boolean
        local boxes = {}
        for _, o in g.untracked(monitors.outputs) do
            local at = positions[o.name]
            table.insert(boxes, { x = at.x, y = at.y, w = o.width, h = o.height })
        end
        for i = 1, #boxes do
            for j = i + 1, #boxes do
                local a, b = boxes[i], boxes[j]
                if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then return true end
            end
        end
        return false
    end

    local function take(name: string)
        frozen.value = g.untracked(function() return fit.value end)
        held.value = name
        refusal.value = ""
        choose(name)
    end

    local function carry(name: string, x: number, y: number)
        local next = table.clone(g.untracked(function() return moving.value end))
        local sx, sy = snapped(name, x, y)
        next[name] = { x = sx, y = sy }
        moving.value = next
    end

    local function settle()
        moving.value = {}
        frozen.value = nil
    end

    -- Let go: the whole layout, moved so its top-left is the origin, and
    -- written if anything actually moved.
    local function drop()
        local positions = {}
        local on = g.untracked(monitors.outputs)
        for _, o in on do
            local moved = g.untracked(function() return moving.value end)[o.name]
            positions[o.name] = if moved then { x = moved.x, y = moved.y } else { x = o.x, y = o.y }
        end
        held.value = ""
        guide_x.value = nil
        guide_y.value = nil
        if overlaps(positions) then
            refusal.value = "Monitors cannot overlap"
            settle()
            return
        end
        local min_x, min_y = math.huge, math.huge
        for _, at in positions do
            min_x = math.min(min_x, at.x)
            min_y = math.min(min_y, at.y)
        end
        local moved = false
        for _, o in on do
            local at = positions[o.name]
            at.x -= min_x
            at.y -= min_y
            if at.x ~= o.x or at.y ~= o.y then moved = true end
        end
        -- Put back where it was: nothing to write.
        if not moved then
            settle()
            return
        end
        monitors.place(positions)
    end

    -- What niri reports next is the layout from then on.
    g.watch(monitors.outputs, function()
        if g.untracked(function() return held.value end) == "" then settle() end
    end)
    g.watch(monitors.error, function(e: string)
        if e ~= "" and g.untracked(function() return held.value end) == "" then settle() end
    end)

    -- ---- The area ----------------------------------------------------------------

    local function technical(text: string | () -> string, size: () -> number, color: any, weight: any?): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = size,
            weight = weight,
            tracking = typography.label_tracking,
        }
    end

    local function monitor(o: () -> any): any
        local function name(): string return o().name end
        local function is_chosen(): boolean return chosen() == name() end
        local function lit(): boolean return o().on end
        local function carried(): boolean return held.value == name() end
        local function at(): (number, number) return to_area(position_of(o())) end
        local function w(): number return o().width * fit.value.scale end
        local function h(): number return o().height * fit.value.scale end
        -- Where the press landed, and where the monitor was then: a drag is
        -- told from the node as it was at the press.
        local grab_x, grab_y = 0, 0
        local from_x, from_y = 0, 0
        local pressed = false
        local function inset(): number return 2 * f() end
        return g.box {
            role = "button",
            name = g.untracked(o).name,
            overlay = true,
            attach = "corner",
            offset_x = function() local x = at() return x end,
            offset_y = function() local _, y = at() return y end,
            width = w,
            height = h,
            -- Settling where niri put it, not jumping there.
            transition = {
                offset_x = function() return if carried() then "instant" else "transition" end,
                offset_y = function() return if carried() then "instant" else "transition" end,
            },
            on_press = function(button: number, x: number, y: number)
                if button ~= 272 then return end
                choose(g.untracked(name))
                if not g.untracked(lit) or g.untracked(monitors.busy) then return end
                pressed = true
                grab_x, grab_y = x, y
                from_x = g.untracked(function() local v = at() return v end)
                from_y = g.untracked(function() local _, v = at() return v end)
            end,
            -- Carried from where it was touched, not by its middle.
            on_drag = function(x: number, y: number)
                if not pressed then return end
                local n = g.untracked(name)
                if g.untracked(function() return held.value end) ~= n then take(n) end
                local lx, ly = to_logical(from_x + x - grab_x, from_y + y - grab_y)
                carry(n, lx, ly)
            end,
            on_release = function()
                if not pressed then return end
                pressed = false
                if g.untracked(function() return held.value end) ~= "" then drop() end
            end,
            on_click = function() end,
            -- Inset, so two monitors that touch read as two and not as one
            -- shape with a line through it.
            g.capsule {
                overlay = true,
                attach = "corner",
                offset_x = inset,
                offset_y = inset,
                width = function() return w() - inset() * 2 end,
                height = function() return h() - inset() * 2 end,
                radius = function() return 10 * f() end,
                fill = function()
                    if not lit() then return CLEAR end
                    return colour.alpha(theme.lift(theme.background(), if is_chosen() then 0.06 else 0.02), 0.9)
                end,
                rim_top = function() return if is_chosen() then theme.primary() else theme.line() end,
                rim_bottom = function() return if is_chosen() then theme.primary() else theme.line() end,
                stroke = function() return if is_chosen() then 1.5 else 1 end,
                transition = { fill = "transition", rim_top = "transition", rim_bottom = "transition" },
            },
            g.box {
                overlay = true,
                width = w,
                height = h,
                direction = "column",
                align = "center",
                justify = "center",
                gap = function() return 4 * f() end,
                technical(name, function() return m().font_secondary end, function()
                    if not lit() then return theme.text_faint() end
                    return if is_chosen() then theme.text() else theme.text_muted()
                end, function() return if is_chosen() then typography.weight_title else typography.weight_label end),
                g.text {
                    text = function()
                        local x = o()
                        return x.mode_width .. " × " .. x.mode_height .. " · " .. math.round(x.refresh) .. " Hz"
                    end,
                    color = function() return if lit() then theme.text_muted() else theme.text_faint() end,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tracking = typography.label_tracking,
                    tabular = true,
                    max_width = function() return w() - 16 * f() end,
                },
            },
        }
    end

    local function guide(vertical: boolean): any
        return g.capsule {
            overlay = true,
            attach = "corner",
            present = function() return (if vertical then guide_x.value else guide_y.value) ~= nil end,
            offset_x = function()
                if not vertical then return 0 end
                local x = to_area(guide_x.value or 0, 0)
                return math.round(x)
            end,
            offset_y = function()
                if vertical then return 0 end
                local _, y = to_area(0, guide_y.value or 0)
                return math.round(y)
            end,
            width = function() return if vertical then 1 else area_width() end,
            height = function() return if vertical then area_height() else 1 end,
            crisp = true,
            fill = function() return colour.alpha(theme.primary(), 0.6) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
        }
    end

    local area = g.capsule {
        width = area_width,
        height = area_height,
        radius = function() return metrics_mod.inner_radius(m().radius_panel, 6 * f()) end,
        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
        rim_top = CLEAR,
        rim_bottom = CLEAR,
        guide(true),
        guide(false),
        g.each {
            overlay = true,
            attach = "corner",
            items = all,
            key = function(o: any) return o.name end,
            row = monitor,
        },
        g.text {
            overlay = true,
            present = function() return #all() == 0 end,
            text = "Asking niri…",
            color = theme.text_faint,
            font = typography.expressive,
            size = function() return m().font_secondary end,
        },
    }

    -- ---- The chosen one ------------------------------------------------------

    local function power_lit(): boolean local o = chosen_output() return o ~= nil and o.on end
    local function role_fixed(): boolean return monitors.busy() or not power_lit() end
    local function vrr_offered(): boolean local o = chosen_output() return power_lit() and o.vrr_supported == true end
    local function vrr_mode(): string return if power_lit() then chosen_output().vrr else "off" end
    local function meta_label(text: string): any
        return technical(text, function() return m().font_meta end, theme.text, typography.weight_label)
    end

    local first = g.box {
        width = area_width,
        height = line_height,
        direction = "row",
        align = "center",
        gap = function() return 14 * f() end,
        padding_left = function() return 4 * f() end,
        padding_right = function() return 4 * f() end,
        technical(chosen, function() return m().font_label end, theme.text, typography.weight_label),
        -- What went wrong, in the one place that says anything here.
        g.text {
            text = function() return if refusal.value ~= "" then refusal.value else monitors.error() end,
            color = theme.alert,
            font = typography.expressive,
            size = function() return m().font_meta end,
            max_width = function() return area_width() * 0.3 end,
        },
        g.box { grow = 1 },
        switch.new {
            on = power_lit,
            factor = f,
            settling = monitors.busy,
            dimmed = function() return power_lit() and monitors.count() <= 1 end,
            on_toggle = function(value: boolean)
                if not g.untracked(chosen_output) or g.untracked(monitors.busy) then return end
                refusal.value = if monitors.power(g.untracked(chosen), value) then "" else "The last monitor stays on"
            end,
        },
        segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            button_height = function() return 26 * f() end,
            options = function()
                return {
                    { key = "primary", label = "Primary", dimmed = role_fixed() },
                    { key = "secondary", label = "Secondary", dimmed = role_fixed() },
                }
            end,
            current = function() local o = chosen_output() return if o and o.primary then "primary" else "secondary" end,
            on_choose = function(key: string)
                if g.untracked(role_fixed) then return end
                local o = g.untracked(chosen_output)
                if not o then return end
                if key == "primary" then monitors.make_primary(o.name)
                elseif o.primary then monitors.make_primary("") end
            end,
        },
        g.text {
            text = function() return if power_lit() then "scale " .. string.format("%.1f", chosen_output().scale) else "" end,
            color = theme.text_muted,
            font = typography.expressive,
            size = function() return m().font_secondary end,
        },
    }

    -- ---- Variable refresh ---------------------------------------------------

    local second = g.box {
        present = power_lit,
        width = area_width,
        height = line_height,
        direction = "row",
        align = "center",
        gap = function() return 14 * f() end,
        padding_left = function() return 4 * f() end,
        padding_right = function() return 4 * f() end,
        -- The name of a setting is the machine's voice; the sentence
        -- saying it is not offered is the human one.
        g.box { present = vrr_offered, meta_label("VARIABLE REFRESH") },
        g.text {
            present = function() return not vrr_offered() end,
            text = "No variable refresh on this monitor",
            color = theme.text_faint,
            font = typography.expressive,
            size = function() return m().font_secondary end,
        },
        g.text {
            present = function() return vrr_offered() and vrr_mode() == "demand" and not monitors.vrr_rule() end,
            text = "No window rule asks for it yet",
            color = theme.alert,
            font = typography.expressive,
            size = function() return m().font_meta end,
            max_width = function() return area_width() * 0.3 end,
        },
        g.box { grow = 1 },
        g.box {
            present = function() return vrr_offered() and vrr_mode() == "demand" end,
            direction = "row",
            align = "center",
            gap = function() return 8 * f() end,
            meta_label("GAMES"),
            switch.new {
                on = monitors.games_rule,
                factor = f,
                settling = monitors.busy,
                on_toggle = function(value: boolean)
                    if not g.untracked(monitors.busy) then monitors.set_games(value) end
                end,
            },
        },
        g.box {
            present = vrr_offered,
            segmented.new {
                metrics = m,
                font_size = function() return m().font_meta end,
                button_height = function() return 26 * f() end,
                options = function()
                    local fixed = monitors.busy()
                    return {
                        { key = "off", label = "Off", dimmed = fixed },
                        { key = "demand", label = "On demand", dimmed = fixed },
                        { key = "on", label = "Always", dimmed = fixed },
                    }
                end,
                current = vrr_mode,
                on_choose = function(key: string)
                    if g.untracked(monitors.busy) or key == g.untracked(vrr_mode) then return end
                    monitors.set_vrr(g.untracked(chosen), key)
                end,
            },
        },
    }

    return g.box {
        width = area_width,
        height = t.height,
        direction = "column",
        gap = footer_gap,
        area,
        g.box { width = area_width, height = footer_height, direction = "column", first, second },
    }
end

return M
