--!strict
-- The media cell, opened (cells/media/MediaExpansion.qml at 60ca560): the
-- band with room, and the track hung underneath it. See
-- docs/design/CELLS.md §04.
--
-- The track hangs from the visualiser, not the other way round: sound is
-- always there and a track only sometimes, so the thread says which holds
-- the other. With no MPRIS source the track does not exist rather than
-- standing empty; it buds and goes as a track comes and ends, without the
-- cell closing.
--
-- Not yet: the keyboard travel through the controls (shell-wide, to come).
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local media = require("services/media")
local sinestesia = require("services/sinestesia")
local band = require("components/band")
local thread = require("components/thread")

local BARS = 34

local M = {}

function M.new(cell: any): any
    local function m(): any return cell.metrics() end
    local function f(): number return m().factor end
    local down = cell.edge ~= "bottom"

    local function capsule_width(): number return 372 * f() end
    local function capsule_height(): number return 88 * f() end
    local function panel_height(): number return 164 * f() end
    local function gap(): number return m().gap end
    local function inset(): number return 10 * f() end
    local function cover(): number return 88 * f() end
    local function column(): number return capsule_width() - inset() * 2 - cover() - 16 * f() end
    local function beside(): number return cover() + 16 * f() end

    -- The track is there while the cell is open and something names it.
    local function has_track(): boolean return media.has_metadata() end
    local function shown(): boolean return cell.open.value and has_track() end
    local function curve(): string return if shown() then "pod_1" else "pod_retract_1" end

    local band_left = g.computed(function() return sinestesia.fold(sinestesia.left(), BARS // 2) end)
    local band_right = g.computed(function() return sinestesia.fold(sinestesia.right(), BARS // 2) end)

    local function content(): any
        return band.new {
            left = function() return band_left.value end,
            right = function() return band_right.value end,
            count = function() return BARS end,
            bar_width = function() return 4 * f() end,
            pitch = function() return 8 * f() end,
            base = theme.primary,
            effect = sinestesia.effect,
            width = function() return 268 * f() end,
            height = function() return 52 * f() end,
        }
    end

    -- Placed from the panel's top-left corner, as the QML places it.
    local function at(x: () -> number, y: () -> number, node: { [any]: any }): { [any]: any }
        node.overlay = true
        node.attach = "corner"
        node.offset_x = x
        node.offset_y = y
        return node
    end

    local function technical_meta(text: () -> string): any
        return g.text {
            text = text,
            color = theme.text_muted,
            font = typography.technical,
            size = function() return m().font_meta end,
            weight = typography.weight_secondary,
            tabular = true,
        }
    end

    -- The one that acts is filled and larger; the two that step are rings.
    -- A control is not a surface: the filled one carries the primary
    -- gradient.
    local function step(glyph: string, enabled: () -> boolean, act: () -> ()): any
        return g.capsule {
            role = "button",
            width = function() return 36 * f() end,
            height = function() return 36 * f() end,
            fill = "#00000000",
            rim_top = theme.line,
            rim_bottom = theme.line,
            align = "center",
            justify = "center",
            opacity = function() return if enabled() then 1 else 0.38 end,
            on_click = function() if g.untracked(enabled) then act() end end,
            g.icon {
                width = function() return 16 * f() end,
                height = function() return 16 * f() end,
                icon = glyph,
                color = theme.text,
            },
        }
    end

    local function toggles(): boolean return media.can_toggle() or media.can_play() end

    local transport = g.box {
        direction = "row",
        align = "center",
        gap = function() return 14 * f() end,
        step("skip-previous", media.can_go_previous, media.previous),
        g.capsule {
            role = "button",
            width = function() return 44 * f() end,
            height = function() return 44 * f() end,
            fill = function() return theme.gradient_top(theme.primary()) end,
            fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            align = "center",
            justify = "center",
            on_click = function() if g.untracked(toggles) then media.play_pause() end end,
            g.icon {
                width = function() return 18 * f() end,
                height = function() return 18 * f() end,
                icon = function() return if media.playing() then "pause" else "play" end,
                color = theme.background,
            },
        },
        step("skip-next", media.can_go_next, media.next),
    }
    local function transport_width(): number return (36 + 14 + 44 + 14 + 36) * f() end

    -- The selector appears only with more than one source, and changes only
    -- this panel: the band is the whole machine. One press, the next source:
    -- a list of two is a menu nobody needs.
    local function chosen(): string
        local identity = media.identity()
        return if identity ~= "" then identity else "Player"
    end
    local function chooser_pad(): number return 12 * f() end
    local function arrow(): number return 9 * f() end
    local function chooser_room(): number return column() - transport_width() - 14 * f() end
    local function chooser_width(): number
        local natural = g.text_width { text = chosen(), font = typography.expressive(), size = m().font_secondary }
            + chooser_pad() * 2 + 7 * f() + arrow()
        return math.min(natural, chooser_room())
    end
    local function next_player()
        local players = g.untracked(media.players)
        if #players < 2 then return end
        -- By name: each reading of the players is a new list of new tables.
        local current = g.untracked(media.player)
        local here = 0
        for i, p in players do
            if current and p.name == current.name then here = i end
        end
        local following = players[here % #players + 1]
        if following then media.select(following.name) end
    end
    local chooser = g.capsule {
        role = "button",
        present = function() return media.count() > 1 and chooser_room() > 60 * f() end,
        width = chooser_width,
        height = function() return 30 * f() end,
        radius = function() return metrics_mod.radius_for(30 * f(), m()) end,
        fill = "#00000000",
        rim_top = theme.line,
        rim_bottom = theme.line,
        direction = "row",
        align = "center",
        justify = "center",
        gap = function() return 7 * f() end,
        on_click = next_player,
        g.text {
            text = chosen,
            color = theme.text,
            font = typography.expressive,
            size = function() return m().font_secondary end,
            max_width = function() return math.max(0, chooser_width() - chooser_pad() * 2 - 7 * f() - arrow()) end,
        },
        g.icon {
            width = arrow,
            height = arrow,
            icon = "chevron-down",
            color = function() return colour.alpha(theme.text(), 0.6) end,
        },
    }

    -- Where the track is. The node rides the line's head: a bar without a
    -- head says how much rather than where.
    local function line(): number return 3 * f() end
    local function elapsed(): number return column() * math.clamp(media.progress(), 0, 1) end
    local progress = g.box {
        role = "slider",
        present = media.has_length,
        width = column,
        height = function() return 14 * f() end,
        on_click = function(_: number, x: number)
            if g.untracked(media.can_seek) then
                media.seek_to(g.untracked(media.length) * math.clamp(x / g.untracked(column), 0, 1))
            end
        end,
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_y = function() return (14 * f() - line()) / 2 end,
            width = column,
            height = line,
            radius = function() return metrics_mod.shaped(line() / 2) end,
            fill = function() return colour.alpha(theme.line(), 0.55) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_y = function() return (14 * f() - line()) / 2 end,
            width = elapsed,
            height = line,
            radius = function() return metrics_mod.shaped(line() / 2) end,
            fill = function() return theme.gradient_top(theme.primary()) end,
            fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            fill_across = true,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() return elapsed() - 3.5 * f() end,
            offset_y = function() return (14 * f() - 7 * f()) / 2 end,
            width = function() return 7 * f() end,
            height = function() return 7 * f() end,
            fill = function() return theme.gradient_top(theme.primary()) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
    }

    -- The cover, concentric inside the panel. The artwork belongs to the
    -- record, not the palette, so it is not tinted; without one the well
    -- stands with the cell's own glyph, which follows the palette (not
    -- Bioma's mark: a record without a picture is not the shell
    -- introducing itself).
    local function art_radius(): number return metrics_mod.inner_radius(m().radius_panel, inset()) end
    local function has_art(): boolean return media.art_path() ~= "" end
    local art = g.box {
        width = cover,
        height = cover,
        g.capsule {
            overlay = true,
            attach = "corner",
            present = function() return not has_art() end,
            width = cover,
            height = cover,
            radius = art_radius,
            fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
            rim_top = "#00000000",
            rim_bottom = "#00000000",
            align = "center",
            justify = "center",
            g.icon {
                width = function() return cover() * 0.4 end,
                height = function() return cover() * 0.4 end,
                icon = "sinestesia",
                color = theme.text_muted,
            },
        },
        g.image {
            overlay = true,
            attach = "corner",
            present = has_art,
            width = cover,
            height = cover,
            radius = art_radius,
            src = media.art_path,
            fit = "cover",
        },
    }

    -- Title, then who made it: human language, the expressive face.
    local function subtitle(): string
        local artist, album = media.artist(), media.album()
        if artist ~= "" and album ~= "" then return artist .. " · " .. album end
        return if artist ~= "" then artist else album
    end
    local names = g.box {
        direction = "column",
        align = "start",
        gap = function() return 2 * f() end,
        g.text {
            text = media.title,
            color = theme.text,
            font = typography.expressive,
            size = function() return math.floor(19 * f() + 0.5) end,
            max_width = column,
        },
        g.text {
            text = subtitle,
            color = theme.text_muted,
            font = typography.expressive,
            size = function() return math.floor(15 * f() + 0.5) end,
            max_width = column,
        },
    }

    local function zero(): number return 0 end
    local track = g.capsule {
        name = "track",
        role = "group",
        overlay = true,
        attach = if down then "below" else "above",
        present = function() return has_track() or cell.open.value end,
        width = capsule_width,
        height = panel_height,
        offset_y = function()
            if not shown() then return 0 end
            return if down then gap() else -gap()
        end,
        radius = function() return m().radius_panel end,
        growth = function() return if shown() then 1 else 0 end,
        bud = function() return if shown() then 0 else m().cell_height end,
        blur = true,
        fill = function() return colour.alpha(theme.cell(), 0.72) end,
        rim_top = theme.rim,
        rim_bottom = theme.line,
        on_press = function() end,
        on_click = function() end,
        transition = { growth = curve, bud = curve, offset_y = curve },
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = inset,
            offset_y = inset,
            width = function() return capsule_width() - inset() * 2 end,
            height = function() return panel_height() - inset() * 2 end,
            opacity = function() return if shown() then 1 else 0 end,
            transition = { opacity = function() return if shown() then "pod_content_1" else "content_leave" end },
            at(zero, zero, art),
            at(beside, zero, names),
            at(beside, function() return 62 * f() end, progress),
            at(beside, function() return 78 * f() end, g.box {
                present = media.has_length,
                width = column,
                direction = "row",
                justify = "between",
                technical_meta(function() return media.format_time(media.position()) end),
                technical_meta(function() return media.format_time(media.length()) end),
            }),
            at(beside, function() return 104 * f() end, transport),
            at(function() return beside() + column() - chooser_width() end,
                function() return 104 * f() + (44 * f() - 30 * f()) / 2 end, chooser),
        },
    }

    -- The thread between the two belongs to the band, drawn out of it.
    local link = thread.new {
        vertical = true,
        overlay = true,
        attach = if down then "below-center" else "above-center",
        present = function() return has_track() or cell.open.value end,
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
        beyond = function() return if has_track() then gap() + panel_height() else 0 end,
        content = content,
        satellites = function() return { link, track } end,
    }
end

return M
