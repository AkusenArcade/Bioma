--!strict
-- What has the focus (cells/window_title/WindowTitle.qml at 670c660). The
-- second of the two exceptions to the silence rule: without a name a window
-- cannot be recognised, so the text is always there.
--
-- Usually a window. Sometimes one of Bioma's own cells: one with a field to
-- type in takes the keyboard, and the compositor takes it off the window to
-- give it. The focus did not go nowhere, so neither does this cell: it names
-- the cell in the machine's voice, and hands the window back the moment the
-- window has it back (Akusen, 2026-09-22).
--
-- It exists only while something has the focus, it is elastic between a
-- minimum and a cap past which the text elides, and a press centres the
-- window. See docs/design/CELLS.md §01.
--
-- Not yet: the cell's own glyph in the disc while a cell has the focus (no
-- cell ported takes the keyboard so far).
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local typography = require("core/typography")
local timing = require("core/timing")
local niri = require("services/niri")
local apps = require("core/apps")
local focus = require("structure/focus")
local sweep = require("components/sweep")

-- A window that is working says so in its own title: a spinner glyph in
-- front of the name, rewritten several times a second. The glyph is taken
-- out and shown as the loader instead, which also lets the title settle.
local function spins(code: number): boolean
    return (code >= 0x25D0 and code <= 0x25D3) -- half-filled circles
        or (code >= 0x25F4 and code <= 0x25F7) -- quartered circles
        or (code >= 0x2800 and code <= 0x28FF) -- braille, the usual dots
        or (code >= 0x1F550 and code <= 0x1F55B) -- clock faces
        or (code >= 0x1F311 and code <= 0x1F318) -- moon phases
end

local function settled(title: string): (boolean, string)
    if title == "" then return false, "" end
    local ok, first = pcall(utf8.codepoint, title, 1)
    if not ok or not spins(first) then return false, title end
    local rest = string.sub(title, utf8.offset(title, 2) :: number)
    return true, (string.gsub(rest, "^[%s\u{a0}]+", ""))
end

return {
    new = function(cell: any)
        local function m() return cell.metrics() end
        local function icon_size(): number return 30 * m().factor end
        local function spacing(): number return 10 * m().factor end
        local function loader_size(): number return 16 * m().factor end

        -- The shell has the focus, and a cell is what has it: a cell holding
        -- the keyboard while the window keeps the focus is still a window.
        local function on_cell(): boolean return focus.holds_keyboard() and niri.focused_window() == nil end
        local function cell_name(): string
            local subject = focus.open_cell()
            if not subject then return "" end
            local header = subject.spec.header_title and subject.spec.header_title() or ""
            return if header ~= "" then header else string.upper(subject.domain)
        end

        local function incoming(): string
            if on_cell() then return cell_name() end
            local _, text = settled(niri.focused_title())
            return text
        end

        -- Late in, immediate out: a wait under a moment shows nothing, but
        -- the moment the work finishes the loader is wrong.
        local waiting = g.signal(false)
        local appear: any = nil
        g.watch(function()
            if on_cell() then return false end
            local spinning = settled(niri.focused_title())
            return spinning
        end, function(spinning: boolean)
            if appear then appear:stop() end
            appear = nil
            if spinning then
                appear = g.after(timing.seconds.debounce, function() waiting.value = true end)
            else
                waiting.value = false
            end
        end)

        -- Browsers rewrite the title on every tab: the text waits out the
        -- debounce and crosses over, never swapped abruptly. A window's name
        -- is human language and a cell's the machine's own word, and the
        -- voice travels with the text through the cross-fade.
        local shown = g.signal(g.untracked(incoming))
        local technical = g.signal(g.untracked(on_cell))
        local visible = g.signal(true)
        local debounce: any = nil
        g.watch(incoming, function(text: string)
            if g.untracked(function() return shown.value end) == "" then
                shown.value = text
                technical.value = g.untracked(on_cell)
                return
            end
            if debounce then debounce:stop() end
            debounce = g.after(timing.seconds.debounce, function()
                if g.untracked(function() return shown.value end) == g.untracked(incoming) then return end
                visible.value = false
                g.after(timing.seconds.content_fade, function()
                    g.batch(function()
                        shown.value = g.untracked(incoming)
                        technical.value = g.untracked(on_cell)
                        visible.value = true
                    end)
                end)
            end)
        end)

        local function font(): string
            return if technical.value then typography.technical() else typography.expressive()
        end
        local function size(): number return m().font_title end

        local function label_width(): number
            return g.text_width {
                text = shown.value,
                font = font(),
                size = size(),
                weight = if technical.value then typography.weight_label else 400,
                tracking = if technical.value then typography.label_tracking else 0,
            }
        end

        local function waiting_room(): number
            return if waiting.value then loader_size() + spacing() else 0
        end

        return {
            -- The icon is round and sits against the leading cap, concentric
            -- with it; the text keeps the full margin on the other side.
            padding_leading = 5,
            padding_trailing = 16,
            interactive = true,
            -- It exists while something has the focus, either of the two.
            condition = function() return if niri.focused_window() ~= nil or on_cell() then 1 else 0 end,
            content_width = function() return icon_size() + spacing() + waiting_room() + label_width() end,
            -- With a cell in the title there is no window to centre.
            on_click = function()
                if not g.untracked(on_cell) then niri.center_focused_window() end
            end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    -- Application icons are third-party and stylistically
                    -- unrelated: the dark disc with a thin outline makes
                    -- them a family. The fallback follows the palette.
                    g.capsule {
                        width = icon_size,
                        height = icon_size,
                        fill = function() return theme.lift(theme.background(), -0.015) end,
                        rim_top = function() return colour.alpha(theme.text(), 0.5) end,
                        rim_bottom = function() return colour.alpha(theme.text(), 0.5) end,
                        g.icon {
                            width = function() return icon_size() * 0.62 end,
                            height = function() return icon_size() * 0.62 end,
                            present = function() return not on_cell() end,
                            color = theme.text_muted,
                            -- Never another application's logo: an unresolved
                            -- icon gets the neutral glyph.
                            icon = function()
                                local path = apps.icon_for(niri.focused_app_id())
                                return if path ~= "" then path else "app-fallback"
                            end,
                        },
                    },
                    -- Beside the name, never in place of the icon: replacing
                    -- the glyph would make the row jump twice.
                    sweep.new {
                        size = loader_size(),
                        present = function() return waiting.value end,
                        running = function() return waiting.value end,
                    },
                    g.text {
                        color = theme.text,
                        font = font,
                        size = size,
                        weight = function() return if technical.value then typography.weight_label else 400 end,
                        tracking = function()
                            return if technical.value then typography.label_tracking else 0
                        end,
                        text = function() return shown.value end,
                        -- The ellipsis goes on the text, never on the cell:
                        -- clipping the cell eats the rim.
                        max_width = function()
                            return math.max(0, cell.room() - icon_size() - spacing() - waiting_room())
                        end,
                        opacity = function() return if visible.value then 1 else 0 end,
                        transition = { opacity = "content_fade" },
                    },
                }
            end,
        }
    end,
}
