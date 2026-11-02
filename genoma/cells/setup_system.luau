--!strict
-- The setup's system step (cells/settings/SetupSystem.qml at 2cafc17):
-- `bioma-install --check`, drawn. See docs/design/SETUP.md, step 6.
--
-- It exists only when something is missing. Packages are named by what
-- they are for, with the one command that installs them all: Bioma never
-- runs a package manager. Services installed but off are enabled in place,
-- through pkexec. Another polkit agent started with the session is named,
-- with where it starts, and handed over in one press, or kept, which
-- switches Bioma's off: polkit allows one, and two only race.
local g = require("@genoma")
local config = require("core/config")
local theme = require("core/theme")
local colour = require("core/colour")
local page = require("components/page")
local choice = require("components/choice")
local setup = require("services/setup")

local M = {}

function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    g.effect(function()
        local parts = {}
        local missing, off = #setup.missing(), #setup.disabled()
        if missing > 0 then table.insert(parts, if missing == 1 then "One to install" else missing .. " to install") end
        if off > 0 then table.insert(parts, if off == 1 then "one service off" else off .. " services off") end
        if setup.polkit_rival() ~= "" then table.insert(parts, if #parts > 0 then "another polkit agent" else "Another polkit agent") end
        local line = if #parts > 0 then table.concat(parts, ", ") else "Nothing missing"
        g.untracked(function() setup.note("system", line) end)
    end)

    local function service_row(unit: () -> string): any
        return p.fact {
            label = function() return string.upper((string.gsub(unit(), "%.service$", ""):gsub("%.socket$", ""))) end,
            detail = function()
                local e = setup.enable_error(unit())
                if e == "not given" then return "The password was not given." end
                if e == "no agent" then return "Nothing could ask for the password." end
                if e == "failed" then return "systemd refused it." end
                return "Installed, and off: the cells that read it stay empty."
            end,
            state = function() return if setup.enable_error(unit()) ~= "" then "alert" else "active" end,
            trailing = choice.new {
                metrics = t.metrics,
                label = function() return if setup.enabling(unit()) then "ENABLING" else "ENABLE" end,
                dimmed = function() return setup.enabling(unit()) or not setup.polkit_agent() end,
                on_click = function() setup.enable_service(g.untracked(unit)) end,
            },
        }
    end

    local function places(): string
        local said = { niri = "niri's configuration", unit = "a systemd unit", autostart = "the session's autostart", running = "" }
        local out = {}
        for _, source in setup.polkit_sources() do
            local s = said[source.kind] or ""
            if s ~= "" and not table.find(out, s) then table.insert(out, s) end
        end
        return table.concat(out, " and ")
    end

    return p.column {
        p.section("TO INSTALL", nil, {
            g.each {
                direction = "column",
                align = "start",
                gap = function() return 10 * f() end,
                items = setup.missing,
                key = function(e: any) return e.name end,
                row = function(e: () -> any)
                    return p.fact {
                        label = function() return string.upper(e().name) end,
                        detail = function() return e().what end,
                        state = function() return "active" end,
                    }
                end,
            },
            p.command(setup.install_command, function() return setup.install_command() ~= "" end),
        }, function() return #setup.missing() > 0 end),
        p.section("TO SWITCH ON", nil, {
            g.each {
                direction = "column",
                align = "start",
                gap = function() return 10 * f() end,
                items = setup.disabled,
                key = function(u: string) return u end,
                row = service_row,
            },
            p.command(function() return "sudo systemctl enable --now " .. table.concat(setup.disabled(), " ") end,
                function() return not setup.polkit_agent() end),
        }, function() return #setup.disabled() > 0 end),
        p.section("PASSWORDS", nil, {
            p.line(function()
                local where = places()
                return setup.polkit_rival() .. " asks for passwords in this session"
                    .. (if where ~= "" then ", started by " .. where .. ". " else ". ")
                    .. "Bioma has its own agent, with the lock screen's field, and polkit allows only one. "
                    .. "Switching turns the other off where it starts — commented out, disabled or hidden, never deleted."
            end),
            p.fact {
                present = function() return setup.hand_over_error() ~= "" end,
                label = "NOT SWITCHED",
                detail = setup.hand_over_error,
                state = function() return "alert" end,
            },
            g.box {
                direction = "row",
                gap = function() return 8 * f() end,
                choice.new {
                    metrics = t.metrics,
                    label = function() return if setup.handing_over() then "Switching" else "Use Bioma's agent" end,
                    kind = "primary",
                    dimmed = setup.handing_over,
                    on_click = setup.use_bioma_agent,
                },
                choice.new {
                    metrics = t.metrics,
                    label = function() return "Keep " .. setup.polkit_rival() end,
                    dimmed = setup.handing_over,
                    on_click = setup.keep_other_agent,
                },
            },
        }, function() return setup.polkit_rival() ~= "" end),
        p.section("PASSWORDS", nil, {
            p.line(function()
                if setup.polkit_wanted() then
                    return "No polkit agent is running, so nothing in Bioma that needs your password can ask for it. Bioma's own could not register with polkit; the shell's log says why."
                end
                return "No polkit agent is running, so nothing in Bioma that needs your password can ask for it. Bioma has its own, and it is switched off: turn it back on, or install another and start it with niri — polkit-gnome is the usual choice."
            end),
            g.box {
                present = function() return not setup.polkit_wanted() end,
                choice.new {
                    metrics = t.metrics,
                    label = "Use Bioma's agent",
                    kind = "primary",
                    on_click = function() config.set("polkit.agent", true) end,
                },
            },
        }, function() return not setup.polkit_agent() and setup.polkit_rival() == "" end),
        g.capsule {
            present = setup.dictation_missing,
            width = t.width,
            height = 1,
            crisp = true,
            rim_top = function() return colour.alpha(theme.line(), 0.7) end,
            rim_bottom = function() return colour.alpha(theme.line(), 0.7) end,
            dash = 3,
            dash_gap = 3,
        },
        p.section("OPTIONAL · DICTATION", nil, {
            p.line(function() return "Speech typed into any window, with Mod+Alt+D. About half a gigabyte, for one key." end),
            p.command(function() return setup.dictation_command end),
        }, setup.dictation_missing),
    }
end

return M
