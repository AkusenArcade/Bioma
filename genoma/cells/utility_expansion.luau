--!strict
-- What is captured above, where it is captured from below
-- (cells/utility/UtilityPanel.qml at 11bb81e). See docs/design/CELLS.md §06.
--
-- Two independent choices, never a list of nine: the pair is what the user
-- holds in their head, and the last pair used stays selected, so the common
-- case is one press. The press on a source is the press that acts: a
-- screenshot tool that asks twice is never used.
--
-- Not yet: the keyboard's travel through the sources (KeyMark), which
-- comes with keyboard travel inside an open cell (genoma/PORT.md).
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local config = require("core/config")
local typography = require("core/typography")
local segmented = require("components/segmented")

local M = {}

-- `t`: what(), from(), supports(what, place), act(what, place),
-- recent_colour(key), from the cell.
function M.new(cell: any, t: { [string]: any }): { [string]: any }
    local function m(): { [string]: any } return cell.metrics() end
    local function f(): number return m().factor end
    local function button_width(): number return 112 * f() end
    local function button_height(): number return 92 * f() end
    local function button_gap(): number return 8 * f() end
    local function row_gap(): number return 12 * f() end
    local function pad(): number return 10 * f() end
    -- The segmented track: its buttons and their inset.
    local function kinds_height(): number return 32 * f() end

    local function for_text(): boolean return t.what() == "text" end
    local function for_colour(): boolean return t.what() == "colour" end

    -- One of the three places. Under Text the row reads OCR SCREEN ·
    -- DICTATION · OCR REGION: text is never read from a window here, so the
    -- middle place is dictation's (PRD §9.6), its key still `window`. Under
    -- Colour it reads PICK · the last colour · the one before: a colour has
    -- no place to choose, so the places are the colours already taken.
    local function source(slot: number): any
        local function key(): string
            if for_colour() then return ({ "pick", "recent0", "recent1" })[slot] end
            return ({ "screen", "window", "region" })[slot]
        end
        local function holds_colour(): boolean return for_colour() and slot > 1 end
        local function swatch(): string return if holds_colour() then t.recent_colour(key()) else "" end
        local function label(): string
            if holds_colour() then
                local s = swatch()
                return if s ~= "" then s else "NONE"
            end
            if for_colour() then return "PICK" end
            if for_text() then return ({ "OCR SCREEN", "DICTATION", "OCR REGION" })[slot] end
            return ({ "SCREEN", "WINDOW", "REGION" })[slot]
        end
        local function icon(): string
            if for_colour() then return "picker" end
            if slot == 2 then return if for_text() then "microphone" else "window" end
            return ({ "screen", "window", "region" })[slot]
        end
        -- Under Colour nothing is remembered as a place: the pick is the
        -- control, the colours beside it wells.
        local function chosen(): boolean
            return if for_colour() then key() == "pick" else t.from() == key()
        end
        local function available(): boolean return t.supports(t.what(), key()) end
        local function label_size(): number return math.round(11 * f()) end

        return g.capsule {
            role = "button",
            name = ({ "first source", "second source", "third source" })[slot],
            width = button_width,
            height = button_height,
            radius = function() return m().radius_panel end,
            direction = "column",
            align = "center",
            justify = "center",
            gap = function() return 12 * f() end,
            opacity = function() return if available() then 1 else 0.38 end,
            -- Chosen, it is a control carrying the primary at a whisper;
            -- otherwise a well with the outline family round it.
            fill = function()
                return if chosen() then colour.alpha(theme.primary(), 0.13)
                    else colour.alpha(theme.lift(theme.background(), -0.01), 0.8)
            end,
            rim_top = function() return if chosen() then "#00000000" else theme.line() end,
            rim_bottom = function() return if chosen() then "#00000000" else theme.line() end,
            transition = { opacity = "transition", fill = "transition", rim_top = "transition", rim_bottom = "transition" },
            on_click = function()
                if g.untracked(available) then t.act(g.untracked(t.what), g.untracked(key)) end
            end,
            -- An empty place is a ring, never a colour that was not picked.
            g.capsule {
                present = holds_colour,
                width = function() return 28 * f() end,
                height = function() return 28 * f() end,
                fill = function() local s = swatch() return if s ~= "" then s else "#00000000" end,
                rim_top = function() return colour.alpha(theme.text(), 0.5) end,
                rim_bottom = function() return colour.alpha(theme.text(), 0.5) end,
            },
            -- The icon says what the source is; the gradient which one is
            -- active. An icon never takes a state colour.
            g.icon {
                present = function() return not holds_colour() end,
                width = function() return 28 * f() end,
                height = function() return 28 * f() end,
                icon = icon,
                gradient_top = function()
                    return if chosen() then theme.gradient_top(theme.primary()) else colour.alpha(theme.text(), 0.62)
                end,
                gradient_bottom = function()
                    return if chosen() then theme.gradient_bottom(theme.primary()) else colour.alpha(theme.text(), 0.62)
                end,
            },
            g.text {
                text = label,
                color = theme.text,
                font = typography.technical,
                size = label_size,
                weight = typography.weight_label,
                tracking = 0.08,
            },
        }
    end

    local function content(): any
        return g.box {
            direction = "column",
            align = "center",
            gap = row_gap,
            -- Choosing what to capture captures nothing: it is the first half
            -- of the pair, and the second half is the press that acts.
            segmented.new {
                metrics = m,
                options = function()
                    return {
                        { key = "image", label = "Image" },
                        { key = "video", label = "Video" },
                        { key = "text", label = "Text" },
                        { key = "colour", label = "Colour" },
                    }
                end,
                current = t.what,
                on_choose = function(key: string) config.set("capture.what", key) end,
            },
            g.box {
                direction = "row",
                gap = button_gap,
                source(1),
                source(2),
                source(3),
            },
        }
    end

    return {
        panel = {
            width = function() return button_width() * 3 + button_gap() * 2 + pad() * 2 end,
            height = function() return kinds_height() + row_gap() + button_height() + pad() * 2 end,
            content = content,
        },
    }
end

return M
