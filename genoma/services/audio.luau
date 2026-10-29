--!strict
-- The machine's sound (services/Audio.qml), the part read so far: the signal
-- leaving the default sink, which is what raises the media cell. The sinks,
-- sources, streams and their volumes come with the audio cell (phase 4),
-- on Genoma's audio domain.
--
-- The signal is one number, read by `sinestesia-bands --peak`: it captures
-- in stereo and lets PipeWire mix the node down, so a pro-audio interface
-- whose channels are AUX reads true too (Audio.qml's fallback for the
-- PreSonus Revelator, 2026-09-29, here the only way). Ten readings a second:
-- the condition only has to see a signal hold for its confirm step.
local g = require("@genoma")
local config = require("core/config")
local sinestesia = require("services/sinestesia")

local M = {}

local peak = g.signal(0)
function M.peak(): number return peak.value end
function M.signal_present(): boolean return peak.value > 0 end

g.effect(function()
    if not config.get("audio.monitor_signal", true) then return end
    g.untracked(function()
        g.process {
            command = { sinestesia.binary, "--peak", "--fps", "10" },
            on_line = function(line: string) peak.value = tonumber(line) or 0 end,
            on_exit = function() peak.value = 0 end,
        }
    end)
end)

return M
