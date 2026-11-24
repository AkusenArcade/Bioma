--!strict
-- Settings → Hyprland or Umbriel: the page that stands where NIRI does when
-- another compositor runs (cells/settings_niri.luau is niri's), with what
-- that compositor can be told from here (services/compositor_settings.luau):
-- the gaps, the border, the focus following the pointer, Umbriel's hot
-- corners, num lock, the mouse and the touchpad, and Hyprland's window
-- opacity.
--
-- One well per setting, as on NIRI, and a line in Spectral saying what the
-- current choice does. Every choice is written into one file of Bioma's,
-- which wins over the same setting in the compositor's own files; a
-- setting never touched here is left to them.
local g = require("@genoma")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local page = require("components/page")
local slider = require("components/slider")
local switch = require("components/switch")
local choice_mod = require("components/choice")
local settings = require("services/compositor_settings")

local M = {}

local CORNER_LABELS = { top_left = "TOP LEFT", top_right = "TOP RIGHT", bottom_left = "BOTTOM LEFT", bottom_right = "BOTTOM RIGHT" }

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end
    local function busy(): boolean return settings.busy() end
    local function meta(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color or theme.text,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end
    -- Where the choice is: Bioma's file once one is made here, the
    -- compositor's own files until then.
    local function written(...: string): string
        for _, id in { ... } do
            if settings.chosen(id) then return "Written in " .. settings.file .. "." end
        end
        return "As " .. settings.title .. "'s own files say; a change here goes in " .. settings.file .. "."
    end

    -- A slider with its figure (settings_niri.luau's): written once the
    -- hand rests.
    local function amount(id: string, from: number, to: number, step: number, unit: string, scale: number?): any
        local k = scale or 1
        local held = g.signal(nil :: number?)
        local timer: any = nil
        local function shown(): number?
            local h = held.value
            if h ~= nil then return h end
            local v = settings.value(id)
            return if type(v) == "number" then v * k else nil
        end
        return g.box {
            width = p.inner,
            height = function() return 28 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 12 * f() end,
            slider.new {
                width = function() return p.inner() - 64 * f() - 12 * f() end,
                factor = f,
                dimmed = busy,
                value = function() local v = shown() return if v then (v - from) / (to - from) else 0 end,
                on_move = function(fraction: number)
                    local v = math.round((from + fraction * (to - from)) / step) * step
                    held.value = v
                    if timer then timer:stop() end
                    timer = g.after(timing.seconds.debounce, function()
                        timer = nil
                        settings.set(id, v / k)
                        g.after(1.2, function()
                            if timer == nil and g.untracked(function() return held.value end) == v then held.value = nil end
                        end)
                    end)
                end,
            },
            g.box {
                width = function() return 64 * f() end,
                justify = "end",
                g.text {
                    text = function()
                        local v = shown()
                        if v == nil then return "—" end
                        local r = math.round(v * 10) / 10
                        if r == 0 then r = 0 end -- not -0
                        return tostring(r) .. unit
                    end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tabular = true,
                },
            },
        }
    end
    local function on(id: string): boolean return settings.value(id) == true end
    local function toggle(id: string): any
        return switch.new {
            on = function() return on(id) end,
            factor = f,
            dimmed = busy,
            on_toggle = function(value: boolean) settings.set(id, value) end,
        }
    end
    local function labelled(label: string, body: any): any
        return g.box {
            direction = "column",
            gap = function() return 6 * f() end,
            g.box { width = p.inner, direction = "row", meta(label, theme.text_muted) },
            body,
        }
    end

    local error_line = g.box {
        present = function() return settings.error() ~= "" end,
        line(function() return settings.error() end, theme.alert),
    }

    local gaps = section("GAPS", nil, {
        amount("gaps", 0, 48, 1, " px"),
        line(function()
            local n = settings.value("gaps") or 0
            return (if n == 0 then "Windows touch each other and the edges of the screen. "
                else n .. " px between windows, and between them and the edges of the screen. ") .. written("gaps")
        end),
    })

    local border = section("BORDER", nil, {
        amount("border", 0, 8, 1, " px"),
        line(function()
            local n = settings.value("border") or 0
            return (if n == 0 then "No border marks the focused window. " else n .. " px around every window, lit on the focused one. ") .. written("border")
        end),
    })

    local follows = section("FOCUS FOLLOWS THE POINTER", toggle("follows"), {
        line(function()
            return (if on("follows")
                then "The window under the pointer takes the focus as soon as the pointer is on it, without a click. "
                else "A window takes the focus when it is clicked, or reached from the keyboard. ") .. written("follows")
        end),
    })

    -- Umbriel's four corners, standing where they are.
    local function corner_chip(corner: string): any
        local id = "corner_" .. corner
        return choice_mod.new {
            id = "corner-" .. corner,
            label = CORNER_LABELS[corner],
            kind = function() return if on(id) then "primary" else "plain" end,
            metrics = m,
            dimmed = busy,
            on_click = function() settings.set(id, not g.untracked(function() return on(id) end)) end,
        }
    end
    local function corner_column(top: string, bottom: string, align: string): any
        return g.box { direction = "column", align = align, gap = function() return 6 * f() end, corner_chip(top), corner_chip(bottom) }
    end
    local hot_corners = section("HOT CORNERS", nil, {
        g.box {
            width = p.inner,
            direction = "row",
            justify = "between",
            corner_column("top_left", "bottom_left", "start"),
            corner_column("top_right", "bottom_right", "end"),
        },
        line(function()
            local names = {}
            for _, c in settings.corners do
                if on("corner_" .. c) then table.insert(names, string.lower(CORNER_LABELS[c])) end
            end
            if #names == 0 then return "No corner opens the overview; its key still does. " .. written("corner_top_left", "corner_top_right", "corner_bottom_left", "corner_bottom_right") end
            local list = if #names == 1 then names[1] else table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
            return "Pushing the pointer into the " .. list .. " corner of a screen opens the overview. " .. written("corner_top_left", "corner_top_right", "corner_bottom_left", "corner_bottom_right")
        end),
    }, function() return settings.supports("corner_top_left") end)

    local numlock = section("NUM LOCK AT START", toggle("numlock"), {
        line(function()
            return (if on("numlock")
                then "The keypad types figures from the moment the session starts. "
                else "The keypad moves the cursor until num lock is pressed. ") .. written("numlock")
        end),
    })

    local mouse = section("MOUSE", nil, {
        labelled("SPEED", amount("mouse_speed", -1, 1, 0.1, "")),
        p.row("FLAT ACCELERATION", toggle("mouse_flat")),
        p.row("NATURAL SCROLLING", toggle("mouse_natural")),
        p.row("LEFT-HANDED", toggle("mouse_left")),
        line(function()
            local speed = settings.value("mouse_speed") or 0
            return (if speed == 0 then "At libinput's own speed" elseif speed > 0 then "Faster than libinput's own speed" else "Slower than libinput's own speed")
                .. (if on("mouse_flat") then ", the pointer moving as far as the hand does at any pace. " else ", the pointer going further when the hand moves fast. ")
                .. (if on("mouse_natural") then "Scrolling is reversed: the content moves with the hand. " else "Scrolling down goes down the page. ")
                .. (if on("mouse_left") then "The buttons are swapped for the left hand. " else "")
                .. written("mouse_speed", "mouse_flat", "mouse_natural", "mouse_left")
        end),
    })

    local touchpad = section("TOUCHPAD", nil, {
        p.row("TAP TO CLICK", toggle("tap")),
        p.row("NATURAL SCROLLING", toggle("touchpad_natural")),
        p.row("OFF WHILE TYPING", toggle("typing")),
        line(function()
            return (if on("tap") then "A tap clicks. " else "Only a press clicks. ")
                .. (if on("touchpad_natural") then "Scrolling is reversed: the content moves with the fingers. " else "Scrolling down goes down the page. ")
                .. (if on("typing") then "It goes quiet while the keyboard is in use. " else "")
                .. written("tap", "touchpad_natural", "typing")
        end),
    }, settings.has_touchpad)

    local opacity = section("WINDOW OPACITY", nil, {
        labelled("IN FOCUS", amount("opacity_focused", 10, 100, 5, "%", 100)),
        labelled("OUT OF FOCUS", amount("opacity_unfocused", 10, 100, 5, "%", 100)),
        line(function() return "Every window's opacity, with and without the focus. " .. written("opacity_focused", "opacity_unfocused") end),
    }, function() return settings.supports("opacity_focused") end)

    settings.look()
    return p.column { error_line, gaps, border, follows, hot_corners, numlock, mouse, touchpad, opacity }
end

return M
