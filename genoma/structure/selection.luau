--!strict
-- Bioma's own selection rectangle, one surface per monitor
-- (structure/SelectionSurface.qml at 11bb81e). PRD §9.6 asks for it rather
-- than slurp: the selector covers the whole desktop, the largest surface
-- Bioma ever draws, and another program's rectangle there is another shell
-- for as long as it is up. Only the selection is drawn here; grim and the
-- recorder still take the picture.
--
-- It is there only while the capture service asks for a region, and holds
-- the keyboard for exactly that long, because Escape has to mean cancel.
-- The surface sits over every exclusive zone (`above_zones`): inside what
-- the other surfaces leave, its origin would not be the output's, and the
-- region handed to grim would be that much off.
local g = require("@genoma")
local theme = require("core/theme")
local config = require("core/config")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local typography = require("core/typography")
local paths = require("core/paths")
local capture = require("services/capture")
local monitors = require("services/monitors")

local M = {}

local VEIL = paths.root .. "/genoma/components/veil.wgsl"

-- Linux's button codes.
local LEFT, RIGHT = 272, 273

-- A rectangle too small to be meant is a click, and a click is how someone
-- changes their mind: it cancels rather than capturing four pixels.
local MINIMUM = 6

function M.node(output: string, size: { width: number, height: number }): any
    local m = metrics_mod.step("normal")
    local anchor = g.signal({ x = 0, y = 0 })
    local pointer = g.signal({ x = 0, y = 0 })
    local drawing = g.signal(false)

    -- Each selection starts from nothing.
    g.watch(capture.selecting, function()
        drawing.value = false
    end)

    local function sel(): (number, number, number, number)
        local a, p = anchor.value, pointer.value
        return math.min(a.x, p.x), math.min(a.y, p.y), math.abs(p.x - a.x), math.abs(p.y - a.y)
    end
    local function sel_x(): number local x = sel() return x end
    local function sel_y(): number local _, y = sel() return y end
    local function sel_w(): number local _, _, w = sel() return w end
    local function sel_h(): number local _, _, _, h = sel() return h end

    -- One radius for the hole and the border round it.
    local function corner(): number
        return math.min(m.radius_well, math.min(sel_w(), sel_h()) / 2)
    end

    -- The region in the compositor's coordinates, where this surface's
    -- origin sits on the layout: the string slurp printed.
    local function region(): string
        local o = g.untracked(function() return monitors.output_of(output) end)
        local ox, oy = if o then o.x else 0, if o then o.y else 0
        local a, p = g.untracked(function() return anchor.value end), g.untracked(function() return pointer.value end)
        local x, y = math.min(a.x, p.x), math.min(a.y, p.y)
        local w, h = math.abs(p.x - a.x), math.abs(p.y - a.y)
        return string.format("%d,%d %dx%d", math.floor(ox + x + 0.5), math.floor(oy + y + 0.5),
            math.floor(w + 0.5), math.floor(h + 0.5))
    end

    local veil_values = g.computed(function(): { number }
        local c = colour.parse(colour.alpha(theme.background(), 0.45))
        local x, y, w, h = sel()
        if not drawing.value then w, h = 0, 0 end
        return { x, y, w, h, corner(), c.r, c.g, c.b, c.a }
    end)

    local readout_pad = 8 * m.factor
    local readout_height = 26 * m.factor
    local function figure(): string
        return string.format("%d × %d", math.floor(sel_w() + 0.5), math.floor(sel_h() + 0.5))
    end
    local function readout_width(): number
        return g.text_width {
            text = figure(), font = typography.technical(), size = m.font_meta,
            weight = typography.weight_secondary, tabular = true,
        } + readout_pad * 2
    end
    -- Inside the rectangle when there is room, under it when there is not:
    -- it never covers the edge being drawn.
    local function below(): boolean return sel_h() < 48 * m.factor end

    return g.box {
        width = size.width,
        height = size.height,
        g.box {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            present = capture.selecting,
            catch = capture.selecting,
            cursor = "crosshair",
            on_press = function(button: number, x: number, y: number)
                if button == RIGHT then
                    capture.cancel_selection()
                    return
                end
                if button ~= LEFT then return end
                anchor.value = { x = x, y = y }
                pointer.value = { x = x, y = y }
                drawing.value = true
            end,
            on_drag = function(x: number, y: number)
                if not drawing.value then return end
                pointer.value = { x = math.clamp(x, 0, size.width), y = math.clamp(y, 0, size.height) }
            end,
            on_release = function(button: number)
                if button ~= LEFT or not g.untracked(function() return drawing.value end) then return end
                drawing.value = false
                -- g.untracked gives back one value.
                local w, h = g.untracked(sel_w), g.untracked(sel_h)
                if w < MINIMUM or h < MINIMUM then
                    capture.cancel_selection()
                    return
                end
                capture.region_chosen(region())
            end,
            on_key = function(name: string)
                if name == "Escape" then capture.cancel_selection() end
            end,

            g.shader {
                overlay = true,
                attach = "corner",
                src = VEIL,
                width = size.width,
                height = size.height,
                values = function() return veil_values.value end,
                follow = 0,
            },

            -- The same lit border every surface in the shell carries: the
            -- rectangle is Bioma's, and says so the one way every shape does.
            g.capsule {
                overlay = true,
                attach = "corner",
                present = function() return drawing.value end,
                offset_x = sel_x,
                offset_y = sel_y,
                width = sel_w,
                height = sel_h,
                radius = corner,
                fill = "#00000000",
                rim_top = theme.rim,
                rim_bottom = theme.line,
            },

            -- What the region is, in the technical voice, tabular so it does
            -- not dance while the pointer moves.
            g.capsule {
                overlay = true,
                attach = "corner",
                present = function() return drawing.value end,
                offset_x = function() return sel_x() + math.max(0, sel_w() - readout_width() - readout_pad) end,
                offset_y = function()
                    return sel_y() + (if below() then sel_h() + readout_pad else sel_h() - readout_height - readout_pad)
                end,
                width = readout_width,
                height = readout_height,
                radius = function() return metrics_mod.radius_for(readout_height, m) end,
                fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                align = "center",
                justify = "center",
                g.text {
                    text = figure,
                    font = typography.technical,
                    size = m.font_meta,
                    weight = typography.weight_secondary,
                    tabular = true,
                    color = theme.text,
                },
            },
        },
    }
end

return M
