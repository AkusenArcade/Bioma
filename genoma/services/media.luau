--!strict
-- MPRIS: what is playing, and the controls for it (services/Media.qml).
--
-- One of the media cell's two independent inputs, and the smaller: the band
-- is fed by the sound leaving the machine (services/sinestesia.luau), this
-- only by the metadata and the transport. Choosing another player changes
-- what is written beside the band and nothing about the band. Nor is this
-- what raises the cell: a game with no MPRIS player still has a signal.
--
-- Genoma's media domain holds the players; this is Bioma's choice of one,
-- and what it says about it.
local g = require("@genoma")
local mpris = require("@genoma/media")

local M = {}

function M.players(): { any } return mpris.players end
function M.count(): number return #mpris.players end

-- The user's choice from the expanded cell, by the player's D-Bus name. It
-- survives that player going: when it comes back it is chosen again.
local selected = g.signal("")

-- What the user picked, then whatever is playing, then whatever there is.
local player = g.computed(function(): any
    local list = mpris.players
    local chosen = selected.value
    if chosen ~= "" then
        for _, p in list do
            if p.name == chosen then return p end
        end
    end
    for _, p in list do
        if p.status == "playing" then return p end
    end
    return list[1]
end)

function M.player(): any return player.value end
function M.available(): boolean return player.value ~= nil end
function M.select(name: string?) selected.value = name or "" end
function M.clear_selection() selected.value = "" end
function M.chosen_explicitly(): boolean return selected.value ~= "" and player.value ~= nil end

-- ---- Metadata --------------------------------------------------------------
--
-- Human language, the expressive register, but for the times below.

local function field(key: string): string
    local p = player.value
    return if p and p[key] then tostring(p[key]) else ""
end
function M.title(): string return field("title") end
function M.artist(): string return field("artist") end
function M.album(): string return field("album") end
function M.album_artist(): string return field("album_artist") end
function M.identity(): string return field("identity") end
-- A local file or a remote address; often none.
function M.art_url(): string return field("art_url") end
function M.has_art(): boolean return M.art_url() ~= "" end
-- Something worth writing beside the band.
function M.has_metadata(): boolean return M.title() ~= "" or M.artist() ~= "" end

-- ---- Playback ----------------------------------------------------------------

function M.playing(): boolean
    local p = player.value
    return p ~= nil and p.status == "playing"
end
function M.paused(): boolean
    local p = player.value
    return p ~= nil and p.status == "paused"
end
local function can(key: string): boolean
    local p = player.value
    return p ~= nil and p[key] == true
end
function M.can_play(): boolean return can("can_play") end
function M.can_pause(): boolean return can("can_pause") end
function M.can_toggle(): boolean return can("can_play") or can("can_pause") end
function M.can_go_next(): boolean return can("can_go_next") end
function M.can_go_previous(): boolean return can("can_go_previous") end
function M.can_seek(): boolean return can("can_seek") end

-- The track's length as the player last reported it. Firefox and Zen send
-- it with a track's metadata, then once it plays send metadata again
-- without it (logged 2026-10-07): a length seen for this track is kept
-- until the track changes.
local function track_key(): string
    local p = player.value
    return if p then p.name .. "\0" .. M.title() .. "\0" .. M.artist() else ""
end
local last_length = { key = "", value = 0 }
local length = g.computed(function(): number
    local p = player.value
    local reported = if p and p.length and p.length > 0 then p.length else 0
    local key = track_key()
    if reported > 0 and key ~= "" then
        last_length = { key = key, value = reported }
        return reported
    end
    return if last_length.key == key then last_length.value else 0
end)
function M.length(): number return length.value end
function M.has_length(): boolean return length.value > 0 end

-- ---- Position ------------------------------------------------------------------
--
-- MPRIS does not push position: it is asked for, on a beat of one second,
-- and only while something plays and the player answers it. A smooth bar
-- interpolates between beats rather than asking more often.

local position = g.signal(0)
local function read_position()
    local p = g.untracked(function() return player.value end)
    position.value = if p and p.position_supported then (mpris:position(p.name) or 0) else 0
end
g.effect(function()
    local p = player.value
    if not p then
        g.untracked(function() position.value = 0 end)
        return
    end
    g.untracked(read_position)
    if p.status == "playing" and p.position_supported then
        g.timer { every = 1, on_tick = read_position }
    end
end)

function M.position_supported(): boolean return can("position_supported") end
function M.position(): number return position.value end
function M.progress(): number
    if not M.has_length() or position.value <= 0 then return 0 end
    return math.clamp(position.value / length.value, 0, 1)
end

-- ---- Controls --------------------------------------------------------------------

local function act(method: string, check: () -> boolean)
    local p = g.untracked(function() return player.value end)
    if p and g.untracked(check) then (mpris :: any)[method](mpris, p.name) end
end
function M.play_pause() act("play_pause", M.can_toggle) end
function M.play() act("play", M.can_play) end
function M.pause() act("pause", M.can_pause) end
function M.next() act("next", M.can_go_next) end
function M.previous() act("previous", M.can_go_previous) end
function M.seek_by(seconds: number)
    local p = g.untracked(function() return player.value end)
    if p and g.untracked(M.can_seek) then mpris:seek(p.name, seconds) end
    read_position()
end
function M.seek_to(seconds: number)
    local p = g.untracked(function() return player.value end)
    if p and g.untracked(M.can_seek) then mpris:set_position(p.name, seconds) end
    read_position()
end

-- A duration for display: a measurement, the technical register, tabular,
-- or its width dances on every tick.
function M.format_time(seconds: number): string
    if not (seconds > 0) then return "0:00" end
    local total = math.floor(seconds)
    local h, m, s = total // 3600, (total % 3600) // 60, total % 60
    return if h > 0 then string.format("%d:%02d:%02d", h, m, s) else string.format("%d:%02d", m, s)
end

return M
