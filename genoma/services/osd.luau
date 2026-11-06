--!strict
-- What the on-screen display is saying, and where (services/Osd.qml at
-- 8ed8892).
--
-- The shell answers a change in the volume or the brightness where
-- something already speaks for it, the audio cell, where there is one; the
-- display is for where there is none (Akusen, 2026-09-23). So it shows the
-- brightness always, having no cell, and the volume only on a monitor that
-- declares no audio cell; the keyboard's layout the same, where no keyboard
-- cell is declared (2026-10-08); performance mode going on or off both ways
-- (2026-10-24), and focus mode the same (2026-11-07). It shows on the monitor the keyboard is pointed at, where
-- the key that changed it was pressed.
local g = require("@genoma")
local timing = require("core/timing")

local M = {}

-- "volume" | "brightness" | "layout" | "performance" | "focus" | "" while
-- nothing is said.
local kind = g.signal("")
local output = g.signal("")
function M.kind(): string return kind.value end
function M.output(): string return output.value end

-- The cell that already says each kind, where there is one.
local SPEAKERS = { volume = "audio", layout = "keyboard" }

-- The values going from nothing to what they are while the services start
-- is not a change anybody made.
local settled = false
local quiet: any = nil

function M.say(what: string)
    if not settled then return end
    local niri = require("services/niri")
    local focus = require("structure/focus")
    local where = g.untracked(niri.focused_output)
    if where == "" then return end
    local domain = SPEAKERS[what]
    if domain and focus.declared(domain, where) then return end
    g.batch(function()
        kind.value = what
        output.value = where
    end)
    if quiet then quiet:stop() end
    quiet = g.after(timing.seconds.osd, function()
        quiet = nil
        kind.value = ""
    end)
end

local started = false
function M.start()
    if started then return end
    started = true
    g.after(timing.seconds.settle, function() settled = true end)

    local audio = require("services/audio")
    local before: any = nil
    g.watch(function() return { audio.volume(), audio.muted() } end, function(now: { any })
        local was = before
        before = now
        if was and (was[1] ~= now[1] or was[2] ~= now[2]) then M.say("volume") end
    end)

    -- The first reading is not a change: over DDC the brightness is read
    -- seconds after start, later than settling, so its first known value is
    -- only remembered.
    local brightness = require("services/brightness")
    local heard = -1
    g.watch(function() return { brightness.known(), brightness.brightness() } end, function(now: { any })
        if not now[1] then return end
        local first = heard < 0
        local moved = heard ~= now[2]
        heard = now[2]
        if not first and moved then M.say("brightness") end
    end)

    local performance = require("core/performance")
    local was_active: boolean? = nil
    g.watch(performance.active, function(on: boolean)
        local was = was_active
        was_active = on
        if was ~= nil and was ~= on then M.say("performance") end
    end)

    local focus_mode = require("core/focus_mode")
    local was_focused: boolean? = nil
    g.watch(focus_mode.active, function(on: boolean)
        local was = was_focused
        was_focused = on
        if was ~= nil and was ~= on then M.say("focus") end
    end)

    -- The keyboard reports a switch only after its first reading.
    require("services/keyboard").on_switched(function() M.say("layout") end)
end

return M
