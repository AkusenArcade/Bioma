--!strict
-- What is playing, on the desktop (organisms/media/MediaOrganism.qml at
-- 2cafc17). See docs/design/ORGANISMS.md §02.
--
-- The cover edge to edge, darkened toward the bottom where the words are:
-- the band the media cell draws, the title, the artist, the album, and how
-- far along the track is. Absent with nothing loaded; with no cover, the
-- domain's glyph. The band runs only while something sounds.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local media = require("services/media")
local sinestesia = require("services/sinestesia")
local band = require("components/band")

local BARS = 48

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function present(): boolean
            return media.available() and media.has_metadata() and (media.playing() or media.paused())
        end
        local function has_art(): boolean return present() and media.art_path() ~= "" end
        local function shows_band(): boolean return o.entry().band ~= false end
        local function sounding(): boolean return present() and shows_band() and media.playing() end
        local token = {}
        g.watch(sounding, function(on: boolean) sinestesia.hold(token, on) end)
        sinestesia.hold(token, g.untracked(sounding))
        local band_left = g.computed(function() return if sounding() then sinestesia.fold(sinestesia.left(), BARS // 2) else {} end)
        local band_right = g.computed(function() return if sounding() then sinestesia.fold(sinestesia.right(), BARS // 2) else {} end)
        local function inset(): number return 20 * f() end
        local function inner(): number return o.width() - inset() * 2 end

        -- A new track's cover comes up over the old one, which goes once it
        -- is covered: a cross rather than a blink. One generation per cover,
        -- newest last.
        local covers = g.signal({} :: { any })
        local serial = 0
        g.watch(function() return if has_art() then media.art_path() else "" end, function(path: string)
            if path == "" then return end
            local now = g.untracked(function() return covers.value end)
            if #now > 0 and now[#now].path == path then return end
            serial += 1
            local newest = serial
            local list = table.clone(now)
            table.insert(list, {
                key = newest,
                path = path,
                shown = g.signal(#now == 0),
                ready = function()
                    local current = g.untracked(function() return covers.value end)
                    local last = current[#current]
                    if not last or last.key ~= newest then return end
                    last.shown.value = true
                    g.after(timing.seconds.content_fade + 0.05, function()
                        local kept = {}
                        for _, c in g.untracked(function() return covers.value end) do
                            if c.key >= newest then table.insert(kept, c) end
                        end
                        covers.value = kept
                    end)
                end,
            })
            covers.value = list
        end)
        local function cover(item: () -> any): any
            return g.image {
                overlay = true,
                attach = "corner",
                width = o.width,
                height = o.height,
                radius = function() return m().radius_panel end,
                fit = "cover",
                src = function() return item().path end,
                -- Not quite nothing while it waits: a node not drawn is
                -- never decoded.
                opacity = function() return if item().shown.value then 1 else 0.004 end,
                transition = { opacity = "content_fade" },
                on_ready = function() g.untracked(item).ready() end,
            }
        end

        local function expressive(text: () -> string, color: any, size: number, weight: number?, italic: boolean?, shown: (() -> boolean)?): any
            return g.text { present = shown, text = text, color = color, font = typography.expressive,
                size = function() return math.round(size * f()) end, weight = weight, italic = italic, max_width = inner }
        end

        return {
            bleeds = true,
            present = present,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    g.each {
                        overlay = true,
                        attach = "corner",
                        present = has_art,
                        width = o.width,
                        height = o.height,
                        items = function() return covers.value end,
                        key = function(c: any) return tostring(c.key) end,
                        row = cover,
                    },
                    -- Darker toward the words.
                    g.capsule {
                        overlay = true,
                        attach = "corner",
                        present = has_art,
                        width = o.width,
                        height = o.height,
                        radius = function() return m().radius_panel end,
                        -- The theme's background, nothing down to 36 % of the
                        -- height, 0.80 at 60 %, 0.92 at the bottom: the words
                        -- read on the shell's own colour whatever the picture.
                        fill_stops = function()
                            local b = theme.background()
                            return { { 0.36, colour.alpha(b, 0) }, { 0.6, colour.alpha(b, 0.8) }, { 1, colour.alpha(b, 0.92) } }
                        end,
                        rim_top = "#00000000",
                        rim_bottom = "#00000000",
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = function() return not has_art() end,
                        offset_y = function() return 52 * f() end,
                        width = o.width,
                        justify = "center",
                        g.icon {
                            width = function() return 96 * f() end,
                            height = function() return 96 * f() end,
                            icon = "sinestesia",
                            color = theme.text_muted,
                        },
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        offset_x = inset,
                        width = inner,
                        height = function() return o.height() - inset() end,
                        direction = "column",
                        align = "start",
                        justify = "end",
                        g.box {
                            present = shows_band,
                            band.new {
                                left = function() return band_left.value end,
                                right = function() return band_right.value end,
                                count = function() return BARS end,
                                bar_width = function() return 4 * f() end,
                                pitch = function() return 8 * f() end,
                                base = theme.primary,
                                effect = sinestesia.effect,
                                width = inner,
                                height = function() return 96 * f() end,
                            },
                        },
                        g.box { present = shows_band, height = function() return 16 * f() end },
                        expressive(function() return if present() then media.title() else "Nothing playing" end,
                            function() return if present() then theme.text() else theme.text_faint() end, 22, 700),
                        expressive(media.artist, theme.text_muted, 16, nil, false, function() return present() and media.artist() ~= "" end),
                        expressive(media.album, theme.text_faint, 13, nil, true, function() return present() and media.album() ~= "" end),
                        g.box { present = function() return present() and media.has_length() end, height = function() return 14 * f() end },
                        g.box {
                            present = function() return present() and media.has_length() end,
                            width = inner,
                            direction = "column",
                            gap = function() return 5 * f() end,
                            g.capsule {
                                width = inner,
                                height = function() return 3 * f() end,
                                crisp = true,
                                fill = function() return colour.alpha(theme.text(), 0.16) end,
                                rim_top = "#00000000",
                                rim_bottom = "#00000000",
                                justify = "start",
                                g.capsule {
                                    width = function() return inner() * math.clamp(media.progress(), 0, 1) end,
                                    height = function() return 3 * f() end,
                                    fill = theme.primary,
                                    rim_top = "#00000000",
                                    rim_bottom = "#00000000",
                                },
                                g.capsule {
                                    overlay = true,
                                    attach = "corner",
                                    offset_x = function() return inner() * math.clamp(media.progress(), 0, 1) - 3.5 * f() end,
                                    offset_y = function() return -2 * f() end,
                                    width = function() return 7 * f() end,
                                    height = function() return 7 * f() end,
                                    fill = theme.primary,
                                    rim_top = "#00000000",
                                    rim_bottom = "#00000000",
                                },
                            },
                            g.box {
                                width = inner,
                                direction = "row",
                                justify = "between",
                                g.text { text = function() return media.format_time(media.position()) end, color = theme.text_muted,
                                    font = typography.technical, size = function() return m().font_meta end, tabular = true },
                                g.text { text = function() return media.format_time(media.length()) end, color = theme.text_muted,
                                    font = typography.technical, size = function() return m().font_meta end, tabular = true },
                            },
                        },
                    },
                }
            end,
        }
    end,
}
