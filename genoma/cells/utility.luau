--!strict
-- Screenshots, regions, text recognition, recording, dictation and colour
-- (cells/utility/Utility.qml at 11bb81e). See docs/design/CELLS.md §06.
--
-- The first purely functional cell: at rest it has nothing to represent,
-- so it shows its icon and nothing else — no figure, no state colour,
-- because it measures nothing.
--
-- While it records, it is the recording: the count and the stop are here,
-- and so is the question that follows (Akusen, 2026-09-27). Only the stop
-- stops; the rest of the pill opens the panel as ever, so a screenshot can
-- still be taken while the recording runs.
--
-- The dot is the one place where the alert colour says no load at all:
-- the machine is writing to disk, and that has to be visible from across
-- the room. It beats once per counted second, so the movement is the
-- count. Listening for dictation, the dot's size is the voice instead,
-- still in silence; transcribing, the loader stands beside the glyph until
-- the text is there.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local config = require("core/config")
local typography = require("core/typography")
local capture = require("services/capture")
local dictation = require("services/dictation")
local niri = require("services/niri")
local choice = require("components/choice")
local sweep = require("components/sweep")
local expansion = require("cells/utility_expansion")

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function icon_size(): number return 20 * f() end
        local function dot_size(): number return 9 * f() end
        local function mic_size(): number return 18 * f() end
        local function stop_size(): number return 26 * f() end
        local function spacing(): number return 11 * f() end
        local function font_time(): number return math.round(14 * f()) end

        -- ---- Which of its shapes ----------------------------------------------

        local function recording(): boolean return capture.recording() end
        -- Recording, then the question: the file asked about is the one it
        -- just made.
        local function confirming(): boolean return not capture.recording() and capture.pending_video() ~= "" end
        local function dictating(): boolean return dictation.active() end
        local function idle(): boolean return not recording() and not confirming() and not dictating() end

        -- Something is happening, and a narrow tissue must not drop it.
        g.effect(function() cell.busy.value = not idle() end)

        -- Conditional, it is there for a moment after a screenshot, Bioma's
        -- or niri's, as the sign that it was taken. Not for a pick the
        -- palette editor asked for: that one is answered where it was asked.
        capture.on("captured", function() cell.pulse() end)
        capture.on("picked", function() if capture.pick_kept then cell.pulse() end end)
        niri.on_screenshot(function() cell.pulse() end)

        -- ---- What it does -------------------------------------------------------

        -- Two choices, what and where from, remembered in the configuration
        -- so the last pair used is the one waiting.
        local function what(): string return config.get("capture.what", "image") end
        local function from(): string return config.get("capture.from", "screen") end

        -- `recent0` the last colour picked, `recent1` the one before.
        local function recent_colour(key: string): string
            local at = if key == "recent0" then 1 elseif key == "recent1" then 2 else 0
            return capture.colours()[at] or ""
        end

        -- A pair the machine cannot do is drawn unavailable rather than
        -- offered and refused. The recorder takes an output or a region,
        -- never a window; text has no window here, so the middle place is
        -- dictation's (PRD §9.6); one capture at a time.
        local function supports(w: string, place: string): boolean
            if w == "colour" then return place == "pick" or recent_colour(place) ~= "" end
            if w == "video" and not idle() then return false end
            if place ~= "window" then return true end
            if w == "text" then return idle() and dictation.available() end
            return w == "image"
        end

        local function act(w: string, place: string)
            if not g.untracked(function() return supports(w, place) end) then return end
            -- A colour is a pick, not a place: it remembers the tab and
            -- nothing else.
            if w == "colour" then
                config.set("capture.what", w)
                cell.open.value = false
                if place == "pick" then capture.pick_colour() else capture.copy_colour(g.untracked(function() return recent_colour(place) end)) end
                return
            end
            config.set_many({ { "capture.what", w }, { "capture.from", place } })
            capture.pending_action = if w == "video" then "record" elseif w == "text" then "text" else "still"
            -- The cell closes first and the capture follows, as the panel
            -- is on the screen being photographed.
            cell.open.value = false
            if place == "region" then
                capture.select_region()
            elseif w == "text" and place == "window" then
                -- Closing gives the focus back to the window the text is for.
                dictation.start()
            elseif place == "window" then
                local window = g.untracked(niri.focused_window)
                capture.capture_window(if window then window.id else 0)
            elseif w == "video" then
                capture.record_output(cell.output)
            elseif w == "text" then
                capture.recognise_region(capture.output_region(cell.output))
            else
                capture.capture_output(cell.output)
            end
        end

        local opened = expansion.new(cell, {
            what = what, from = from, supports = supports, act = act, recent_colour = recent_colour,
        })

        -- ---- Its parts --------------------------------------------------------------

        local function clock_font(): { [string]: any }
            return { font = typography.technical(), size = font_time(), weight = typography.weight_label,
                tracking = typography.label_tracking, tabular = true }
        end
        -- The seconds at the width of "00:00" whatever they read: Orbitron
        -- has no tabular figures, and the pill narrowed and widened every
        -- second, a movement that measured nothing (Akusen, 2026-09-29).
        local function clock_width(): number
            local t = clock_font()
            t.text = "00:00"
            return g.text_width(t)
        end
        local function clock_text(total: number): string
            return string.format("%02d:%02d", total // 60, total % 60)
        end
        local function clock(text: () -> string, present: (() -> boolean)?): any
            return g.box {
                present = present,
                width = clock_width,
                justify = "center",
                g.text {
                    text = text,
                    font = typography.technical,
                    size = font_time,
                    weight = typography.weight_label,
                    tracking = typography.label_tracking,
                    tabular = true,
                    color = theme.text,
                },
            }
        end

        local function alert_disc(size: () -> number, transition: any): any
            return g.capsule {
                width = size,
                height = size,
                fill = function() return theme.gradient_top(theme.alert()) end,
                fill_bottom = function() return theme.gradient_bottom(theme.alert()) end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                transition = if transition then { width = transition, height = transition } else nil,
            }
        end
        local function holder(child: any, present: (() -> boolean)?): any
            return g.box {
                present = present,
                width = function() return dot_size() * 1.6 end,
                height = function() return dot_size() * 1.6 end,
                align = "center",
                justify = "center",
                child,
            }
        end

        -- One beat per second counted: swelling over a grow step, settling
        -- over a transition. Width and height, never a scale.
        local beat = g.signal(false)
        capture.on("second", function()
            beat.value = true
            g.after(require("core/timing").seconds.grow, function() beat.value = false end)
        end)
        local function beat_size(): number return if beat.value then dot_size() * 1.45 else dot_size() end

        -- The stop, in the colour of what it stops. It takes the press for
        -- itself, or the same press would stop and open the panel.
        local function stop(on_click: () -> (), present: (() -> boolean)?): any
            return g.capsule {
                role = "button",
                name = "Stop",
                present = present,
                width = stop_size,
                height = stop_size,
                align = "center",
                justify = "center",
                fill = "#00000000",
                rim_top = function() return colour.alpha(theme.alert(), 0.55) end,
                rim_bottom = function() return colour.alpha(theme.alert(), 0.55) end,
                on_click = on_click,
                g.capsule {
                    width = function() return 10 * f() end,
                    height = function() return 10 * f() end,
                    radius = function() return 2 * f() end,
                    fill = function() return theme.gradient_top(theme.alert()) end,
                    fill_bottom = function() return theme.gradient_bottom(theme.alert()) end,
                    rim_top = "#00000000",
                    rim_bottom = "#00000000",
                },
            }
        end

        local function question_width(): number
            local text = g.text_width { text = "Save recording?", font = typography.expressive(), size = cell.metrics().font_title }
            local function chip(label: string, bold: boolean): number
                return g.text_width { text = label, font = typography.technical(), size = math.round(12 * f()),
                    weight = if bold then typography.weight_title else typography.weight_label, tracking = 0.04 } + 24 * f()
            end
            return text + chip("Discard", false) + chip("Save", true) + 24 * f()
        end
        local function counter_width(): number
            return dot_size() * 1.6 + clock_width() + stop_size() + spacing() * 2
        end
        local function dictation_width(): number
            if dictation.listening() then return mic_size() + dot_size() * 1.6 + clock_width() + stop_size() + spacing() * 3 end
            return mic_size() * 2 + spacing()
        end

        local function glyph(name: string, size: () -> number, present: (() -> boolean)?): any
            return g.icon {
                present = present,
                width = size,
                height = size,
                icon = name,
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            }
        end

        return {
            panel = opened.panel,
            -- A square round its glyph at rest. Counting, the figure keeps a
            -- figure's margins; asking, the question ends in a control, and
            -- a control sits closer to the cap.
            padding_leading = function() return (if idle() then 10 else 16) * f() end,
            padding_trailing = function()
                return (if idle() then 10 elseif confirming() then 6 else 16) * f()
            end,
            condition = function() return if cell.pulsing() or not idle() then 1 else 0 end,
            content_width = function()
                if confirming() then return question_width() end
                if recording() then return counter_width() end
                if dictating() then return dictation_width() end
                return icon_size()
            end,
            -- The question is the whole pill, and its answers are in it: a
            -- press there is an answer, never an opening.
            on_click = function()
                if g.untracked(confirming) then return end
                cell.open.value = not g.untracked(function() return cell.open.value end)
            end,
            -- Its category, not what it does today: a title that has to be
            -- renamed when the cell grows is the wrong title (Akusen,
            -- 2026-09-22).
            header_title = "UTILITY",
            header_mark_size = icon_size,
            header_mark = function(mark: () -> number) return glyph("capture", mark) end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    glyph("capture", icon_size, idle),
                    -- While it records.
                    g.box {
                        present = recording,
                        direction = "row",
                        align = "center",
                        gap = spacing,
                        holder(alert_disc(beat_size, function() return if beat.value then "grow" else "transition" end)),
                        clock(function() return clock_text(capture.elapsed()) end),
                        stop(capture.stop_recording),
                    },
                    -- While it listens: the glyph, the open microphone, the
                    -- seconds spoken, the stop; the loader once it transcribes.
                    g.box {
                        present = dictating,
                        direction = "row",
                        align = "center",
                        gap = spacing,
                        glyph("microphone", mic_size),
                        holder(alert_disc(function() return dot_size() * (1 + 0.6 * dictation.level()) end, "grow"),
                            dictation.listening),
                        clock(function() return clock_text(dictation.elapsed()) end, dictation.listening),
                        stop(dictation.stop, dictation.listening),
                        sweep.new { size = mic_size(), present = dictation.transcribing, running = dictation.transcribing },
                    },
                    -- And then asks. Not a dialog: it grows from the cell that
                    -- made the file, always in the same place. The video waits
                    -- in a temporary directory, so discard means it never
                    -- existed.
                    g.box {
                        present = confirming,
                        direction = "row",
                        align = "center",
                        gap = function() return 12 * f() end,
                        g.text {
                            text = "Save recording?",
                            color = theme.text,
                            font = typography.expressive,
                            size = function() return cell.metrics().font_title end,
                        },
                        choice.new { metrics = cell.metrics, label = "Discard", on_click = capture.discard_recording },
                        choice.new { metrics = cell.metrics, label = "Save", kind = "primary", on_click = capture.save_recording },
                    },
                }
            end,
        }
    end,
}
