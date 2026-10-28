--!strict
-- The temporal grammar (structure/Visibility.qml). Every cell owns one.
--
--   always       never hidden, never takes keyboard focus
--   conditional  appears when a condition becomes true, never takes focus
--   invoked      appears on a shortcut, takes keyboard focus, closes on the
--                same shortcut, Escape, or a click outside
--
-- The types combine: the same cell may be conditional and invocable. Three
-- parameters on the condition, asymmetric on purpose — appear promptly, leave
-- slowly. Interaction suspends disappearance, and the dwell resumes where it
-- stopped rather than restarting.
local g = require("@genoma")

local M = {}

export type Rule = { type: string, enter: number, exit: number, confirm: number, dwell: number }

-- `rule()` gives the type and the figures (confirm and dwell in ms);
-- `value()` the measurement the condition watches. Both are read reactively.
function M.new(rule: () -> Rule, value: () -> number)
    local v = {}
    local met = g.signal(false)
    local invoked = g.signal(false)
    local interacting = g.signal(false)
    local confirm: any = nil
    local dwell: any = nil
    local dwell_left = 0     -- seconds, while paused under the pointer
    local dwell_end = 0      -- when the running dwell fires, g.now()

    local function stop_confirm()
        if confirm then confirm:stop(); confirm = nil end
    end
    local function stop_dwell()
        if dwell then dwell:stop(); dwell = nil end
    end
    local function start_dwell(seconds: number)
        stop_dwell()
        dwell_end = g.now() + seconds
        dwell = g.after(seconds, function()
            dwell = nil
            met.value = false
        end)
    end

    local function evaluate()
        local r = rule()
        if r.type ~= "conditional" then return end
        local x = value()
        if not met.value and x >= r.enter then
            stop_dwell()
            if not confirm then
                confirm = g.after(r.confirm / 1000, function()
                    confirm = nil
                    met.value = true
                end)
            end
        elseif met.value and x < r.exit then
            stop_confirm()
            if not interacting.value and not dwell then start_dwell(r.dwell / 1000) end
        elseif not met.value and x < r.enter then
            stop_confirm()
        elseif met.value and x >= r.exit then
            stop_dwell()
            dwell_left = 0
        end
    end

    -- On the measurement and the rule, as QML's onValueChanged.
    g.watch(function() return { value(), rule() } end, function() evaluate() end)

    -- While the pointer is on the cell the dwell holds, and resumes where it
    -- stopped: a stray hover must not keep the cell alive indefinitely. If
    -- the condition lapsed while the pointer was on it, no dwell ran, and
    -- there is nothing to resume: evaluated again.
    g.watch(function() return interacting.value end, function(on: boolean)
        if on and dwell then
            dwell_left = math.max(0, dwell_end - g.now())
            stop_dwell()
        elseif not on and dwell_left > 0 then
            local left = dwell_left
            dwell_left = 0
            start_dwell(left)
        elseif not on then
            evaluate()
        end
    end)

    -- Asked for is asked for, whatever the type says: a conditional cell
    -- that is not on the membrane still answers a shortcut.
    function v.shown(): boolean
        local t = rule().type
        return t == "always" or invoked.value or met.value
    end

    function v.invoked(): boolean return invoked.value end
    function v.set_invoked(on: boolean) invoked.value = on end
    function v.toggle() invoked.value = not invoked.value end
    function v.set_interacting(on: boolean) interacting.value = on end
    function v.type(): string return rule().type end

    return v
end

return M
