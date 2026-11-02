--!strict
-- The setup's niri step (cells/settings/SetupNiri.qml at 2cafc17): Bioma's
-- keys and files in niri's configuration. See docs/design/SETUP.md, step 3.
--
-- What `bioma-install --autostart` does from a terminal, with the outcome
-- drawn instead of printed: the keys file beside config.kdl, the includes,
-- and the line that starts Bioma with the session. config.kdl is copied
-- aside first and handed to `niri validate`; what niri refuses is put back,
-- and the first line it refused is quoted here. Written by Quickshell
-- while the two run side by side (services/setup.luau).
local g = require("@genoma")
local theme = require("core/theme")
local page = require("components/page")
local choice = require("components/choice")
local switch = require("components/switch")
local sweep = require("components/sweep")
local setup = require("services/setup")

local M = {}

-- Starting with the session is on unless it was turned off here; kept
-- across the page being left and come back to.
local autostart = g.signal(true)

function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    local function known(): boolean return setup.report_read() end
    local function has_config(): boolean return setup.niri_state().config == "ok" end
    local function complete(): boolean return setup.niri_set() and (not autostart.value or setup.autostart_set()) end
    local function state(ok: boolean): string
        if setup.niri_error() ~= "" and not ok then return "alert" end
        return if ok then "calm" else "muted"
    end
    g.effect(function()
        if not known() then return end
        local line = if setup.niri_error() ~= "" then "niri refused it"
            elseif setup.niri_set() then (if setup.autostart_set() then "Set up, starts with niri" else "Set up")
            else ""
        if line ~= "" then g.untracked(function() setup.note("niri", line) end) end
    end)
    local home = g.env("HOME") or ""

    return p.column {
        p.section("IN NIRI'S CONFIGURATION", nil, {
            p.fact {
                label = "KEYS",
                detail = function() return "bioma-binds.kdl, beside config.kdl: yours to edit" end,
                state = function() return state(setup.niri_state().binds == "ok") end,
            },
            p.fact {
                label = "INCLUDES",
                detail = function() return "Bioma's niri rules and the keys file" end,
                state = function()
                    local s = setup.niri_state()
                    return state(s.include == "ok" and s["include-binds"] == "ok")
                end,
            },
            p.fact {
                label = "START WITH NIRI",
                detail = function() return "Bioma comes up when the session does" end,
                state = function() return state(setup.autostart_set()) end,
                trailing_width = 50,
                -- Once written, the line is there: taking it out is a
                -- terminal's job, not this switch's.
                trailing = switch.new {
                    factor = f,
                    on = function() return autostart.value or setup.autostart_set() end,
                    dimmed = setup.autostart_set,
                    on_toggle = function(value: boolean) autostart.value = value end,
                },
            },
            g.box {
                present = function() return known() and has_config() and not complete() end,
                direction = "row",
                align = "center",
                gap = function() return 10 * f() end,
                choice.new {
                    metrics = t.metrics,
                    label = function() return if setup.niri_busy() then "WRITING" else "SET UP NIRI" end,
                    kind = "primary",
                    dimmed = setup.niri_busy,
                    on_click = function() setup.set_up_niri(g.untracked(function() return autostart.value end)) end,
                },
                sweep.new { size = 18 * f(), present = setup.niri_busy, running = setup.niri_busy },
            },
            g.box {
                present = function() return setup.niri_error() ~= "" end,
                p.line(function() return "niri refused the result, so config.kdl was put back as it was: " .. setup.niri_error() end, theme.alert),
            },
            p.line(function()
                if not known() then return "Reading niri's configuration…" end
                if not has_config() then return "niri has no configuration file yet. Start niri once, then come back to this step." end
                if complete() then return "Everything is in place. The keys can be changed in Settings → Keybinds." end
                return "config.kdl is copied aside first, and nothing niri would refuse is kept."
            end),
        }),
        p.section("THE FILE", nil, {
            p.line(function()
                local path = setup.niri_config()
                if home ~= "" and string.sub(path, 1, #home + 1) == home .. "/" then return "~" .. string.sub(path, #home + 1) end
                return path
            end, theme.text_muted),
        }, function() return setup.niri_config() ~= "" end),
    }
end

return M
