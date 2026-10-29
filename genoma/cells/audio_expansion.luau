--!strict
-- Audio, opened (cells/audio/AudioExpansion.qml at 11bb81e): the capsule
-- that carries the level, and under it the three wells — where the sound
-- goes, where it comes from, and who is making it. See docs/design/CELLS.md
-- §05.
--
-- Three wells and not three tabs: this cell is usually opened because the
-- sound comes out of the wrong place, and a tab would hide half the answer.
-- The heights are fixed rather than fitted: PipeWire nodes come and go (a
-- notification sound lives a second and a half), and a panel resizing
-- round them would jump under the hand using it. Rows arrive and leave
-- inside a well that does not move, and scroll past three.
--
-- Summoned, the cell is the capsule already, and the wells hang from it on
-- the cell's own thread.
--
-- Not yet: the keyboard's travel through the rows.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local performance = require("core/performance")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local apps = require("core/apps")
local audio = require("services/audio")
local slider = require("components/slider")
local scroller_mod = require("components/scroller")
local thread = require("components/thread")
local capsule_mod = require("cells/audio_capsule")

local CLEAR = "#00000000"
local SHOWN_ROWS = 3

local M = {}

-- `bare`: the cell is the capsule (summoned), so only the wells hang.
function M.new(cell: any, bare: boolean): any
    local function m(): any return cell.metrics() end
    local function f(): number return m().factor end
    local down = cell.edge ~= "bottom"

    local function capsule_width(): number return 372 * f() end
    local function capsule_height(): number return 88 * f() end
    local function panel_width(): number return 372 * f() end
    local function panel_padding(): number return 10 * f() end
    local function well_padding(): number return 8 * f() end
    local function well_inset(): number return 10 * f() end
    local function well_spacing(): number return 8 * f() end
    local function row_height(): number return 38 * f() end
    local function gap(): number return m().gap end
    local function well_width(): number return panel_width() - panel_padding() * 2 end
    local function label_height(): number return math.ceil(m().font_meta * 1.3) + 2 * f() end

    local function well_height(rows: number): number
        return well_padding() * 2 + label_height() + math.max(1, math.min(rows, SHOWN_ROWS)) * row_height()
    end
    local function outputs_height(): number return well_height(#audio.outputs()) end
    local function inputs_height(): number return well_height(#audio.inputs()) end
    -- Fixed at its full three rows whatever is playing: this is the well
    -- things come and go from.
    local function streams_height(): number return well_height(SHOWN_ROWS) end
    local function panel_height(): number
        return panel_padding() * 2 + well_spacing() * 2 + outputs_height() + inputs_height() + streams_height()
    end

    -- ---- Rows ---------------------------------------------------------------

    local function meta_text(text: () -> string, colour_of: (() -> string)?): any
        return g.text {
            text = text,
            color = colour_of or theme.text_muted,
            font = typography.technical,
            size = function() return m().font_meta end,
        }
    end

    -- A device: the mark of what is chosen, its own name, and how it is
    -- attached to the machine.
    local function device_row(chosen: (any) -> boolean, pick: (any) -> ()): (() -> any, () -> number) -> any
        return function(node: () -> any, index: () -> number): any
            local function on(): boolean return chosen(node()) end
            local function mark(): number return 16 * f() end
            local function meta(): string return audio.connection(node()) end
            return g.box {
                role = "button",
                overlay = true,
                attach = "corner",
                offset_y = function() return (index() - 1) * row_height() end,
                width = well_width,
                height = row_height,
                direction = "row",
                align = "center",
                padding_x = well_inset,
                gap = function() return 12 * f() end,
                on_click = function() pick(g.untracked(node)) end,
                g.box {
                    width = mark,
                    height = mark,
                    align = "center",
                    justify = "center",
                    g.capsule {
                        overlay = true,
                        present = function() return not on() end,
                        width = mark,
                        height = mark,
                        stroke = metrics_mod.rim_width,
                        rim_top = theme.line,
                        rim_bottom = theme.line,
                    },
                    -- The hole in a chosen mark is the panel showing
                    -- through, not a second colour.
                    g.capsule {
                        overlay = true,
                        present = on,
                        width = mark,
                        height = mark,
                        fill = function() return theme.gradient_top(theme.primary()) end,
                        fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                        rim_top = CLEAR,
                        rim_bottom = CLEAR,
                        g.capsule {
                            width = function() return mark() / 2 end,
                            height = function() return mark() / 2 end,
                            fill = theme.background,
                            rim_top = CLEAR,
                            rim_bottom = CLEAR,
                        },
                    },
                },
                -- A device's own words are human language, whoever wrote
                -- them into the firmware.
                g.text {
                    grow = 1,
                    text = function() return audio.describe(node()) end,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    max_width = function()
                        local meta_width = g.text_width { text = meta(), font = typography.technical(), size = m().font_meta }
                        return well_width() - well_inset() * 2 - mark() - 24 * f() - meta_width
                    end,
                },
                meta_text(meta),
            }
        end
    end

    -- An application: its own icon, its name, a short slider, the figure
    -- and its mute. The controls take their places from the right and the
    -- name what is left: a slider shortened by a long title would be a
    -- different control on every row.
    local function stream_row(node: () -> any, index: () -> number): any
        local function label(): string return audio.describe_stream(node()) end
        local function level(): number return node().volume end
        local function muted(): boolean return node().muted end
        local function icon(): string return apps.icon_for(label()) end
        local function badge(): number return 20 * f() end
        local function controls(): number return 80 * f() + 34 * f() + 22 * f() + 12 * f() * 2 end
        return g.box {
            overlay = true,
            attach = "corner",
            offset_y = function() return (index() - 1) * row_height() end,
            width = well_width,
            height = row_height,
            direction = "row",
            align = "center",
            padding_x = well_inset,
            gap = function() return 12 * f() end,
            g.box {
                width = badge,
                height = badge,
                align = "center",
                justify = "center",
                g.capsule {
                    overlay = true,
                    width = badge,
                    height = badge,
                    stroke = metrics_mod.rim_width,
                    rim_top = theme.line,
                    rim_bottom = theme.line,
                },
                -- An application's icon is the application's, so it is not
                -- tinted; where none resolves, the neutral glyph, which
                -- follows the palette. Never another application's logo.
                g.icon {
                    present = function() return icon() ~= "" end,
                    width = function() return badge() * 0.62 end,
                    height = function() return badge() * 0.62 end,
                    icon = function() local i = icon() return if i ~= "" then i else "app-fallback" end,
                },
                g.icon {
                    present = function() return icon() == "" end,
                    width = function() return badge() * 0.58 end,
                    height = function() return badge() * 0.58 end,
                    icon = "app-fallback",
                    gradient_top = theme.text_muted,
                    gradient_bottom = theme.text_muted,
                },
            },
            g.box {
                grow = 1,
                g.text {
                    text = label,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    max_width = function() return well_width() - well_inset() * 2 - badge() - 12 * f() * 2 - controls() end,
                },
            },
            -- Deliberately short: a fine adjustment, not the main one.
            slider.new {
                width = function() return 80 * f() end,
                factor = f,
                value = level,
                dimmed = muted,
                on_move = function(v: number) audio.set_stream_volume(g.untracked(node), v) end,
            },
            g.box {
                width = function() return 34 * f() end,
                justify = "end",
                g.text {
                    text = function() return math.floor(level() * 100 + 0.5) .. "%" end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tabular = true,
                    opacity = function() return if muted() then 0.45 else 1 end,
                },
            },
            g.box {
                role = "button",
                name = "Mute",
                width = function() return 22 * f() end,
                height = function() return 22 * f() end,
                align = "center",
                justify = "center",
                on_click = function() audio.toggle_stream_mute(g.untracked(node)) end,
                g.icon {
                    width = function() return 16 * f() end,
                    height = function() return 16 * f() end,
                    icon = function() return if muted() then "sound-off" else "sound-on" end,
                    gradient_top = function() return if muted() then theme.gradient_top(theme.primary()) else theme.text_muted() end,
                    gradient_bottom = function() return if muted() then theme.gradient_bottom(theme.primary()) else theme.text_muted() end,
                },
            },
        }
    end

    -- ---- Wells ----------------------------------------------------------------

    local function well(title: string, items: () -> { any }, height: () -> number, row: any, empty: string?): any
        local function viewport(): number return height() - well_padding() * 2 - label_height() end
        local scroll = scroller_mod.new {
            viewport = viewport,
            content = function() return #items() * row_height() end,
            step = row_height,
            factor = f,
        }
        local node: { [any]: any } = {
            width = well_width,
            height = height,
            radius = function() return metrics_mod.inner_radius(m().radius_panel, panel_padding()) end,
            fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            transition = { height = "reflow" },
            -- The label of a well: its domain, in the technical voice, once.
            g.text {
                overlay = true,
                attach = "corner",
                offset_x = well_inset,
                offset_y = well_padding,
                text = title,
                color = theme.text_faint,
                font = typography.technical,
                size = function() return m().font_meta end,
                weight = typography.weight_label,
                tracking = typography.label_tracking,
            },
            g.box {
                overlay = true,
                attach = "corner",
                offset_y = function() return well_padding() + label_height() end,
                width = well_width,
                height = viewport,
                clip = true,
                scroll_y = scroll.offset,
                transition = { scroll_y = "reflow" },
                on_wheel = scroll.wheel,
                g.each {
                    overlay = true,
                    attach = "corner",
                    width = well_width,
                    items = items,
                    key = function(n: any) return n.id end,
                    row = row,
                },
                scroll.bar(function() return well_width() - 7 * f() end),
            },
        }
        -- It keeps its height with nothing in it, and says why it is empty
        -- rather than standing as a blank surface.
        if empty then
            table.insert(node, g.box {
                overlay = true,
                present = function() return #items() == 0 end,
                g.text {
                    text = empty,
                    color = theme.text_muted,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                },
            })
        end
        return g.capsule(node)
    end

    local function wells(): any
        return g.box {
            direction = "column",
            gap = well_spacing,
            well("OUTPUT", audio.outputs, outputs_height, device_row(audio.is_default_output, audio.set_default)),
            well("INPUT", audio.inputs, inputs_height, device_row(audio.is_default_input, audio.set_default)),
            well("APPLICATIONS", audio.streams, streams_height, stream_row, "Nothing is playing"),
        }
    end

    if bare then
        return {
            width = panel_width,
            height = panel_height,
            content = wells,
        }
    end

    -- ---- Capsule, thread, wells ---------------------------------------------------

    local capsule = capsule_mod.new(m)
    local function shown(): boolean return cell.open.value end
    local function curve(): string return if shown() then "pod_1" else "pod_retract_1" end

    local devices = g.capsule {
        name = "devices",
        role = "group",
        overlay = true,
        attach = if down then "below" else "above",
        present = function() return cell.open.value or cell.expanded() end,
        width = panel_width,
        height = panel_height,
        offset_y = function()
            if not shown() then return 0 end
            return if down then gap() else -gap()
        end,
        radius = function() return m().radius_panel end,
        growth = function() return if shown() then 1 else 0 end,
        bud = function() return if shown() then 0 else m().cell_height end,
        blur = performance.blurred,
        fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
        rim_top = theme.rim,
        rim_bottom = theme.line,
        on_press = function() end,
        on_click = function() end,
        transition = { growth = curve, bud = curve, offset_y = curve, height = "reflow" },
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = panel_padding,
            offset_y = panel_padding,
            opacity = function() return if shown() then 1 else 0 end,
            transition = { opacity = function() return if shown() then "pod_content_1" else "content_leave" end },
            wells(),
        },
    }

    local link = thread.new {
        vertical = true,
        overlay = true,
        attach = if down then "below-center" else "above-center",
        present = function() return cell.open.value or cell.expanded() end,
        length = gap,
        reversed = not down,
        shown = shown,
        timing = function() return "pod_thread_1" end,
        closing = function() return "pod_thread_close_1" end,
    }

    return {
        width = capsule_width,
        height = capsule_height,
        radius = function() return metrics_mod.radius_for(capsule_height(), m()) end,
        beyond = function() return gap() + panel_height() end,
        content = capsule.node,
        satellites = function() return { link, devices } end,
    }
end

return M
