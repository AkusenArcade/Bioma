--!strict
-- Focus mode (Akusen, 2026-11-06): the desktop handed to the windows. The
-- membranes fold away over their own edge and give their strips back, the
-- organisms recede into the screen, and the cells answer only when they
-- are asked for. What speaks without being asked waits: an ordinary
-- notification is held until the mode ends; the on-screen display and a
-- critical notification still come, since the first answers a gesture and
-- the other is not to be missed. The privacy cell waits too (Akusen,
-- 2026-11-09): in focus mode it is one more thing on the screen.
--
-- Not `structure/focus.luau`, which is the attention (which cell is open).
--
-- The mode goes in two steps. `active` is what was asked for: the strips
-- are given back and the folding starts at once. `settled` follows once
-- the fold has run its time: only then do the cells on the folded
-- membranes go quiet, so the membranes are seen folding with what they
-- held, not emptying first. Leaving undoes both at once, and the cells
-- come back while their membranes unfold.
--
-- A cell asked for by its key appears in the middle of its monitor, as a
-- cell with no place does (`focus_mode.summon` = "centre"), or at its own
-- place, its membrane unfolding for it alone ("place").
--
-- On for the session: kept across a reload, not across a restart, so a
-- new session never starts with the desktop hidden.
local g = require("@genoma")
local config = require("core/config")
local timing = require("core/timing")

local M = {}

local active = g.state("focus_mode.active", false)
local settled = g.signal(g.untracked(function() return active.value end))
local settling: any = nil

function M.active(): boolean return active.value end
function M.settled(): boolean return settled.value end

-- Where a cell asked for by its key appears while the mode lasts.
function M.summon(): string
    return if config.get("focus_mode.summon", "centre") == "place" then "place" else "centre"
end
function M.summons_centre(): boolean return active.value and M.summon() == "centre" end

g.watch(function() return active.value end, function(on: boolean)
    if settling then settling:stop() end
    settling = nil
    if not on then
        settled.value = false
        return
    end
    settling = g.after(timing.seconds.fold, function()
        settling = nil
        if g.untracked(function() return active.value end) then settled.value = true end
    end)
end)

function M.on() active.value = true end
function M.off() active.value = false end
function M.toggle() active.value = not g.untracked(function() return active.value end) end
function M.set(on: boolean) active.value = on end

return M
