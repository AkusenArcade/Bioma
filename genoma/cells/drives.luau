--!strict
-- A removable drive, while one is attached: a stick for each, and while one
-- is written to, the thread the bytes run along (cells/drives/
-- DrivesCell.qml and DrivesPanel.qml at 11bb81e). See docs/design/CELLS.md
-- §18.
--
-- The thread is what the cell is for: a copy ends for the program long
-- before it ends for the stick, and a stick pulled then is a file lost.
-- While the light runs it is not safe to pull; still and gone, it is.
-- Opened, each drive on its row, with OPEN and EJECT; ejecting, the loader
-- where the buttons were; refused, why, in the alert colour.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local drives = require("services/drives")
local proxy = require("services/proxy")
local choice = require("components/choice")
local sweep = require("components/sweep")
local rate_thread = require("components/rate_thread")

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 18 * f() end
        local function glyph_gap(): number return 6 * f() end
        local function thread_width(): number return 44 * f() end
        local function spacing(): number return 10 * f() end
        local function row_height(): number return 56 * f() end
        local function error_height(): number return 22 * f() end
        local function panel_width(): number return 380 * f() end
        local function inner(): number return panel_width() - 20 * f() - 12 * f() end

        drives.hold(cell, true)

        -- Kept while the cell fades after the last drive, so it leaves as what
        -- it was; and the last one gone closes it: a panel listing a stick
        -- just ejected would say it is still there.
        local count = g.signal(math.max(1, #g.untracked(drives.drives)))
        local rows = g.signal(g.untracked(drives.drives))
        g.watch(function() return #drives.drives() end, function(n: number)
            if n > 0 then
                count.value = n
                rows.value = g.untracked(drives.drives)
            elseif g.untracked(function() return cell.open.value end) then
                cell.open.value = false
            end
        end)
        g.watch(drives.drives, function(list: { any }) if #list > 0 then rows.value = list end end)

        local function writing(): boolean return drives.rate() >= 4096 end
        local function glyphs_width(): number return count.value * glyph() + (count.value - 1) * glyph_gap() end
        local function stick(lit: (() -> boolean)?): any
            local function top(): string
                return if lit == nil or lit() then theme.gradient_top(theme.primary()) else theme.text_muted()
            end
            local function bottom(): string
                return if lit == nil or lit() then theme.gradient_bottom(theme.primary()) else theme.text_muted()
            end
            return g.icon { width = glyph, height = glyph, icon = "drive", gradient_top = top, gradient_bottom = bottom }
        end

        local function row(item: () -> any, index: () -> number): any
            local function d(): any return item() end
            local function doing(): string return drives.busy(d().id) end
            local function problem(): string return drives.error(d().id) end
            local function volume(): any return d().volumes[1] or {} end
            local function y(): number
                local at = 0
                for i, other in rows.value do
                    if i >= index() then break end
                    at += row_height() + (if drives.error(other.id) ~= "" then error_height() else 0)
                end
                return at
            end
            local function meta(): string
                if drives.writing(d()) then return "WRITING · " .. drives.bytes(d().rate) .. "/S" end
                local parts = { drives.bytes(drives.size(d())) }
                if (volume().type or "") ~= "" then table.insert(parts, string.upper(volume().type)) end
                if drives.mounted(d()) then table.insert(parts, "MOUNTED") end
                return table.concat(parts, " · ")
            end
            local function meta_width(): number
                return g.text_width { text = meta(), font = typography.technical(), size = m().font_meta,
                    weight = typography.weight_secondary, tabular = true }
            end
            local function actions_width(): number return 140 * f() end
            return g.box {
                overlay = true,
                attach = "corner",
                offset_y = y,
                width = inner,
                height = function() return row_height() + (if problem() ~= "" then error_height() else 0) end,
                transition = { offset_y = "transition", height = "transition" },
                g.box {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return 10 * f() end,
                    offset_y = function() return (row_height() - 20 * f()) / 2 end,
                    g.icon {
                        width = function() return 20 * f() end,
                        height = function() return 20 * f() end,
                        icon = "drive",
                        gradient_top = function() return if drives.mounted(d()) then theme.gradient_top(theme.primary()) else theme.text_muted() end,
                        gradient_bottom = function() return if drives.mounted(d()) then theme.gradient_bottom(theme.primary()) else theme.text_muted() end,
                    },
                },
                -- What was written on it, or what its maker called it.
                g.text {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return 42 * f() end,
                    offset_y = function() return 9 * f() end,
                    text = function() local l = volume().label or "" return if l ~= "" then l else d().name end,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return math.floor(14 * f() + 0.5) end,
                    max_width = function() return inner() - 42 * f() - actions_width() - 10 * f() end,
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return 42 * f() end,
                    offset_y = function() return row_height() - 9 * f() - 14 * f() end,
                    width = function() return inner() - 42 * f() - actions_width() - 10 * f() end,
                    height = function() return 14 * f() end,
                    direction = "row",
                    align = "center",
                    gap = function() return 10 * f() end,
                    g.text {
                        text = meta,
                        color = theme.text_muted,
                        font = typography.technical,
                        size = function() return m().font_meta end,
                        weight = typography.weight_secondary,
                        tabular = true,
                    },
                    -- Still being written to: not to be pulled.
                    g.box {
                        present = function() return drives.writing(d()) end,
                        rate_thread.new {
                            width = function() return math.max(0, inner() - 42 * f() - actions_width() - 20 * f() - meta_width()) end,
                            rate = function() return d().rate or 0 end,
                            factor = f,
                        },
                    },
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    present = function() return doing() == "" end,
                    offset_x = function() return inner() - actions_width() - 8 * f() end,
                    offset_y = function() return (row_height() - 26 * f()) / 2 end,
                    width = actions_width,
                    direction = "row",
                    justify = "end",
                    gap = function() return 8 * f() end,
                    choice.new { metrics = m, label = "Open", on_click = function()
                        drives.open(g.untracked(d), g.untracked(proxy.environment))
                        cell.open.value = false
                    end },
                    choice.new { metrics = m, label = "Eject", on_click = function() drives.eject(g.untracked(d)) end },
                },
                -- Unmounting waits for the writing, for as long as that takes.
                g.box {
                    overlay = true,
                    attach = "corner",
                    present = function() return doing() ~= "" end,
                    offset_x = function() return inner() - 16 * f() - 18 * f() end,
                    offset_y = function() return (row_height() - 18 * f()) / 2 end,
                    sweep.new { size = 18 * f(), present = function() return doing() ~= "" end, running = function() return doing() ~= "" end },
                },
                g.box {
                    overlay = true,
                    attach = "corner",
                    present = function() return problem() ~= "" end,
                    offset_x = function() return 42 * f() end,
                    offset_y = function() return row_height() - 4 * f() end,
                    direction = "row",
                    align = "center",
                    gap = function() return 8 * f() end,
                    g.icon {
                        width = function() return 14 * f() end,
                        height = function() return 14 * f() end,
                        icon = "error",
                        gradient_top = theme.alert,
                        gradient_bottom = theme.alert,
                    },
                    g.text {
                        text = problem,
                        color = theme.alert,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                    },
                },
            }
        end

        local function list_height(): number
            local h = 0
            for _, d in rows.value do h += row_height() + (if drives.error(d.id) ~= "" then error_height() else 0) end
            return math.max(h, row_height())
        end

        return {
            panel = {
                width = panel_width,
                height = function() return list_height() + 12 * f() + 20 * f() end,
                content = function()
                    return g.capsule {
                        width = function() return panel_width() - 20 * f() end,
                        height = function() return list_height() + 12 * f() end,
                        radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                        rim_top = "#00000000",
                        rim_bottom = "#00000000",
                        transition = { height = "transition" },
                        g.each {
                            overlay = true,
                            attach = "corner",
                            offset_x = function() return 6 * f() end,
                            offset_y = function() return 6 * f() end,
                            width = inner,
                            items = function() return rows.value end,
                            key = function(d: any) return d.id end,
                            row = row,
                        },
                    }
                end,
            },
            -- One stick a round cell; more, or one written to, a pill.
            padding_leading = function() return (if count.value > 1 or writing() then 12 else 11) * f() end,
            padding_trailing = function() return (if writing() then 16 elseif count.value > 1 then 12 else 11) * f() end,
            condition = function() return if drives.attached() then 1 else 0 end,
            content_width = function() return glyphs_width() + (if writing() then spacing() + thread_width() else 0) end,
            header_title = "DRIVES",
            header_mark_size = glyph,
            header_mark = function() return stick() end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = spacing,
                    g.each {
                        direction = "row",
                        align = "center",
                        gap = glyph_gap,
                        items = function()
                            local out = {}
                            for i = 1, count.value do table.insert(out, i) end
                            return out
                        end,
                        key = function(i: number) return i end,
                        row = function() return stick() end,
                    },
                    g.box {
                        present = writing,
                        rate_thread.new {
                            width = thread_width,
                            rate = drives.rate,
                            factor = f,
                            running = function() return cell.placed.value and writing() end,
                        },
                    },
                }
            end,
        }
    end,
}
