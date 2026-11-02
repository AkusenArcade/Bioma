--!strict
-- What every settings page is built from (the `Section`, `Line` and row
-- components each page of cells/settings/ declares for itself).
--
-- A page is wells, one per thing a person decides, each with its label in
-- the technical face, perhaps its control on the same line, then a line in
-- Spectral saying what the current choice does: a page of bare rows says
-- nothing a person can check against (Akusen, 2026-09-29).
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local field_mod = require("components/field")

local M = {}

-- `t`: metrics(), width(). The helpers are measured from both.
function M.new(t: { [string]: any }): any
    local p = {}
    local function m(): any return t.metrics() end
    local function f(): number return m().factor end
    function p.factor(): number return f() end
    function p.inset(): number return 14 * f() end
    function p.header(): number return 28 * f() end
    -- The width inside a well.
    function p.inner(): number return t.width() - p.inset() * 2 end

    -- What a person reads, so the human voice. `color` for a line that
    -- warns.
    function p.line(text: () -> string, color: (() -> string)?): any
        return g.text {
            text = text,
            color = color or theme.text,
            font = typography.expressive,
            size = function() return m().font_secondary end,
            max_width = p.inner,
            wrap = true,
        }
    end

    -- A small label in the technical face, faint: what a row is for.
    function p.label(text: string | () -> string): any
        return g.text {
            text = text,
            color = theme.text_faint,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end

    -- A row inside a well: what it is for on the left, its control on the
    -- right.
    function p.row(label: string | () -> string, control: any): any
        return g.box {
            width = p.inner,
            direction = "row",
            align = "center",
            justify = "between",
            p.label(label),
            control,
        }
    end

    -- A well: its label, perhaps its control on the same line, then what
    -- it means. `present` for a well that is there only sometimes.
    function p.section(label: string | () -> string, trailing: any?, body: { any }, present: (() -> boolean)?): any
        local well: { [any]: any } = {
            present = present,
            width = t.width,
            padding = p.inset,
            direction = "column",
            align = "start",
            gap = function() return 6 * f() end,
            radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
            fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            g.box {
                width = p.inner,
                height = p.header,
                direction = "row",
                align = "center",
                justify = "between",
                g.text {
                    text = label,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tracking = typography.label_tracking,
                },
                trailing or g.box {},
            },
        }
        for _, node in body do table.insert(well, node) end
        return g.capsule(well)
    end

    local function chip_height(): number return 28 * f() end
    local function meta_text(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end

    -- A place for something not there yet: dashed, a plus and its name.
    function p.offer(label: string, on_click: () -> ()): any
        local hovered = g.signal(false)
        local function ink(): string return if hovered.value then theme.primary() else theme.text() end
        local function edge(): string return if hovered.value then theme.primary() else colour.alpha(theme.line(), 0.7) end
        return g.capsule {
            role = "button",
            name = label,
            height = chip_height,
            padding_left = function() return 11 * f() end,
            padding_right = function() return 15 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 7 * f() end,
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            rim_top = edge,
            rim_bottom = edge,
            dash = 3,
            dash_gap = 3,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = on_click,
            g.icon { width = function() return 9 * f() end, height = function() return 9 * f() end, icon = "plus", color = ink },
            meta_text(label, ink),
        }
    end

    -- The press that takes a row away for good, asking once before it
    -- does (components/RemoveTool.qml): the trash at rest; the first press
    -- grows the question out of it toward the row, alert, the second
    -- answers; leaving withdraws the question. Red only while it asks.
    function p.remove(on_confirm: () -> (), visible: (() -> boolean)?, question: string?): any
        local asking = g.signal(false)
        local hovered = g.signal(false)
        local words = question or "REMOVE?"
        local function side(): number return 22 * f() end
        local function size(): number return math.round(11 * f()) end
        local function word_width(): number
            return g.text_width {
                text = words, font = typography.technical(), size = size(),
                weight = typography.weight_label, tracking = typography.label_tracking,
            }
        end
        return g.capsule {
            role = "button",
            name = "Remove",
            opacity = function()
                if visible == nil or asking.value or hovered.value then return 1 end
                return if visible() then 1 else 0
            end,
            width = function() return if asking.value then side() + word_width() + 12 * f() else side() end,
            height = side,
            radius = function() return side() / 2 end,
            clip = true,
            direction = "row",
            align = "center",
            justify = "end",
            fill = function() return if asking.value then colour.alpha(theme.alert(), 0.12) else "#00000000" end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            transition = { width = "transition", opacity = "fade", fill = "colour" },
            on_hover = function(on: boolean)
                hovered.value = on
                if not on then asking.value = false end
            end,
            on_click = function()
                if not g.untracked(function() return asking.value end) then
                    asking.value = true
                    return
                end
                asking.value = false
                on_confirm()
            end,
            g.text {
                opacity = function() return if asking.value then 1 else 0 end,
                text = words,
                color = theme.alert,
                font = typography.technical,
                size = size,
                weight = typography.weight_label,
                tracking = typography.label_tracking,
            },
            g.box {
                width = side,
                height = side,
                align = "center",
                justify = "center",
                g.icon {
                    width = function() return 14 * f() end,
                    height = function() return 14 * f() end,
                    icon = "trash",
                    color = function()
                        if asking.value then return theme.alert() end
                        return if hovered.value then theme.primary() else theme.text()
                    end,
                },
            },
        }
    end

    -- An application: its icon, its name, and a detail in the technical
    -- face at the far end (the app-id, OPEN NOW). `t`: icon() (a path or
    -- ""), name(), detail(), on_choose (a press on the whole row chooses
    -- it), trailing (nodes at the end), hovered (a signal it keeps).
    function p.app(a: { [string]: any }): any
        local hovered = a.hovered or g.signal(false)
        local function side(): number return 20 * f() end
        local row: { [any]: any } = {
            role = if a.on_choose then "button" else nil,
            width = p.inner,
            height = function() return 30 * f() end,
            padding_left = function() return 8 * f() end,
            padding_right = function() return 4 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 10 * f() end,
            radius = function() return metrics_mod.radius_for(30 * f(), m()) end,
            fill = function()
                return if hovered.value and a.on_choose then colour.alpha(theme.text(), 0.06) else "#00000000"
            end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = a.on_choose,
            g.icon {
                present = function() return a.icon() ~= "" end,
                width = side,
                height = side,
                icon = a.icon,
            },
            g.icon {
                present = function() return a.icon() == "" end,
                width = side,
                height = side,
                icon = "app-fallback",
                color = theme.text_muted,
            },
            g.text {
                text = a.name,
                color = theme.text,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                max_width = function() return p.inner() * 0.5 end,
            },
            g.box { grow = 1 },
            meta_text(a.detail, theme.text_muted),
        }
        for _, node in a.trailing or {} do table.insert(row, node) end
        return g.capsule(row)
    end

    -- A one-line field, outlined, in the human voice. Returns the node and
    -- the field's handle (key, set). `t`: text (a signal), placeholder,
    -- taking().
    function p.field(a: { [string]: any }): (any, any)
        local node, handle = field_mod.new {
            text = a.text,
            width = function() return p.inner() - 28 * f() end,
            font = typography.expressive,
            size = function() return m().font_secondary end,
            placeholder = a.placeholder,
            taking = a.taking,
        }
        local function edge(): string return if a.taking() then theme.primary() else theme.line() end
        return g.capsule {
            width = p.inner,
            height = chip_height,
            padding_x = function() return 14 * f() end,
            align = "center",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = "#00000000",
            rim_top = edge,
            rim_bottom = edge,
            node,
        }, handle
    end

    -- Chips that go on to the next line when the row is full (Qt's Flow):
    -- `items()`, `key(item)`, `width_of(item)` measured as drawn, and
    -- `chip(item)` building one from a getter. `gap` between chips and
    -- rows.
    function p.flow(a: { [string]: any }): any
        local function gap(): number return if a.gap then a.gap() else 6 * f() end
        local rows = g.computed(function(): { any }
            local out, line, used = {}, {}, 0
            local room = p.inner()
            for _, item in a.items() do
                local w = a.width_of(item)
                if #line > 0 and used + gap() + w > room then
                    table.insert(out, line)
                    line, used = {}, 0
                end
                used += (if #line > 0 then gap() else 0) + w
                table.insert(line, item)
            end
            if #line > 0 then table.insert(out, line) end
            return out
        end)
        return g.each {
            direction = "column",
            align = "start",
            gap = gap,
            items = function()
                local out = {}
                for i, line in rows.value do table.insert(out, { index = i, line = line }) end
                return out
            end,
            key = function(r: any) return tostring(r.index) end,
            row = function(r: () -> any)
                return g.each {
                    direction = "row",
                    gap = gap,
                    items = function() return r().line end,
                    key = a.key,
                    row = a.chip,
                }
            end,
        }
    end

    -- The page itself: its wells in a column, ten apart.
    function p.column(wells: { any }): any
        local out: { [any]: any } = {
            width = t.width,
            direction = "column",
            align = "start",
            gap = function() return 10 * f() end,
        }
        for _, node in wells do table.insert(out, node) end
        return g.box(out)
    end

    return p
end

return M
