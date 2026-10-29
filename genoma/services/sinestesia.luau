--!strict
-- The sound leaving the machine, as bands (services/Sinestesia.qml).
--
-- The capture and the transform are `tools/sinestesia-bands`'s: one process,
-- since two capturing the same audio is an error paid for later. This reads
-- what it emits. It runs only while something draws the band (a media cell
-- on screen, an organism on a desktop that shows), and it is shut by
-- closing it: it exits when its stdout does.
--
-- Performance mode's still band comes with the performance service.
local g = require("@genoma")
local config = require("core/config")
local performance = require("core/performance")
local paths = require("core/paths")

local M = {}

M.binary = paths.root .. "/tools/sinestesia-bands/target/release/sinestesia-bands"

-- Who is drawing it. A list rather than a switch: two holders (two
-- membranes' cells, a cell and an organism) would turn each other off.
local holders = g.signal({})
function M.hold(owner: any, wanted: boolean)
    local now = g.untracked(function() return holders.value end)
    local held = table.find(now, owner) ~= nil
    if wanted and not held then
        local next_list = table.clone(now)
        table.insert(next_list, owner)
        holders.value = next_list
    elseif not wanted and held then
        local next_list = {}
        for _, h in now do
            if h ~= owner then table.insert(next_list, h) end
        end
        holders.value = next_list
    end
end
-- Held, and not stilled by performance mode's motion lever: a still band
-- needs no spectrum.
function M.active(): boolean return #holders.value > 0 and not performance.still() end

function M.band_count(): number return config.get("sinestesia.bands", 64) end
-- How every band draws the sound: bars, plasma, vesicles or eardrum
-- (components/Band.qml), a property of the domain: the cell and the organism
-- show the same sound the same way.
function M.effect(): string return config.get("sinestesia.effect", "eardrum") end

-- One spectrum per channel, `band_count` values 0…1, lowest first; and the
-- loudest band of the last frame.
local left = g.signal({})
local right = g.signal({})
local level = g.signal(0)
function M.left(): { number } return left.value end
function M.right(): { number } return right.value end
function M.level(): number return level.value end

-- Without the tool built there is no band, and a cell with nothing to say
-- does not appear: half a visualiser is worse than none.
local available = g.signal(true)
local failures = 0
function M.available(): boolean return available.value end

-- One line a frame, two hexadecimal digits a band, the left channel then
-- the right.
local function take(line: string)
    local text = string.match(line, "^%s*(.-)%s*$") or ""
    local half = #text // 4
    if half == 0 then return end
    local one, other, loudest = table.create(half), table.create(half), 0
    for i = 0, half - 1 do
        local l = (tonumber(string.sub(text, i * 2 + 1, i * 2 + 2), 16) or 0) / 255
        local r = (tonumber(string.sub(text, (half + i) * 2 + 1, (half + i) * 2 + 2), 16) or 0) / 255
        one[i + 1] = l
        other[i + 1] = r
        if l > loudest then loudest = l end
        if r > loudest then loudest = r end
    end
    g.batch(function()
        left.value = one
        right.value = other
        level.value = loudest
    end)
end

g.effect(function()
    if not M.active() or not available.value then return end
    local command = { M.binary,
        "--bands", tostring(M.band_count()),
        "--fps", tostring(config.get("sinestesia.fps", 60)),
        "--gain", tostring(config.get("sinestesia.gain", 1.0)),
        "--source", config.get("sinestesia.source", "output") }
    g.untracked(function()
        g.process {
            command = command,
            on_line = take,
            on_exit = function(code: number)
                g.batch(function()
                    left.value = {}
                    right.value = {}
                    level.value = 0
                end)
                if code == 0 or code == 143 then return end
                failures += 1
                if failures > 2 then
                    available.value = false
                    print("Sinestesia: no bands — is tools/sinestesia-bands built?")
                end
            end,
        }
    end)
end)

-- The band the cell draws is coarser than the one that arrives: folded by
-- peak rather than by mean, as the tool takes the peak bin inside a band (a
-- mean turns a snare into a shrug).
function M.fold(source: { number }, into: number): { number }
    if into <= 0 or #source == 0 then return {} end
    if into >= #source then return source end
    local out = table.create(into)
    for i = 0, into - 1 do
        local from = (i * #source) // into
        local to = math.max(from + 1, ((i + 1) * #source) // into)
        local peak = 0
        for b = from + 1, to do
            if source[b] > peak then peak = source[b] end
        end
        out[i + 1] = peak
    end
    return out
end

return M
