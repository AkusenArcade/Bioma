--!strict
-- Settings → Cells (cells/settings/SettingsCells.qml at 11bb81e): when each
-- cell exists.
--
-- One row per cell in the catalogue, with its visibility as a small
-- segmented control: always, or conditional. Every cell answers a keybind
-- whatever this says, so the only question left here is whether it is on
-- screen without being asked for; where it is, is the Structure page's.
-- Options a cell cannot wear stay in the track, dimmed: a window title
-- with no window has nothing to say, and seeing that is how the shell
-- explains itself. A cell in no tissue at all has neither answer, and its
-- row says it is reached by keybind only.
--
-- What "conditional" means is different for every cell, so the question
-- mark beside the choice opens the sentence under the row, grown out of
-- it, one row at a time. The sentences are the registry's.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local page = require("components/page")
local segmented = require("components/segmented")
local switch = require("components/switch")
local dropdown = require("components/dropdown")
local registry = require("cells/registry")

local M = {}

local CLEAR = "#00000000"

-- How the media band draws the sound. A dropdown rather than a segmented
-- control: the effects grow, and a row of buttons ran out of room beside
-- the visibility at the third (Akusen, 2026-10-11).
local EFFECTS = {
    { key = "bars", label = "BARS" },
    { key = "plasma", label = "PLASMA" },
    { key = "vesicles", label = "VESICLES" },
    { key = "eardrum", label = "EARDRUM" },
}

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    local function m(): any return t.metrics() end
    local function width(): number return t.width() end
    local function list_row(): number return 38 * f() end
    local function index_width(): number return 26 * f() end
    local function note_padding(): number return 10 * f() end
    local function note_gap(): number return 6 * f() end

    -- The row whose condition is being read, by type.
    local explained = g.signal("")

    -- Where a cell is declared, if anywhere. The first declaration wins:
    -- the visibility of a domain is a property of the domain.
    local function find(kind: string): any
        local membranes = config.get("membranes", {})
        for _, membrane in membranes do
            for _, tissue in membrane.tissues or {} do
                for _, entry in tissue.cells or {} do
                    if registry.canonical(entry.type or "") == kind then return { floating = false, entry = entry } end
                end
            end
        end
        for _, block in config.get("floating", {}) do
            for _, entry in block.cells or {} do
                if registry.canonical(entry.type or "") == kind then return { floating = true, entry = entry } end
            end
        end
        return nil
    end

    local rows = g.computed(function(): { any }
        local out = {}
        for i, pair in registry.catalogue do
            local kind = pair[1]
            local found = find(kind)
            local rule = if found then found.entry.visibility or {} else {}
            local floating = found ~= nil and found.floating
            local fixed = if floating then registry.fixed_when_floating(kind) else ""
            table.insert(out, {
                kind = kind,
                index = i,
                name = pair[2],
                placed = found ~= nil,
                floating = floating,
                state = if found then (if fixed ~= "" then fixed else rule.type or "always") else "",
            })
        end
        return out
    end)

    -- Only the kind is written. What a condition means (its thresholds,
    -- how long it waits to be believed and to stay) is the domain's, in the
    -- registry's grammar, and figures copied into the block would freeze
    -- it; switching drops figures an earlier page copied in.
    local function ruled(existing: any, kind: string): any
        local rule = {}
        for k, v in (if type(existing) == "table" then existing else {}) do rule[k] = v end
        rule.type = kind
        rule.enter, rule.exit, rule.confirm, rule.dwell, rule.invocable = nil, nil, nil, nil, nil
        return rule
    end

    -- Writing it back means writing the whole list, and every declaration
    -- of that cell changes, on every monitor: when a cell exists is a
    -- property of the cell, not of the copy of it on the second screen.
    local function apply(kind: string, visibility: string)
        local writes = {}
        for _, list in { "membranes", "floating" } do
            local copy = config.copy_list(g.untracked(function() return config.get(list, {}) end))
            local touched = false
            for _, block in copy do
                local groups = if list == "membranes" then (block.tissues or {}) else { block }
                for _, group in groups do
                    for _, entry in group.cells or {} do
                        if registry.canonical(entry.type or "") == kind then
                            entry.visibility = ruled(entry.visibility, visibility)
                            touched = true
                        end
                    end
                end
            end
            if touched then table.insert(writes, { list, registry.renamed(copy) }) end
        end
        if #writes > 0 then config.set_many(writes) end
    end

    local function meta(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end

    local effect_node, effect = dropdown.new {
        metrics = m,
        width = function() return 132 * f() end,
        options = function() return EFFECTS end,
        current = function() return config.get("sinestesia.effect", "eardrum") end,
        on_choose = function(key: string) config.set("sinestesia.effect", key) end,
    }

    t.keyed(function(name: string): boolean
        if name == "Escape" and g.untracked(function() return effect.open.value end) then
            effect.close()
            return true
        end
        return false
    end)

    local function row(r: () -> any): any
        local function kind(): string return r().kind end
        local function open(): boolean return explained.value == kind() end
        local function condition(): string return registry.condition_of(kind()) end
        local function note_width(): number return width() - index_width() end
        local function note_height(): number
            return g.text_height {
                text = condition(),
                font = typography.expressive(),
                size = m().font_secondary,
                width = note_width() - note_padding() * 2,
            } + note_padding() * 2
        end
        local help_hovered = g.signal(false)

        -- What a cell may carry beyond when it appears: the dock its
        -- launcher, the media its effect (which the media organism follows
        -- too, so it is offered even when the cell is placed nowhere), the
        -- launcher its form when it is asked for (simple, a list; organic,
        -- clusters on threads round the field).
        local function extra(): string
            local k = kind()
            if k == "dock" and r().placed then return "dock" end
            if k == "media" then return "media" end
            if k == "launcher" then return "launcher" end
            return ""
        end

        local line = g.box {
            width = width,
            height = list_row,
            direction = "row",
            align = "center",
            gap = function() return 0 end,
            -- The number is the machine counting: tabular and faint, there
            -- to make the list countable, not to be read.
            g.text {
                width = index_width,
                text = function() return string.format("%02d", r().index) end,
                color = theme.text_faint,
                font = typography.technical,
                size = function() return m().font_meta end,
                tabular = true,
            },
            g.text {
                text = function() return r().name end,
                color = function() return if r().placed then theme.text() else theme.text_muted() end,
                font = typography.expressive,
                size = function() return 14 * f() end,
                max_width = function() return width() * 0.3 end,
            },
            g.box { grow = 1 },
            g.box {
                present = function() return extra() ~= "" end,
                direction = "row",
                align = "center",
                gap = function() return 8 * f() end,
                padding_right = function() return 12 * f() end,
                meta(function()
                    local e = extra()
                    return if e == "dock" then "LAUNCHER" elseif e == "launcher" then "FORM" else "EFFECT"
                end, theme.text),
                g.box {
                    present = function() return extra() == "dock" end,
                    switch.new {
                        on = function() return config.get("dock.launcher", false) == true end,
                        factor = f,
                        on_toggle = function(value: boolean) config.set("dock.launcher", value) end,
                    },
                },
                g.box { present = function() return extra() == "media" end, effect_node },
                g.box {
                    present = function() return extra() == "launcher" end,
                    segmented.new {
                        metrics = m,
                        font_size = function() return m().font_meta end,
                        button_height = function() return 22 * f() end,
                        button_padding = function() return 10 * f() end,
                        options = function()
                            return { { key = "simple", label = "Simple" }, { key = "organic", label = "Organic" } }
                        end,
                        current = function() return config.get("launcher.style", "simple") end,
                        on_choose = function(key: string) config.set("launcher.style", key) end,
                    },
                },
            },
            -- The question: what "conditional" means for this one.
            g.box {
                present = function() return condition() ~= "" end,
                padding_right = function() return 10 * f() end,
              g.capsule {
                role = "button",
                name = "What conditional means",
                width = function() return 18 * f() end,
                height = function() return 18 * f() end,
                radius = function() return 9 * f() end,
                align = "center",
                justify = "center",
                fill = function() return if open() then colour.alpha(theme.primary(), 0.16) else CLEAR end,
                rim_top = function()
                    if open() then return theme.primary() end
                    return if help_hovered.value then theme.text() else theme.line()
                end,
                rim_bottom = function()
                    if open() then return theme.primary() end
                    return if help_hovered.value then theme.text() else theme.line()
                end,
                on_hover = function(on: boolean) help_hovered.value = on end,
                on_click = function()
                    explained.value = if g.untracked(open) then "" else g.untracked(kind)
                end,
                g.text {
                    text = "?",
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    weight = typography.weight_label,
                },
              },
            },
            g.box {
                present = function() return r().placed end,
                segmented.new {
                    metrics = m,
                    font_size = function() return m().font_meta end,
                    button_height = function() return 22 * f() end,
                    button_padding = function() return 10 * f() end,
                    options = function()
                        local x = r()
                        return {
                            { key = "always", label = "Always", dimmed = not registry.allows_in(x.kind, "always", x.floating) },
                            { key = "conditional", label = "Conditional", dimmed = not registry.allows_in(x.kind, "conditional", x.floating) },
                        }
                    end,
                    current = function() return r().state end,
                    on_choose = function(key: string) apply(g.untracked(kind), key) end,
                },
            },
            -- Placed nowhere, it has no rest state to choose: it is there
            -- when it is asked for, and that is what the row says.
            g.box {
                present = function() return not r().placed end,
                padding_right = function() return 6 * f() end,
                meta("KEYBIND ONLY", theme.text_faint),
            },
        }

        -- The note: a well under the row that grows from it by height, with
        -- the sentence arriving once it is whole.
        local note = g.box {
            padding_left = index_width,
            width = width,
            height = function() return if open() then note_height() + note_gap() else 0 end,
            direction = "column",
            clip = true,
            transition = { height = function() return if open() then "grow" else "close" end },
            g.box { height = note_gap },
            g.capsule {
                width = note_width,
                height = note_height,
                padding = note_padding,
                radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                g.text {
                    text = condition,
                    color = theme.text_muted,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    max_width = function() return note_width() - note_padding() * 2 end,
                    wrap = true,
                    opacity = function() return if open() then 1 else 0 end,
                    transition = { opacity = function() return if open() then "content_enter" else "content_leave" end },
                },
            },
        }

        return g.box {
            width = width,
            direction = "column",
            line,
            note,
        }
    end

    return g.each {
        width = width,
        direction = "column",
        items = function() return rows.value end,
        key = function(r: any) return r.kind end,
        row = row,
    }
end

return M
