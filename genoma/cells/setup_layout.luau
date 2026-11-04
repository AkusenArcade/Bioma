--!strict
-- The setup's layout step (cells/settings/SetupLayout.qml at 2cafc17): one
-- of the three layouts Bioma ships. See docs/design/SETUP.md, step 1.
--
-- Choosing one applies it, live: the desktop recomposes behind the panel,
-- and the panel stays where it is, because every shipped preset keeps the
-- settings cell at the right end of the top membrane. A layout kept under
-- no name is asked about first, in its own row, as on the Structure page.
--
-- Each row draws its preset: the monitor as an outline, the tissues as
-- bars on their edges, the organisms as the panels they are. A name and a
-- sentence cannot say how much a layout puts on the screen; the drawing
-- does at once.
local g = require("@genoma")
local colour = require("core/colour")
local presets = require("core/presets")
local theme = require("core/theme")
local typography = require("core/typography")
local page = require("components/page")
local monitors = require("services/monitors")
local setup = require("services/setup")

local M = {}

local CLEAR = "#00000000"

-- An organism's panel, in units, by kind (docs/design/ORGANISMS.md).
local function template(entry: any): (number, number)
    local kind = entry.type
    if kind == "lava" or kind == "osmosis" then return 1, 2 end
    if kind == "media" or kind == "calendar" or kind == "agenda" or kind == "rings" or kind == "vacuole" or kind == "sediment" then
        return 2, 2
    end
    if kind == "vitals" then return 2, if entry.layout == "square" then 2 else 1 end
    return 2, 1
end

function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    local function m(): any return t.metrics() end
    local armed = g.signal("")

    local function choose(name: string)
        if presets.active() == name and not presets.changed() then
            setup.note("layout", name)
            return
        end
        if not presets.kept() and armed.value ~= name then
            armed.value = name
            return
        end
        armed.value = ""
        presets.apply(name)
        setup.note("layout", name)
    end
    -- The layout on screen is the step's answer, however it got there.
    g.effect(function()
        local active = presets.active()
        if active == "" then return end
        local line = active .. (if presets.changed() then ", changed" else "")
        g.untracked(function() setup.note("layout", line) end)
    end)

    local function shipped(): { any }
        local out = {}
        for _, preset in presets.all() do
            if preset.shipped then table.insert(out, preset) end
        end
        return out
    end
    -- The primary screen's proportions, for the drawing.
    local function screen(): (number, number)
        local o = monitors.output_of(monitors.primary())
        if o then return o.width, o.height end
        return 1920, 1080
    end

    local function schematic(preset: () -> any, chosen: () -> boolean): any
        local function w(): number return 96 * f() end
        local function h(): number return 54 * f() end
        local function ink(): string return if chosen() then theme.primary() else theme.text_muted() end
        local function inset(): number return 4 * f() end
        local function bar(): number return 4 * f() end
        -- Every tissue on a horizontal edge, placed by its anchor and its
        -- share of the edge.
        local function bars(): { any }
            local out = {}
            for _, membrane in preset().membranes or {} do
                local edge = membrane.edge or "top"
                if edge == "top" or edge == "bottom" then
                    local tissues = membrane.tissues or {}
                    local span = w() - inset() * 2
                    local start, finish = inset(), w() - inset()
                    for i, tissue in tissues do
                        local anchor = tissue.anchor or (if tissue.growth == "symmetric" then "centre"
                            elseif i == 1 then "start" elseif i == #tissues then "end" else "centre")
                        local length = math.max(6 * f(), span * (tissue.percentage or 30) / 100 * 0.7)
                        local x = (w() - length) / 2
                        if anchor == "start" then
                            x = start
                            start += length + 2 * f()
                        elseif anchor == "end" then
                            x = finish - length
                            finish -= length + 2 * f()
                        end
                        table.insert(out, { key = edge .. i, x = x, width = length, bottom = edge == "bottom" })
                    end
                end
            end
            return out
        end
        local function panels(): { any }
            local sw, sh = screen()
            local sx, sy = w() / sw, h() / sh
            local out = {}
            for i, entry in preset().organisms or {} do
                local cw, ch = template(entry)
                table.insert(out, {
                    key = tostring(i),
                    x = (24 + (entry.col or 0) * 224) * sx,
                    y = (60 + (entry.row or 0) * 224) * sy,
                    width = (cw * 224 - 24) * sx,
                    height = (ch * 224 - 24) * sy,
                })
            end
            return out
        end
        return g.capsule {
            width = w,
            height = h,
            radius = function() return 6 * f() end,
            fill = CLEAR,
            rim_top = theme.control_edge,
            rim_bottom = theme.control_edge,
            g.each {
                overlay = true,
                attach = "corner",
                items = bars,
                key = function(b: any) return b.key end,
                row = function(b: () -> any)
                    return g.capsule {
                        overlay = true,
                        attach = "corner",
                        offset_x = function() return b().x end,
                        offset_y = function() return if b().bottom then h() - inset() - bar() else inset() end,
                        width = function() return b().width end,
                        height = bar,
                        fill = ink,
                        rim_top = CLEAR,
                        rim_bottom = CLEAR,
                    }
                end,
            },
            g.each {
                overlay = true,
                attach = "corner",
                items = panels,
                key = function(o: any) return o.key end,
                row = function(o: () -> any)
                    return g.capsule {
                        overlay = true,
                        attach = "corner",
                        offset_x = function() return o().x end,
                        offset_y = function() return o().y end,
                        width = function() return o().width end,
                        height = function() return o().height end,
                        radius = function() return 1.5 * f() end,
                        fill = function() return colour.alpha(ink(), 0.35) end,
                        rim_top = CLEAR,
                        rim_bottom = CLEAR,
                    }
                end,
            },
        }
    end

    local function row(item: () -> any): any
        local function name(): string return item().name end
        local function chosen(): boolean return presets.active() == name() and not presets.changed() end
        local function asking(): boolean return armed.value == name() end
        local hovered = g.signal(false)
        local function edge(): string
            if asking() then return theme.alert() end
            return if chosen() then theme.primary() else colour.alpha(theme.line(), 0.7)
        end
        return g.capsule {
            role = "button",
            name = "Layout",
            width = t.width,
            height = function() return 76 * f() end,
            padding_left = function() return 11 * f() end,
            padding_right = function() return 16 * f() end,
            direction = "row",
            align = "center",
            justify = "start",
            gap = function() return 16 * f() end,
            radius = function() return m().radius_well end,
            fill = function()
                if asking() then return colour.alpha(theme.alert(), 0.12) end
                return if hovered.value then colour.alpha(theme.text(), 0.06) else CLEAR
            end,
            rim_top = edge,
            rim_bottom = edge,
            on_hover = function(on: boolean)
                hovered.value = on
                if not on and g.untracked(asking) then armed.value = "" end
            end,
            on_click = function() choose(g.untracked(name)) end,
            schematic(item, chosen),
            g.box {
                direction = "column",
                align = "start",
                gap = function() return 4 * f() end,
                g.text {
                    text = function() return if asking() then "DISCARD THE LAYOUT ON SCREEN?" else string.upper(name()) end,
                    color = function()
                        if asking() then return theme.alert() end
                        return if chosen() then theme.primary() else theme.text()
                    end,
                    font = typography.technical,
                    size = function() return math.round(12 * f()) end,
                    weight = function() return if chosen() then typography.weight_title else typography.weight_label end,
                    tracking = 0.04,
                },
                g.text {
                    text = function() return if asking() then "It is kept under no name. Press again to replace it." else item().line end,
                    color = theme.text_muted,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    wrap = true,
                    max_width = function() return t.width() - 11 * f() - 96 * f() - 16 * f() * 3 - 6 * f() end,
                },
            },
            g.box { grow = 1 },
            -- The choice is exclusive, so the mark may be a dot.
            g.capsule {
                opacity = function() return if chosen() then 1 else 0 end,
                width = function() return 6 * f() end,
                height = function() return 6 * f() end,
                fill = theme.primary,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
            },
        }
    end

    return p.column {
        g.each {
            direction = "column",
            align = "start",
            gap = function() return 10 * f() end,
            items = shipped,
            key = function(preset: any) return preset.name end,
            row = row,
        },
        g.box {
            present = function() return #monitors.outputs() > 1 end,
            p.line(function() return "These are for the primary screen. The others start empty; compose them in Settings → Structure." end, theme.text_muted),
        },
    }
end

return M
