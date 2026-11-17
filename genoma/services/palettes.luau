--!strict
-- The user's own palettes (services/Palettes.qml at 11bb81e): made, edited
-- and deleted from Settings → Appearance.
--
-- A palette of the user's is a file in ~/.config/bioma/palettes/, in the
-- shipped palettes' own form (a name and the four interface roles), so
-- copying one file to somebody else gives them the theme. A palette is
-- edited while it is the one on screen, and every change is the desktop
-- changing under the hand: the file is written while the hand moves, a
-- step at a time, and the theme follows the file. NEW starts from the
-- colours on screen now, whatever made them.
--
-- And each wallpaper remembers the theme it was last worn with, with no one
-- asking it to: going back to a picture brings its theme back. The pair is
-- the source and what the source was told: for a manual one which palette,
-- for matugen which scheme it read the picture with, since the same picture
-- makes a different desktop under each (Akusen, 2026-10-18). A picture
-- never paired keeps whatever is on screen.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local theme = require("core/theme")
local timing = require("core/timing")
local capture = require("services/capture")
local wallpaper = require("services/wallpaper")

local M = {}

M.roles = { "background", "text", "primary", "secondary" }

-- The palette on screen, if a palette is what is on screen.
function M.current(): any
    if theme.source() ~= "manual" then return nil end
    local chosen = theme.manual_palette()
    for _, p in theme.palettes() do
        if p.file == chosen then return p end
    end
    return nil
end
function M.editable(): boolean local c = M.current() return c ~= nil and c.own end

-- What is being written: the file's own content, until a change makes a
-- draft of it, kept after it is written so the editor does not step back
-- for the moment the file takes to be read again.
local draft = g.signal(nil :: any)
local draft_file = g.signal("")
function M.colours(): { [string]: any }
    local c = M.current()
    if not c then return {} end
    if draft.value and draft_file.value == c.file then return draft.value end
    return c.colours
end

function M.hex(c: string): string return string.upper(string.sub(c, 1, 7)) end

-- `#RRGGBB` from what somebody typed, or "" when it is not a colour.
function M.parse(text: string): string
    local six = string.match(string.match(text, "^%s*(.-)%s*$") or "", "^#?(%x%x%x%x%x%x)$")
    return if six then "#" .. string.upper(six) else ""
end

local function path_of(file: string): string return theme.user_palettes .. "/" .. file .. ".json" end

-- One writer per file, written whole and atomically.
local writers: { [string]: any } = {}
local function write(file: string, data: { [string]: any }, after: (() -> ())?)
    local text = g.to_json({
        name = data.name, background = data.background, text = data.text,
        primary = data.primary, secondary = data.secondary,
    }, true)
    local path = path_of(file)
    writers[path] = writers[path] or g.file { path = path, watch = false }
    writers[path]:write(text .. "\n")
    if after then g.after(0, after) end
end

-- Written while the hand moves, at most a step every debounce, and once
-- more when it rests.
local writing: any = nil
local function save()
    local c = g.untracked(M.current)
    local d = g.untracked(function() return draft.value end)
    if c and d and g.untracked(function() return draft_file.value end) == c.file then write(c.file, d) end
end
local function settle()
    if writing then return end
    save()
    writing = g.after(timing.seconds.debounce, function()
        writing = nil
        save()
    end)
end
-- While the hand moves a colour the desktop follows it at once, not a
-- crossing behind (services/Palettes.qml: Theme.immediate); once it has
-- rested past the last write, the theme follows its file again.
local resting: any = nil
local function let_go()
    if resting then
        resting:stop()
        resting = nil
    end
    theme.immediate.value = false
end
local function follow_hand()
    theme.immediate.value = true
    theme.show(g.untracked(function() return draft.value end))
    if resting then resting:stop() end
    resting = g.after(timing.seconds.debounce * 2, function()
        resting = nil
        theme.immediate.value = false
    end)
end

local function flush()
    let_go()
    if writing then
        writing:stop()
        writing = nil
        save()
    end
end

function M.choose(file: string)
    flush()
    config.set_many({ { "theme.source", "manual" }, { "theme.palette", file } })
end

local function taken(name: string, except: string?): boolean
    for _, p in theme.palettes() do
        if p.name == name and p.file ~= except then return true end
    end
    return false
end
function M.name_taken(name: string): boolean
    local c = M.current()
    return taken(name, if c then c.file else nil)
end

function M.create()
    flush()
    local list = g.untracked(theme.palettes)
    local n = 1
    local function file_taken(f: string): boolean
        for _, p in list do if p.file == f then return true end end
        return false
    end
    while file_taken("custom-" .. n) do n += 1 end
    local file = "custom-" .. n
    local name, k = "Custom", 1
    while g.untracked(function() return taken(name) end) do
        k += 1
        name = "Custom " .. k
    end
    local data = {
        name = name,
        background = M.hex(theme.target("background")),
        text = M.hex(theme.target("text")),
        primary = M.hex(theme.target("primary")),
        secondary = M.hex(theme.target("secondary")),
    }
    -- Chosen once it is on disk: asked for before, the theme looks for a
    -- file that is not there yet.
    write(file, data, function() M.choose(file) end)
end

local function change(patch: { [string]: any })
    if not g.untracked(M.editable) then return end
    local next = table.clone(g.untracked(M.colours))
    for k, v in patch do next[k] = v end
    draft_file.value = g.untracked(M.current).file
    draft.value = next
    settle()
end

function M.set_role(role: string, text: string)
    if not table.find(M.roles, role) then return end
    local hex = M.parse(text)
    if hex == "" or not g.untracked(M.editable) then return end
    change({ [role] = hex })
    follow_hand()
end

function M.rename(name: string)
    local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
    if not g.untracked(M.editable) or trimmed == "" or g.untracked(function() return M.name_taken(trimmed) end) then return end
    if trimmed ~= g.untracked(M.colours).name then change({ name = trimmed }) end
end

-- Back to Bioma's own palette first, so the desktop is never left wearing a
-- palette that has no file.
function M.remove()
    if not g.untracked(M.editable) then return end
    local file = g.untracked(M.current).file
    let_go()
    if writing then writing:stop() writing = nil end
    draft.value = nil
    draft_file.value = ""
    -- And every picture that wore it forgets it, in the same write, so none
    -- asks for it again.
    local kept, dropped = {}, false
    for image, pair in g.untracked(M.pairs) do
        if type(pair) == "table" and pair.source == "manual" and pair.palette == file then
            dropped = true
        else
            kept[image] = pair
        end
    end
    local changes: { { any } } = { { "theme.source", "manual" }, { "theme.palette", "default" } }
    if dropped then table.insert(changes, { "theme.pairs", kept }) end
    config.set_many(changes)
    g.process { command = { "rm", "-f", path_of(file) } }
end

-- ---- Each wallpaper's theme -----------------------------------------------------
--
-- `theme.pairs`, in the override layer: { "<image>": { "source": "manual",
-- "palette": "custom-1" } } or { "<image>": { "source": "matugen", "scheme":
-- "scheme-content" } }. Written whole, never by a path: an image's path is
-- full of dots.

function M.pairs(): { [string]: any }
    local saved = config.get("theme.pairs", {})
    return if type(saved) == "table" then saved else {}
end

local function pair_now(): { [string]: any }
    if theme.source() == "matugen" then
        return { source = "matugen", scheme = config.get("theme.matugen.scheme", "scheme-tonal-spot") }
    end
    return { source = "manual", palette = theme.manual_palette() }
end

local function remember()
    local image = g.untracked(wallpaper.current)
    if image == "" then return end
    local now = g.untracked(pair_now)
    local saved = g.untracked(M.pairs)
    local was = saved[image]
    if type(was) == "table" and was.source == now.source and was.scheme == now.scheme and was.palette == now.palette then
        return
    end
    local next_pairs = {}
    for k, v in saved do next_pairs[k] = v end
    next_pairs[image] = now
    config.set("theme.pairs", next_pairs)
end

-- A wallpaper and a theme are a pair once they have stayed together for
-- `timing.pair`: the pictures a carousel runs past are not.
local together: any = nil
local function settle_together()
    if together then together:stop() end
    together = g.after(timing.seconds.pair, function()
        together = nil
        remember()
    end)
end

-- The picture's own theme, if it has one and, for a palette, that palette
-- still exists.
local function recall(image: string)
    local pair = g.untracked(M.pairs)[image]
    if type(pair) ~= "table" then return end
    if pair.source == "matugen" then
        flush()
        -- The scheme and the source in one write: matugen runs once, with
        -- the picture's own.
        local changes: { { any } } = {}
        if type(pair.scheme) == "string" and pair.scheme ~= "" then
            table.insert(changes, { "theme.matugen.scheme", pair.scheme })
        end
        table.insert(changes, { "theme.source", "matugen" })
        config.set_many(changes)
    elseif pair.source == "manual" then
        for _, p in g.untracked(theme.palettes) do
            if p.file == pair.palette then
                M.choose(pair.palette)
                return
            end
        end
    end
end

-- By Bioma on Genoma alone (shell.luau). The first picture is the one the
-- session starts on, already wearing its theme: only a change of picture
-- recalls anything, and that first one, unpaired, is paired with what it
-- wears, so the first change has something to change from.
local started = false
function M.start()
    if started then return end
    started = true
    local last = ""
    g.watch(wallpaper.current, function(image: string)
        local before = last
        last = image
        if before ~= "" and image ~= before then recall(image) end
        settle_together()
    end)
    g.watch(function(): string
        local now = pair_now()
        return now.source .. "\n" .. (now.scheme or now.palette or "")
    end, settle_together)
end

-- ---- The eyedropper ----------------------------------------------------------
--
-- niri's own picker, through the capture service: the colour comes back here
-- and nowhere else, not to the clipboard, not to the utility's list.
local picking = g.signal("")
function M.picking(): string return picking.value end
function M.pick(role: string)
    if not g.untracked(M.editable) then return end
    picking.value = role
    capture.pick_colour(false)
end
capture.on("picked", function(hex: string)
    local role = g.untracked(function() return picking.value end)
    picking.value = ""
    if role ~= "" then M.set_role(role, hex) end
end)
capture.on("cancelled", function() picking.value = "" end)
capture.on("failed", function() picking.value = "" end)

-- The colour of a role as hue, saturation and value, for the sliders.
function M.hsv(role: string): (number, number, number)
    local c = M.colours()[role]
    if type(c) ~= "string" or c == "" then return 0, 0, 0 end
    return colour.hsv(colour.parse(c))
end
function M.set_hsv(role: string, h: number, s: number, v: number)
    M.set_role(role, M.hex(colour.format(colour.hsva(h, s, v, 1))))
end

return M
