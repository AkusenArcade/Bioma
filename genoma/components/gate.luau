--!strict
-- The threshold (components/Gate.qml at 2cafc17): what stands between a
-- person and the desktop, on one screen. The lock screen and the greeter
-- are both this; what differs is the surface that holds it and who checks
-- the password, PAM for the lock, greetd for the greeter. So both wear the
-- shell's own appearance, from one place (Akusen, 2026-09-27).
--
-- Every screen gets the wallpaper, blurred and veiled: nothing behind it can
-- be read. Only the screen the keyboard is on holds anything else: the time
-- and the clock's face, the date, who this is and the field. Two fields
-- would be two places to type into and one of them deaf.
--
-- Nothing moves on its own once it is there. It arrives from the wallpaper,
-- sharp, blurring into the veiled picture, and the composition follows, one
-- element after the next. Between the two the only change is the minute.
--
-- The lock arrives from a photograph of the desktop instead (`capture`),
-- which dissolves into the veiled picture, and leaves back to it: the
-- composition goes quickly, then the picture clears to the desktop it came
-- from, and the session unlocks onto that.
--
-- The greeter leaves differently (`welcomes`): the person stays, the
-- portrait and the name, while the rest goes; "Welcome to" and the logotype
-- open out from under the name, and then the whole screen fades to black.
-- What follows is the session's compositor starting on a black screen, so
-- the handover has no seam.
--
-- `t.gate` is the state it reads and writes:
--   active()                 the output that holds the field
--   password                 a g.signal holding what was typed
--   checking(), failed(), reason(), leaving()
--   submit()                 the field was accepted
--   failed_reset()           something new was typed: the error goes
--   full_name(), avatar()    who this is ("" for no picture)
--   density(), twenty_four()
--   entered()                optional: once a welcome has gone dark, called
--                            by every screen, the owner acting on the first
--   set_active(output)       optional: a press brings the field here (the lock)
--   capture(output)          optional: a photograph of the screen to start
--                            from, and to leave back to (the lock)
local g = require("@genoma")
local clock = require("@genoma/clock")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local dial = require("components/dial")
local field_mod = require("components/field")
local portrait = require("components/portrait")
local wallpaper = require("structure/wallpaper")

local M = {}

local DAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }
local MONTHS = { "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER",
    "OCTOBER", "NOVEMBER", "DECEMBER" }

-- What the keypad's keys mean with num lock off, read as the figures
-- printed on them. niri turns num lock on only when it starts, and every
-- reload of the keymap turns it off again, so a password with figures in
-- it would otherwise depend on what happened to the keymap since login.
local KEYPAD = {
    KP_Insert = "0", KP_End = "1", KP_Down = "2", KP_Next = "3", KP_Page_Down = "3", KP_Left = "4",
    KP_Begin = "5", KP_Right = "6", KP_Home = "7", KP_Up = "8", KP_Prior = "9", KP_Page_Up = "9",
    KP_Delete = ".",
}

-- The density the Appearance page sets on every membrane at once.
function M.density(): string
    for _, membrane in config.get("membranes", {}) do
        if type(membrane) == "table" and membrane.scale then return membrane.scale end
    end
    return "normal"
end
-- The clock says the time the way the clock cell does, wherever it is.
function M.twenty_four(): boolean
    for _, list in { config.get("membranes", {}), config.get("floating", {}) } do
        for _, block in list do
            for _, group in (block.tissues or { block }) do
                for _, cell in (group.cells or {}) do
                    if cell.type == "clock" and type(cell.options) == "table" and cell.options.format then
                        return cell.options.format == "24h"
                    end
                end
            end
        end
    end
    return true
end

-- `t`: gate (above), output, size { width, height }, welcomes (the
-- greeter's leaving). Returns the node and a handle: key(name, text, mods).
function M.new(t: { [string]: any }): (any, any)
    local gate = t.gate
    local output = t.output
    local size = t.size
    local function m(): any return metrics_mod.step(gate.density()) end
    local function f(): number return m().factor end
    local function active(): boolean return gate.active() == output end
    local function leaving(): boolean return gate.leaving() end
    local function welcoming(): boolean return t.welcomes == true and leaving() end

    -- Here from the first turn on: the picture dissolves and the
    -- composition follows, each by its own timing. From a photograph, only
    -- once it is on screen, or the dissolve would begin under a frame still
    -- waiting for it; never later than the opening time, in case it never
    -- comes.
    local here = g.signal(false)
    local photograph = if gate.capture then gate.capture(output) else ""
    local function arrive() here.value = true end
    if photograph == "" then
        g.after(0, arrive)
    else
        g.after(timing.seconds.open, arrive)
    end
    local function dissolved(): boolean
        if leaving() and not t.welcomes then return false end
        return here.value
    end
    -- Leaving, the picture clears once the composition has gone.
    local function clearing(): string return if leaving() then "gate_clear" else "gate_dissolve" end

    -- ---- Behind ------------------------------------------------------------------

    local behind = g.box {
        overlay = true,
        attach = "corner",
        width = size.width,
        height = size.height,
        g.box { overlay = true, attach = "corner", wallpaper.node(output, size, false) },
        g.box {
            overlay = true,
            attach = "corner",
            opacity = function() return if dissolved() then 1 else 0.004 end,
            transition = { opacity = clearing },
            wallpaper.node(output, size, true),
        },
        -- The desktop as it was, over the picture until the dissolve takes
        -- it, and back over it before the session opens.
        g.image {
            overlay = true,
            attach = "corner",
            present = photograph ~= "",
            src = photograph,
            width = size.width,
            height = size.height,
            fit = "fill",
            opacity = function() return if dissolved() then 0 else 1 end,
            transition = { opacity = clearing },
            on_ready = arrive,
        },
        -- The veil: the picture is a place, not something to look at, and
        -- the text on it has to hold on any image.
        g.capsule {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            radius = 0,
            fill = function() return colour.alpha(theme.background(), 0.45) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            opacity = function() return if dissolved() then 1 else 0 end,
            transition = { opacity = clearing },
        },
    }

    -- ---- In front, where the keyboard is -------------------------------------------

    -- One element of the composition: it comes in `index` after the first,
    -- from 4 below; it goes when the gate leaves, unless it is the person
    -- and the gate welcomes.
    local function element(index: number, kept: boolean, child: any): any
        return g.box {
            opacity = function() return if here.value then 1 else 0 end,
            offset_y = function() return if here.value then 0 else 4 * f() end,
            transition = { opacity = "gate_" .. index, offset_y = "gate_" .. index },
            g.box {
                opacity = function()
                    if not leaving() then return 1 end
                    return if kept and t.welcomes then 1 else 0
                end,
                transition = { opacity = if t.welcomes then "gate_leave" else "gate_close" },
                child,
            },
        }
    end
    local function spacer(h: () -> number): any return g.box { height = h } end

    local function time(): string
        local h = clock.hour
        local hours = if gate.twenty_four() then string.format("%02d", h) else tostring(if h % 12 == 0 then 12 else h % 12)
        return hours .. ":" .. string.format("%02d", clock.minute)
    end
    local function date(): string
        local _ = clock.hour
        local d = os.date("*t") :: any
        return DAYS[d.wday] .. " " .. d.day .. " " .. MONTHS[d.month]
    end
    local function time_size(): number return math.round(112 * f()) end

    -- The field, its text the password, drawn as dots.
    local field_width = function() return 300 * f() end
    local field_height = function() return 44 * f() end
    local field_node, field = field_mod.new {
        text = gate.password,
        width = function()
            local dots = string.rep("•", utf8.len(gate.password.value) or 0)
            local w = g.text_width { text = dots, font = typography.expressive(), size = math.round(16 * f()) } + 2
            return math.min(field_width() - 40 * f(), w)
        end,
        font = typography.expressive,
        size = function() return math.round(16 * f()) end,
        taking = function() return active() and not gate.checking() and not leaving() end,
        secret = true,
        on_submit = function() gate.submit() end,
        -- Escape empties the field: the one way back from a password typed
        -- wrong, other than typing over it.
        on_release = function()
            field.set("")
            gate.failed_reset()
        end,
    }
    -- A wrong password leaves what was typed where it was, selected: the
    -- next key replaces it.
    g.watch(gate.failed, function(on: boolean) if on then field.select_all() end end)

    local function rim(): string
        if gate.failed() then return theme.alert() end
        return if active() then theme.primary() else theme.line()
    end

    local field_shape = g.capsule {
        width = function() return if here.value then field_width() else field_height() end,
        height = field_height,
        radius = function() return metrics_mod.radius_for(field_height(), m()) end,
        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), config.get("cell.opacity", 0.72)) end,
        rim_top = rim,
        rim_bottom = rim,
        stroke = 1.5,
        transition = { width = "gate_5", rim_top = "colour", rim_bottom = "colour" },
        -- Waiting on the check, the field says so by stepping back rather
        -- than by a spinner: nothing here moves without a value behind it.
        opacity = function() return if gate.checking() then 0.6 else 1 end,
        align = "center",
        justify = "center",
        g.box {
            opacity = function() return if here.value then 1 else 0 end,
            transition = { opacity = "gate_inside" },
            align = "center",
            justify = "center",
            g.text {
                present = function() return gate.password.value == "" end,
                text = "Password",
                color = theme.text_muted,
                font = typography.expressive,
                size = function() return m().font_secondary end,
            },
            g.box { present = function() return gate.password.value ~= "" end, field_node },
        },
    }

    -- The welcome, where the field was and from the name down: each line
    -- comes in from just above, as if let out of the name.
    local function greeted(index: number, node: { [any]: any }): any
        node.opacity = function() return if welcoming() then 1 else 0 end
        node.offset_y = function() return if welcoming() then 0 else -4 * f() end
        node.transition = { opacity = "greet_" .. index, offset_y = "greet_" .. index }
        return node
    end
    local function unit(): number return math.round(112 * f()) end
    local welcome = g.box {
        overlay = true,
        attach = "corner",
        present = welcoming,
        width = field_width,
        direction = "column",
        align = "center",
        g.text(greeted(1, {
            text = "Welcome to", color = theme.text_muted, font = typography.expressive,
            size = function() return math.round(18 * f()) end,
        })),
        spacer(function() return 20 * f() end),
        g.icon(greeted(2, {
            width = unit, height = unit, icon = "mark",
            gradient_top = function() return theme.gradient_top(theme.primary()) end,
            gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
        })),
        spacer(function() return 10 * f() end),
        g.text(greeted(3, {
            text = "BIOMA", color = theme.text, font = typography.technical,
            size = function() return math.round(0.18 * unit() / 0.72) end, tracking = 0.02,
        })),
        spacer(function() return 4 * f() end),
        g.text(greeted(4, {
            text = "A Living Shell", color = theme.text_muted, font = typography.expressive,
            size = function() return math.round(0.094 * unit() / 0.66) end,
        })),
    }

    local badge_portrait = function() return 76 * f() end
    local badge_size = function() return badge_portrait() * (metrics_mod.cell_height / 30) end

    local composition = g.box {
        present = active,
        offset_y = function() return -size.height * 0.06 end,
        direction = "column",
        align = "center",
        -- The time is the clock's, and the clock is a human thing: the
        -- expressive voice, tabular figures so the minute does not move
        -- the line, and beside it the clock cell's own face.
        element(1, false, g.box {
            direction = "row",
            align = "center",
            gap = function() return math.round(time_size() * 0.22) end,
            g.text { text = time, color = theme.text, font = typography.expressive, size = time_size,
                weight = typography.weight_value, tabular = true },
            dial.new {
                size = function() return math.round(time_size() * 0.62) end,
                fraction = function() return (clock.minute * 60 + clock.second) / 3600 end,
                orbit = function() return clock.second / 60 end,
            },
        }),
        element(2, false, g.text {
            text = date, color = theme.text_muted, font = typography.technical,
            size = function() return m().font_secondary end, weight = typography.weight_label,
            tracking = typography.label_tracking,
        }),
        spacer(function() return 72 * f() end),
        -- The avatar as the System cell wears it at rest, the portrait in a
        -- round cell of its own, glass and lit rim, at the lock's scale.
        element(3, true, g.capsule {
            width = badge_size,
            height = badge_size,
            radius = function() return metrics_mod.radius_for(badge_size(), m()) end,
            fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            align = "center",
            justify = "center",
            portrait.new { size = badge_portrait, source = gate.avatar },
        }),
        spacer(function() return 14 * f() end),
        element(4, true, g.text {
            text = gate.full_name, color = theme.text, font = typography.expressive,
            size = function() return math.round(20 * f()) end,
        }),
        spacer(function() return m().gap end),
        g.box {
            align = "center",
            justify = "center",
            element(5, false, field_shape),
            welcome,
        },
        spacer(function() return 10 * f() end),
        -- Errors live where they happened, in a sentence.
        g.text {
            text = gate.reason, color = theme.alert, font = typography.expressive,
            size = function() return m().font_secondary end,
            opacity = function() return if gate.failed() and not leaving() then 1 else 0 end,
            transition = { opacity = "transition" },
        },
    }

    -- The dark the welcome ends in: plain black, the colour of the screen
    -- between the greeter's compositor and the session's.
    local dark = g.capsule {
        overlay = true,
        attach = "corner",
        width = size.width,
        height = size.height,
        radius = 0,
        fill = "#000000",
        rim_top = "#00000000",
        rim_bottom = "#00000000",
        opacity = function() return if welcoming() then 1 else 0 end,
        transition = { opacity = "gate_dark" },
    }
    if t.welcomes then
        g.watch(welcoming, function(on: boolean)
            if not on then return end
            local s = timing.seconds
            g.after(s.open + s.welcome_open + s.welcome_stagger * 3 + s.welcome + s.welcome_fade + 0.05, function()
                if gate.entered then gate.entered() end
            end)
        end)
    end

    local node = g.box {
        width = size.width,
        height = size.height,
        on_press = function()
            if gate.set_active and not active() then gate.set_active(output) end
        end,
        behind,
        g.box {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            align = "center",
            justify = "center",
            composition,
        },
        dark,
    }

    local handle = {}
    function handle.key(name: string, typed: string?, mods: { [string]: boolean }?): boolean
        if not active() or gate.checking() or leaving() then return false end
        local figure = KEYPAD[name]
        if figure then
            return field.key(name, figure, mods)
        end
        local taken = field.key(name, typed, mods)
        if taken and gate.failed() and name ~= "Return" and name ~= "KP_Enter" then gate.failed_reset() end
        return taken
    end
    return node, handle
end

return M
