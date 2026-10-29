--!strict
-- Capture: screenshots, text recognition, colour, video
-- (services/Capture.qml at 11bb81e).
--
-- The selection rectangle is not here: a service owns no surfaces.
-- `select_region()` raises a flag; `structure/selection.luau` draws the
-- rectangle and answers with `region_chosen` or `cancel_selection`, the
-- region in slurp's format (`x,y WxH`, the compositor's logical
-- coordinates), which grim and wl-screenrec both take.
local g = require("@genoma")
local config = require("core/config")
local timing = require("core/timing")
local monitors = require("services/monitors")

local M = {}

local home = g.env("HOME") or ""
local runtime = g.env("XDG_RUNTIME_DIR") or "/tmp"

local function expand(candidate: string): string
    if string.sub(candidate, 1, 2) == "~/" then return home .. string.sub(candidate, 2) end
    if string.sub(candidate, 1, 5) == "$HOME" then return home .. string.sub(candidate, 6) end
    return candidate
end

function M.folder(): string return expand(config.get("capture.folder", "$HOME/Pictures/Screenshots")) end
function M.video_folder(): string return expand(config.get("capture.video_folder", "$HOME/Videos/Recordings")) end
local function copies(): boolean return config.get("capture.clipboard", true) == true end

-- ---- State ------------------------------------------------------------------

local busy = g.signal(false)
local last_path = g.signal("")
local last_text = g.signal("")
local last_error = g.signal("")
local selecting = g.signal(false)
local recording = g.signal(false)
local pending_video = g.signal("")
local elapsed = g.signal(0)

function M.busy(): boolean return busy.value end
function M.last_path(): string return last_path.value end
function M.last_text(): string return last_text.value end
function M.last_error(): string return last_error.value end
function M.selecting(): boolean return selecting.value end
function M.recording(): boolean return recording.value end
function M.pending_video(): string return pending_video.value end
function M.elapsed(): number return elapsed.value end

-- "still" | "text" | "record": what a region chosen is for.
M.pending_action = "still"

-- What happened, for who listens: the cell pulses on a capture, beats on
-- each counted second.
local listeners: { [string]: { (any) -> () } } = {
    captured = {}, recognised = {}, cancelled = {}, failed = {}, picked = {},
    second = {}, recording_saved = {},
}
local function emit(name: string, value: any)
    for _, f in listeners[name] do f(value) end
end
function M.on(name: string, f: (any) -> ())
    table.insert(listeners[name], f)
end

local function fail(reason: string)
    last_error.value = reason
    busy.value = false
    -- Every failure ends up on this line: a capture that fails silently is
    -- indistinguishable from one never asked for.
    print("Capture: " .. reason)
    emit("failed", reason)
end

-- ---- Saying where it went ---------------------------------------------------
--
-- A saved screenshot or recording is announced, with a way to its folder
-- (Akusen, 2026-09-23): an ordinary notification, its action waited for in
-- a process of its own, so three captures in a row each still answer.

local function announce(path: string, video: boolean)
    if config.get("capture.notify", true) ~= true or path == "" then return end
    local folder = string.match(path, "^(.*)/[^/]*$") or "."
    local name = string.match(path, "[^/]*$") or path
    local args = {
        "sh", "-c", 'folder="$1"; shift; [ "$("$@")" = open ] && exec xdg-open "$folder"', "announce", folder,
        "notify-send", "--app-name=Bioma", "--action=open=Open folder",
        if video then "--icon=video-x-generic" else "--hint=string:image-path:" .. path,
        if video then "Recording saved" else "Screenshot saved",
        if not video and copies() then name .. " — also on the clipboard" else name,
    }
    g.process { command = args }
end

-- Seconds are not fine enough: two captures inside one second (a held
-- keybind) overwrote each other. The suffix appears only when a second is
-- reused, so ordinary names stay readable.
local last_stamp, sequence = "", 0
local function timestamp(): string
    local stamp = os.date("%Y%m%d-%H%M%S")
    if stamp == last_stamp then
        sequence += 1
        return stamp .. "-" .. sequence
    end
    last_stamp, sequence = stamp, 0
    return stamp
end

local function still_path(): string return M.folder() .. "/screenshot-" .. timestamp() .. ".png" end

-- ---- Regions ----------------------------------------------------------------

local function parse(region: string): (number?, number?, number?, number?)
    local x, y, w, h = string.match(region, "^%s*(-?%d+),(-?%d+)%s+(%d+)x(%d+)%s*$")
    return tonumber(x), tonumber(y), tonumber(w), tonumber(h)
end

-- H.264 refuses odd dimensions, and a hand-drawn rectangle gives them half
-- the time. Rounding the region does not help: it is logical, the encoder
-- physical, and 101 at 1.5× rounds back to 101. The encode resolution is
-- physical, so it is where evenness can be stated; the region stays as
-- drawn.
function M.encode_resolution(region: string, scale: number): string
    local _, _, w, h = parse(region)
    if not w or not h then return "" end
    local factor = if scale > 0 then scale else 1
    local function even(logical: number): number
        local physical = math.floor(logical * factor + 0.5)
        return math.max(2, physical - physical % 2)
    end
    return even(w) .. "x" .. even(h)
end

-- The scale of the output a region starts on: a rectangle over two scales
-- has no single answer, and neither does the encoder.
local function scale_for_region(region: string): number
    local x, y = parse(region)
    if not x or not y then return 1 end
    for _, o in g.untracked(monitors.outputs) do
        if x >= o.x and x < o.x + o.width and y >= o.y and y < o.y + o.height then return o.scale or 1 end
    end
    return 1
end

-- An output's own rectangle, the region a whole screen of text is.
function M.output_region(output: string): string
    local o = g.untracked(function() return monitors.output_of(output) end)
    if not o or not o.on then return "" end
    return string.format("%d,%d %dx%d", o.x, o.y, o.width, o.height)
end

-- ---- Settling ---------------------------------------------------------------
--
-- Everything Bioma draws is on the screen being photographed, and the cell
-- closing and the rectangle going are animations still running when the
-- call returns. So every capture waits here, once, for the shell to be gone.

local settling: any = nil
local function settle_then(action: () -> ())
    if settling then settling:stop() end
    settling = g.after(timing.seconds.close + 0.08, function()
        settling = nil
        action()
    end)
end

-- ---- Selection --------------------------------------------------------------

function M.select_region()
    last_error.value = ""
    selecting.value = true
end

function M.region_chosen(region: string)
    selecting.value = false
    if region == "" then
        emit("cancelled", nil)
        return
    end
    if M.pending_action == "text" then
        M.recognise_region(region)
    elseif M.pending_action == "record" then
        M.record_region(region)
    else
        M.capture_region(region)
    end
end

-- Escape is a normal way to finish with a screenshot tool: not a failure.
function M.cancel_selection()
    selecting.value = false
    emit("cancelled", nil)
end

-- ---- The clipboard ----------------------------------------------------------
--
-- wl-copy forks and holds the selection itself, so the process ends at once
-- and the copy outlives it.

local function copy_image(path: string)
    g.process { command = { "sh", "-c", 'wl-copy --type image/png < "$1"', "copy", path } }
end

local function copy_text(text: string)
    g.process { command = { "wl-copy", "--type", "text/plain", "--", text } }
end

-- ---- Stills -----------------------------------------------------------------

local function shoot(command: { string }, target: string)
    last_error.value = ""
    busy.value = true
    settle_then(function()
        g.process {
            command = command,
            on_exit = function(code: number)
                if code ~= 0 then
                    fail("capture failed (" .. code .. ")")
                    return
                end
                last_path.value = target
                busy.value = false
                if copies() then copy_image(target) end
                emit("captured", target)
                announce(target, false)
            end,
        }
    end)
end

function M.capture_region(region: string)
    local target = still_path()
    shoot({ "grim", "-g", region, target }, target)
end

function M.capture_output(output: string?)
    local target = still_path()
    shoot(if output and output ~= "" then { "grim", "-o", output, target } else { "grim", target }, target)
end

-- A window is the one shape grim cannot take: niri reports no window
-- position, so the compositor captures it by id, onto the clipboard
-- (niri's own file goes wherever niri's configuration says), and the
-- clipboard is written out. `niri msg` returns when the action is
-- dispatched, not when the image is there, and a clipboard manager puts
-- the old selection straight back after a clear: so it waits for the
-- contents to change, by checksum, up to two seconds.
function M.capture_window(id: number)
    last_error.value = ""
    busy.value = true
    local target = still_path()
    g.process {
        command = { "sh", "-c",
            'before=$(wl-paste --type image/png 2>/dev/null | md5sum); '
            .. 'niri msg action screenshot-window $2 -d false || exit 1; '
            .. 'i=0; while [ $i -lt 40 ]; do '
            .. 'now=$(wl-paste --type image/png 2>/dev/null | md5sum); '
            .. '[ "$now" != "$before" ] && break; '
            .. 'sleep 0.05; i=$((i+1)); done; '
            .. 'wl-paste --type image/png > "$1" 2>/dev/null; [ -s "$1" ]',
            "window", target, if id > 0 then "--id " .. id else "" },
        on_exit = function(code: number)
            if code ~= 0 then
                fail("window capture failed (" .. code .. ")")
                return
            end
            last_path.value = target
            busy.value = false
            emit("captured", target)
            announce(target, false)
        end,
    }
end

-- ---- Text -------------------------------------------------------------------
--
-- Tesseract wants a scanned page and a screen is not one: interface text at
-- 1× comes back as nothing. Upscaled first, where ImageMagick is there.

function M.recognise_region(region: string)
    last_error.value = ""
    busy.value = true
    local language = config.get("capture.ocr_language", "eng")
    settle_then(function()
        local lines = {}
        g.process {
            command = { "sh", "-c",
                'grim -g "$1" - | { command -v magick >/dev/null 2>&1 '
                .. '&& magick - -resize 300% -colorspace Gray -sharpen 0x1 - || cat; } | '
                .. 'tesseract - stdout -l "$2" 2>/dev/null',
                "ocr", region, language },
            on_line = function(line: string) table.insert(lines, line) end,
            on_exit = function(code: number)
                busy.value = false
                if code ~= 0 then
                    fail("recognition failed (" .. code .. ")")
                    return
                end
                local text = string.match(table.concat(lines, "\n"), "^%s*(.-)%s*$") or ""
                -- Nothing recognised is a result: a region of empty desktop
                -- has no text.
                last_text.value = text
                if text ~= "" then
                    if copies() then copy_text(text) end
                else
                    print("Capture: nothing legible in that region")
                end
                emit("recognised", text)
            end,
        }
    end)
end

-- ---- Colour -----------------------------------------------------------------
--
-- One pixel, by niri's own picker: the compositor draws the crosshair and
-- reads the frame it composited. The hex goes on the clipboard, and the
-- last few are kept so a colour picked a minute ago is one press away.

function M.colours(): { string } return config.get("capture.colours", {}) end

-- A pick for somebody else (the palette editor) answers on `picked` alone:
-- the clipboard and the list are the utility's.
M.pick_kept = true

local function remember(hex: string)
    local next = { hex }
    for _, c in g.untracked(M.colours) do
        if c ~= hex then table.insert(next, c) end
    end
    local count = config.get("capture.colour_count", 8)
    while #next > count do table.remove(next) end
    config.set("capture.colours", next)
end

function M.copy_colour(hex: string)
    if hex == "" then return end
    copy_text(hex)
    remember(hex)
    emit("picked", hex)
end

local function hex_of(rgb: { number }): string
    local out = "#"
    for i = 1, 3 do
        out ..= string.format("%02X", math.floor(math.clamp(rgb[i], 0, 1) * 255 + 0.5))
    end
    return out
end

-- `{"rgb":[r,g,b]}` with each channel 0–1, or `null` for a pick cancelled.
function M.pick_colour(kept: boolean?)
    last_error.value = ""
    M.pick_kept = kept ~= false
    settle_then(function()
        local said = {}
        g.process {
            command = { "niri", "msg", "--json", "pick-color" },
            on_line = function(line: string) table.insert(said, line) end,
            on_exit = function(code: number)
                if code ~= 0 then
                    fail("colour picker failed (" .. code .. ")")
                    return
                end
                local text = table.concat(said, "")
                local ok, answer = pcall(g.parse_json, text)
                if not ok then
                    fail("colour picker said something unreadable: " .. text)
                    return
                end
                if type(answer) ~= "table" or type(answer.rgb) ~= "table" or #answer.rgb < 3 then
                    emit("cancelled", nil)
                    return
                end
                local hex = hex_of(answer.rgb)
                if M.pick_kept then M.copy_colour(hex) else emit("picked", hex) end
            end,
        }
    end)
end

-- ---- Video ------------------------------------------------------------------
--
-- No audio (PRD §9.6), H.264, written to a temporary directory and moved
-- into place only when the user saves: a discarded recording leaves nothing
-- among their files. wl-screenrec takes an output or a region, never a
-- window.

local temporary = runtime .. "/bioma-capture"
local recorder: any = nil
local counting: any = nil

local function start_recorder(target: { string })
    if recording.value or pending_video.value ~= "" then return end
    last_error.value = ""
    elapsed.value = 0
    local file = temporary .. "/recording-" .. timestamp() .. ".mp4"
    pending_video.value = file
    settle_then(function()
        local command = { "sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "record", temporary,
            "wl-screenrec", "--filename", file,
            "--codec", config.get("capture.codec", "avc"),
            "--max-fps", tostring(config.get("capture.fps", 60)),
            "--bitrate", config.get("capture.bitrate", "5 MB"),
            "--no-cursor" }
        for _, a in target do table.insert(command, a) end
        recording.value = true
        counting = g.timer {
            every = 1,
            on_tick = function()
                elapsed.value += 1
                emit("second", elapsed.value)
            end,
        }
        recorder = g.process {
            command = command,
            on_exit = function(code: number)
                recording.value = false
                recorder = nil
                if counting then counting:stop() end
                counting = nil
                -- SIGINT is how a recording ends: 130 (or 2), not a failure.
                if code ~= 0 and code ~= 130 and code ~= 2 then
                    fail("recording failed (" .. code .. ")")
                    pending_video.value = ""
                end
            end,
        }
    end)
end

function M.record_region(region: string)
    local target = { "-g", region }
    local resolution = M.encode_resolution(region, scale_for_region(region))
    if resolution ~= "" then
        table.insert(target, "--encode-resolution")
        table.insert(target, resolution)
    end
    start_recorder(target)
end

function M.record_output(output: string?)
    start_recorder(if output and output ~= "" then { "-o", output } else {})
end

-- wl-screenrec finalises the container on SIGINT; killed outright the file
-- has no moov atom and does not play.
function M.stop_recording()
    if recorder then recorder:signal(2) end
end

function M.save_recording()
    local file = pending_video.value
    if file == "" or recording.value then return end
    local target = M.video_folder() .. "/" .. (string.match(file, "[^/]*$") or "recording.mp4")
    g.process {
        command = { "sh", "-c", 'mkdir -p "$1" && mv "$2" "$3"', "save", M.video_folder(), file, target },
        on_exit = function(code: number)
            if code ~= 0 then
                fail("could not move the recording into place")
                return
            end
            last_path.value = target
            pending_video.value = ""
            emit("recording_saved", target)
            announce(target, true)
        end,
    }
end

function M.discard_recording()
    local file = pending_video.value
    if file == "" or recording.value then return end
    g.process {
        command = { "rm", "-f", file },
        on_exit = function() pending_video.value = "" end,
    }
end

-- ---- Destination ------------------------------------------------------------
--
-- Made once: grim will not create it, and a screenshot lost to a missing
-- folder is lost at the moment it was wanted.
g.process { command = { "mkdir", "-p", g.untracked(M.folder) } }

return M
