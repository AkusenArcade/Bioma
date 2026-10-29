--!strict
-- The sound leaving the machine, made visible, and when there is a track,
-- the track too (cells/media/MediaCell.qml at 60ca560). See
-- docs/design/CELLS.md §04.
--
-- The one cell where movement does not measure a load: it measures the
-- sound itself, the only reason it may move continuously at all. It exists
-- on the signal, not on playback: a browser video, a game and a music
-- player are the same thing to it, and when the sound stops it goes.
--
-- Two independent inputs, and that is the point. The band shows everything
-- leaving the machine (services/sinestesia.luau); the name beside it the
-- chosen MPRIS source (services/media.luau). Choosing another player does
-- not touch the band.
--
-- Pressed, it opens its expansion (cells/media_expansion.luau): the band
-- with room, and the track hung under it. The wheel does nothing on
-- purpose: volume is another cell.
local g = require("@genoma")
local theme = require("core/theme")
local typography = require("core/typography")
local timing = require("core/timing")
local audio = require("services/audio")
local media = require("services/media")
local sinestesia = require("services/sinestesia")
local band = require("components/band")
local expansion = require("cells/media_expansion")

local BARS = 14

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function band_width(): number return 81 * f() end
        local function band_height(): number return 22 * f() end
        local function spacing(): number return 14 * f() end

        -- The bands cost a process: it runs only while the cell is on
        -- screen, and whether it is is decided by the peak, which runs
        -- anyway.
        g.watch(function() return cell.placed.value end, function(placed: boolean)
            sinestesia.hold(cell, placed)
        end)

        -- Half the bars to a channel: the row is mirrored about its middle.
        local band_left = g.computed(function() return sinestesia.fold(sinestesia.left(), BARS // 2) end)
        local band_right = g.computed(function() return sinestesia.fold(sinestesia.right(), BARS // 2) end)

        -- What the cell says beside the band, only sometimes: without
        -- metadata the band stands alone and the cell narrows to it.
        local function track(): string
            if not media.has_metadata() then return "" end
            local artist = media.artist()
            return if artist ~= "" then media.title() .. " · " .. artist else media.title()
        end

        -- A track change is the window title's kind of event: the name waits
        -- out the debounce and crosses over, never swapped.
        local shown = g.signal(g.untracked(track))
        local visible = g.signal(true)
        local debounce: any = nil
        g.watch(track, function(text: string)
            if g.untracked(function() return shown.value end) == "" then
                shown.value = text
                return
            end
            if debounce then debounce:stop() end
            debounce = g.after(timing.seconds.debounce, function()
                if g.untracked(function() return shown.value end) == g.untracked(track) then return end
                visible.value = false
                g.after(timing.seconds.content_fade, function()
                    g.batch(function()
                        shown.value = g.untracked(track)
                        visible.value = true
                    end)
                end)
            end)
        end)

        local function size(): number return cell.metrics().font_title end
        local function named(): boolean return track() ~= "" end
        local function label_width(): number
            return g.text_width { text = shown.value, font = typography.expressive(), size = size() }
        end
        -- What the name may take once the band and the gap have theirs.
        local function available(): number return math.max(0, cell.room() - band_width() - spacing()) end
        -- A name needs room to be a name. Below it the band stands alone,
        -- centred in what the tissue gave: the answer for a track with no
        -- metadata, reached from the other side.
        local function shows_name(): boolean return named() and available() >= 60 * f() end

        return {
            panel = expansion.new(cell),
            padding_leading = 16,
            padding_trailing = 16,
            -- The signal and nothing else; the thresholds and the dwell are
            -- the configuration's, so the silence between two tracks does not
            -- make the cell flicker.
            condition = audio.peak,
            content_width = function()
                return band_width() + (if named() then spacing() + label_width() else 0)
            end,
            least_width = function() return band_width() + 32 * f() end,
            -- Open, it names itself.
            header_title = "MEDIA",
            header_mark_size = function() return 22 * f() end,
            header_mark = function(mark: () -> number)
                return g.icon {
                    width = mark,
                    height = mark,
                    icon = "sinestesia",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                }
            end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    offset_x = function()
                        return if shows_name() then 0 else math.max(0, (cell.room() - band_width()) / 2)
                    end,
                    band.new {
                        left = function() return band_left.value end,
                        right = function() return band_right.value end,
                        count = function() return BARS end,
                        bar_width = function() return 3 * f() end,
                        pitch = function() return 6 * f() end,
                        base = theme.primary,
                        effect = sinestesia.effect,
                        width = band_width,
                        height = band_height,
                    },
                    -- Human language: the expressive face.
                    g.text {
                        present = shows_name,
                        color = theme.text,
                        font = typography.expressive,
                        size = size,
                        text = function() return shown.value end,
                        max_width = available,
                        opacity = function() return if visible.value then 1 else 0 end,
                        transition = { opacity = "content_fade" },
                    },
                }
            end,
        }
    end,
}
