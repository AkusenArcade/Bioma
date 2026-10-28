--!strict
-- A unit of content with one domain (structure/Cell.qml). It has no position
-- of its own and no max width of its own: it takes what the tissue grants.
--
-- A cell always has its own background — flat glass, the one blurred surface
-- in the shell — a full-pill radius up to the pill ceiling, and the lit rim
-- on the top edge. Nothing clips: clipping eats the rim.
--
-- A cell type (`cells/<domain>.luau`) returns `{ new = function(cell) … end }`
-- and `new` returns what is the domain's:
--   contracted()       the content at rest, a node
--   content_width()    what that content asks for, logical units (unclamped)
--   condition()        the measurement its visibility watches, if any
--   padding_leading, padding_trailing, least_width, body_height
--   interactive        whether it answers a press (default: it has a panel)
--   on_click()         what a press does, if not opening
-- and the cell gives back room(), the width its content may draw in, once
-- the tissue has placed it.
-- Everything the engine needs from a cell arrives in its block; adding a
-- cell costs one config block.
local g = require("@genoma")
local theme = require("core/theme")
local config = require("core/config")
local colour = require("core/colour")
local registry = require("cells/registry")
local visibility = require("structure/visibility")

local M = {}

-- `ctx`: block() (the cell's configuration block, read reactively),
-- metrics(), output, edge, output_width.
function M.new(kind: any, ctx: { [string]: any })
    local c: { [string]: any } = {}
    c.domain = registry.canonical(ctx.block().type)
    c.block = ctx.block
    c.metrics = ctx.metrics
    c.output = ctx.output
    c.edge = ctx.edge

    function c.option(key: string, fallback: any): any
        local options = c.block().options
        if options and options[key] ~= nil then return options[key] end
        return fallback
    end

    c.open = g.signal(false)
    c.hovered = g.signal(false)
    -- In the middle of something (a recording to save): it keeps its place.
    c.busy = g.signal(false)

    local spec = kind.new(c)
    c.spec = spec

    -- ---- Width ----------------------------------------------------------

    local function width_rule(): { [string]: any }
        local own = registry.width_of(c.domain)
        local declared = c.block().width or {}
        local declares_max = declared.max ~= nil or declared.max_percent ~= nil
        local elastic = declared.elastic
        if elastic == nil then elastic = own.elastic == true end
        return {
            elastic = elastic == true,
            max = if declares_max then declared.max else own.max,
            max_percent = if declares_max then declared.max_percent else own.max_percent,
        }
    end

    function c.elastic(): boolean return width_rule().elastic end

    -- Below its minimum a cell prefers not to appear rather than appear
    -- illegible. At the normal step, so it takes the step.
    function c.min_width(): number
        local m = c.block().min_width
        return ((m and m.value) or 24) * c.metrics().factor
    end

    -- The narrowest the content can be drawn at all: an elastic cell is
    -- never granted less.
    function c.least_width(): number
        return if spec.least_width then spec.least_width() else 0
    end

    function c.max_width(): number
        local rule = width_rule()
        if rule.max then return rule.max * c.metrics().factor end
        if rule.max_percent then return ctx.output_width() * rule.max_percent / 100 end
        return -1
    end

    local function leading(): number return spec.padding_leading or 16 end
    local function trailing(): number return spec.padding_trailing or 16 end

    function c.contracted_width(): number
        local natural = math.max(c.min_width(), spec.content_width() + leading() + trailing())
        local max = c.max_width()
        return if max > 0 then math.min(natural, max) else natural
    end

    function c.contracted_height(): number
        return if spec.body_height then spec.body_height() else c.metrics().cell_height
    end

    -- ---- Visibility -------------------------------------------------------

    c.visibility = visibility.new(function()
        local rule = c.block().visibility or {}
        local grammar = registry.grammar_of(c.domain)
        return {
            type = spec.fixed_visibility or rule.type or "always",
            enter = rule.enter or grammar.enter,
            exit = rule.exit or grammar.exit,
            confirm = rule.confirm or grammar.confirm,
            dwell = rule.dwell or grammar.dwell,
        }
    end, function()
        return if spec.condition then spec.condition() else 0
    end)

    function c.shown(): boolean return c.visibility.shown() end

    -- Interaction suspends disappearance; an open cell is interacted with
    -- wherever the pointer is.
    g.effect(function()
        c.visibility.set_interacting(c.hovered.value or c.open.value)
    end)

    -- A cell that goes while it is open closes on the way out.
    g.watch(function() return c.shown() end, function(shown: boolean)
        if not shown and c.open.value then c.open.value = false end
    end)

    -- Who keeps their place when the tissue runs short: an open cell, then
    -- one that is here because something is happening, then the rest.
    function c.precedence(): number
        if c.open.value then return 2 end
        if c.busy.value or c.visibility.type() == "conditional" then return 1 end
        return 0
    end

    -- ---- Surfaces -----------------------------------------------------------

    c.has_panel = spec.panel ~= nil
    local interactive = if spec.interactive ~= nil then spec.interactive else c.has_panel

    -- A cell that answers the pointer says so before it is pressed, in the
    -- light: the glass lifts a step and the rim catches more of it.
    local function lit(): boolean
        return interactive and c.hovered.value and not c.open.value
    end

    local function opacity(): number return config.get("cell.opacity", 0.72) end

    -- Built by the tissue, which knows where the cell goes: `place` has
    -- x(), y(), width() (granted), placed() and radius().
    function c.node(place: { [string]: any }): any
        -- What the content may occupy: the granted width inside the cell's
        -- own padding. An elastic content ends in an ellipsis there.
        function c.room(): number return math.max(0, place.width() - leading() - trailing()) end

        -- Still drawn while it fades out: present until the fade is over.
        local present = g.signal(true)
        g.watch(function() return place.placed() end, function(placed: boolean)
            if placed then
                present.value = true
            else
                g.after(require("core/timing").seconds.reflow, function()
                    if not g.untracked(place.placed) then present.value = false end
                end)
            end
        end)

        return g.capsule {
            name = c.domain,
            role = if interactive then "button" else "group",
            overlay = true,
            attach = "corner",
            offset_x = place.x,
            offset_y = place.y,
            width = place.width,
            height = function() return c.contracted_height() end,
            radius = place.radius,
            present = function() return present.value end,
            opacity = function() return if place.placed() then 1 else 0 end,
            blur = function() return config.get("cell.blur", true) end,
            fill = function()
                local base = if lit() then theme.lift(theme.cell(), 0.05) else theme.cell()
                return colour.alpha(base, opacity())
            end,
            rim_top = function() return if lit() then theme.lift(theme.rim(), 0.10) else theme.rim() end,
            rim_bottom = function() return if lit() then theme.lift(theme.line(), 0.06) else theme.line() end,
            on_hover = function(on: boolean) c.hovered.value = on end,
            on_click = function()
                if spec.on_click then
                    spec.on_click()
                elseif c.has_panel then
                    c.open.value = not c.open.value
                end
            end,
            transition = {
                offset_x = "reflow",
                offset_y = "reflow",
                width = "reflow",
                height = "reflow",
                opacity = "fade",
                fill = "colour",
                rim_top = "colour",
                rim_bottom = "colour",
            },
            -- The content, inset by the cell's own padding, never clipped.
            g.box {
                overlay = true,
                attach = "corner",
                width = place.width,
                transition = { width = "reflow" },
                height = function() return c.contracted_height() end,
                padding_left = leading(),
                padding_right = trailing(),
                direction = "row",
                align = "center",
                justify = "start",
                spec.contracted(),
            },
        }
    end

    return c
end

return M
