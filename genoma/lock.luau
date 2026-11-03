--!strict
-- Bioma's lock screen (lock.qml at 92cd36c), on Genoma: a third entry point
-- of the same interface, and a process of its own, run by `scripts/lock` as
-- `genoma <this directory> lock.luau` when the configuration says
-- `"lock": { "runtime": "genoma" }`.
--
-- Not a part of the shell, on purpose. A lock screen that fails shuts its
-- owner out of their own session, and the shell is the larger program. If
-- the shell falls over, the screen stays locked; if this falls over, niri
-- keeps the outputs locked and `scripts/lock`, which started it, starts
-- hyprlock in its place.
--
-- It ends by unlocking: there is no way to put it away without the
-- password.
--
-- Its state is kept by key (`g.state`): Genoma evaluates an interface again
-- when its surfaces change, and the lock's are made once the lock is asked
-- for, so this file runs twice before anything is on screen. What it shows is the threshold (components/gate.luau): the
-- wallpaper blurred, the time and the date, who is logged in, and the field
-- (Akusen, 2026-09-23). It arrives from a photograph of the desktop and
-- leaves back to it.
local g = require("@genoma")
local lock = require("@genoma/lock")
local niri = require("@genoma/niri")
local monitors = require("services/monitors")
local paths = require("core/paths")
local timing = require("core/timing")
local session = require("services/session")
local gate_mod = require("components/gate")

-- The shell's own glyphs, by name.
g.icon_dir(paths.root .. "/assets/icons")

-- ---- The desktop, as it was -----------------------------------------------------
--
-- A moment before the lock takes the screens, each one is photographed, and
-- the first frame of the lock is that photograph. `grim`, a process, rather
-- than a capture inside the lock: a lock screen is the one place that must
-- not depend on one more protocol going right. Without grim the lock starts
-- from the wallpaper, sharp, which is the next best thing.
--
-- The photographs are the screens' contents, so they live in the runtime
-- directory (memory, readable only by the user) and are removed when the
-- lock ends, and again when the next one starts.
local captures = (g.env("XDG_RUNTIME_DIR") or "/tmp") .. "/bioma-lock"
local photographed = g.state("lock.photographed", false)
local function capture_for(output: string): string
    return if photographed.value then captures .. "/" .. output .. ".png" else ""
end

local began = g.state("lock.began", false)
local function begin()
    if g.untracked(function() return began.value end) then return end
    began.value = true
    lock:lock()
end

if not g.untracked(function() return began.value end) then
    local names = {}
    for _, o in g.outputs() do table.insert(names, o.name) end
    g.process {
        command = { "sh", "-c",
            'umask 077; d="$1"; shift; rm -rf "$d"; mkdir -p "$d"; '
            .. 'command -v grim >/dev/null || exit 1; '
            .. 'for o in "$@"; do grim -l 0 -o "$o" "$d/$o.png" & done; wait',
            "capture", captures, table.unpack(names) },
        on_exit = function(code: number)
            if g.untracked(function() return began.value end) then return end
            photographed.value = code == 0
            begin()
        end,
    }
    -- Never later than this, however long the photographs take: a lock
    -- that waits on a screenshot is a lock that is late.
    g.after(timing.seconds.open, begin)
end

-- ---- What the lock tells the rest of the machine ----------------------------------

-- logind's own flag for "this session is locked". `scripts/lock` waits for
-- it before deciding the lock took; the shell waits for it before letting a
-- suspend go ahead.
local function hint(locked: boolean)
    g.dbus.call {
        bus = "system",
        destination = "org.freedesktop.login1",
        path = "/org/freedesktop/login1",
        interface = "org.freedesktop.login1.Manager",
        method = "GetSession",
        signature = "s",
        args = { "auto" },
        reply = function(ok: boolean, path: any)
            if not ok then print("Bioma lock: no session — " .. tostring(path)) return end
            g.dbus.call {
                bus = "system",
                destination = "org.freedesktop.login1",
                path = path,
                interface = "org.freedesktop.login1.Session",
                method = "SetLockedHint",
                signature = "b",
                args = { locked },
            }
        end,
    }
end

-- Once, whichever way the lock ended. A process left behind after an unlock
-- is a lock that `scripts/lock` believes is still up, and every later lock
-- would stop there.
local finished = g.state("lock.finished", false)
local function finish(code: number)
    if g.untracked(function() return finished.value end) then return end
    finished.value = true
    hint(false)
    g.process { command = { "rm", "-rf", captures } }
    -- A beat for the compositor to take the surfaces down, and for the
    -- hint to be sent, before the process that owns them goes.
    g.after(timing.seconds.close, function() g.quit(code) end)
end

-- Everything is on screen and the compositor says so: the session is locked
-- in the sense logind means.
local was_locked = false
g.watch(function() return lock.locked end, function(on: boolean)
    if on and not was_locked then hint(true) end
    was_locked = on
end)
-- The compositor refused the lock, or ended it on its own. Refused, the
-- exit says so and `scripts/lock` falls back; ended after it took, there is
-- nothing left to guard.
g.watch(function() return lock.finished end, function(on: boolean)
    if on then finish(if was_locked then 0 else 1) end
end)

-- ---- Checking the password -------------------------------------------------------

local password = g.state("lock.password", "")
-- A check in flight belongs to the load that started it: a new load has
-- none.
local checking = g.state("lock.checking", false)
checking.value = false
local failed = g.state("lock.failed", false)
local reason = g.state("lock.reason", "")
local leaving = g.state("lock.leaving", false)

-- The screen that holds the field: the primary monitor, as Bioma's
-- settings make it (niri's `focus-at-startup`), the same screen as the
-- greeter's (Akusen, 2026-11-03); the focused output while there is none.
-- Whichever lock surface niri gives the keys to, they reach the field: they
-- go to the surface that catches.
local function active(): string
    local primary = monitors.primary()
    if primary ~= "" then return primary end
    return niri.focused_output or ""
end

local function submit()
    if g.untracked(function() return checking.value or leaving.value or password.value == "" end) then return end
    g.batch(function()
        checking.value = true
        failed.value = false
    end)
    -- Bioma's own PAM file, beside the repository rather than in /etc: see
    -- assets/pam/bioma-lock for why it is not `login`.
    local auth: any
    auth = g.pam.start {
        service = "bioma-lock",
        directory = paths.root .. "/assets/pam",
        on_prompt = function()
            auth:respond(g.untracked(function() return password.value end))
        end,
        on_done = function(result: string)
            g.batch(function()
                checking.value = false
                if result == "success" then
                    failed.value = false
                    leaving.value = true
                    return
                end
                failed.value = true
                reason.value = if result == "max-tries" then "Too many attempts"
                    elseif result == "failure" then "That is not the password"
                    else "The password could not be checked"
                if result ~= "failure" and result ~= "max-tries" then
                    print("Bioma lock: PAM " .. result)
                end
            end)
        end,
    }
end

-- The composition goes quickly, then the picture clears back to the
-- desktop; the session unlocks once both have.
local was_leaving = false
g.watch(function() return leaving.value end, function(on: boolean)
    local started = on and not was_leaving
    was_leaving = on
    if not started then return end
    g.after(timing.seconds.close + timing.seconds.open, function()
        lock:unlock()
        finish(0)
    end)
end)

local gate = {
    active = active,
    password = password,
    checking = function(): boolean return checking.value end,
    failed = function(): boolean return failed.value end,
    failed_reset = function() failed.value = false end,
    reason = function(): string return reason.value end,
    leaving = function(): boolean return leaving.value end,
    full_name = session.full_name,
    avatar = session.avatar,
    density = gate_mod.density,
    twenty_four = gate_mod.twenty_four,
    submit = submit,
    capture = function(output: string): string return g.untracked(function() return capture_for(output) end) end,
}

-- ---- The surfaces -------------------------------------------------------------------

return g.surface {
    layer = "lock",
    outputs = "all",
    full = true,
    anchor = { "top", "bottom", "left", "right" },
    namespace = "bioma-lock",
    function(output: string, size: any)
        size = size or { width = 1920, height = 1080 }
        local gate_node, gate_keys = gate_mod.new { gate = gate, output = output, size = size }
        local function here(): boolean return active() == output end
        return g.box {
            width = size.width,
            height = size.height,
            catch = here,
            on_key = function(name: string, text: string?, mods: any)
                gate_keys.key(name, text, mods)
            end,
            gate_node,
        }
    end,
}
