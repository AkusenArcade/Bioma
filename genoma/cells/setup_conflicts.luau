--!strict
-- The setup's conflicts (cells/settings/SetupConflicts.qml at 2cafc17):
-- another shell still starting with niri. See docs/design/SETUP.md, step 5.
--
-- Two things then go wrong without saying why: two bars on one edge, and
-- notifications that never reach Bioma, because the name has one owner per
-- session. Each row says what it collides on and where it starts from.
-- STOP ends it now and takes it out of startup (asked of Quickshell): a
-- spawn line is commented out, never deleted; a user unit is disabled.
local g = require("@genoma")
local theme = require("core/theme")
local page = require("components/page")
local choice = require("components/choice")
local setup = require("services/setup")

local M = {}

local function where(from: string): string
    if string.sub(from, 1, 5) == "niri:" then
        return "started by niri, " .. (string.match(from, "([^/]+)$") or string.sub(from, 6))
    end
    if string.sub(from, 1, 5) == "unit:" then return "started by systemd, " .. string.sub(from, 6) end
    return "where it starts from was not found"
end

function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    g.effect(function()
        local n = #setup.conflicts()
        local line = if n == 0 then "Nothing else running" elseif n == 1 then "One other shell" else n .. " other shells"
        g.untracked(function() setup.note("conflicts", line) end)
    end)

    local function row(item: () -> any): any
        local function pid(): string return item().pid end
        return p.fact {
            label = function() return string.upper(item().name) end,
            detail = function()
                local c = item()
                local err = setup.stop_error(c.pid)
                return (if c.what == "notifications" then "Owns the notifications; " else "Draws a bar; ")
                    .. where(c.from) .. (if err ~= "" then ". " .. err else "")
            end,
            state = function() return if setup.stop_error(pid()) ~= "" then "alert" else "active" end,
            trailing = choice.new {
                metrics = t.metrics,
                label = function() return if setup.stopping(pid()) then "STOPPING" else "STOP" end,
                dimmed = function() return setup.stopping(pid()) end,
                on_click = function() setup.stop(g.untracked(item)) end,
            },
        }
    end

    local function none_found(): boolean
        for _, c in setup.conflicts() do
            if c.from == "none" then return true end
        end
        return false
    end

    return p.column {
        p.section("ALSO DRAWING THIS DESKTOP", nil, {
            g.each {
                direction = "column",
                align = "start",
                gap = function() return 10 * f() end,
                items = setup.conflicts,
                key = function(c: any) return c.pid end,
                row = row,
            },
            g.box {
                present = function() return #setup.conflicts() == 0 end,
                p.line(function() return "Nothing else is drawing this desktop now." end),
            },
            g.box {
                present = none_found,
                p.line(function() return "Where it starts from could not be found, so STOP only stops it: it will come back at the next login." end, theme.text_muted),
            },
        }),
        p.section("NOTIFICATIONS", nil, {
            p.line(function() return "Bioma takes the notifications over once it starts again, which it does by itself when this setup is done." end),
        }, setup.restart_at_end),
    }
end

return M
