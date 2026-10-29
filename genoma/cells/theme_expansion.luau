--!strict
-- The theme, opened (cells/theme/ThemeExpansion.qml at 60ca560): the
-- wallpapers, and under them where the palette comes from, which one it is,
-- and how the rest of the desktop looks. See docs/design/CELLS.md §07.
--
-- There is no preview and no "apply": choosing retints the shell while you
-- watch, and the shell itself is the only honest preview. A choice made here
-- writes the shared state (wallpaper.json, override.json); until the switch
-- Bioma on Quickshell is the one that acts on it (genoma/PORT.md).
--
-- The panel is the wallpapers, as a carousel or a grid. The source capsule
-- buds out of it, the palette out of the source on the horizontal thread,
-- and DESKTOP out of the source on the spine: icons, cursor, the wallpaper
-- folder and the applications the palette is carried to. A dropdown opens
-- its list over whatever lies beyond it, raised over the capsules.
--
-- Not yet: the keyboard travel (shell-wide, to come), the shell's icons
-- waiting for a restart, the failures of a template's render, a cursor
-- niri refused.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local wallpaper = require("services/wallpaper")
local looks = require("services/looks")
local templates = require("services/templates")
local segmented = require("components/segmented")
local scroller_mod = require("components/scroller")
local thread = require("components/thread")

local M = {}

local SCHEMES = {
    { key = "scheme-content", label = "Content" },
    { key = "scheme-expressive", label = "Expressive" },
    { key = "scheme-fidelity", label = "Fidelity" },
    { key = "scheme-fruit-salad", label = "Fruit salad" },
    { key = "scheme-monochrome", label = "Monochrome" },
    { key = "scheme-neutral", label = "Neutral" },
    { key = "scheme-rainbow", label = "Rainbow" },
    { key = "scheme-smart", label = "Smart" },
    { key = "scheme-tonal-spot", label = "Tonal spot" },
    { key = "scheme-vibrant", label = "Vibrant" },
}

local CLEAR = "#00000000"

function M.new(cell: any): any
    local function m(): any return cell.metrics() end
    local function f(): number return m().factor end
    local down = cell.edge ~= "bottom"

    -- ---- Measures ------------------------------------------------------------

    local function carousel_width(): number return 560 * f() end
    local function carousel_height(): number return 160 * f() end
    local function tile_width(): number return 320 * f() end
    local function tile_height(): number return 140 * f() end
    local function neighbour_width(): number return 100 * f() end
    local function pitch(): number return 10 * f() end
    local function tile_radius(): number return metrics_mod.shaped(10 * f()) end
    local function strip_width(): number return carousel_width() - 20 * f() end

    local function grid(): boolean return config.get("wallpaper.picker", "carousel") == "grid" end
    local COLUMNS, ROWS = 3, 3
    local function grid_inner(): number return carousel_width() - 20 * f() end
    local function grid_tile_width(): number return (grid_inner() - pitch() * (COLUMNS - 1)) / COLUMNS end
    local function grid_tile_height(): number return grid_tile_width() * tile_height() / tile_width() end
    local function grid_viewport(): number return grid_tile_height() * ROWS + pitch() * (ROWS - 1) end
    local function picker_height(): number
        return if grid() then grid_viewport() + 20 * f() else carousel_height()
    end

    local function capsule_width(): number return 268 * f() end
    local function capsule_height(): number return 96 * f() end
    local function gap(): number return m().gap end
    local function chip_size(): number return 20 * f() end
    local function chip_pitch(): number return 5 * f() end
    local function stack_spacing(): number return 12 * f() end
    local function dropdown_height(): number return 30 * f() end
    local function stack_top(): number
        return (capsule_height() - (chip_size() + stack_spacing() + dropdown_height())) / 2
    end
    local function desktop_padding(): number return 20 * f() end
    local function font_control(): number return math.round(12 * f()) end
    local function label_height(): number return math.ceil(font_control() * 1.2) end

    -- Every block is placed from the panel's top-left corner, where the
    -- carousel is: arithmetic, so a list knows where its dropdown will be
    -- while the capsule holding it is still growing.
    local function capsule_y(): number return picker_height() + gap() end
    local function desktop_y(): number return capsule_y() + capsule_height() + gap() end

    -- ---- Text ----------------------------------------------------------------

    local function control_text(props: { [any]: any }): any
        props.font = typography.technical
        props.size = font_control
        props.weight = typography.weight_label
        props.tracking = props.tracking or 0.04
        props.color = props.color or theme.text
        return g.text(props)
    end
    local function label(text: string | () -> string, extra: { [any]: any }?): any
        local props: { [any]: any } = { text = text, tracking = typography.label_tracking }
        if extra then for k, v in extra do props[k] = v end end
        return control_text(props)
    end
    local function control_width(text: string): number
        return g.text_width { text = text, font = typography.technical(), size = font_control(),
            weight = typography.weight_label, tracking = 0.04 }
    end

    -- ---- What the capsules are about -------------------------------------------

    local function from_wallpaper(): boolean return theme.source() == "matugen" end
    local function scheme(): string return config.get("theme.matugen.scheme", "scheme-tonal-spot") end
    local function options(): { any }
        if from_wallpaper() then return SCHEMES end
        local out = {}
        for _, p in theme.palettes() do table.insert(out, { key = p.file, label = p.name }) end
        return out
    end
    local function chosen(): string return if from_wallpaper() then scheme() else theme.manual_palette() end
    local function chosen_label(): string
        for _, o in options() do
            if o.key == chosen() then return o.label end
        end
        return chosen()
    end

    -- ---- The list a dropdown opens ---------------------------------------------
    --
    -- One at a time, since they all open in the same place: the palette's, the
    -- icon themes, the base under Bioma's, the cursors, or none. The list shown
    -- is kept while it closes, so it still has its rows until it is gone.

    local listing = g.signal("")
    local list_shown = g.signal("")
    local list_origin = g.signal({ x = 0, y = 0 })
    local list_out = g.signal(false)
    local putting_away: any = nil

    local function close_list() listing.value = "" end
    g.watch(function() return listing.value end, function(which: string)
        if putting_away then putting_away:stop() end
        putting_away = nil
        if which ~= "" then
            list_shown.value = which
            list_out.value = true
        else
            putting_away = g.after(timing.seconds.close + timing.seconds.content_fade, function()
                list_out.value = false
            end)
        end
    end)
    g.watch(function() return cell.open.value end, function(open: boolean)
        if not open then close_list() end
    end)
    -- A matugen method never stands open over a list of Bioma palettes.
    g.watch(from_wallpaper, function()
        if g.untracked(function() return listing.value end) == "palette" then close_list() end
    end)

    local function toggle_list(which: string, origin: () -> (number, number))
        if g.untracked(function() return listing.value end) == which then
            close_list()
            return
        end
        -- g.untracked hands back one value: the pair goes through a table.
        list_origin.value = g.untracked(function()
            local x, y = origin()
            return { x = x, y = y }
        end)
        listing.value = which
    end

    local function bioma_icons(): boolean return looks.is_slotted(looks.icons(), looks.icon_theme()) end

    local function list_options(): { any }
        local which = list_shown.value
        local out = {}
        if which == "palette" then return options() end
        if which == "icons" then
            for _, t in looks.icons() do table.insert(out, { key = t.id, label = t.name }) end
        elseif which == "base" then
            for _, t in looks.icons() do
                if not t.slotted then table.insert(out, { key = t.id, label = t.name }) end
            end
        elseif which == "cursor" then
            for _, t in looks.cursors() do table.insert(out, { key = t.id, label = t.name }) end
        end
        return out
    end
    local function list_chosen(): string
        local which = list_shown.value
        if which == "palette" then return chosen() end
        if which == "icons" then return looks.icon_theme() end
        if which == "base" then return looks.icon_base() end
        if which == "cursor" then return looks.cursor_theme() end
        return ""
    end
    local function list_choose(key: string)
        local which = g.untracked(function() return list_shown.value end)
        if which == "palette" then
            config.set(if g.untracked(from_wallpaper) then "theme.matugen.scheme" else "theme.palette", key)
        elseif which == "icons" then looks.set_icons(key)
        elseif which == "base" then looks.set_icon_base(key)
        elseif which == "cursor" then looks.set_cursor(key, 0) end
        close_list()
    end

    -- ---- A dropdown --------------------------------------------------------------

    local function chevron(): any
        return g.icon {
            width = function() return 9 * f() end,
            height = function() return 9 * f() end,
            icon = "chevron-down",
            color = function() return colour.alpha(theme.text(), 0.6) end,
        }
    end
    -- The width a dropdown takes for its label, at most `widest`.
    local function dropdown_width(text: string, widest: number?): number
        local natural = control_width(text) + 12 * f() * 2 + 7 * f() + 9 * f()
        return if widest then math.min(widest, natural) else natural
    end
    local function dropdown(text: () -> string, which: string, widest: (() -> number)?, origin: () -> (number, number)): any
        local hovered = g.signal(false)
        local function width(): number return dropdown_width(text(), if widest then widest() else nil) end
        return g.capsule {
            role = "button",
            width = width,
            height = dropdown_height,
            radius = function() return metrics_mod.radius_for(dropdown_height(), m()) end,
            fill = CLEAR,
            rim_top = function()
                if listing.value == which then return theme.primary() end
                return if hovered.value then theme.text() else theme.line()
            end,
            rim_bottom = function()
                if listing.value == which then return theme.primary() end
                return if hovered.value then theme.text() else theme.line()
            end,
            direction = "row",
            align = "center",
            justify = "center",
            gap = function() return 7 * f() end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function() toggle_list(which, origin) end,
            control_text {
                text = text,
                max_width = function() return math.max(0, width() - 12 * f() * 2 - 7 * f() - 9 * f()) end,
            },
            chevron(),
        }
    end

    -- ---- The carousel ------------------------------------------------------------
    --
    -- Stepping answers a gesture: the strip travels one place at the
    -- transition timing and is still again. Five places, clipped to the
    -- panel's inside, so the two beyond the neighbours are what a step
    -- brings in. A place is as wide as its distance from the centre says, so
    -- the wallpaper arriving grows while the one leaving shrinks: the
    -- movement itself rather than a slide with a swap at the end. Each picture
    -- keeps its place in the list by its path, and moves to the next one.

    local function slide(delta: number)
        if #g.untracked(wallpaper.entries) < 2 then return end
        wallpaper.step(delta)
    end

    local function place_width(k: number): number
        return if k == 0 then tile_width() else neighbour_width()
    end
    local function place_left(k: number): number
        -- The middle place centred in the strip, the others a pitch apart.
        local centre = strip_width() / 2
        if k == 0 then return centre - tile_width() / 2 end
        if k > 0 then
            return centre + tile_width() / 2 + pitch() + (k - 1) * (neighbour_width() + pitch())
        end
        return centre - tile_width() / 2 + k * (neighbour_width() + pitch())
    end

    local function places(): { any }
        local count = #wallpaper.entries()
        local out = {}
        for k = -2, 2 do
            local image = wallpaper.neighbour(k)
            if image ~= "" then
                -- A short list repeats itself: the key carries the place then.
                table.insert(out, { k = k, image = image, key = if count >= 5 then image else image .. "#" .. k })
            end
        end
        return out
    end

    local function lit_rim(width: () -> number, height: () -> number, lit: () -> number): any
        return g.capsule {
            overlay = true,
            attach = "corner",
            width = width,
            height = height,
            radius = tile_radius,
            fill = CLEAR,
            opacity = lit,
            transition = { opacity = "transition", width = "transition" },
        }
    end

    local strip = g.box {
        overlay = true,
        attach = "corner",
        offset_y = function() return (picker_height() - 20 * f() - tile_height()) / 2 end,
        width = strip_width,
        height = tile_height,
        clip = true,
        opacity = function() return if grid() then 0 else 1 end,
        transition = { opacity = "content_fade" },
        g.each {
            overlay = true,
            attach = "corner",
            width = strip_width,
            height = tile_height,
            items = function() return if cell.expanded() then places() else {} end end,
            key = function(p: any) return p.key end,
            row = function(place: () -> any)
                local function k(): number return place().k end
                local function closeness(): number return if k() == 0 then 1 else 0 end
                return g.box {
                    role = "button",
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return place_left(k()) end,
                    width = function() return place_width(k()) end,
                    height = tile_height,
                    opacity = function() return 0.40 + 0.60 * closeness() end,
                    transition = { offset_x = "transition", width = "transition", opacity = "transition" },
                    on_click = function()
                        local at = g.untracked(k)
                        if math.abs(at) == 1 then slide(at) end
                    end,
                    g.image {
                        overlay = true,
                        attach = "corner",
                        width = function() return place_width(k()) end,
                        height = tile_height,
                        radius = tile_radius,
                        -- Decoded once at the middle place's size: bound to the
                        -- moving width it would be a decode every frame.
                        decode_width = tile_width,
                        decode_height = tile_height,
                        src = function() return wallpaper.thumbnail(place().image) end,
                        fit = "cover",
                        transition = { width = "transition" },
                    },
                    lit_rim(function() return place_width(k()) end, tile_height, closeness),
                }
            end,
        },
    }

    -- ---- The grid -----------------------------------------------------------------
    --
    -- Every image at once, three to a row, three rows in view and the rest a
    -- scroll away. Built only while it is wanted or still fading: a hundred
    -- decoded thumbnails behind a carousel are memory spent on nothing.

    local grid_alive = g.signal(g.untracked(grid))
    g.watch(grid, function(on: boolean)
        if on then grid_alive.value = true
        else g.after(timing.seconds.content_fade, function()
            if not g.untracked(grid) then grid_alive.value = false end
        end) end
    end)

    local function switch_height(): number return 22 * f() + 6 * f() end
    local function grid_content(): number
        local rows = math.ceil(#wallpaper.entries() / COLUMNS)
        return rows * (grid_tile_height() + pitch()) - pitch() + switch_height() + pitch()
    end
    local scroll = scroller_mod.new {
        viewport = grid_viewport,
        content = grid_content,
        step = function() return grid_tile_height() + pitch() end,
        factor = f,
    }
    -- Opened on the one on screen, wherever it is in the list.
    local function reveal_current()
        local i = g.untracked(wallpaper.index)
        if i == 0 then return end
        local row = (i - 1) // COLUMNS
        scroll.reveal(row * (g.untracked(grid_tile_height) + g.untracked(pitch)), g.untracked(grid_tile_height))
    end
    g.watch(function() return cell.open.value and grid() end, function(on: boolean)
        if on then reveal_current() end
    end)

    local function grid_tile(path: () -> string, index: () -> number): any
        local hovered = g.signal(false)
        local star_hovered = g.signal(false)
        local function current(): boolean return wallpaper.current() == path() end
        local function liked(): boolean return wallpaper.is_favourite(path()) end
        return g.box {
            role = "button",
            overlay = true,
            attach = "corner",
            offset_x = function() return ((index() - 1) % COLUMNS) * (grid_tile_width() + pitch()) end,
            offset_y = function() return ((index() - 1) // COLUMNS) * (grid_tile_height() + pitch()) end,
            width = grid_tile_width,
            height = grid_tile_height,
            opacity = function() return if current() or hovered.value then 1 else 0.6 end,
            transition = { opacity = "content_fade" },
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function() wallpaper.set_path(g.untracked(path)) end,
            g.image {
                overlay = true,
                attach = "corner",
                width = grid_tile_width,
                height = grid_tile_height,
                radius = tile_radius,
                src = function() return wallpaper.thumbnail(path()) end,
                fit = "cover",
            },
            lit_rim(grid_tile_width, grid_tile_height, function() return if current() then 1 else 0 end),
            -- A favourite, kept at the top of the list: always there on one,
            -- lit in the primary; on the others only under the pointer. On a
            -- disc of the background, or it is lost in the picture's corner.
            -- Raised: a shape is drawn before every picture on its layer, and
            -- the disc belongs over its own.
            g.capsule {
                role = "button",
                overlay = true,
                attach = "corner",
                raised = true,
                present = function() return liked() or hovered.value or star_hovered.value end,
                offset_x = function() return grid_tile_width() - 6 * f() - 28 * f() end,
                offset_y = function() return 6 * f() end,
                width = function() return 28 * f() end,
                height = function() return 28 * f() end,
                fill = function() return colour.alpha(theme.background(), 0.72) end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                align = "center",
                justify = "center",
                on_hover = function(on: boolean) star_hovered.value = on end,
                on_click = function() wallpaper.favour(g.untracked(path), not g.untracked(liked)) end,
                g.icon {
                    present = function() return not liked() end,
                    width = function() return 18 * f() end,
                    height = function() return 18 * f() end,
                    icon = "star",
                    color = function() return if star_hovered.value then theme.primary() else theme.text() end,
                },
                g.icon {
                    present = liked,
                    width = function() return 18 * f() end,
                    height = function() return 18 * f() end,
                    icon = "star-filled",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                },
            },
        }
    end

    local grid_node = g.box {
        overlay = true,
        attach = "corner",
        present = function() return grid_alive.value end,
        width = grid_inner,
        height = grid_viewport,
        clip = true,
        opacity = function() return if grid() then 1 else 0 end,
        transition = { opacity = "content_fade", scroll_y = "reflow" },
        scroll_y = scroll.offset,
        on_wheel = scroll.wheel,
        g.each {
            overlay = true,
            attach = "corner",
            width = grid_inner,
            -- Only while the cell is out: closed, eighty pictures' nodes were
            -- laid out on every frame the clock's hand moved.
            items = function() return if cell.expanded() then wallpaper.entries() else {} end end,
            key = function(p: string) return p end,
            row = grid_tile,
        },
        scroll.bar(function() return grid_inner() - 3 * f() end),
    }

    -- Carousel or grid, in the corner away from the thread and the same in
    -- both: a control that moved when it was used would have to be found again.
    local picker_switch = segmented.new {
        metrics = m,
        options = function() return { { key = "carousel", icon = "carousel" }, { key = "grid", icon = "grid" } } end,
        current = function() return if grid() then "grid" else "carousel" end,
        on_choose = function(key: string) config.set("wallpaper.picker", key) end,
        button_height = function() return 22 * f() end,
        icon_size = function() return 13 * f() end,
        icon_padding = function() return 7 * f() end,
    }

    local function content(): any
        return g.box {
            width = function() return carousel_width() - 20 * f() end,
            height = function() return picker_height() - 20 * f() end,
            transition = { height = "transition" },
            on_wheel = function(_: number, dy: number)
                if g.untracked(grid) then return end
                if dy > 0 then slide(1) elseif dy < 0 then slide(-1) end
            end,
            strip,
            grid_node,
            -- An empty folder is not a broken cell: it says where it looked.
            g.text {
                overlay = true,
                present = function() return #wallpaper.entries() == 0 end,
                text = function() return "No images in " .. wallpaper.folder() end,
                color = theme.text_muted,
                font = typography.expressive,
                size = function() return m().font_title end,
            },
            g.box {
                overlay = true,
                attach = "corner",
                width = function() return carousel_width() - 20 * f() end,
                height = function() return picker_height() - 20 * f() end,
                direction = "row",
                justify = "end",
                align = if down then "end" else "start",
                -- Over the pictures, as QML's z: 2: raised, since a shape is
                -- otherwise drawn under every image on its layer.
                g.box { raised = true, picker_switch },
            },
        }
    end

    -- ---- The capsules ---------------------------------------------------------------

    local function shown(): boolean return cell.open.value end
    local function budding(order: number, node: { [any]: any }): any
        local function curve(): string return if shown() then "pod_" .. order else "pod_retract_" .. order end
        node.overlay = true
        node.growth = function() return if shown() then 1 else 0 end
        node.bud = function() return if shown() then 0 else m().cell_height end
        node.blur = true
        node.fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end
        node.rim_top = theme.rim
        node.rim_bottom = theme.line
        node.on_press = function() end
        node.transition = { growth = curve, bud = curve, offset_x = curve, offset_y = curve, height = "reflow" }
        return g.capsule(node)
    end
    local function content_of(order: number, node: { [any]: any }): any
        node.opacity = function() return if shown() then 1 else 0 end
        node.transition = { opacity = function() return if shown() then "pod_content_" .. order else "content_leave" end }
        return g.box(node)
    end
    local function link(order: number, node: { [any]: any }): any
        node.overlay = true
        node.length = gap
        node.shown = shown
        node.timing = function() return "pod_thread_" .. order end
        node.closing = function() return "pod_thread_close_" .. order end
        return thread.new(node)
    end

    local function pill_radius(): number return metrics_mod.radius_for(capsule_height(), m()) end

    -- ---- Source -----------------------------------------------------------------------

    local source_content = content_of(1, {
        width = capsule_width,
        height = capsule_height,
        direction = "column",
        align = "center",
        justify = "center",
        gap = stack_spacing,
        label("SOURCE"),
        segmented.new {
            metrics = m,
            font_size = font_control,
            options = function() return { { key = "matugen", label = "matugen" }, { key = "manual", label = "Bioma" } } end,
            current = theme.source,
            on_choose = function(key: string)
                config.set("theme.source", key)
                close_list()
            end,
        },
    })

    -- ---- What comes out of it ------------------------------------------------------------

    local chips: { [any]: any } = { direction = "row", gap = chip_pitch }
    for i = 1, 7 do
        table.insert(chips, g.capsule {
            width = chip_size,
            height = chip_size,
            radius = function() return metrics_mod.shaped(5 * f()) end,
            fill = function() return theme.target_roles()[i] end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            transition = { fill = "chip_" .. i },
        })
    end
    local function palette_origin(): (number, number)
        return capsule_width() + gap() + capsule_width() / 2,
            capsule_y() + stack_top() + chip_size() + stack_spacing() + dropdown_height()
    end
    local palette_content = content_of(2, {
        width = capsule_width,
        height = capsule_height,
        direction = "column",
        align = "center",
        justify = "center",
        gap = stack_spacing,
        g.box(chips),
        dropdown(chosen_label, "palette", nil, palette_origin),
    })

    -- ---- How the desktop looks ---------------------------------------------------------------

    local function widest(): number return 164 * f() end
    local function icons_label(): string return looks.name_of(looks.icons(), looks.icon_theme()) end
    local function base_label(): string return looks.name_of(looks.icons(), looks.icon_base()) end
    local function cursor_label(): string return looks.name_of(looks.cursors(), looks.cursor_theme()) end
    local function column_one_width(): number
        local w = math.max(control_width("ICONS"), dropdown_width(icons_label(), widest()))
        if bioma_icons() then w = math.max(w, control_width("BASE"), dropdown_width(base_label(), widest())) end
        return w
    end
    local function looks_top(): number return desktop_y() + desktop_padding() + label_height() + stack_spacing() end
    local function icons_origin(): (number, number)
        return desktop_padding() + dropdown_width(icons_label(), widest()) / 2, looks_top() + dropdown_height()
    end
    local function base_origin(): (number, number)
        local below = looks_top() + dropdown_height() + stack_spacing() + (20 * f() - stack_spacing())
            + label_height() + stack_spacing()
        return desktop_padding() + dropdown_width(base_label(), widest()) / 2, below + dropdown_height()
    end
    local function segmented_height(): number return 26 * f() + 6 * f() end
    local function cursor_origin(): (number, number)
        local x = desktop_padding() + column_one_width() + 24 * f()
        local row = math.max(dropdown_height(), segmented_height())
        return x + dropdown_width(cursor_label(), widest()) / 2, looks_top() + (row + dropdown_height()) / 2
    end

    local function looks_height(): number
        local one = label_height() + stack_spacing() + dropdown_height()
        if bioma_icons() then
            one += stack_spacing() + (20 * f() - stack_spacing()) + label_height() + stack_spacing() + dropdown_height()
        end
        local two = label_height() + stack_spacing() + math.max(dropdown_height(), segmented_height())
        return math.max(one, two)
    end
    local function inner_width(): number return carousel_width() - desktop_padding() * 2 end

    -- The applications, wrapped into rows inside the capsule's width, as a
    -- flow lays them out.
    local function chip_width(entry: any): number
        return g.text_width { text = entry.name or "", font = typography.technical(), size = m().font_meta,
            tracking = typography.label_tracking } + 24 * f()
    end
    local function app_rows(): { { any } }
        local rows, row, used = {}, {}, 0
        local spacing = 6 * f()
        for _, entry in templates.catalogue() do
            local w = chip_width(entry)
            if #row > 0 and used + spacing + w > inner_width() then
                table.insert(rows, row)
                row, used = {}, 0
            end
            used += (if #row > 0 then spacing else 0) + w
            table.insert(row, entry)
        end
        if #row > 0 then table.insert(rows, row) end
        return rows
    end
    local function apps_height(): number
        local n = #app_rows()
        return if n == 0 then 0 else n * 24 * f() + (n - 1) * 6 * f()
    end
    local function desktop_height(): number
        local d = desktop_padding()
        return d + looks_height() + 20 * f() + (label_height() + stack_spacing() + dropdown_height())
            + 20 * f() + (label_height() + stack_spacing() + apps_height()) + d
    end

    -- One application: lit when the palette goes to it; one not on this
    -- machine is dimmed and can only be switched off, if it was on before.
    local function app_chip(entry: () -> any): any
        local hovered = g.signal(false)
        local function on(): boolean return templates.is_on(entry().id) end
        local function here(): boolean return entry().installed == true end
        return g.capsule {
            role = "button",
            width = function() return chip_width(entry()) end,
            height = function() return 24 * f() end,
            radius = function() return metrics_mod.radius_for(24 * f(), m()) end,
            opacity = function() return if here() or on() then 1 else 0.35 end,
            fill = function() return if on() then colour.alpha(theme.primary(), 0.16) else CLEAR end,
            rim_top = function()
                if on() then return theme.primary() end
                return if hovered.value and here() then theme.text() else theme.line()
            end,
            rim_bottom = function()
                if on() then return theme.primary() end
                return if hovered.value and here() then theme.text() else theme.line()
            end,
            align = "center",
            justify = "center",
            on_hover = function(v: boolean) hovered.value = v end,
            on_click = function()
                if g.untracked(here) or g.untracked(on) then
                    templates.set_on(g.untracked(entry).id, not g.untracked(on))
                end
            end,
            g.text {
                text = function() return entry().name or "" end,
                color = function() return if on() then theme.text() else theme.text_muted() end,
                font = typography.technical,
                size = function() return m().font_meta end,
                tracking = typography.label_tracking,
            },
        }
    end

    local function short_path(path: string): string
        local home = g.env("HOME") or ""
        if home ~= "" and string.sub(path, 1, #home) == home then return "~" .. string.sub(path, #home + 1) end
        return path
    end
    local folder_hovered = g.signal(false)
    local folder_box = g.capsule {
        role = "button",
        width = inner_width,
        height = dropdown_height,
        radius = function() return metrics_mod.radius_for(dropdown_height(), m()) end,
        fill = CLEAR,
        rim_top = function()
            if wallpaper.picking() then return theme.primary() end
            return if folder_hovered.value then theme.text() else theme.line()
        end,
        rim_bottom = function()
            if wallpaper.picking() then return theme.primary() end
            return if folder_hovered.value then theme.text() else theme.line()
        end,
        direction = "row",
        align = "center",
        justify = "between",
        padding_x = function() return 12 * f() end,
        on_hover = function(on: boolean) folder_hovered.value = on end,
        -- The cell closes first: while it is open the shell holds the
        -- keyboard and the picker would be a window nobody can type into.
        on_click = function()
            cell.open.value = false
            wallpaper.pick_folder()
        end,
        control_text {
            text = function() return short_path(wallpaper.folder()) end,
            max_width = function() return inner_width() - 24 * f() - 7 * f() - 11 * f() end,
        },
        g.icon {
            width = function() return 11 * f() end,
            height = function() return 11 * f() end,
            icon = "edit",
            color = function() return if folder_hovered.value then theme.text() else colour.alpha(theme.text(), 0.6) end,
        },
    }

    local desktop_content = content_of(3, {
        overlay = true,
        attach = "corner",
        offset_x = desktop_padding,
        offset_y = desktop_padding,
        width = inner_width,
        direction = "column",
        align = "start",
        gap = function() return 20 * f() end,
        g.box {
            direction = "row",
            align = "start",
            gap = function() return 24 * f() end,
            g.box {
                direction = "column",
                align = "start",
                gap = stack_spacing,
                width = column_one_width,
                label("ICONS"),
                dropdown(icons_label, "icons", widest, icons_origin),
                g.box { present = bioma_icons, height = function() return 20 * f() - 2 * stack_spacing() end },
                label("BASE", { present = bioma_icons }),
                g.box {
                    present = bioma_icons,
                    dropdown(base_label, "base", widest, base_origin),
                },
            },
            g.box {
                direction = "column",
                align = "start",
                gap = stack_spacing,
                label("CURSOR"),
                g.box {
                    direction = "row",
                    align = "center",
                    gap = function() return 8 * f() end,
                    dropdown(cursor_label, "cursor", widest, cursor_origin),
                    segmented.new {
                        metrics = m,
                        font_size = font_control,
                        options = function()
                            local out = {}
                            for _, size in looks.sizes() do table.insert(out, { key = tostring(size), label = tostring(size) }) end
                            return out
                        end,
                        current = function() return tostring(looks.cursor_size()) end,
                        on_choose = function(key: string) looks.set_cursor("", tonumber(key) or 0) end,
                    },
                },
            },
        },
        g.box {
            direction = "column",
            align = "start",
            gap = stack_spacing,
            g.box {
                direction = "row",
                gap = function() return 8 * f() end,
                label("WALLPAPER FOLDER"),
                label(function() return "· " .. wallpaper.folder_error() end, {
                    present = function() return wallpaper.folder_error() ~= "" end,
                    color = theme.alert,
                }),
            },
            folder_box,
        },
        g.box {
            direction = "column",
            align = "start",
            gap = stack_spacing,
            label("APP TEMPLATES"),
            g.each {
                direction = "column",
                align = "start",
                gap = function() return 6 * f() end,
                items = function()
                    local rows = {}
                    for i, row in app_rows() do
                        local ids = {}
                        for _, e in row do table.insert(ids, e.id) end
                        table.insert(rows, { key = i .. ":" .. table.concat(ids, ","), entries = row })
                    end
                    return rows
                end,
                key = function(r: any) return r.key end,
                row = function(r: () -> any)
                    return g.each {
                        direction = "row",
                        gap = function() return 6 * f() end,
                        items = function() return r().entries end,
                        key = function(e: any) return e.id end,
                        row = app_chip,
                    }
                end,
            },
        },
    })

    -- ---- The list's shape ---------------------------------------------------------------

    local function list_row(): number return m().row_height end
    local function list_padding(): number return 6 * f() end
    local LIST_ROWS = 8
    local function list_width(): number
        return if list_shown.value == "palette" then capsule_width() - 40 * f() else 300 * f()
    end
    local function list_view(): number return math.min(#list_options(), LIST_ROWS) * list_row() end
    local function list_height(): number return list_view() + list_padding() * 2 end
    local list_scroll = scroller_mod.new {
        viewport = list_view,
        content = function() return #list_options() * list_row() end,
        step = list_row,
        factor = f,
    }
    -- Opened on a long list, the choice is where the eye is.
    g.watch(function() return list_shown.value end, function()
        list_scroll.to(0)
        local opts = g.untracked(list_options)
        local at = 0
        for i, o in opts do
            if o.key == g.untracked(list_chosen) then at = i end
        end
        if at > 0 then list_scroll.reveal((at - 1) * g.untracked(list_row), g.untracked(list_row)) end
    end)

    local function list_row_node(option: () -> any, index: () -> number): any
        local function current(): boolean return option().key == list_chosen() end
        return g.box {
            role = "button",
            overlay = true,
            attach = "corner",
            offset_y = function() return (index() - 1) * list_row() end,
            width = function() return list_width() - list_padding() * 2 end,
            height = list_row,
            direction = "row",
            align = "center",
            justify = "between",
            padding_x = function() return 6 * f() end,
            on_click = function() list_choose(g.untracked(option).key) end,
            control_text {
                text = function() return option().label end,
                color = function() return if current() then theme.text() else theme.text_muted() end,
                max_width = function() return list_width() - list_padding() * 2 - 24 * f() end,
            },
            -- The choice is exclusive, so the mark may be a dot.
            g.capsule {
                present = current,
                width = function() return 6 * f() end,
                height = function() return 6 * f() end,
                fill = theme.primary,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
            },
        }
    end

    local function list_growing(): boolean return listing.value ~= "" end
    local list = g.capsule {
        name = "list",
        role = "group",
        overlay = true,
        attach = "corner",
        raised = true,
        present = function() return list_out.value end,
        -- Born from its dropdown's edge and settled just past it, over
        -- whatever lies beyond, away from the cell.
        offset_x = function()
            local w = list_width()
            return math.clamp(list_origin.value.x - w / 2, 0, math.max(0, carousel_width() - w))
        end,
        offset_y = function()
            local o = list_origin.value.y
            return if down then o + 8 * f() else o - dropdown_height() - 8 * f() - list_height()
        end,
        width = list_width,
        height = list_height,
        radius = function() return m().radius_well end,
        growth = function() return if list_growing() then 1 else 0 end,
        transition = { growth = function() return if list_growing() then "grow" else "close" end },
        blur = true,
        fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
        rim_top = theme.rim,
        rim_bottom = theme.line,
        on_press = function() end,
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = list_padding,
            offset_y = list_padding,
            width = function() return list_width() - list_padding() * 2 end,
            height = list_view,
            clip = true,
            scroll_y = list_scroll.offset,
            transition = { scroll_y = "reflow" },
            on_wheel = list_scroll.wheel,
            opacity = function() return if list_growing() then 1 else 0 end,
            g.each {
                overlay = true,
                attach = "corner",
                width = function() return list_width() - list_padding() * 2 end,
                items = list_options,
                key = function(o: any) return o.key end,
                row = list_row_node,
            },
            list_scroll.bar(function() return list_width() - list_padding() * 2 - 3 * f() end),
        },
    }

    -- ---- The composition -------------------------------------------------------------------

    local palette_capsule = budding(2, {
        name = "palette",
        attach = "right",
        width = capsule_width,
        height = capsule_height,
        radius = pill_radius,
        offset_x = function() return if shown() then gap() else 0 end,
        palette_content,
    })
    local desktop_panel = budding(3, {
        name = "desktop",
        attach = if down then "below" else "above",
        width = carousel_width,
        height = desktop_height,
        radius = function() return m().radius_panel end,
        offset_y = function()
            if not shown() then return 0 end
            return if down then gap() else -gap()
        end,
        desktop_content,
    })
    local source_capsule = budding(1, {
        name = "source",
        attach = if down then "below" else "above",
        width = capsule_width,
        height = capsule_height,
        radius = pill_radius,
        offset_y = function()
            if not shown() then return 0 end
            return if down then gap() else -gap()
        end,
        source_content,
        -- The palette hangs off the source on the horizontal thread, and
        -- DESKTOP off it on the spine.
        link(2, { vertical = false, attach = "right" }),
        palette_capsule,
        link(3, { vertical = true, attach = if down then "below-center" else "above-center", reversed = not down }),
        desktop_panel,
    })

    local spec = {
        width = carousel_width,
        height = picker_height,
        beyond = function() return gap() + capsule_height() + gap() + desktop_height() end,
        content = content,
        satellites = function()
            return {
                -- The spine from the wallpapers to the source, at the source's
                -- middle.
                link(1, {
                    vertical = true,
                    attach = if down then "below" else "above",
                    offset_x = function() return capsule_width() / 2 - metrics_mod.node_size end,
                    reversed = not down,
                }),
                source_capsule,
                list,
            }
        end,
    }

    local function on_key(name: string): boolean
        if name == "Escape" and g.untracked(function() return listing.value end) ~= "" then
            close_list()
            return true
        end
        return false
    end

    return { panel = spec, on_key = on_key }
end

return M
