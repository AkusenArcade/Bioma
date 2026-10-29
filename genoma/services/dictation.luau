--!strict
-- Dictation: speech to text, into the window that has the focus
-- (services/Dictation.qml at 11bb81e). PRD §9.6.
--
-- One take is three processes in a row, each started when needed and gone
-- when done: `scripts/listen` while the user speaks, `whisper-cli` on what
-- was said, `scripts/paste` to put the text where the keyboard is. Nothing
-- stays resident between takes. Every process dies with the shell
-- (g.process sets the death signal): a shell that dies leaves no
-- microphone open.
--
-- Not yet: keeping the clipboard cell quiet through the paste; it comes
-- with the clipboard service.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local capture = require("services/capture")
local niri = require("services/niri")

local M = {}

local function model(): string
    return config.get("capture.dictation.model",
        "/usr/share/whisper.cpp-model-large-v3-turbo-q5_0/ggml-large-v3-turbo-q5_0.bin")
end

-- "idle" | "listening" | "transcribing"
local state = g.signal("idle")
local elapsed = g.signal(0)
local peak = g.signal(0)
local available = g.signal(false)

function M.state(): string return state.value end
function M.listening(): boolean return state.value == "listening" end
function M.transcribing(): boolean return state.value == "transcribing" end
function M.active(): boolean return state.value ~= "idle" end
function M.elapsed(): number return elapsed.value end
function M.available(): boolean return available.value end

-- The microphone's level while listening, 0–1 on a decibel scale: speech
-- sits far below full scale, and a linear peak would barely move.
function M.level(): number
    if state.value ~= "listening" or peak.value <= 0 then return 0 end
    local db = 20 * math.log10(peak.value)
    return math.clamp((db + 50) / 50, 0, 1)
end

-- Whether the engine and its model are there, again whenever the model's
-- path changes: without them dictation is drawn unavailable.
g.effect(function()
    local path = model()
    g.process {
        command = { "sh", "-c", 'command -v whisper-cli >/dev/null && [ -r "$1" ]', "probe", path },
        on_exit = function(code: number) available.value = code == 0 end,
    }
end)

-- Only what the cell can no longer say: by the time a take fails or ends
-- on the clipboard, the cell has gone quiet.
local function tell(summary: string, body: string)
    print("Dictation: " .. summary .. " " .. body)
    g.process { command = { "notify-send", "--app-name=Bioma", "--icon=audio-input-microphone", summary, body } }
end

local temporary = (g.env("XDG_RUNTIME_DIR") or "/tmp") .. "/bioma-dictation"
local take = ""
local recorder: any = nil
local engine: any = nil
local paster: any = nil
local can_paste = false
local cancelling = false
local counting: any = nil
local ceiling: any = nil

local function stop_clocks()
    if counting then counting:stop() end
    if ceiling then ceiling:stop() end
    counting, ceiling = nil, nil
end

-- Idle first, then the paster stopped: its exit reads the state, and a
-- stop on the way out of a good take is not a paster that died.
local function finish()
    stop_clocks()
    local done = take
    take = ""
    state.value = "idle"
    if paster then
        local p = paster
        paster = nil
        p:stop()
    end
    if done ~= "" then g.process { command = { "rm", "-f", done } } end
    cancelling = false
end

-- Whisper marks what is not speech in brackets ([BLANK_AUDIO], (music)),
-- and a line of nothing but that is not something the user said.
local function clean(lines: { string }): string
    local kept = {}
    for _, line in lines do
        local l = string.match(line, "^%s*(.-)%s*$") or ""
        if l ~= "" and not string.match(l, "^[%[%(].*[%]%)]$") then table.insert(kept, l) end
    end
    local text = string.gsub(table.concat(kept, " "), "%s+", " ")
    return string.match(text, "^%s*(.-)%s*$") or ""
end

local function is_terminal(app_id: string): boolean
    local id = string.lower(app_id or "")
    for _, t in config.get("capture.dictation.terminals", {}) do
        if string.lower(tostring(t)) == id then return true end
    end
    return false
end

local function deliver(text: string)
    if text == "" then
        print("Dictation: nothing heard")
        finish()
        return
    end
    if not paster then
        tell("Dictation could not paste", "The paster is gone.")
        finish()
        return
    end
    -- No window to paste into: the text stays on the clipboard rather than
    -- be pasted into nothing and taken back by the restore.
    local window = g.untracked(niri.focused_window)
    paster:write(g.to_json({
        text = text,
        terminal = is_terminal(g.untracked(niri.focused_app_id)),
        copyOnly = window == nil or not can_paste,
    }) .. "\n")
end

local function transcribe()
    local lines = {}
    engine = g.process {
        command = { "whisper-cli", "--model", model(), "--language", config.get("capture.dictation.language", "auto"),
            "--no-timestamps", "--no-prints", "--file", take },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function(code: number)
            engine = nil
            if cancelling then return end
            if code ~= 0 then
                tell("Dictation failed", "whisper-cli exited with " .. code .. ".")
                finish()
                return
            end
            deliver(clean(lines))
        end,
    }
end

-- Capture's recorder and this one are one capture at a time: the cell has
-- one contracted form to speak with.
local function blocked(): boolean
    return capture.recording() or capture.pending_video() ~= ""
end

function M.start()
    if state.value ~= "idle" or g.untracked(blocked) then return end
    if not g.untracked(M.available) then
        tell("Dictation is not available", "whisper-cli or its model is missing.")
        return
    end
    elapsed.value = 0
    peak.value = 0
    take = temporary .. "/take-" .. math.floor(g.now() * 1000) .. ".wav"
    state.value = "listening"
    can_paste = false
    paster = g.process {
        command = { paths.script("paste") },
        on_line = function(line: string)
            if line == "ready" then
                can_paste = true
            elseif line == "no-uinput" then
                can_paste = false
                print("Dictation: /dev/uinput is not writable; the text will be left on the clipboard")
            elseif line == "pasted" then
                print("Dictation: pasted")
                finish()
            elseif line == "copied" then
                tell("Dictation is on the clipboard", "Paste it with Ctrl+V.")
                finish()
            end
        end,
        -- A paster that dies with a text on its way never answers, and the
        -- take would stay transcribing for ever.
        on_exit = function(code: number)
            if state.value == "transcribing" and not cancelling and paster then
                paster = nil
                tell("Dictation could not paste", "The paster exited with " .. code .. ".")
                finish()
            end
        end,
    }
    recorder = g.process {
        command = { paths.script("listen"), take },
        on_line = function(line: string) peak.value = tonumber(line) or 0 end,
        on_exit = function(code: number)
            recorder = nil
            if cancelling then return end
            -- Gone before it was asked to stop: no pw-record, a microphone
            -- that went away.
            if state.value == "listening" then
                tell("Dictation stopped", "The recorder exited with " .. code .. ".")
                finish()
                return
            end
            if state.value == "transcribing" then transcribe() end
        end,
    }
    counting = g.timer { every = 1, on_tick = function() elapsed.value += 1 end }
    -- A forgotten toggle does not keep the microphone open.
    local most = config.get("capture.dictation.max_seconds", 120)
    ceiling = g.after(most, function()
        ceiling = nil
        print("Dictation: stopped at the " .. most .. " s ceiling")
        M.stop()
    end)
    print("Dictation: listening")
end

-- Stopping is what transcribes. The recorder closes the file properly on
-- SIGINT; killed outright the header would say zero samples.
function M.stop()
    if state.value ~= "listening" then return end
    stop_clocks()
    state.value = "transcribing"
    if recorder then recorder:signal(2) end
end

function M.toggle()
    if state.value == "listening" then M.stop() elseif state.value == "idle" then M.start() end
end

-- Nothing transcribed, nothing typed, nothing kept.
function M.cancel()
    if state.value == "idle" then return end
    print("Dictation: cancelled")
    cancelling = true
    if recorder then recorder:stop() end
    if engine then engine:stop() end
    finish()
end

return M
