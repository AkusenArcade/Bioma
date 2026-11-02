--!strict
-- The setup's login step (cells/settings/SetupLogin.qml at 2cafc17): the
-- login screen, as a choice. See docs/design/SETUP.md, step 4.
--
-- The login screen is the one thing Bioma must not change without asking
-- (Akusen, 2026-10-13): KEEP is what is there, and NEXT without touching
-- anything keeps it. Choosing Bioma runs `scripts/greeter-setup enable`
-- through pkexec (asked of Quickshell, services/setup.luau), and the
-- password is asked by the session's polkit agent. Nothing is restarted:
-- it takes effect at the next boot.
local g = require("@genoma")
local theme = require("core/theme")
local page = require("components/page")
local setup = require("services/setup")

local M = {}

function M.new(t: { [string]: any }): any
    local p = page.new(t)
    -- Which row a press asked for, while pkexec runs.
    local asked = g.signal(false)
    local function no_agent(): boolean
        return not setup.polkit_agent() or string.find(setup.login_error(), "Nothing could ask", 1, true) == 1
    end
    g.effect(function()
        if not setup.greeter_read() then return end
        local line = if setup.bioma_greeter() then "Bioma's login screen"
            else "Kept " .. (if setup.manager_name() == "TEXT LOGIN" then "the text login" else setup.manager_name())
        g.untracked(function() setup.note("login", line) end)
    end)
    local function choose(bioma: boolean)
        asked.value = bioma
        setup.set_greeter(bioma)
    end

    return p.column {
        p.section("WHO GREETS YOU", nil, {
            p.option {
                label = function() return "BIOMA'S LOGIN SCREEN" end,
                line = function() return "Your wallpaper, your palette and your picture, before anyone is logged in." end,
                chosen = setup.bioma_greeter,
                busy = function() return setup.login_busy() and asked.value end,
                on_click = function() choose(true) end,
            },
            p.option {
                label = function()
                    if setup.bioma_greeter() and setup.manager() == "greetd.service" then return "THE ONE BEFORE BIOMA" end
                    return "KEEP " .. setup.manager_name()
                end,
                line = function()
                    local mgr = setup.manager()
                    if mgr == "none" or mgr == "" then return "A text login on the console, as now." end
                    return "The login screen this machine has now, unchanged."
                end,
                chosen = function() return not setup.bioma_greeter() end,
                busy = function() return setup.login_busy() and not asked.value end,
                on_click = function() choose(false) end,
            },
            g.box {
                present = function() return setup.login_error() ~= "" end,
                p.line(setup.login_error, theme.alert),
            },
            p.line(function()
                if setup.bioma_greeter() then
                    return "From the next boot. greetd's old configuration is kept as config.toml.before-bioma, and removing Bioma puts it back."
                end
                return "Choosing Bioma asks for your password, and takes effect from the next boot."
            end),
        }),
        -- When nothing can ask for the password, the same thing as a command.
        p.section("FROM A TERMINAL", nil, {
            p.line(function() return "No polkit agent is running, so nothing here can ask for your password. The same change, from a terminal:" end),
            p.command(function() return setup.login_command(not setup.bioma_greeter()) end),
        }, no_agent),
    }
end

return M
