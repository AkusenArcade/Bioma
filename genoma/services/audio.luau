--!strict
-- The machine's sound (services/Audio.qml at 11bb81e): the devices, the
-- streams and their volumes, on Genoma's audio domain, and the signal
-- leaving the default sink, which is what raises the media cell.
--
-- The signal is one number, read by `sinestesia-bands --peak`: it captures
-- in stereo and lets PipeWire mix the node down, so a pro-audio interface
-- whose channels are AUX reads true too (Audio.qml's fallback for the
-- PreSonus Revelator, 2026-09-29, here the only way). Ten readings a second:
-- the condition only has to see a signal hold for its confirm step.
local g = require("@genoma")
local config = require("core/config")
local sinestesia = require("services/sinestesia")
local pipewire = require("@genoma/audio")

local M = {}

-- ---- Devices and streams -----------------------------------------------------
--
-- PipeWire allows volumes above 100 %, and refusing to show that would make
-- the indicator lie about the state of the system; 150 % is the ceiling.
M.max_volume = 1.5

local nodes = g.computed(function(): { any } return pipewire.nodes end)

local function by_name(name: string): any
    if name == "" then return nil end
    for _, n in nodes.value do
        if n.name == name then return n end
    end
    return nil
end

local sink = g.computed(function(): any return by_name(pipewire.default_sink) end)
local source = g.computed(function(): any return by_name(pipewire.default_source) end)
function M.sink(): any return sink.value end
function M.source(): any return source.value end

function M.volume(): number local n = sink.value return if n then n.volume else 0 end
function M.muted(): boolean local n = sink.value return n ~= nil and n.muted end
function M.volume_percent(): number return math.floor(M.volume() * 100 + 0.5) end
function M.input_volume(): number local n = source.value return if n then n.volume else 0 end
function M.input_muted(): boolean local n = source.value return n ~= nil and n.muted end

local function clamp(v: number): number return math.clamp(v, 0, M.max_volume) end

function M.set_volume(value: number)
    local n = g.untracked(M.sink)
    if n then pipewire:set_volume(n.id, clamp(value)) end
end
function M.step_volume(delta: number) M.set_volume(g.untracked(M.volume) + delta) end
function M.toggle_mute()
    local n = g.untracked(M.sink)
    if n then pipewire:set_mute(n.id, not n.muted) end
end
function M.set_input_volume(value: number)
    local n = g.untracked(M.source)
    if n then pipewire:set_volume(n.id, clamp(value)) end
end
function M.toggle_input_mute()
    local n = g.untracked(M.source)
    if n then pipewire:set_mute(n.id, not n.muted) end
end

-- By the node's kind, which Genoma takes from its media class: the graph's
-- driver nodes, MIDI bridges and webcams are none of these, and no list
-- offers "Freewheel-Driver" as a microphone.
local function of_kind(kind: string): { any }
    local out = {}
    for _, n in nodes.value do
        if n.kind == kind then table.insert(out, n) end
    end
    return out
end
local outputs = g.computed(function() return of_kind("sink") end)
local inputs = g.computed(function() return of_kind("source") end)
-- An application playing is an output stream; something recording, an
-- input stream.
local streams = g.computed(function() return of_kind("output-stream") end)
local recording = g.computed(function() return of_kind("input-stream") end)
function M.outputs(): { any } return outputs.value end
function M.inputs(): { any } return inputs.value end
function M.streams(): { any } return streams.value end
function M.recording_streams(): { any } return recording.value end
function M.stream_count(): number return #streams.value end
function M.anyone_recording(): boolean return #recording.value > 0 end

-- A device's own words for itself, in descending order of how much thought
-- went into them; `name` is the ALSA path and is never shown.
function M.describe(n: any): string
    if not n then return "" end
    if n.nickname ~= "" then return n.nickname end
    if n.description ~= "" then return n.description end
    return n.name or ""
end

-- What to say on the right of a device's name: what it is, if it says, else
-- its bus (USB, PCI).
function M.connection(n: any): string
    local p = if n then n.properties else {}
    local form = p["device.form-factor"] or ""
    if form ~= "" and form ~= "internal" then return string.upper(form) end
    return string.upper(p["device.bus"] or "")
end

-- A preference, not a command: PipeWire applies it and reports back
-- through the defaults, so nothing assumes it took.
function M.set_default(n: any) if n then pipewire:set_default(n.id) end end
function M.is_default_output(n: any): boolean local s = sink.value return s ~= nil and n ~= nil and s.id == n.id end
function M.is_default_input(n: any): boolean local s = source.value return s ~= nil and n ~= nil and s.id == n.id end

-- The application's own name first: `media.name` is the track or the page
-- title, informative but changing under the user's hand.
function M.describe_stream(n: any): string
    if not n then return "" end
    local p = n.properties
    local name = p["application.name"]
    if name and name ~= "" then return name end
    if n.description ~= "" then return n.description end
    return p["media.name"] or n.name or ""
end

-- For an icon: the name the application published, else its binary.
function M.stream_icon(n: any): string
    local p = if n then n.properties else {}
    return p["application.icon-name"] or p["application.process.binary"] or ""
end

function M.set_stream_volume(n: any, value: number) if n then pipewire:set_volume(n.id, clamp(value)) end end
function M.toggle_stream_mute(n: any) if n then pipewire:set_mute(n.id, not n.muted) end end

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
