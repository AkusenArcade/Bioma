--!strict
-- Hyprland's keybinds. Its configuration is a Lua program, where a key is
-- often built from a variable (`mainMod .. " + Q"`), so it cannot be read
-- as text the way niri's and Umbriel's are. Two sources, then:
--
-- - Bioma's own file, bioma-binds.lua (config/hyprland/bioma-binds.lua.in),
--   one `bind("SUPER + ALT + V", command, { description = … })` a line:
--   read as text and rewritten in place, through `scripts/hypr-include`,
--   which has Hyprland check the file first.
-- - Every other bind, as Hyprland holds it (`hyprctl binds -j`): listed,
--   marked `fixed`, and left to hyprland.lua. They come first, as
--   hyprland.lua is read before the file it requires last.
--
-- Keys are kept in niri's spelling ("Super+Alt+V"), which the page records
-- and shows, and turned into Hyprland's ("SUPER + ALT + V") when written.
local g = require("@genoma")
local kdl = require("services/niri_kdl")
local paths = require("core/paths")
local spawn = require("services/keybinds_spawn")

local M = {}

local home = g.env("HOME") or ""
local dir = (g.env("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/hypr"
M.main = dir .. "/bioma-binds.lua"
M.group = "HYPRLAND"
M.where = "rewrites bioma-binds.lua, reads hyprland.lua"
local config_path = dir .. "/hyprland.lua"

-- ---- Keys, both ways -------------------------------------------------------------

local MODS_IN = { SUPER = "Super", WIN = "Super", LOGO = "Super", MOD4 = "Super", ALT = "Alt", MOD1 = "Alt",
    SHIFT = "Shift", CTRL = "Ctrl", CONTROL = "Ctrl" }
local MODS_OUT = { Mod = "SUPER", Super = "SUPER", Alt = "ALT", Shift = "SHIFT", Ctrl = "CTRL" }
-- The modifier mask hyprctl reports.
local MASK = { { 64, "Super" }, { 4, "Ctrl" }, { 8, "Alt" }, { 1, "Shift" } }
local MOUSE_IN = { ["mouse:272"] = "MouseLeft", ["mouse:273"] = "MouseRight", ["mouse:274"] = "MouseMiddle",
    ["mouse:275"] = "MouseBack", ["mouse:276"] = "MouseForward", mouse_down = "WheelScrollDown", mouse_up = "WheelScrollUp" }
local MOUSE_OUT: { [string]: string } = {}
for k, v in MOUSE_IN do MOUSE_OUT[v] = k end
-- niri's names for punctuation and space are keysyms in lower case.
local LOWER = { space = true, minus = true, equal = true, bracketleft = true, bracketright = true, semicolon = true,
    apostrophe = true, grave = true, backslash = true, comma = true, period = true, slash = true, less = true }

local function from_hyprland(keys: string): string
    local parts = {}
    for part in string.gmatch(keys, "[^+]+") do
        local word = string.match(part, "^%s*(.-)%s*$") or ""
        if word ~= "" then table.insert(parts, word) end
    end
    local key = table.remove(parts) or ""
    local mods = {}
    for _, p in parts do table.insert(mods, MODS_IN[string.upper(p)] or p) end
    return kdl.compose(mods, MOUSE_IN[key] or key)
end

local function to_hyprland(key: string): string
    local parts = kdl.split(key)
    local out = {}
    for _, m in parts.mods do
        local word = MODS_OUT[m]
        if word and not table.find(out, word) then table.insert(out, word) end
    end
    local k = MOUSE_OUT[parts.key] or (if LOWER[string.lower(parts.key)] then string.lower(parts.key) else parts.key)
    table.insert(out, k)
    return table.concat(out, " + ")
end

local function from_mask(mask: number, key: string): string
    local mods = {}
    for _, bit in MASK do
        if bit32.band(mask, bit[1]) ~= 0 then table.insert(mods, bit[2]) end
    end
    return kdl.compose(mods, MOUSE_IN[key] or key)
end

-- ---- Bioma's file ---------------------------------------------------------------

local file = g.file { path = M.main }

local function scan(text: string): { any }
    local out = {}
    local pos = 1
    while pos <= #text do
        local line_end = string.find(text, "\n", pos, true) or (#text + 1)
        local line = string.sub(text, pos, line_end - 1)
        local open_at, key_open = string.find(line, "^%s*bind%s*%(%s*\"")
        if open_at then
            local close = string.find(line, "\"", (key_open :: number) + 1, true)
            if close then
                local keys = string.sub(line, (key_open :: number) + 1, close - 1)
                local title = string.match(line, "description%s*=%s*\"(.-)\"")
                local command = string.match(line, "^%s*,%s*(.-)%s*,%s*{", close + 1) or string.match(line, "^%s*,%s*(.-)%s*%)%s*$", close + 1)
                local key = from_hyprland(keys)
                table.insert(out, {
                    id = M.main .. "#" .. (pos - 1) .. "#" .. keys,
                    file = M.main,
                    key = key,
                    key_raw = keys,
                    line_start = pos,
                    line_end = line_end,
                    key_start = pos + (key_open :: number),
                    key_end = pos + close - 1,
                    command = command,
                    label = if title and title ~= "" then title else "Run " .. (command or ""),
                    caps = kdl.keycaps(key),
                    norm = kdl.normalize(key),
                    shadowed = false,
                    fixed = false,
                })
            end
        end
        pos = line_end + 1
    end
    return out
end
local own = g.computed(function(): { any }
    local text = file.text
    return if text then scan(text) else {}
end)

-- ---- Hyprland's own -------------------------------------------------------------

-- What an undescribed bind does. A Lua configuration's dispatchers come
-- as "HL.Dispatcher(window.close)", their argument a reference: the name
-- alone says it. hyprlang's ("killactive") come with their words.
local function dispatcher_words(b: any): string
    local d = b.dispatcher or ""
    local inner = string.match(d, "^HL%.Dispatcher%((.-)%)$")
    if inner then
        if inner == "exec_cmd" then return "Run a command" end
        return kdl.humanize((string.gsub(inner, "[%._]", " ")))
    end
    return kdl.humanize(d) .. (if (b.arg or "") ~= "" then " " .. b.arg else "")
end

local held = g.signal({} :: { any })
local reading = false
local function read_held()
    if reading or not g.env("HYPRLAND_INSTANCE_SIGNATURE") then return end
    reading = true
    local out = {}
    g.process {
        command = { "hyprctl", "binds", "-j" },
        on_line = function(line: string) table.insert(out, line) end,
        on_exit = function(code: number)
            reading = false
            if code ~= 0 then return end
            local ok, list = pcall(g.parse_json, table.concat(out, "\n"))
            if not ok or type(list) ~= "table" then return end
            local found = {}
            for i, b in list do
                if (b.submap or "") == "" and (b.key or "") ~= "" then
                    local key = from_mask(b.modmask or 0, b.key)
                    local what = if (b.description or "") ~= "" then b.description else dispatcher_words(b)
                    table.insert(found, {
                        id = "hyprland#" .. i .. "#" .. key,
                        file = config_path,
                        key = key,
                        label = what,
                        caps = kdl.keycaps(key),
                        norm = kdl.normalize(key),
                        shadowed = false,
                        fixed = true,
                    })
                end
            end
            held.value = found
        end,
    }
end
read_held()
-- Bioma's file rewritten: Hyprland reloads, and what it holds is asked again.
g.watch(function() return file.text end, function() g.after(0.5, read_held) end)

local binds = g.computed(function(): { any }
    local mine = own.value
    local taken: { [string]: boolean } = {}
    for _, b in mine do taken[b.norm] = true end
    local found = {}
    -- Bioma's binds are in Hyprland's list too: once, as Bioma's.
    for _, b in held.value do
        if not taken[b.norm] then table.insert(found, b) end
    end
    for _, b in mine do table.insert(found, table.clone(b)) end
    local last = {}
    for i, b in found do last[b.norm] = i end
    for i, b in found do b.shadowed = last[b.norm] ~= i end
    return found
end)
function M.binds(): { any } return binds.value end
function M.count(): number return #binds.value end

function M.owner(key: string, except: string?): any
    local norm = kdl.normalize(key)
    local list = binds.value
    for i = #list, 1, -1 do
        local b = list[i]
        if b.norm == norm and b.id ~= except then return b end
    end
    return nil
end

function M.keycaps(key: string): { string } return kdl.keycaps(key) end
function M.humanize(name: string): string return kdl.humanize(name) end

-- ---- Writing ---------------------------------------------------------------------

local busy = g.signal(false)
local refused = g.signal("")
function M.busy(): boolean return busy.value end
function M.error(): string return refused.value end

local function write(text: string)
    if g.untracked(function() return busy.value end) then
        refused.value = "Still writing the last change."
        return
    end
    busy.value = true
    local said = {}
    local p = g.process {
        command = { paths.script("hypr-include"), "binds" },
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number)
            busy.value = false
            refused.value = if code == 0 then ""
                else "Hyprland refused it" .. (if #said > 0 then ": " .. said[1] else ".")
        end,
    }
    p:write(text)
    p:close_input()
end

local function current(bind: any): string?
    local text = file.text
    if bind.fixed then
        refused.value = "That bind is hyprland.lua's: change it there."
        return nil
    end
    if not text or string.sub(text, bind.key_start, bind.key_end - 1) ~= bind.key_raw then
        refused.value = "The file changed under this bind. Try again."
        return nil
    end
    return text
end

function M.rekey(bind: any, key: string)
    local text = current(bind)
    if text then write(string.sub(text, 1, bind.key_start - 1) .. to_hyprland(key) .. string.sub(text, bind.key_end)) end
end

function M.remove(bind: any)
    local text = current(bind)
    if text then write(string.sub(text, 1, bind.line_start - 1) .. string.sub(text, bind.line_end + 1)) end
end

-- What a file of Bioma's binds needs before its first line, when there is
-- none yet (config/hyprland/bioma-binds.lua.in has the same).
local HEAD = [[
-- Bioma — the keys that ask for a cell, for Hyprland. Yours to edit, one
-- bind a line; the settings cell's Keybinds page rewrites it in place.
local function bind(keys, command, options)
    pcall(hl.unbind, keys)
    hl.bind(keys, hl.dsp.exec_cmd(command), options)
end
]]

-- Only commands: Hyprland's other actions are Lua calls, not words.
function M.add(key: string, action: { name: string, args: { string } }, title: string)
    if action.name ~= "spawn" then
        refused.value = "Hyprland binds only commands here."
        return
    end
    local text = file.text or HEAD
    if string.sub(text, -1) ~= "\n" then text ..= "\n" end
    local options = if title ~= "" then string.format(", { description = %q }", title) else ""
    write(text .. string.format("bind(%q, %q%s)\n", to_hyprland(key), spawn.command_line(action.args), options))
end

function M.actions(): { string } return {} end
function M.ask_actions()
    spawn.ask()
    read_held()
end

M.spawn_of = spawn.of

return M
