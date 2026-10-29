--!strict
-- The sound: its level, where it goes, where it comes from and who is
-- making it (cells/audio/AudioCell.qml at 11bb81e). See docs/design/CELLS.md
-- §05.
--
-- Named for its domain, not the dial it shows at rest (Akusen,
-- 2026-09-22). The first control in the catalogue rather than an
-- indicator: the wheel moves it, so it keeps the primary for its whole run.
-- At rest it is the dial alone, no figure: the arc already says where the
-- volume is.
--
-- Two forms, one cell. On a membrane it is the dial, and the capsule hangs
-- from it when it opens. Summoned into the middle of a screen (floating and
-- invoked) it has no membrane to hang from, so it is the capsule, with the
-- wells hanging below. A floating tissue always there is the cell at rest,
-- so it is the dial (Akusen, 2026-10-09).
local g = require("@genoma")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local audio = require("services/audio")
local focus = require("structure/focus")
local gauge = require("components/gauge")
local capsule_mod = require("cells/audio_capsule")
local expansion = require("cells/audio_expansion")

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function dial(): number return 26 * f() end
        local as_capsule = cell.floating
            and g.untracked(function() return (cell.block().visibility or {}).type end) == "invoked"

        local capsule = capsule_mod.new(cell.metrics)
        local function capsule_height(): number return 88 * f() end
        local function capsule_padding(): number return (372 * f() - capsule.content_width()) / 2 end

        -- Conditional, it is there for a moment after the level or the mute
        -- changes, from the wheel, a key or another program. Only a change:
        -- the service recomputes whenever any node does.
        local last = g.untracked(function() return { audio.volume(), audio.muted() } end)
        g.watch(function() return { audio.volume(), audio.muted() } end, function(now: { any })
            if now[1] ~= last[1] or now[2] ~= last[2] then cell.pulse() end
            last = now
        end)

        local function travel(): number return math.min(1, audio.volume()) end
        local function overflow(): number return math.max(0, audio.volume() - 1) end
        local function face(size: () -> number): any
            return gauge.new { size = size, fraction = travel, overflow = overflow, muted = audio.muted }
        end

        -- The wheel is the main interaction here, over the whole pill: on a
        -- forty-unit cell the content is the glyph and little else. A notch
        -- is a step; a touchpad's travel is counted out in steps.
        local carried = 0
        local function wheel(_: number, dy: number)
            local step = config.get("audio.step", 0.05)
            local discrete = dy == math.floor(dy) and math.abs(dy) <= 3
            if discrete then
                audio.step_volume(-dy * step)
                return
            end
            carried += dy
            local notches = if carried > 0 then math.floor(carried / 24) else -math.floor(-carried / 24)
            if notches ~= 0 then
                carried -= notches * 24
                audio.step_volume(-notches * step)
            end
        end

        -- Summoned, closing the wells does not end the summoning: it keeps
        -- the attention, so a press outside is what sends it away. A moment
        -- later, because the structure lets the attention go first.
        if as_capsule then
            g.watch(function() return cell.open.value end, function(open: boolean)
                if open then return end
                g.after(0, function()
                    if g.untracked(cell.visibility.invoked) and not g.untracked(function() return cell.open.value end) then
                        focus.opened(cell)
                    end
                end)
            end)
        end

        return {
            panel = expansion.new(cell, as_capsule),
            padding_leading = function() return if as_capsule then capsule_padding() else 7 * f() end,
            padding_trailing = function() return if as_capsule then capsule_padding() else 7 * f() end,
            content_width = function() return if as_capsule then capsule.content_width() else dial() end,
            body_height = if as_capsule then capsule_height else nil,
            radius = if as_capsule then function() return metrics_mod.radius_for(capsule_height(), cell.metrics()) end else nil,
            condition = function() return if cell.pulsing() then 1 else 0 end,
            on_wheel = wheel,
            on_middle = audio.toggle_mute,
            -- The capsule keeps what it carries when it opens.
            replaces_content = not as_capsule,
            leaves_on_close = not as_capsule,
            -- Open, its glyph is the dial itself, still live: the wheel keeps
            -- working while the panel is open.
            header_title = if as_capsule then nil else "AUDIO",
            header_mark_size = function() return 20 * f() end,
            header_mark = if as_capsule then nil else face,
            contracted = function()
                if as_capsule then return capsule.node() end
                return face(dial)
            end,
        }
    end,
}
