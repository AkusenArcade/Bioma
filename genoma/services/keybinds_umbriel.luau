--!strict
-- Umbriel's keybinds: every `[keybinds]` line of config.toml and of the
-- files it includes, in the order Umbriel applies them (the included files
-- in list order, config.toml last, so a key there wins), each rewritten in
-- place like niri's.
--
-- A bind is one line, `"Mod+T" = "action"` or `"Mod+T" = { action = … }`,
-- and the comment at its end, when there is one, is its title (Bioma's own
-- file says `# Bioma: vitals`). A line is rewritten as text: its key, or
-- the whole line taken out; the rest stays as written. A file goes back
-- only once Umbriel has accepted it whole (`umbriel config validate`), and
-- Umbriel reloads by itself.
--
-- A new bind goes into bioma-binds.toml, Bioma's own, through
-- `scripts/umbriel-include`: written there, and the same key in
-- config.toml taken out of it, since config.toml would win.
local g = require("@genoma")
local kdl = require("services/niri_kdl")
local paths = require("core/paths")
local spawn = require("services/keybinds_spawn")

local M = {}

local home = g.env("HOME") or ""
local dir = (g.env("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/umbriel"
local config_path = dir .. "/config.toml"
M.main = dir .. "/bioma-binds.toml"
M.group = "UMBRIEL"
M.where = "reads and rewrites Umbriel's binds, where they are written"

-- ---- Reading ---------------------------------------------------------------

local files: { [string]: any } = {}
local opened = g.signal(0)
local function open(path: string): any
    if not files[path] then
        files[path] = g.file { path = path }
        opened.value += 1
    end
    return files[path]
end
open(config_path)

local function resolve(path: string): string
    if string.sub(path, 1, 2) == "~/" then return home .. string.sub(path, 2) end
    if string.sub(path, 1, 1) == "/" then return path end
    return dir .. "/" .. (string.gsub(path, "^%./", ""))
end

-- The value of a TOML string starting at `at` (its quote), and where it
-- ends. Basic strings know \" and \\; literal ones nothing.
local function read_string(text: string, at: number): (string?, number)
    local q = string.sub(text, at, at)
    if q ~= '"' and q ~= "'" then return nil, at end
    local out, i = {}, at + 1
    while i <= #text do
        local c = string.sub(text, i, i)
        if c == q then return table.concat(out), i + 1 end
        if c == "\n" then return nil, i end
        if q == '"' and c == "\\" then
            local n = string.sub(text, i + 1, i + 1)
            table.insert(out, if n == "n" then "\n" elseif n == "t" then "\t" else n)
            i += 2
        else
            table.insert(out, c)
            i += 1
        end
    end
    return nil, i
end

-- The include lists of config.toml, required then optional, in order.
local function includes(text: string): { string }
    local out = {}
    for _, section in { "include", "include.optional" } do
        local header = "\n%[" .. string.gsub(section, "%.", "%%.") .. "%][ \t]*[^\n]*"
        local _, head_end = string.find("\n" .. text, header)
        if head_end then
            local rest = string.sub("\n" .. text, head_end + 1)
            local next_header = string.find(rest, "\n%s*%[") or #rest + 1
            local body = string.sub(rest, 1, next_header)
            local list = string.match(body, "\n%s*files%s*=%s*(%b[])")
            if list then
                local i = 1
                while i <= #list do
                    local c = string.sub(list, i, i)
                    if c == "#" then
                        i = (string.find(list, "\n", i) or #list) + 1
                    elseif c == '"' or c == "'" then
                        local value, after = read_string(list, i)
                        if value then table.insert(out, resolve(value)) end
                        i = after
                    else
                        i += 1
                    end
                end
            end
        end
    end
    return out
end

-- `general.mod_key`, which "Mod" stands for.
local function mod_key(text: string): string
    local general = string.match("\n" .. text, "\n%[general%][^\n]*(.-)\n%s*%[") or string.match("\n" .. text, "\n%[general%][^\n]*(.*)$") or ""
    local named = string.match(general, "\n%s*mod_key%s*=%s*[\"']([%a]+)[\"']")
    return if named then named else "Super"
end

-- Every bind line of one file's [keybinds] tables.
local function scan(path: string, text: string, modifier: string): { any }
    local out = {}
    local in_binds = false
    local pos = 1
    while pos <= #text do
        local line_end = string.find(text, "\n", pos, true) or (#text + 1)
        local line = string.sub(text, pos, line_end - 1)
        local header = string.match(line, "^%s*%[%[?%s*([^%]%s]+)%s*%]%]?%s*$") or string.match(line, "^%s*%[%[?%s*([^%]%s]+)%s*%]%]?%s*#")
        if header then
            in_binds = header == "keybinds"
        elseif in_binds then
            local indent = #(string.match(line, "^%s*") or "")
            local first = string.sub(line, indent + 1, indent + 1)
            local key, after = nil, indent + 1
            if first == '"' or first == "'" then
                key, after = read_string(line, indent + 1)
            elseif first ~= "#" and first ~= "" then
                local bare = string.match(line, "^[%w_%+%-]+", indent + 1)
                if bare then key, after = bare, indent + 1 + #bare end
            end
            local rest = if key then string.match(string.sub(line, after), "^%s*=%s*(.*)$") else nil
            -- Submap binds ("submap[name],Escape") are another layer's.
            if key and rest and not string.find(key, "[%[,]") then
                local action, title = nil, nil
                local value_at = #line - #rest + 1
                if string.sub(rest, 1, 1) == "{" then
                    local close = string.find(rest, "}", 1, true)
                    local inner = string.sub(rest, 2, (close or #rest) - 1)
                    local a = string.find(inner, "action%s*=%s*[\"']")
                    if a then action = read_string(inner, (string.find(inner, "[\"']", a) :: number)) end
                    local tail = if close then string.sub(rest, close + 1) else ""
                    title = string.match(tail, "^%s*#%s*(.-)%s*$")
                else
                    local v, v_end = read_string(line, value_at)
                    action = v
                    title = string.match(string.sub(line, v_end), "^%s*#%s*(.-)%s*$")
                end
                local key_spelled = key :: string
                local norm_key = string.gsub(key_spelled, "^[Mm][Oo][Dd]%+", modifier .. "+")
                norm_key = string.gsub(norm_key, "%+[Mm][Oo][Dd]%+", "+" .. modifier .. "+")
                table.insert(out, {
                    id = path .. "#" .. (pos - 1) .. "#" .. key_spelled,
                    file = path,
                    key = key_spelled,
                    key_raw = string.sub(line, indent + 1, after - 1),
                    line_start = pos,
                    line_end = line_end,
                    key_start = pos + indent,
                    key_end = pos + after - 1,
                    action = action,
                    title = if title and title ~= "" then title else nil,
                    norm_key = norm_key,
                })
            end
        end
        pos = line_end + 1
    end
    return out
end

-- Umbriel's wheel is niri's by a shorter name; here it goes by niri's.
local function from_umbriel(key: string): string
    return (string.gsub(key, "([Ww]heel)([UDLR]%a+)$", "%1Scroll%2"))
end
local function to_umbriel(key: string): string
    return (string.gsub(key, "WheelScroll(%a+)$", "Wheel%1"))
end

local function label_of(b: any): string
    if b.title then return b.title end
    local action = b.action or ""
    local name, args = string.match(action, "^(%S+)%s*(.*)$")
    if name == "spawn" then
        local words = string.split(args or "", " ")
        local first = string.gsub(words[1] or "", "^['\"]", "")
        first = string.gsub(first, "['\"]$", "")
        local parts = string.split(first, "/")
        words[1] = parts[#parts]
        return "Run " .. table.concat(words, " ")
    end
    if name then return kdl.humanize(name) .. (if args ~= "" then " " .. args else "") end
    return b.key
end

-- The files in the order Umbriel applies them; one named for the first
-- time is opened, and what follows runs again.
local order = g.computed(function(): { string }
    local text = files[config_path].text
    if text == nil then return {} end
    local out = includes(text)
    table.insert(out, config_path)
    return out
end)
g.watch(function() return order.value end, function(list: { string })
    for _, path in list do open(path) end
end)

local binds = g.computed(function(): { any }
    local _ = opened.value
    local text = files[config_path].text
    if text == nil then return {} end
    local modifier = mod_key(text)
    local found = {}
    for _, path in order.value do
        local file = files[path]
        if file and file.text then
            for _, b in scan(path, file.text, modifier) do
                b.label = label_of(b)
                b.caps = kdl.keycaps(from_umbriel(b.key))
                b.norm = kdl.normalize(from_umbriel(b.norm_key))
                b.shadowed = false
                b.fixed = false
                table.insert(found, b)
            end
        end
    end
    local last = {}
    for i, b in found do last[b.norm] = i end
    for i, b in found do b.shadowed = last[b.norm] ~= i end
    return found
end)
function M.binds(): { any } return binds.value end
function M.count(): number return #binds.value end

function M.owner(key: string, except: string?): any
    local text = files[config_path].text or ""
    local modifier = mod_key(text)
    local spelled = string.gsub(key, "^Mod%+", modifier .. "+")
    local norm = kdl.normalize(spelled)
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

local function reason(said: { string }): string
    for _, line in said do
        local why = string.match(line, "^warning:%s*%S+:%d+:%d+:%s*(.*)$") or string.match(line, "^error:%s*(.*)$")
        if why then return "Umbriel refused it: " .. why end
    end
    return if #said > 0 then "Umbriel refused it: " .. said[#said] else "Umbriel refused it."
end

-- One write at a time. Bioma's own file through umbriel-include; any other
-- checked beside itself, so its includes resolve as they will, then moved
-- over the file (or the file a link points to).
local CHECKED = [[
set -u
target=$(readlink -f "$1")
tmp=$(mktemp "$(dirname "$target")/.bioma-binds.XXXXXX.toml") || exit 1
cat > "$tmp"
if env -u UMBRIEL_SOCKET umbriel config validate -c "$tmp" >/dev/null; then
    chmod --reference="$target" "$tmp" 2>/dev/null
    mv "$tmp" "$target"
else
    rm -f "$tmp"
    exit 1
fi
]]
local function write(path: string, text: string)
    if g.untracked(function() return busy.value end) then
        refused.value = "Still writing the last change."
        return
    end
    busy.value = true
    local said = {}
    local command = if path == M.main then { paths.script("umbriel-include"), "binds" } else { "sh", "-c", CHECKED, "write", path }
    local p = g.process {
        command = command,
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number)
            busy.value = false
            refused.value = if code == 0 then "" else reason(said)
        end,
    }
    p:write(text)
    p:close_input()
end

local function current(bind: any): string?
    local file = files[bind.file]
    local text = if file then file.text else nil
    if not text or string.sub(text, bind.key_start, bind.key_end - 1) ~= bind.key_raw then
        refused.value = "The file changed under this bind. Try again."
        return nil
    end
    return text
end

local function quoted(s: string): string
    return '"' .. string.gsub(string.gsub(s, "\\", "\\\\"), '"', '\\"') .. '"'
end

function M.rekey(bind: any, key: string)
    local text = current(bind)
    if not text then return end
    write(bind.file, string.sub(text, 1, bind.key_start - 1) .. quoted(to_umbriel(key)) .. string.sub(text, bind.key_end))
end

function M.remove(bind: any)
    local text = current(bind)
    if not text then return end
    write(bind.file, string.sub(text, 1, bind.line_start - 1) .. string.sub(text, bind.line_end + 1))
end

-- The action as Umbriel spells it: `spawn` and a command line, or the
-- action's name and its words.
local function action_text(action: { name: string, args: { string } }): string
    if action.name == "spawn" then return "spawn " .. spawn.command_line(action.args) end
    if #action.args == 0 then return action.name end
    return action.name .. " " .. table.concat(action.args, " ")
end

function M.add(key: string, action: { name: string, args: { string } }, title: string)
    local file = open(M.main)
    local text = file.text or "[keybinds]\n"
    if not string.find("\n" .. text, "\n%s*%[keybinds%]") then text ..= "\n[keybinds]\n" end
    if string.sub(text, -1) ~= "\n" then text ..= "\n" end
    local line = quoted(to_umbriel(key)) .. " = " .. quoted(action_text(action))
    if title ~= "" then line ..= " # " .. string.gsub(title, "\n", " ") end
    write(M.main, text .. line .. "\n")
end

-- ---- What a new bind can do -------------------------------------------------
--
-- Umbriel's own actions, asked of `umbriel msg --help`, minus those that
-- need an argument and `spawn`, offered as the applications instead.
local actions = g.signal({} :: { string })
local asked = false
function M.actions(): { string } return actions.value end
function M.ask_actions()
    spawn.ask()
    if asked then return end
    asked = true
    local out = {}
    g.process {
        command = { "umbriel", "msg", "--help" },
        on_line = function(line: string)
            local name, rest = string.match(line, "^  ([a-z][a-z0-9%-]+)(.*)$")
            -- "[<output>]" is optional; a bare "<…>" is not.
            local required = string.gsub(rest, "%b[]", "")
            if name and name ~= "spawn" and not string.find(required, "<", 1, true) then table.insert(out, name) end
        end,
        on_exit = function() actions.value = out end,
    }
end

M.spawn_of = spawn.of

return M
