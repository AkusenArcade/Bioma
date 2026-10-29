--!strict
-- A download, while one is coming in: the glyph and a thread the bytes run
-- along (cells/download/DownloadCell.qml and DownloadPanel.qml at 11bb81e).
-- See docs/design/CELLS.md §16.
--
-- The thread is the cell's whole measure: no figure at rest. There is no
-- progress to draw because there is none to know: no browser writes the
-- total outside itself. Opened, each download on its own row, its own
-- thread at its own speed, and the figures; a press shows the file where
-- it is being written.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local downloads = require("services/downloads")
local rate_thread = require("components/rate_thread")

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 18 * f() end
        local function thread_width(): number return 44 * f() end
        local function spacing(): number return 10 * f() end
        local function row_height(): number return 52 * f() end
        local function panel_width(): number return 340 * f() end

        downloads.hold(cell, true)

        -- Kept while the cell closes after the last download has finished.
        local rows = g.signal(g.untracked(downloads.files))
        g.watch(downloads.files, function(live: { any }) if #live > 0 then rows.value = live end end)

        local function inner(): number return panel_width() - 20 * f() - 12 * f() end
        local function row(item: () -> any, index: () -> number): any
            local function d(): any return item() end
            local hovered = g.signal(false)
            local function figures(): string
                local r = d().rate or 0
                return downloads.bytes(d().size or 0) .. " · " .. (if r >= 1024 then downloads.bytes(r) .. "/S" else "STALLED")
            end
            local function figures_width(): number
                return g.text_width { text = figures(), font = typography.technical(), size = m().font_meta,
                    weight = typography.weight_secondary, tabular = true }
            end
            return g.capsule {
                role = "button",
                name = "Download",
                overlay = true,
                attach = "corner",
                offset_y = function() return (index() - 1) * row_height() end,
                width = inner,
                height = row_height,
                radius = function() return 10 * f() end,
                fill = function() return if hovered.value then colour.alpha(theme.primary(), 0.08) else "#00000000" end,
                rim_top = "#00000000",
                rim_bottom = "#00000000",
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function() downloads.reveal(g.untracked(d).path) end,
                g.text {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return 10 * f() end,
                    offset_y = function() return 8 * f() end,
                    text = function() return d().name end,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return math.floor(14 * f() + 0.5) end,
                    max_width = function() return inner() - 20 * f() end,
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return 10 * f() end,
                    offset_y = function() return row_height() - 8 * f() - 14 * f() end,
                    width = function() return inner() - 20 * f() end,
                    height = function() return 14 * f() end,
                    direction = "row",
                    align = "center",
                    justify = "between",
                    rate_thread.new {
                        width = function() return inner() - 30 * f() - figures_width() end,
                        rate = function() return d().rate or 0 end,
                        factor = f,
                    },
                    g.text {
                        text = figures,
                        color = theme.text_muted,
                        font = typography.technical,
                        size = function() return m().font_meta end,
                        weight = typography.weight_secondary,
                        tabular = true,
                    },
                },
            }
        end

        local function content(): any
            return g.capsule {
                width = function() return panel_width() - 20 * f() end,
                height = function() return math.max(1, #rows.value) * row_height() + 12 * f() end,
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
                    items = function() return rows.value end,
                    key = function(d: any) return d.path end,
                    row = row,
                },
            }
        end

        return {
            panel = {
                width = panel_width,
                height = function() return math.max(1, #rows.value) * row_height() + 12 * f() + 20 * f() end,
                content = content,
            },
            padding_leading = function() return 12 * f() end,
            padding_trailing = function() return 16 * f() end,
            condition = function() return if downloads.downloading() then 1 else 0 end,
            content_width = function() return glyph() + spacing() + thread_width() end,
            header_title = "DOWNLOADS",
            header_mark_size = glyph,
            header_mark = function(mark: () -> number)
                return g.icon {
                    width = mark,
                    height = mark,
                    icon = "download",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                }
            end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    g.icon {
                        width = glyph,
                        height = glyph,
                        icon = "download",
                        gradient_top = function() return theme.gradient_top(theme.primary()) end,
                        gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    },
                    rate_thread.new {
                        width = thread_width,
                        rate = downloads.rate,
                        factor = f,
                        running = function() return cell.placed.value end,
                    },
                }
            end,
        }
    end,
}
