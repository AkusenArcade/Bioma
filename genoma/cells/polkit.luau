--!strict
-- Permission, asked for: the session's authentication agent made visible
-- (cells/polkit/PolkitCell.qml and PolkitPanel.qml at 11bb81e). See
-- docs/design/CELLS.md §19.
--
-- Never placed and never asked for by a key: polkit asks, and the cell is
-- summoned into the middle of the screen the keyboard is on (services/
-- polkit.luau). It wears AUTHENTICATION with the lock in its pill and hangs
-- the request from it: the icon of the action, the message polkit was
-- given, and the field, drawn as the lock screen draws it, because it is
-- the same password and the same gesture. Enter answers; Escape, a press
-- outside or CANCEL is "no", and polkit is told so at once rather than left
-- to wait.
--
-- A refused password empties the field for the next try, where Quickshell
-- selects it: typing replaces it either way (Genoma's field has no
-- select-all from outside yet).
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local field = require("components/field")
local choice = require("components/choice")
local polkit = require("services/polkit")

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 20 * f() end
        local function inner(): number return 380 * f() end
        local function portrait(): number return 36 * f() end
        local function words_width(): number return inner() - portrait() - 14 * f() end
        local function field_height(): number return 44 * f() end
        local function message_size(): number return math.round(15 * f()) end

        local function request(): any return polkit.request() or {} end
        local function failed(): boolean return request().failed == true end

        -- Between the press and polkit's answer the field steps back, as the
        -- lock's does while PAM is checking: nothing moves without a value.
        local checking = g.signal(false)
        local secret = g.signal("")
        local function answer()
            local r = g.untracked(polkit.request)
            if not r or g.untracked(function() return checking.value end) then return end
            checking.value = true
            polkit.submit(g.untracked(function() return secret.value end))
        end
        local field_node, field_handle = field.new {
            text = secret,
            secret = true,
            -- As wide as what is typed, so the capsule centres it.
            width = function()
                local typed = g.text_width { text = string.rep("•", utf8.len(secret.value) or 0),
                    font = typography.expressive(), size = math.round(16 * f()) }
                return math.clamp(typed + 4 * f(), 4 * f(), inner() - 40 * f())
            end,
            font = typography.expressive,
            size = function() return math.round(16 * f()) end,
            taking = function() return cell.open.value and not checking.value end,
            on_submit = answer,
        }

        -- polkit's answer: asked again (refused, or the next prompt), or done.
        g.watch(function()
            local r = polkit.request()
            return if r then tostring(r.cookie) .. tostring(r.failed) .. tostring(r.prompt) .. tostring(r.info) else ""
        end, function()
            checking.value = false
            if g.untracked(failed) then field_handle.set("") end
        end)
        -- A new request starts with an empty field.
        g.watch(function() return tostring(request().cookie) end, function() field_handle.set("") end)

        -- Closed by the user is cancelled; closed because the request ended
        -- is nothing to cancel, and the service knows the difference. Only a
        -- close counts: g.watch answers once at the start too, when the cell
        -- is not open yet, and a cancel then failed the request before it
        -- was shown, which polkit's PAM counts as a failed password.
        local was_open = false
        g.watch(function() return cell.open.value end, function(open: boolean)
            if was_open and not open then polkit.cancel() end
            was_open = open
        end)

        -- What polkit says back: a refusal in the alert colour, anything
        -- else in the muted voice.
        local function said(): string
            local r = request()
            if (r.info or "") ~= "" then return r.info end
            return if r.failed then "That password was not accepted" else ""
        end
        -- polkit's own word for what it wants, without the colon its terminal
        -- habit puts after it.
        local function prompt(): string
            local p = string.gsub(request().prompt or "", "[:%s]+$", "")
            return if p ~= "" then p else "Password"
        end
        local function icon(): string
            local name = request().icon_name or ""
            return if name ~= "" then (g.icon_path(name) or "") else ""
        end

        local function lines(text: string, size: number, width: number): number
            if text == "" then return 0 end
            local w = g.text_width { text = text, font = typography.expressive(), size = size }
            return math.max(1, math.ceil(w / math.max(1, width)))
        end
        local function words_height(): number
            local message = math.min(4, lines(request().message or "", message_size(), words_width()))
            return message * message_size() * 1.4 + 4 * f() + m().font_meta * 1.4
        end
        local function said_height(): number
            local n = lines(said(), m().font_secondary, inner())
            return if n > 0 then n * m().font_secondary * 1.4 + 10 * f() else 0
        end
        local function content_height(): number
            return math.max(portrait(), words_height()) + 16 * f() + field_height() + said_height() + 16 * f() + 26 * f()
        end

        local function content(): any
            return g.box {
                width = inner,
                direction = "column",
                align = "start",
                -- What is asking: the action's icon in the dark circle every
                -- third-party icon in the shell sits in, the message, and
                -- under it the action's own name, which is the machine's.
                g.box {
                    width = inner,
                    direction = "row",
                    align = "start",
                    gap = function() return 14 * f() end,
                    g.capsule {
                        width = portrait,
                        height = portrait,
                        align = "center",
                        justify = "center",
                        fill = function() return theme.lift(theme.background(), -0.015) end,
                        rim_top = function() return colour.alpha(theme.text(), 0.5) end,
                        rim_bottom = function() return colour.alpha(theme.text(), 0.5) end,
                        g.icon {
                            present = function() return icon() ~= "" end,
                            width = function() return portrait() * 0.62 end,
                            height = function() return portrait() * 0.62 end,
                            icon = icon,
                        },
                        g.icon {
                            present = function() return icon() == "" end,
                            width = function() return portrait() * 0.5 end,
                            height = function() return portrait() * 0.5 end,
                            icon = "lock",
                            gradient_top = theme.text_muted,
                            gradient_bottom = theme.text_muted,
                        },
                    },
                    g.box {
                        width = words_width,
                        direction = "column",
                        align = "start",
                        gap = function() return 4 * f() end,
                        g.text {
                            text = function() return request().message or "" end,
                            color = theme.text,
                            font = typography.expressive,
                            size = message_size,
                            max_width = words_width,
                            wrap = true,
                        },
                        g.text {
                            text = function() return request().action_id or "" end,
                            color = theme.text_faint,
                            font = typography.technical,
                            size = function() return m().font_meta end,
                            tracking = typography.label_tracking,
                            max_width = words_width,
                        },
                    },
                },
                g.box { width = 1, height = function() return 16 * f() end },
                -- The field, as the lock screen draws it: the outline turns
                -- to the primary when it has the keys and to the alert when
                -- the password was refused.
                g.capsule {
                    width = inner,
                    height = field_height,
                    radius = function() return metrics_mod.radius_for(field_height(), m()) end,
                    fill = function()
                        return colour.alpha(theme.lift(theme.background(), -0.01), config.get("cell.opacity", 0.72))
                    end,
                    stroke = 1.5,
                    rim_top = function()
                        return if failed() then theme.alert() elseif cell.open.value then theme.primary() else theme.line()
                    end,
                    rim_bottom = function()
                        return if failed() then theme.alert() elseif cell.open.value then theme.primary() else theme.line()
                    end,
                    align = "center",
                    justify = "center",
                    opacity = function() return if checking.value then 0.6 else 1 end,
                    transition = { rim_top = "colour", rim_bottom = "colour", opacity = "transition" },
                    g.text {
                        present = function() return secret.value == "" end,
                        text = prompt,
                        color = theme.text_muted,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                    },
                    g.box {
                        present = function() return secret.value ~= "" end,
                        field_node,
                    },
                },
                g.box {
                    width = 1,
                    present = function() return said() ~= "" end,
                    height = function() return 10 * f() end,
                },
                g.box {
                    width = inner,
                    present = function() return said() ~= "" end,
                    justify = "center",
                    g.text {
                        text = said,
                        color = function()
                            return if failed() then theme.alert() else theme.text_muted()
                        end,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = inner,
                        wrap = true,
                    },
                },
                g.box { width = 1, height = function() return 16 * f() end },
                g.box {
                    width = inner,
                    direction = "row",
                    justify = "end",
                    gap = function() return 8 * f() end,
                    choice.new {
                        label = "Cancel",
                        metrics = m,
                        on_click = function()
                            polkit.cancel()
                            cell.open.value = false
                        end,
                    },
                    g.box {
                        opacity = function() return if checking.value then 0.4 else 1 end,
                        choice.new { label = "Authenticate", kind = "primary", metrics = m, on_click = answer },
                    },
                },
            }
        end

        local function mark(size: () -> number): any
            return g.icon {
                width = size,
                height = size,
                icon = "lock",
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            }
        end

        return {
            panel = {
                width = function() return inner() + 20 * f() end,
                height = function() return content_height() + 20 * f() end,
                content = content,
            },
            wants_keyboard = true,
            padding_leading = function() return (m().cell_height - glyph()) / 2 end,
            padding_trailing = function() return (m().cell_height - glyph()) / 2 end,
            content_width = glyph,
            header_title = "AUTHENTICATION",
            header_mark_size = glyph,
            header_mark = mark,
            contracted = function() return mark(glyph) end,
            -- The field's, while open; Escape is the cell's: it closes, and
            -- closing is "no".
            on_key = function(name: string, typed: string?, mods: { [string]: boolean }): boolean
                if name == "Escape" then return false end
                if not g.untracked(function() return cell.open.value end) then return false end
                return field_handle.key(name, typed, mods)
            end,
        }
    end,
}
