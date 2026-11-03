--!strict
-- The on-screen display, one per monitor (structure/OsdSurface.qml at
-- 8ed8892): the volume, the brightness, the keyboard's layout or
-- performance mode, said for a moment after it changes where no cell says
-- it already (services/osd.luau).
--
-- It is the audio cell's summoned form (dial, figure, slider in one
-- capsule) because it says the same thing, and the brightness wears the
-- same capsule with the sun in its dial. The layout has no travel, so no
-- dial: the keyboard cell's face, glyph and code, with the layout's full
-- name beside it; performance mode the same with its own glyph. It grows
-- from its own centre, low in the middle of the screen, and takes no input:
-- it answers a key, it is not a control.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local performance = require("core/performance")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local gauge = require("components/gauge")
local slider = require("components/slider")
local osd = require("services/osd")

local M = {}

function M.node(output: string, size: { width: number, height: number }): any
    local audio = require("services/audio")
    local brightness = require("services/brightness")
    local keyboard = require("services/keyboard")
    local m = metrics_mod.step("normal")
    local f = m.factor

    local function here(): boolean return osd.kind() ~= "" and osd.output() == output end
    -- What it says, kept while it leaves: the kind is cleared the moment the
    -- display is done, and the capsule shrinks wearing what it wore.
    local kind = g.signal("volume")
    g.watch(function() return { here(), osd.kind() } end, function(now: { any })
        if now[1] then kind.value = now[2] end
    end)

    local capsule_height = 88 * f
    local dial_size, figure_width, slider_width = 56 * f, 62 * f, 168 * f
    local gap, side, glyph_size = 20 * f, 23 * f, 28 * f

    local function plain(): boolean return kind.value == "layout" or kind.value == "performance" end
    local function is_brightness(): boolean return kind.value == "brightness" end
    local function fraction(): number
        return if is_brightness() then brightness.brightness() else math.min(1, audio.volume())
    end
    local function overflow(): number return if is_brightness() then 0 else math.max(0, audio.volume() - 1) end
    local function silenced(): boolean return kind.value == "volume" and audio.muted() end
    local function percent(): number
        return if is_brightness() then math.round(brightness.brightness() * 100) else audio.volume_percent()
    end

    local function code(): string
        if kind.value == "performance" then return if performance.active() then "ON" else "OFF" end
        return keyboard.current_code()
    end
    local function name(): string
        if kind.value == "performance" then
            local reason = performance.reason()
            return "Performance mode" .. (if performance.active() and reason ~= "by hand" then ", " .. reason else "")
        end
        return keyboard.current()
    end
    local function code_size(): number return m.font_value end
    local function name_size(): number return m.font_label end
    local function full_width(): number
        if plain() then
            local code_w = g.text_width { text = code(), font = typography.technical(), size = code_size(),
                weight = typography.weight_value, tracking = typography.label_tracking }
            local name_w = g.text_width { text = name(), font = typography.expressive(), size = name_size(),
                weight = typography.weight_secondary }
            return side * 2 + glyph_size + gap + code_w + gap + name_w
        end
        return side * 2 + dial_size + figure_width + slider_width + gap * 2
    end

    -- Low in the middle: under the eye's line, clear of any membrane.
    local cx = size.width / 2
    local cy = size.height - 3 * m.cell_height - capsule_height / 2
    local function width(): number return if here() then full_width() else 0 end
    local function height(): number return if here() then capsule_height else 0 end
    -- A small capsule: it arrives on a spring and swells a little past its
    -- size, about its centre (core/timing.luau, motion); it closes plainly.
    local function grow(): string return if here() then timing.motion("land", "open") else "close" end

    local dial_face = g.box {
        present = function() return not plain() end,
        direction = "row",
        align = "center",
        gap = gap,
        g.box {
            width = dial_size,
            height = dial_size,
            align = "center",
            justify = "center",
            gauge.new { size = function() return dial_size end, track_units = 1.5, node_units = 4,
                fraction = fraction, overflow = overflow, muted = silenced },
            g.box {
                overlay = true,
                attach = "corner",
                width = dial_size,
                height = dial_size,
                align = "center",
                justify = "center",
                present = is_brightness,
                g.icon {
                    width = 22 * f, height = 22 * f, icon = "brightness",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                },
            },
        },
        g.box {
            width = figure_width,
            g.text {
                text = function() return percent() .. "%" end,
                color = theme.text,
                font = typography.technical,
                size = m.font_value,
                weight = typography.weight_value,
                tabular = true,
                opacity = function() return if silenced() then 0.45 else 1 end,
            },
        },
        slider.new {
            width = function() return slider_width end,
            factor = function() return f end,
            value = fraction,
            dimmed = silenced,
            on_move = function() end,
        },
    }

    local plain_face = g.box {
        present = plain,
        direction = "row",
        align = "center",
        gap = gap,
        g.icon {
            width = glyph_size, height = glyph_size,
            icon = function() return if kind.value == "performance" then "performance" else "keyboard" end,
            -- Muted once the mode is off: an icon that is inactive.
            gradient_top = function()
                if kind.value == "performance" and not performance.active() then return theme.text_muted() end
                return theme.gradient_top(theme.primary())
            end,
            gradient_bottom = function()
                if kind.value == "performance" and not performance.active() then return theme.text_muted() end
                return theme.gradient_bottom(theme.primary())
            end,
        },
        g.text {
            text = code, color = theme.text, font = typography.technical, size = code_size,
            weight = typography.weight_value,
            -- In em, as Genoma's text takes it.
            tracking = typography.label_tracking,
        },
        g.text {
            text = name, color = theme.text_muted, font = typography.expressive, size = name_size,
            weight = typography.weight_secondary,
        },
    }

    return g.box {
        width = size.width,
        height = size.height,
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() return cx - width() / 2 end,
            offset_y = function() return cy - height() / 2 end,
            width = width,
            height = height,
            radius = function() return metrics_mod.radius_for(capsule_height, m) end,
            opacity = function() return if here() then 1 else 0 end,
            transition = { offset_x = grow, offset_y = grow, width = grow, height = grow, opacity = "depart" },
            blur = performance.blurred,
            fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            clip = true,
            padding_x = side,
            direction = "row",
            align = "center",
            justify = "start",
            -- The content arrives once the capsule is grown, and goes first.
            g.box {
                opacity = function() return if here() then 1 else 0 end,
                transition = { opacity = function() return if here() then "content_enter" else "content_leave" end },
                dial_face,
                plain_face,
            },
        },
    }
end

return M
