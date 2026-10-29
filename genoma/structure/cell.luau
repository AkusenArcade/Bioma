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
--   panel              what it opens, if anything: { width(), height(),
--                      content(), satellites() }, the size the panel's own,
--                      padding included; satellites are shapes that bud out of
--                      the panel itself (the vitals' pods)
--   on_key(name)       a key while it is open, Escape aside
--   on_wheel(dx, dy)   the wheel over the cell
--   header_title, header_mark(size), header_mark_size()
--                      what it shows while open: the domain's glyph and its
--                      name in the technical voice, the title of what hangs
--                      under it
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
local focus = require("structure/focus")
local timing = require("core/timing")
local typography = require("core/typography")
local thread = require("components/thread")

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

    -- ---- Events ---------------------------------------------------------
    --
    -- Most conditions are a state; some are an event (the workspace changed,
    -- a device connected). A cell whose condition is an event calls
    -- `pulse()` when it happens: the condition is true for a moment, and the
    -- grammar's dwell is how long the cell stays. What happens while the
    -- shell is still starting is not an event.
    local pulsing = g.signal(false)
    local settled = false
    g.after(timing.seconds.settle, function() settled = true end)
    local pulse_timer: any = nil
    function c.pulse()
        if not settled then return end
        pulsing.value = true
        if pulse_timer then pulse_timer:stop() end
        pulse_timer = g.after(timing.seconds.pulse, function() pulsing.value = false end)
    end
    function c.pulsing(): boolean return pulsing.value end

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
        if spec and spec.min_width then return spec.min_width() end
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

    -- ---- The header ---------------------------------------------------------
    --
    -- While it is expanded (open, or its panel still on its way back) a cell
    -- with an expansion becomes the title of it: the contracted content goes
    -- and the domain's glyph arrives with the cell's name. Every cell wears
    -- the same face, and the rule for too little room is the same: below the
    -- name's width the glyph alone, centred in what was given.
    c.has_panel = spec.panel ~= nil
    local panel_out = g.signal(false)
    if c.has_panel then
        g.watch(function() return c.open.value end, function(open: boolean)
            if open then
                panel_out.value = true
            else
                g.after(timing.retracted(spec.panel.satellites ~= nil), function()
                    if not g.untracked(function() return c.open.value end) then panel_out.value = false end
                end)
            end
        end)
    end
    function c.expanded(): boolean return c.open.value or panel_out.value end

    local function header_title(): string
        local t = spec.header_title
        if type(t) == "function" then return t() end
        return t or ""
    end
    local has_header = spec.header_mark ~= nil or spec.header_title ~= nil
    function c.shows_header(): boolean return has_header and c.expanded() end
    local function mark_size(): number
        return if spec.header_mark_size then spec.header_mark_size() else 20 * c.metrics().factor
    end
    local function header_gap(): number return 12 * c.metrics().factor end
    local function header_font(): { [string]: any }
        local size = c.metrics().font_label
        return {
            font = typography.technical(),
            size = size,
            weight = typography.weight_label,
            tracking = typography.label_tracking,
        }
    end
    local function mark_room(): number return if spec.header_mark then mark_size() + header_gap() else 0 end
    local function header_width(): number
        local f = header_font()
        return mark_room() + g.text_width { text = header_title(), font = f.font, size = f.size, weight = f.weight, tracking = f.tracking }
    end
    -- A header keeps its own margins: the leading one follows the mark, so
    -- the glyph is concentric with the cap, and the name keeps the full one.
    local function leading_inset(): number
        return if c.shows_header() then (c.metrics().cell_height - mark_size()) / 2 else leading()
    end
    local function trailing_inset(): number
        return if c.shows_header() then 16 * c.metrics().factor else trailing()
    end

    -- An open cell does not narrow: it keeps the width it had when it opened
    -- for as long as the header shows, the header in the middle of it. A
    -- cell narrower than its header still grows to it.
    local held = g.signal(0)
    local function rest_width(): number
        local natural = math.max(c.min_width(), spec.content_width() + leading() + trailing())
        local max = c.max_width()
        return if max > 0 then math.min(natural, max) else natural
    end
    g.watch(function() return c.open.value end, function(open: boolean)
        if open and g.untracked(function() return held.value end) == 0 then held.value = g.untracked(rest_width) end
    end)
    g.watch(c.shows_header, function(showing: boolean)
        if not showing then held.value = 0 end
    end)

    function c.contracted_width(): number
        if not c.shows_header() then return rest_width() end
        local natural = math.max(c.min_width(), header_width() + leading_inset() + trailing_inset(), held.value)
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

    -- One cell open at a time: opening this one closes whatever was open.
    c.focus_id = focus.offer(c)
    g.watch(function() return c.open.value end, function(open: boolean)
        if open then focus.opened(c) else focus.released(c) end
    end)

    -- A cell that goes while it is open closes on the way out, and one that
    -- held the attention gives it back.
    g.watch(function() return c.shown() end, function(shown: boolean)
        if shown then return end
        if c.open.value then c.open.value = false end
        focus.released(c)
    end)

    -- Who keeps their place when the tissue runs short: an open cell, then
    -- one that is here because something is happening, then the rest.
    function c.precedence(): number
        if c.open.value then return 2 end
        if c.busy.value or c.visibility.type() == "conditional" then return 1 end
        return 0
    end

    -- ---- Surfaces -----------------------------------------------------------

    -- How far what it opened reaches past it on the side it opens, while
    -- it is out: a floating tissue is centred on all of it.
    function c.reach(): number return 0 end
    local interactive = if spec.interactive ~= nil then spec.interactive else c.has_panel

    -- A cell that answers the pointer says so before it is pressed, in the
    -- light: the glass lifts a step and the rim catches more of it.
    local function lit(): boolean
        return interactive and c.hovered.value and not c.open.value
    end

    local function opacity(): number return config.get("cell.opacity", 0.72) end

    -- ---- Expansion ----------------------------------------------------------
    --
    -- The panel buds out of the cell (Akusen, 2026-10-28; Genoma PRD §8.2):
    -- it leaves from the middle of the cell's edge that faces away from the
    -- screen, joined to it by a neck that narrows and parts, and settles a
    -- gap away, on the line the windows begin on. A corner cell keeps its
    -- edge and the panel opens inward; a centred one opens from both sides.
    -- Closing takes it back the same way, quicker. Its content enters once
    -- the shape is at size and leaves before it.
    local function panel_node(place: { [string]: any }): any
        local p = spec.panel
        local down = c.edge ~= "bottom"
        local function pad(): number return 10 * c.metrics().factor end
        -- A panel others budded out of goes after them.
        local last = p.satellites ~= nil
        local function curve(): string
            if c.open.value then return "bud" end
            return if last then "retract_last" else "retract"
        end

        -- Still drawn while it is taken back.
        function c.reach(): number return if panel_out.value then place.gap() + p.height() else 0 end

        local panel: { [any]: any } = {
            name = c.domain .. " panel",
            role = "group",
            overlay = true,
            attach = if down then "below" else "above",
            present = function() return panel_out.value end,
            width = p.width,
            height = p.height,
            offset_x = function()
                local origin = place.origin()
                if origin == "end" then return place.width() - p.width() end
                if origin == "centre" then return (place.width() - p.width()) / 2 end
                return 0
            end,
            -- On the cell's edge while shut: it leaves from there, so as it
            -- grows it never crosses the cells beside it in the row.
            offset_y = function()
                if not c.open.value then return 0 end
                return if down then place.gap() else -place.gap()
            end,
            radius = function() return c.metrics().radius_panel end,
            growth = function() return if c.open.value then 1 else 0 end,
            -- The neck: soft and wide as it leaves, gone once it is out.
            bud = function() return if c.open.value then 0 else c.metrics().cell_height end,
            blur = function() return config.get("cell.blur", true) end,
            fill = function() return colour.alpha(theme.cell(), opacity()) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            -- Nothing under the shape hears the pointer: a press on the panel
            -- is not a press on the cell it came from.
            on_press = function() end,
            transition = {
                offset_y = curve,
                growth = curve,
                bud = curve,
                offset_x = "reflow",
                width = "reflow",
                height = "reflow",
            },
            g.box {
                overlay = true,
                width = function() return math.max(0, p.width() - pad() * 2) end,
                height = function() return math.max(0, p.height() - pad() * 2) end,
                align = "center",
                justify = "center",
                opacity = function() return if c.open.value then 1 else 0 end,
                transition = {
                    opacity = function() return if c.open.value then "content_enter" else "content_leave" end,
                },
                p.content(),
            },
        }
        if p.satellites then
            for _, satellite in p.satellites() do table.insert(panel, satellite) end
        end
        return g.capsule(panel)
    end

    -- The header, staggered after the content leaves rather than crossed
    -- through it: two strings dissolving through each other read as overlap.
    local function header_node(place: { [string]: any }): any
        local function room(): number return place.width() - leading_inset() - trailing_inset() end
        local function named(): boolean return room() >= header_width() - 0.5 end
        local function slack(): number
            return if held.value > 0 and named() then math.max(0, (room() - header_width()) / 2) else 0
        end
        local f = header_font
        local header: { [any]: any } = {
            overlay = true,
            attach = "corner",
            width = place.width,
            height = function() return c.contracted_height() end,
            present = c.shows_header,
            opacity = function() return if c.shows_header() then 1 else 0 end,
            transition = { opacity = "header" },
        }
        if spec.header_mark then table.insert(header, g.box {
                overlay = true,
                attach = "corner",
                width = mark_size,
                height = mark_size,
                -- Against the leading cap when the name is beside it, in the
                -- middle of the cell when it is alone.
                offset_x = function()
                    if named() then return leading_inset() + slack() end
                    return math.max(0, (place.width() - mark_size()) / 2)
                end,
                offset_y = function() return (c.contracted_height() - mark_size()) / 2 end,
                spec.header_mark(mark_size),
            })
        end
        table.insert(header, g.box {
                overlay = true,
                attach = "corner",
                present = named,
                offset_x = function() return leading_inset() + slack() + mark_room() end,
                height = function() return c.contracted_height() end,
                align = "center",
                g.text {
                    color = theme.text,
                    font = function() return f().font end,
                    size = function() return f().size end,
                    weight = function() return f().weight end,
                    tracking = function() return f().tracking end,
                    text = header_title,
                },
        })
        return g.box(header)
    end

    -- Built by the tissue, which knows where the cell goes: `place` has
    -- x(), y(), width() (granted), placed(), radius(), origin() (the side
    -- the cell was born from) and gap() (how far its panel hangs).
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

        local node: { [any]: any } = {
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
            on_wheel = spec.on_wheel,
            -- While it is open it has the attention: a press on anything but
            -- itself and what it opened closes it, and so does Escape.
            catch = function() return c.open.value or focus.is(c) end,
            on_outside = function() focus.dismiss() end,
            on_key = function(name: string, text: string?, mods: any) focus.key(name, text, mods) end,
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
                opacity = function() return if c.open.value and c.shows_header() then 0 else 1 end,
                transition = { opacity = "content_fade" },
                spec.contracted(),
            },
        }
        -- Appended rather than listed: a child that is nil in the middle of
        -- the list would end it, and every child after it with it.
        if has_header then table.insert(node, header_node(place)) end
        if c.has_panel then
            -- The thread to what it opened, from the middle of the cell's
            -- edge, where the bud left it.
            table.insert(node, thread.new {
                vertical = true,
                overlay = true,
                attach = if c.edge ~= "bottom" then "below-center" else "above-center",
                present = function() return panel_out.value end,
                length = function() return place.gap() end,
                reversed = c.edge == "bottom",
                shown = function() return c.open.value end,
                timing = function() return "thread" end,
                closing = function() return if spec.panel.satellites then "thread_close_last" else "thread_close" end,
            })
            table.insert(node, panel_node(place))
        end
        return g.capsule(node)
    end

    return c
end

return M
