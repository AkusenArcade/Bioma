--!strict
-- Who is taking the microphone, a camera or the screen, there only while
-- something is (cells/privacy/PrivacyCell.qml and PrivacyPanel.qml at
-- 11bb81e). See docs/design/CELLS.md §14.
--
-- A glyph for each thing being taken and the names of who takes them, in
-- the expressive voice: the application's name is what the cell exists to
-- say (Akusen's list, 2026-10-05). The glyphs are in the active colour,
-- never the alert: a call lasting an afternoon is not an afternoon of
-- alarm. Opened, each use on its own row with its device or output.
-- Nothing can be pressed: the shell cannot take a microphone back from an
-- application, and pretending to would be worse than saying so.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local privacy = require("services/privacy")

local KINDS = { "microphone", "camera", "screen" }
local WORDS = { microphone = "MICROPHONE", camera = "CAMERA", screen = "SCREEN" }

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 18 * f() end
        local function glyph_gap(): number return 6 * f() end
        local function spacing(): number return 10 * f() end
        local function row_height(): number return 40 * f() end
        local function panel_width(): number return 360 * f() end

        privacy.hold(cell, true)

        local function kinds(): { string }
            local out = {}
            for _, k in KINDS do
                for _, u in privacy.uses() do
                    if u.kind == k then table.insert(out, k) break end
                end
            end
            return out
        end
        local function names(): string
            local out = {}
            for _, u in privacy.uses() do
                if u.app ~= "" and not table.find(out, u.app) then table.insert(out, u.app) end
            end
            return table.concat(out, " · ")
        end
        -- Kept while the cell leaves after the last use, so the pill does not
        -- empty before it fades.
        local held_kinds = g.signal(g.untracked(kinds))
        local held_names = g.signal(g.untracked(names))
        local held_rows = g.signal(g.untracked(privacy.uses))
        g.watch(function() return table.concat(kinds(), ",") end, function()
            local k = g.untracked(kinds)
            if #k > 0 then held_kinds.value = k end
        end)
        g.watch(names, function(n: string) if n ~= "" then held_names.value = n end end)
        g.watch(function() return #privacy.uses() end, function()
            local u = g.untracked(privacy.uses)
            if #u > 0 then held_rows.value = u end
        end)
        local function shown_kinds(): { string } local k = kinds() return if #k > 0 then k else held_kinds.value end
        local function shown_names(): string local n = names() return if n ~= "" then n else held_names.value end
        local function glyphs_width(): number
            local n = #shown_kinds()
            return n * glyph() + math.max(0, n - 1) * glyph_gap()
        end
        local function lead(): string return shown_kinds()[1] or "microphone" end
        local function tinted(name: () -> string, size: () -> number): any
            return g.icon {
                width = size,
                height = size,
                icon = name,
                gradient_top = theme.active,
                gradient_bottom = theme.active,
            }
        end

        local function inner(): number return panel_width() - 20 * f() - 12 * f() end
        local function row(item: () -> any, index: () -> number): any
            local function u(): any return item() end
            return g.box {
                overlay = true,
                attach = "corner",
                offset_y = function() return (index() - 1) * row_height() end,
                width = inner,
                height = row_height,
                direction = "row",
                align = "center",
                gap = function() return 12 * f() end,
                padding_left = function() return 8 * f() end,
                tinted(function() return u().kind end, glyph),
                g.box {
                    direction = "column",
                    align = "start",
                    gap = function() return 1 * f() end,
                    g.text {
                        text = function() return u().app end,
                        color = theme.text,
                        font = typography.expressive,
                        size = function() return math.floor(14 * f() + 0.5) end,
                        max_width = function() return inner() - 46 * f() end,
                    },
                    g.text {
                        text = function()
                            local d = u().detail or ""
                            return WORDS[u().kind] .. (if d ~= "" then " · " .. string.upper(d) else "")
                        end,
                        color = theme.text_muted,
                        font = typography.technical,
                        size = function() return m().font_meta end,
                        tracking = typography.label_tracking,
                        max_width = function() return inner() - 46 * f() end,
                    },
                },
            }
        end
        local function content(): any
            return g.capsule {
                width = function() return panel_width() - 20 * f() end,
                height = function() return math.max(1, #held_rows.value) * row_height() + 12 * f() end,
                radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                g.each {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return 6 * f() end,
                    offset_y = function() return 6 * f() end,
                    width = inner,
                    items = function() return held_rows.value end,
                    key = function(u: any) return u.key end,
                    row = row,
                },
            }
        end

        local function label_width(): number
            return g.text_width { text = shown_names(), font = typography.expressive(), size = m().font_title }
        end

        return {
            panel = {
                width = panel_width,
                height = function() return math.max(1, #held_rows.value) * row_height() + 12 * f() + 20 * f() end,
                content = content,
            },
            padding_leading = function() return 12 * f() end,
            padding_trailing = function() return 16 * f() end,
            condition = function() return if privacy.in_use() then 1 else 0 end,
            content_width = function() return glyphs_width() + spacing() + label_width() end,
            header_title = "PRIVACY",
            header_mark_size = glyph,
            header_mark = function(mark: () -> number) return tinted(lead, mark) end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    g.each {
                        direction = "row",
                        align = "center",
                        gap = glyph_gap,
                        items = shown_kinds,
                        key = function(k: string) return k end,
                        row = function(k: () -> string) return tinted(k, glyph) end,
                    },
                    g.text {
                        text = shown_names,
                        color = theme.text,
                        font = typography.expressive,
                        size = function() return m().font_title end,
                        max_width = function() return math.max(0, cell.room() - glyphs_width() - spacing()) end,
                    },
                }
            end,
        }
    end,
}
