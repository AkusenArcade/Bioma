--!strict
-- The system cell, opened (cells/system/SystemExpansion.qml at 11bb81e): the
-- identity capsule, the five actions hung under it, the machine beside the
-- actions and, on a machine with power profiles, the power capsule beside
-- the identity, hung from the machine.
--
-- The three actions that end the session ask first, in place: the row
-- turns into its question and its answer. A figure on every row is the key
-- that presses it: 1 to 5, Return to confirm, Escape to take a question
-- back.
--
-- Not yet: the keyboard's travel through the rows.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local session = require("services/session")
local machine = require("services/machine")
local power = require("services/power")
local picker = require("services/picker")
local focus = require("structure/focus")
local choice = require("components/choice")
local portrait = require("components/portrait")
local segmented = require("components/segmented")
local thread = require("components/thread")

local CLEAR = "#00000000"

local ACTIONS = {
    { key = "lock", label = "LOCK", glyph = "lock" },
    { key = "suspend", label = "SUSPEND", glyph = "suspend" },
    { key = "restart", label = "RESTART", glyph = "restart" },
    { key = "shutdown", label = "SHUT DOWN", glyph = "power" },
    { key = "logout", label = "LOG OUT", glyph = "logout" },
}

local M = {}

-- "SHUT DOWN" → "Shut down".
local function sentence(label: string): string
    return string.upper(string.sub(label, 1, 1)) .. string.lower(string.sub(label, 2))
end

function M.new(cell: any): { [string]: any }
    local function m(): any return cell.metrics() end
    local function f(): number return m().factor end
    local down = cell.edge ~= "bottom"

    local function capsule_width(): number return 300 * f() end
    local function capsule_height(): number return 108 * f() end
    local function avatar(): number return 88 * f() end
    local function panel_padding(): number return 10 * f() end
    local function row_height(): number return 44 * f() end
    local function panel_height(): number return panel_padding() * 2 + #ACTIONS * row_height() end
    local function info_width(): number return 340 * f() end
    local function gap(): number return m().gap end
    -- Against the end of the strip, the machine leans the other way.
    local function info_left(): boolean return cell.origin and cell.origin() == "end" end

    local function shown(): boolean return cell.open.value end
    local function opening(i: number): string
        return if shown() then "pod_" .. i else "pod_retract_" .. i
    end

    -- Read once, the first time it is opened; the uptime while it is open.
    g.watch(function() return cell.open.value end, function(open: boolean)
        if open then machine.ask() end
        machine.watch(open)
    end)

    local function blurred(): boolean return config.get("cell.blur", true) end
    local function glass(): string return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end

    -- A shape that buds out of the one holding it, and its content once it
    -- is at size.
    local function budding(i: number, t: { [string]: any }, children: { any }): any
        local node: { [any]: any } = {
            name = t.name,
            role = "group",
            overlay = true,
            attach = t.attach,
            present = t.present or function() return cell.expanded() end,
            width = t.width,
            height = t.height,
            offset_x = t.offset_x,
            offset_y = t.offset_y,
            radius = t.radius,
            growth = function() return if shown() and (not t.on or t.on()) then 1 else 0 end,
            bud = function() return if shown() then 0 else m().cell_height end,
            blur = blurred,
            fill = glass,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            on_press = function() end,
            transition = {
                growth = function() return opening(i) end,
                bud = function() return opening(i) end,
                offset_x = function() return opening(i) end,
                offset_y = function() return opening(i) end,
            },
            g.box {
                overlay = true,
                attach = "corner",
                offset_x = t.pad,
                offset_y = t.pad,
                width = function() return t.width() - t.pad() * 2 end,
                height = function() return t.height() - t.pad() * 2 end,
                direction = t.direction or "column",
                justify = t.justify or "start",
                align = t.align or "stretch",
                opacity = function() return if shown() then 1 else 0 end,
                transition = { opacity = function() return if shown() then "pod_content_" .. i else "content_leave" end },
                table.unpack(t.content),
            },
        }
        for _, c in children do table.insert(node, c) end
        return g.capsule(node)
    end
    local function link(i: number, t: { [string]: any }): any
        return thread.new {
            vertical = t.vertical,
            overlay = true,
            attach = t.attach,
            present = function() return cell.expanded() and (not t.on or t.on()) end,
            length = gap,
            reversed = t.reversed,
            shown = function() return shown() and (not t.on or t.on()) end,
            timing = function() return "pod_thread_" .. i end,
            closing = function() return "pod_thread_close_" .. i end,
        }
    end

    local function technical(text: any, t: { [string]: any }?): any
        local o = t or {}
        return g.text {
            text = text,
            color = o.color or theme.text,
            font = typography.technical,
            size = o.size or function() return m().font_meta end,
            weight = o.weight,
            tracking = o.tracking or typography.label_tracking,
            tabular = o.tabular,
            max_width = o.max_width,
        }
    end

    -- ---- The identity ---------------------------------------------------------------

    local function change_avatar()
        if picker.busy() then return end
        focus.aside(cell, function(done: () -> ())
            picker.choose {
                title = "Choose a picture",
                filters = { { "Images (*.png *.jpg *.jpeg *.webp *.bmp)", { "*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp" } } },
                on_chosen = function(path: string?)
                    if path then session.set_avatar(path) end
                    done()
                end,
            }
        end)
    end

    local function identity(): any
        return g.box {
            direction = "row",
            align = "center",
            gap = function() return 18 * f() end,
            g.box {
                width = avatar,
                height = avatar,
                portrait.new { size = avatar, source = session.avatar },
                -- A new picture, chosen from the files.
                g.capsule {
                    role = "button",
                    name = "Change picture",
                    overlay = true,
                    attach = "corner",
                    offset_x = function() return avatar() - 26 * f() end,
                    offset_y = function() return avatar() - 26 * f() end,
                    width = function() return 26 * f() end,
                    height = function() return 26 * f() end,
                    align = "center",
                    justify = "center",
                    fill = function() return theme.gradient_top(theme.primary()) end,
                    fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                    on_click = change_avatar,
                    g.icon {
                        width = function() return 12 * f() end,
                        height = function() return 12 * f() end,
                        icon = "plus",
                        gradient_top = theme.background,
                        gradient_bottom = theme.background,
                    },
                },
            },
            g.box {
                direction = "column",
                align = "start",
                gap = function() return 6 * f() end,
                g.text {
                    text = session.full_name,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_value end,
                    max_width = function() return capsule_width() - 20 * f() - avatar() - 18 * f() end,
                },
                g.text {
                    text = session.login,
                    color = theme.text_muted,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                },
            },
        }
    end

    -- ---- The actions ------------------------------------------------------------------

    local function action_row(i: number, a: { [string]: string }): any
        local function asking(): boolean return session.pending() == a.key end
        local function available(): boolean return session.available(a.key) end
        return g.box {
            width = function() return capsule_width() - panel_padding() * 2 end,
            height = row_height,
            -- At rest: the glyph, the word, its key.
            g.box {
                role = "button",
                name = a.label,
                overlay = true,
                attach = "corner",
                width = function() return capsule_width() - panel_padding() * 2 end,
                height = row_height,
                direction = "row",
                align = "center",
                justify = "between",
                padding_x = function() return 6 * f() end,
                opacity = function() return if asking() then 0 elseif available() then 1 else 0.38 end,
                transition = { opacity = "content_fade" },
                on_click = function() if g.untracked(available) then session.ask(a.key) end end,
                g.box {
                    direction = "row",
                    align = "center",
                    gap = function() return 16 * f() end,
                    g.icon {
                        width = function() return 20 * f() end,
                        height = function() return 20 * f() end,
                        icon = a.glyph,
                        gradient_top = function() return theme.gradient_top(theme.primary()) end,
                        gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    },
                    technical(a.label, { size = function() return m().font_secondary end,
                        weight = typography.weight_value, tracking = 0.04 }),
                },
                g.box {
                    direction = "row",
                    align = "center",
                    gap = function() return 12 * f() end,
                    -- An upgrade has replaced the kernel running.
                    g.box {
                        present = function() return a.key == "restart" and session.restart_due() end,
                        technical("DUE", { color = theme.primary, weight = typography.weight_value }),
                    },
                    g.capsule {
                        width = function() return 22 * f() end,
                        height = function() return 22 * f() end,
                        radius = function() return metrics_mod.shaped(6 * f()) end,
                        align = "center",
                        justify = "center",
                        stroke = metrics_mod.rim_width,
                        rim_top = theme.line,
                        rim_bottom = theme.line,
                        technical(tostring(i), { color = theme.text_muted, tabular = true, tracking = 0 }),
                    },
                },
            },
            -- Asking: the question, in the row it came from.
            g.capsule {
                overlay = true,
                attach = "corner",
                present = asking,
                width = function() return capsule_width() - panel_padding() * 2 end,
                height = row_height,
                radius = function() return metrics_mod.radius_for(row_height(), m()) end,
                stroke = metrics_mod.rim_width,
                rim_top = theme.alert,
                rim_bottom = theme.alert,
                direction = "row",
                align = "center",
                justify = "between",
                padding_left = function() return 16 * f() end,
                padding_right = function() return 6 * f() end,
                g.text {
                    text = sentence(a.label) .. "?",
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                },
                g.box {
                    direction = "row",
                    gap = function() return 8 * f() end,
                    choice.new { metrics = m, label = "Cancel", on_click = session.cancel },
                    choice.new { metrics = m, label = sentence(a.label), kind = "alert", on_click = session.confirm },
                },
            },
        }
    end

    local function actions(): any
        local list: { [any]: any } = { direction = "column" }
        for i, a in ACTIONS do table.insert(list, action_row(i, a)) end
        return g.box(list)
    end

    -- ---- The machine ----------------------------------------------------------------

    local function fact_height(): number
        local room = panel_height() - (panel_padding() + 4 * f()) * 2
        return math.min(24 * f(), room / math.max(1, #machine.rows()))
    end
    local function facts(): any
        return g.each {
            direction = "column",
            align = "start",
            items = machine.rows,
            key = function(r: any) return r.label .. ":" .. r.value end,
            row = function(r: () -> any)
                return g.box {
                    direction = "row",
                    align = "center",
                    height = fact_height,
                    g.box { width = function() return 70 * f() end,
                        technical(function() return r().label end, { color = theme.text_faint }) },
                    g.box {
                        present = function() return r().human end,
                        g.text {
                            text = function() return r().value end,
                            color = theme.text,
                            font = typography.expressive,
                            size = function() return m().font_secondary end,
                            max_width = function() return info_width() - 28 * f() - 70 * f() end,
                        },
                    },
                    g.box {
                        present = function() return not r().human end,
                        technical(function() return r().value end, { tabular = true,
                            max_width = function() return info_width() - 28 * f() - 70 * f() end }),
                    },
                }
            end,
        }
    end

    local function power_content(): any
        return g.box {
            direction = "column",
            align = "start",
            gap = function() return 8 * f() end,
            technical("POWER", { color = theme.text_faint }),
            segmented.new {
                metrics = m,
                font_size = function() return m().font_meta end,
                options = function()
                    return {
                        { key = "saver", label = "Saver" },
                        { key = "balanced", label = "Balanced" },
                        { key = "performance", label = "Performance", dimmed = not power.performance_available() },
                    }
                end,
                current = power.profile,
                on_choose = power.set,
            },
            g.box {
                present = function() return power.held_back() ~= "" end,
                g.text {
                    text = power.held_back,
                    color = theme.text_muted,
                    font = typography.expressive,
                    size = function() return m().font_meta end,
                    max_width = function() return info_width() - 28 * f() end,
                },
            },
        }
    end

    -- ---- The composition -------------------------------------------------------------

    local function info_pad(): number return panel_padding() + 4 * f() end
    local power_panel = budding(3, {
        name = "power",
        attach = if down then "above" else "below",
        on = power.present,
        present = function() return cell.expanded() and power.present() end,
        width = info_width,
        height = capsule_height,
        offset_y = function()
            if not shown() then return 0 end
            return if down then -gap() else gap()
        end,
        radius = function() return m().radius_panel end,
        pad = info_pad,
        justify = "center",
        content = { power_content() },
    }, {})
    local machine_panel = budding(2, {
        name = "machine",
        attach = function() return if info_left() then "left" else "right" end,
        width = info_width,
        height = panel_height,
        offset_x = function()
            if not shown() then return 0 end
            return if info_left() then -gap() else gap()
        end,
        radius = function() return m().radius_panel end,
        pad = info_pad,
        content = { facts() },
    }, {
        link(3, { vertical = true, attach = if down then "above-center" else "below-center", reversed = down, on = power.present }),
        power_panel,
    })
    local commands = budding(1, {
        name = "actions",
        attach = if down then "below" else "above",
        width = capsule_width,
        height = panel_height,
        offset_y = function()
            if not shown() then return 0 end
            return if down then gap() else -gap()
        end,
        radius = function() return m().radius_panel end,
        pad = panel_padding,
        content = { actions() },
    }, {
        link(2, { vertical = false, attach = function() return if info_left() then "left" else "right" end,
            reversed = info_left }),
        machine_panel,
    })

    return {
        panel = {
            width = capsule_width,
            height = capsule_height,
            radius = function() return metrics_mod.radius_for(capsule_height(), m()) end,
            beyond = function() return gap() + panel_height() end,
            content = identity,
            satellites = function()
                return { link(1, { vertical = true, attach = if down then "below-center" else "above-center", reversed = not down }), commands }
            end,
        },
        -- 1 to 5 press an action; Return confirms the question; Escape takes
        -- it back, and only then closes.
        on_key = function(name: string): boolean
            local n = tonumber(name)
            if n and n >= 1 and n <= #ACTIONS then
                session.ask(ACTIONS[n].key)
                return true
            end
            if (name == "Return" or name == "KP_Enter") and g.untracked(session.pending) ~= "" then
                session.confirm()
                return true
            end
            if name == "Escape" and g.untracked(session.pending) ~= "" then
                session.cancel()
                return true
            end
            return false
        end,
    }
end

return M
