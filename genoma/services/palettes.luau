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
-- The pairing of each wallpaper with its palette stays Bioma on
-- Quickshell's while the two run side by side.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local theme = require("core/theme")
local timing = require("core/timing")
local capture = require("services/capture")

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
local function flush()
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
    if hex ~= "" then change({ [role] = hex }) end
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
    if writing then writing:stop() writing = nil end
    draft.value = nil
    draft_file.value = ""
    M.choose("default")
    g.process { command = { "rm", "-f", path_of(file) } }
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
