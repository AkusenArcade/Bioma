--!strict
-- The session's authentication agent (services/Polkit.qml at 11bb81e): what
-- asks for the password when something the user started needs permission:
-- mounting a disk, changing a system service, `pkexec`.
--
-- Genoma carries the agent itself (`@genoma/polkit`); this is the one place
-- that holds it. When polkit asks, the polkit cell is summoned into the
-- middle of the screen the keyboard is pointed at; when the request ends,
-- however it ends, the cell goes. Closing the cell is cancelling.
--
-- One agent per session is polkit's rule, so this one registers only when
-- `polkit.agent` is on (the default), and a session that already runs
-- another (Bioma on Quickshell's, while the two run side by side) keeps
-- whichever registered first. `GENOMA_POLKIT_PROCESS=<pid>` registers it
-- for that one process instead: how the cell is tried beside the session's
-- agent.
--
-- BIOMA_GENOMA_POLKIT_FAKE=1 registers nothing and asks with a request of
-- its own a few seconds after the start: the cell is drawn, answered and
-- closed with no PAM behind it. polkit's PAM counts every failed or
-- abandoned conversation toward pam_faillock's lockout (three in fifteen
-- minutes), so the interface is never tried against the real helper.
local g = require("@genoma")
local config = require("core/config")

local M = {}

local fake = g.env("BIOMA_GENOMA_POLKIT_FAKE") ~= nil
local wanted = g.untracked(function() return config.get("polkit.agent", true) end) ~= false
local agent: any = if wanted and not fake then require("@genoma/polkit") else nil
local pretend = g.signal(nil :: any)

function M.registered(): boolean return agent ~= nil and agent.registered == true end

-- The request being answered: { cookie, action_id, message, icon_name,
-- user, prompt, echo, failed, info }, or nil.
local request = g.computed(function(): any
    if fake then return pretend.value end
    if not agent then return nil end
    return agent.request
end)

if fake then
    local function ask(failed: boolean)
        pretend.value = {
            cookie = "fake", action_id = "org.freedesktop.policykit.exec",
            message = "Authentication is needed to run `/usr/bin/true' as the super user",
            icon_name = "", user = "test", prompt = "Password: ", echo = false, failed = failed, info = "",
        }
    end
    g.after(3, function() ask(false) end)
    -- "right" is the password; anything else is refused and asked again.
    function M.submit(password: string)
        g.after(0.6, function()
            if password == "right" then pretend.value = nil else ask(true) end
        end)
    end
    function M.cancel() pretend.value = nil end
end
function M.request(): any return request.value end
function M.asking(): boolean return request.value ~= nil end

-- Said once, because a second agent in the session is not a failure of
-- Bioma's, but it does mean this one will never ask.
if agent then
    local said = false
    g.watch(M.registered, function(on: boolean)
        if on and not said then
            said = true
            print("Bioma: polkit agent registered")
        end
    end)
    g.after(5, function()
        if not g.untracked(M.registered) then
            print("Bioma: another polkit agent holds this session; Bioma's will not ask (" .. tostring(agent.error) .. ")")
        end
    end)
end

if not fake then
    function M.submit(password: string)
        local r = g.untracked(M.request)
        if r and agent then agent:respond(r.cookie, password) end
    end

    -- Closing the cell is the answer "no": whatever was waiting is told so,
    -- rather than left to time out.
    function M.cancel()
        local r = g.untracked(M.request)
        if r and agent then agent:cancel(r.cookie) end
    end
end

-- Summoned where the keyboard is, and taken away from the same screen even
-- if the keyboard has moved on meanwhile. Required by the shell at start,
-- so the agent is there before anything asks.
function M.start()
    local focus = require("structure/focus")
    local niri = require("services/niri")
    local output: string? = nil
    g.watch(M.asking, function(asking: boolean)
        if asking then
            local focused = g.untracked(niri.focused_output)
            output = if focused ~= "" then focused else nil
            local c = focus.cell_for("polkit", output)
            if not (c and g.untracked(c.shown)) then focus.invoke("polkit", output) end
        else
            focus.retire("polkit", output)
        end
    end)
end

return M
