--!strict
-- Settings → Appearance (cells/settings/SettingsAppearance.qml at
-- 11bb81e): how the shell looks, the handful of numbers the whole of it is
-- drawn from.
--
-- Every row writes straight into the override, and every surface is bound
-- to those values: a slider moved here is the desktop changing under the
-- hand, not a preview of one, which is why there is no apply button.
-- Sliders are controls, so they keep the primary for their whole travel.
--
-- Under the numbers, the palettes: Bioma's and the user's own, chosen with
-- a press, and the user's edited in place (a name and the four interface
-- roles, each by its hex, by hue, saturation and value, or by niri's
-- eyedropper).
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local page = require("components/page")
local segmented = require("components/segmented")
local slider = require("components/slider")
local switch = require("components/switch")
local choice_mod = require("components/choice")
local field_mod = require("components/field")
local palettes = require("services/palettes")

local M = {}

local CLEAR = "#00000000"

-- Each row: what it is called, where it is kept, its range, and how it
-- says itself. `step` snaps a travel to values that mean something.
local ROWS = {
    { label = "OPACITY", key = "cell.opacity", from = 0.3, to = 1, step = 0.01, unit = "%", scale = 100, fallback = 0.72 },
    { label = "RADIUS", key = "appearance.radius", from = 0, to = 100, step = 1, unit = "%", scale = 1, fallback = 100 },
    { label = "EDGE", key = "appearance.edge", from = 0, to = 32, step = 1, unit = " px", scale = 1, fallback = 12 },
    { label = "TISSUE", key = "tissue.padding", from = 2, to = 12, step = 1, unit = " px", scale = 1, fallback = 2 },
    { label = "GAP", key = "appearance.gap", from = 8, to = 48, step = 1, unit = " px", scale = 1, fallback = 24 },
}

local ROLE_LABELS = { background = "BACKGROUND", text = "TEXT", primary = "PRIMARY", secondary = "SECONDARY" }
local ROLE_LINES = {
    background = "The glass of every cell and tissue, and what the surfaces, the outlines and the shadows are made from. Light or dark follows it.",
    text = "Everything that is read: content, labels, figures.",
    primary = "Icons, controls, selections, and the indicators that have no state to say.",
    secondary = "The supporting accent, beside the primary.",
}

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end
    local function row_height(): number return 44 * f() end
    local function label_width(): number return 92 * f() end
    -- The figures are right-aligned in a column of their own, and the
    -- sliders run from the labels to it: a longer travel is a finer control.
    local function value_width(): number return 56 * f() end
    local function slider_width(): number return math.max(0, t.width() - label_width() - value_width() - 24 * f()) end
    local function chip_height(): number return 28 * f() end

    local function label(text: string): any
        return g.text {
            width = label_width,
            text = text,
            color = theme.text,
            font = typography.technical,
            size = function() return m().font_secondary end,
            tracking = typography.label_tracking,
        }
    end
    -- The figure is a measurement: the machine's voice, tabular numerals.
    local function figure(text: () -> string, opacity: (() -> number)?): any
        return g.box {
            width = value_width,
            justify = "end",
            opacity = opacity,
            g.text {
                text = text,
                color = theme.text,
                font = typography.technical,
                size = function() return m().font_secondary end,
                tabular = true,
            },
        }
    end
    local function plain_row(children: { any }): any
        local out: { [any]: any } = { width = t.width, height = row_height, direction = "row", align = "center", gap = function() return 12 * f() end }
        for _, c in children do table.insert(out, c) end
        return g.box(out)
    end

    local function number_row(r: any): any
        local value, set = p.live(r.key, r.fallback)
        local span = r.to - r.from
        return plain_row {
            label(r.label),
            slider.new {
                width = slider_width,
                factor = f,
                value = function() return (value() - r.from) / span end,
                dimmed = function() return false end,
                on_move = function(fraction: number)
                    local raw = r.from + fraction * span
                    local snapped = math.round(raw / r.step) * r.step
                    set(math.round(snapped * 1000) / 1000)
                end,
            },
            figure(function() return math.round(value() * r.scale) .. r.unit end),
        }
    end

    -- Scale is a membrane property, not a global one, so this moves every
    -- membrane together, and the floating tissues with them; the
    -- per-membrane choice is the Structure page's.
    local function density(): string
        for _, membrane in config.get("membranes", {}) do
            if membrane.scale then return membrane.scale end
        end
        return "normal"
    end
    local function set_density(name: string)
        local membranes = config.copy_list(g.untracked(function() return config.get("membranes", {}) end))
        for _, membrane in membranes do membrane.scale = name end
        local floats = config.copy_list(g.untracked(function() return config.get("floating", {}) end))
        for _, tissue in floats do tissue.scale = name end
        config.set_many({ { "membranes", membranes }, { "floating", floats } })
    end

    -- The glass's strength is a step written into niri's configuration
    -- (services/looks.luau).
    local function glass(): boolean return config.get("cell.blur", true) == true end
    local blur_value, blur_set = p.live("cell.blurStrength", 5, function(step: any)
        require("services/looks").set_blur(step)
    end)
    local steps = #metrics_mod.blur_steps
    local function strength(): number return math.clamp(math.floor(blur_value() + 0.5), 1, steps) end

    local numbers = {}
    for _, r in ROWS do table.insert(numbers, number_row(r)) end
    -- Whether the cells are glass at all, and how strong the glass is: one
    -- row, because the strength of glass that is off means nothing.
    table.insert(numbers, plain_row {
        label("BLUR"),
        switch.new { on = glass, factor = f, on_toggle = function(value: boolean) config.set("cell.blur", value) end },
        slider.new {
            width = function() return slider_width() - 42 * f() - 12 * f() end,
            factor = f,
            dimmed = function() return not glass() end,
            value = function() return (strength() - 1) / (steps - 1) end,
            on_move = function(fraction: number) blur_set(1 + math.round(fraction * (steps - 1))) end,
        },
        figure(function() return tostring(strength()) end, function() return if glass() then 1 else 0.45 end),
    })
    -- The density step: three values, not a range.
    table.insert(numbers, plain_row {
        label("SCALE"),
        segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            options = function()
                return { { key = "compact", label = "Compact" }, { key = "normal", label = "Normal" }, { key = "comfortable", label = "Comfortable" } }
            end,
            current = density,
            on_choose = set_density,
        },
    })
    -- One set of durations, moved together: the shell has a tempo.
    table.insert(numbers, plain_row {
        label("TIMING"),
        segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            options = function()
                return { { key = "slow", label = "Slow" }, { key = "normal", label = "Normal" }, { key = "fast", label = "Fast" } }
            end,
            current = function()
                local speed = config.get("timing.speed", 1)
                return if speed > 1.15 then "slow" elseif speed < 0.85 then "fast" else "normal"
            end,
            on_choose = function(key: string)
                config.set("timing.speed", if key == "slow" then 1.4 elseif key == "fast" then 0.7 else 1)
            end,
        },
    })
    -- How things move, as well as how fast: organic, what travels arrives
    -- on a spring and goes a little past, threads sway behind what they
    -- hold; classic, every movement eases in and stops (core/timing.luau).
    table.insert(numbers, plain_row {
        label("MOTION"),
        segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            options = function()
                return { { key = "classic", label = "Classic" }, { key = "organic", label = "Organic" } }
            end,
            current = function() return if config.get("appearance.motion", "organic") == "classic" then "classic" else "organic" end,
            on_choose = function(key: string) config.set("appearance.motion", key) end,
        },
    })

    -- ---- The palettes ------------------------------------------------------------

    local function meta(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color or theme.text,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end
    local function dot(fill: () -> string, size: () -> number): any
        return g.capsule {
            width = size,
            height = size,
            radius = function() return size() / 2 end,
            fill = fill,
            rim_top = theme.line,
            rim_bottom = theme.line,
        }
    end

    -- A palette to choose: its four colours and its name.
    local function swatches(item: () -> any): any
        local hovered = g.signal(false)
        local function chosen(): boolean local c = palettes.current() return c ~= nil and c.file == item().file end
        local function edge(): string
            if chosen() then return theme.primary() end
            return if hovered.value then theme.text() else theme.line()
        end
        local dots: { [any]: any } = { direction = "row", gap = function() return -3 * f() end }
        for _, role in palettes.roles do
            table.insert(dots, dot(function()
                local c = (item().colours or {})[role]
                return if type(c) == "string" and c ~= "" then c else CLEAR
            end, function() return 12 * f() end))
        end
        return g.capsule {
            role = "button",
            height = chip_height,
            direction = "row",
            align = "center",
            gap = function() return 8 * f() end,
            padding_left = function() return 10 * f() end,
            padding_right = function() return 12 * f() end,
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = function() return if chosen() then colour.alpha(theme.primary(), 0.14) else CLEAR end,
            rim_top = edge,
            rim_bottom = edge,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function() palettes.choose(g.untracked(item).file) end,
            g.box(dots),
            meta(function() return string.upper(tostring(item().name or "")) end),
        }
    end
    local function swatch_width(item: any): number
        return 12 * f() * 4 - 3 * f() * 3 + 8 * f() + 22 * f()
            + g.text_width { text = string.upper(tostring(item.name or "")), font = typography.technical(), size = m().font_meta, tracking = typography.label_tracking }
    end

    -- ---- Your palette: the fields ------------------------------------------------

    local role = g.signal("primary")
    local typing = g.signal("") -- "name", a role, or ""
    local name_text = g.signal("")
    local name_node, name_field = field_mod.new {
        text = name_text,
        width = function() return p.inner() - 28 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        placeholder = "A name for the theme cell's list",
        taking = function() return typing.value == "name" end,
    }
    local function shown_name(): string return tostring(palettes.colours().name or "") end
    local function name_problem(): string
        local name = string.match(if typing.value == "name" then name_text.value else shown_name(), "^%s*(.-)%s*$") or ""
        if name == "" then return "A palette needs a name." end
        if palettes.name_taken(name) then return "Another palette already has this name." end
        return ""
    end

    local hex_text: { [string]: any } = {}
    local hex_field: { [string]: any } = {}
    local hex_node: { [string]: any } = {}
    for _, r in palettes.roles do
        hex_text[r] = g.signal("")
        hex_node[r], hex_field[r] = field_mod.new {
            text = hex_text[r],
            width = function() return 112 * f() - 28 * f() end,
            font = typography.technical,
            size = function() return m().font_meta end,
            taking = function() return typing.value == r end,
        }
        -- Each keystroke that makes a whole colour is the desktop changing.
        g.watch(function() return hex_text[r].value end, function(text: string)
            if g.untracked(function() return typing.value end) == r then palettes.set_role(r, text) end
        end)
    end

    local function release()
        local which = g.untracked(function() return typing.value end)
        if which == "name" then palettes.rename(g.untracked(function() return name_text.value end)) end
        typing.value = ""
    end
    local function start(which: string)
        release()
        typing.value = which
        if which == "name" then
            name_field.set(g.untracked(shown_name))
        else
            role.value = which
            hex_field[which].set(tostring(g.untracked(palettes.colours)[which] or ""))
        end
    end

    t.keyed(function(name: string, typed: string?, mods: { [string]: boolean }): boolean
        local which = g.untracked(function() return typing.value end)
        if which == "" then return false end
        if name == "Escape" then
            typing.value = ""
            return true
        end
        if name == "Return" or name == "KP_Enter" then
            release()
            return true
        end
        if which ~= "name" then
            -- A hex is seven characters at most.
            local text = g.untracked(function() return hex_text[which].value end)
            if typed and typed ~= "" and #text >= 7 and not (mods.ctrl) then return true end
            return hex_field[which].key(name, typed, mods)
        end
        return name_field.key(name, typed, mods)
    end)

    local deleting = g.signal(false)
    g.watch(function() local c = palettes.current() return if c then c.file else "" end, function()
        deleting.value = false
        typing.value = ""
    end)

    local function outlined(node: any, width: () -> number, which: string, wrong: () -> boolean): any
        local function edge(): string
            if wrong() then return theme.alert() end
            return if typing.value == which then theme.primary() else theme.line()
        end
        return g.capsule {
            role = "button",
            width = width,
            height = chip_height,
            padding_x = function() return 14 * f() end,
            direction = "row",
            align = "center",
            justify = "start",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = CLEAR,
            rim_top = edge,
            rim_bottom = edge,
            on_click = function() start(which) end,
            node,
        }
    end

    -- An error lives where it happened, under the field, in Spectral.
    local function problem(text: () -> string): any
        return g.box {
            present = function() return text() ~= "" end,
            direction = "row",
            align = "center",
            gap = function() return 6 * f() end,
            g.icon { width = function() return 12 * f() end, height = function() return 12 * f() end, icon = "error", color = theme.alert },
            g.text { text = text, color = theme.alert, font = typography.expressive, size = function() return m().font_secondary end },
        }
    end

    local function role_row(r: string): any
        local hovered = g.signal(false)
        local tool_hovered = g.signal(false)
        local function chosen(): boolean return role.value == r end
        local function hex(): string return tostring(palettes.colours()[r] or "") end
        local function hex_wrong(): boolean
            local text = if typing.value == r then hex_text[r].value else hex()
            return #string.gsub(text, "#", "") >= 6 and palettes.parse(text) == ""
        end
        return g.capsule {
            role = "button",
            width = p.inner,
            height = function() return 34 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 12 * f() end,
            padding_left = function() return 10 * f() end,
            padding_right = function() return 6 * f() end,
            radius = function() return metrics_mod.radius_for(34 * f(), m()) end,
            fill = function()
                if chosen() then return colour.alpha(theme.primary(), 0.10) end
                return if hovered.value then colour.alpha(theme.text(), 0.05) else CLEAR
            end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function() role.value = r end,
            dot(function() local h = hex() return if h ~= "" then h else CLEAR end, function() return 18 * f() end),
            meta(ROLE_LABELS[r]),
            g.box { grow = 1 },
            outlined(g.box {
                g.text {
                    present = function() return typing.value ~= r end,
                    text = hex,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tracking = typography.label_tracking,
                },
                g.box { present = function() return typing.value == r end, hex_node[r] },
            }, function() return 112 * f() end, r, hex_wrong),
            g.box {
                role = "button",
                name = "Pick from the screen",
                width = function() return 22 * f() end,
                height = function() return 22 * f() end,
                align = "center",
                justify = "center",
                on_hover = function(on: boolean) tool_hovered.value = on end,
                on_click = function()
                    role.value = r
                    palettes.pick(r)
                end,
                g.icon {
                    width = function() return 13 * f() end,
                    height = function() return 13 * f() end,
                    icon = "picker",
                    color = function() return if tool_hovered.value or palettes.picking() == r then theme.primary() else theme.text() end,
                },
            },
        }
    end

    -- One of hue, saturation and value: its name, the travel, the figure.
    -- A grey has no hue of its own; the one it last had is kept, so taking
    -- the saturation down and back up does not turn the colour red.
    local kept_hue = g.signal(0)
    g.effect(function()
        local h = palettes.hsv(role.value)
        if h >= 0 then g.untracked(function() kept_hue.value = h end) end
    end)
    local function hsv(): (number, number, number)
        local h, s, v = palettes.hsv(role.value)
        return (if h >= 0 then h else kept_hue.value), s, v
    end
    local function channel(name: string, which: number, scale: number, unit: string): any
        local function value(): number
            local h, s, v = hsv()
            return if which == 1 then h elseif which == 2 then s else v
        end
        return g.box {
            width = p.inner,
            height = chip_height,
            direction = "row",
            align = "center",
            gap = function() return 0 end,
            g.box { width = label_width, meta(name) },
            slider.new {
                width = function() return p.inner() - label_width() - value_width() - 12 * f() end,
                factor = f,
                dimmed = function() return false end,
                value = value,
                on_move = function(fraction: number)
                    local r = g.untracked(function() return role.value end)
                    -- g.untracked hands back one value: the three go through a table.
                    local packed = g.untracked(function() return table.pack(hsv()) end)
                    local h, s, v = packed[1], packed[2], packed[3]
                    if which == 1 then
                        h = math.min(fraction, 0.999)
                        kept_hue.value = h
                    elseif which == 2 then s = fraction
                    else v = fraction end
                    palettes.set_hsv(r, h, s, v)
                end,
            },
            g.box { width = function() return 12 * f() end },
            figure(function() return math.round(value() * scale) .. unit end),
        }
    end

    local roles = {}
    for _, r in palettes.roles do table.insert(roles, role_row(r)) end

    local palette_well = section("PALETTE", nil, {
        p.flow {
            items = function()
                local out = {}
                for _, palette in theme.palettes() do table.insert(out, { kind = "palette", palette = palette }) end
                table.insert(out, { kind = "new" })
                return out
            end,
            key = function(item: any) return if item.kind == "new" then "new" else item.palette.file end,
            width_of = function(item: any): number
                if item.kind == "new" then
                    return 11 * f() + 9 * f() + 7 * f() + 15 * f()
                        + g.text_width { text = "NEW", font = typography.technical(), size = m().font_meta, tracking = typography.label_tracking }
                end
                return swatch_width(item.palette)
            end,
            chip = function(item: () -> any): any
                if g.untracked(item).kind == "new" then return p.offer("NEW", palettes.create) end
                return swatches(function() return item().palette end)
            end,
        },
        line(function()
            if theme.source() == "matugen" then
                return "The colours on screen come from the wallpaper. A palette chosen here sets them by hand instead; NEW keeps the wallpaper's as a palette of your own, to change."
            end
            if palettes.editable() then
                return "Yours, kept in ~/.config/bioma/palettes/" .. palettes.current().file .. ".json: a file you can copy to somebody else."
            end
            return "Bioma's own palettes are kept as they ship. NEW starts one of your own from the colours on screen now."
        end),
    })

    local yours = section("YOUR PALETTE", choice_mod.new {
        label = function() return if deleting.value then "DELETE?" else "DELETE" end,
        kind = function() return if deleting.value then "alert" else "plain" end,
        metrics = m,
        on_click = function()
            if not g.untracked(function() return deleting.value end) then
                deleting.value = true
                return
            end
            deleting.value = false
            palettes.remove()
        end,
    }, {
        outlined(g.box {
            g.text {
                present = function() return typing.value ~= "name" end,
                text = function() local n = shown_name() return if n ~= "" then n else "A name for the theme cell's list" end,
                color = function() return if shown_name() ~= "" then theme.text() else theme.text_faint() end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
            },
            g.box { present = function() return typing.value == "name" end, name_node },
        }, p.inner, "name", function() return name_problem() ~= "" end),
        problem(name_problem),
        g.box { direction = "column", gap = function() return 2 * f() end, table.unpack(roles) },
        channel("HUE", 1, 360, "°"),
        channel("SATURATION", 2, 100, "%"),
        channel("VALUE", 3, 100, "%"),
        line(function() return ROLE_LINES[role.value] end, theme.text_muted),
    }, palettes.editable)

    local column: { any } = {}
    table.insert(column, g.box { direction = "column", table.unpack(numbers) })
    table.insert(column, palette_well)
    table.insert(column, yours)
    return p.column(column)
end

return M
