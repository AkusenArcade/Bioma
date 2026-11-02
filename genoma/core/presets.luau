--!strict
-- Layout presets (core/Presets.qml at 11bb81e): the whole composition of
-- the desktop (every membrane, every floating tissue, every organism, on
-- every monitor) under a name, to be put back in one press.
--
-- A list offers the user's first, then Bioma's own from config/presets/ in
-- their files' `order`. A shipped one may borrow lists from the base layer
-- (`from_base`): Complete takes the default's membranes and floating
-- tissues rather than a copy of them, so the two cannot drift apart.
--
-- They live in the override, under `presets`, beside the layout they
-- snapshot, because putting one back is a single write: the three lists
-- and the name of the one now in use land together (`config.set_many`).
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

-- What a layout is. The order of the keys is the order of the writes.
M.keys = { "membranes", "floating", "organisms" }

local folder = g.folder { path = paths.root .. "/config/presets" }
local files = g.signal({} :: { any })
g.effect(function()
    local readers = {}
    for _, e in folder.entries do
        if not e.dir and string.match(e.name, "%.json$") then
            table.insert(readers, g.file { path = e.path, watch = false })
        end
    end
    g.effect(function()
        local out = {}
        for _, r in readers do
            local ok, data = pcall(g.parse_json, r.text or "")
            if ok and type(data) == "table" and data.name then table.insert(out, data) end
        end
        table.sort(out, function(a, b) return (a.order or 0) < (b.order or 0) end)
        g.untracked(function() files.value = out end)
    end)
end)

-- The shipped ones, resolved: `{ name, line, shipped, membranes, floating,
-- organisms }`.
local shipped = g.computed(function(): { any }
    local base = config.base_values()
    local out = {}
    for _, entry in files.value do
        local preset: { [string]: any } = { name = entry.name, line = entry.line or "", order = entry.order or 0, shipped = true }
        local borrowed = entry.from_base or {}
        for _, key in M.keys do
            preset[key] = if table.find(borrowed, key) then (base[key] or {}) else (entry[key] or {})
        end
        table.insert(out, preset)
    end
    return out
end)

function M.saved(): { any }
    local list = config.get("presets.saved", {})
    return if type(list) == "table" then list else {}
end

-- Every preset a list offers: the user's first, then Bioma's.
function M.all(): { any }
    local out = {}
    for _, p in M.saved() do table.insert(out, p) end
    for _, p in shipped.value do table.insert(out, p) end
    return out
end

-- The one last put back or saved, by name; empty after NEW, or before the
-- first one is saved.
function M.active(): string return config.get("presets.active", "") end

function M.find(name: string): any
    for _, p in M.saved() do if p.name == name then return p end end
    for _, p in shipped.value do if p.name == name then return p end end
    return nil
end

-- A shipped name cannot be taken by a preset of the user's, in any case:
-- two rows called Minimal, one of them Bioma's, would be one too many.
local function trim(s: string): string return string.match(s or "", "^%s*(.-)%s*$") or "" end
function M.reserved(name: string): boolean
    local wanted = string.lower(trim(name))
    if wanted == "" then return false end
    for _, p in shipped.value do
        if string.lower(p.name) == wanted then return true end
    end
    return false
end

-- Two layouts are the same layout when they say the same thing, whatever
-- order their keys were written in: the override is written by hand as
-- well as by the page. An empty list and an empty object say the same.
local function canonical(v: any): string
    local kind = type(v)
    if kind == "string" then return string.format("%q", v) end
    if kind ~= "table" then return tostring(v) end
    local keys = {}
    for k in v do table.insert(keys, k) end
    if #keys == 0 then return "[]" end
    if #keys == #v then
        local parts = {}
        for _, item in v do table.insert(parts, canonical(item)) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in keys do table.insert(parts, tostring(k) .. ":" .. canonical(v[k])) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function signature(layout: any): string
    local parts = {}
    for _, key in M.keys do table.insert(parts, canonical(if layout and layout[key] then layout[key] else {})) end
    return table.concat(parts, "|")
end

-- The layout as the shell has it now, in the shape a preset keeps.
local function current(): { [string]: any }
    local out = {}
    for _, key in M.keys do out[key] = config.get(key, {}) end
    return out
end
local current_key = g.computed(function() return signature(current()) end)

local empty = g.computed(function(): boolean
    for _, key in M.keys do
        local list = config.get(key, {})
        if type(list) == "table" and #list > 0 then return false end
    end
    return true
end)
function M.empty(): boolean return empty.value end

-- Something on the page differs from the preset in use, or there is no
-- preset in use and the layout is not empty, so it is kept nowhere yet.
local changed = g.computed(function(): boolean
    local active = M.find(M.active())
    if active then return signature(active) ~= current_key.value end
    return not empty.value
end)
function M.changed(): boolean return changed.value end

-- Whether the layout as it stands is kept under some name: switching away
-- from one that is not throws it away, and the page asks first.
local kept = g.computed(function(): boolean
    if empty.value then return true end
    for _, p in M.all() do
        if signature(p) == current_key.value then return true end
    end
    return false
end)
function M.kept(): boolean return kept.value end

-- ---- Writing -----------------------------------------------------------------

-- The layout as it stands, under this name: a new preset at the end of the
-- list, or the one of that name replaced where it was.
function M.save_as(name: string): boolean
    name = trim(name)
    if name == "" or M.reserved(name) then return false end
    local preset: { [string]: any } = { name = name }
    for _, key in M.keys do preset[key] = config.copy_list(config.get(key, {})) end
    local next = config.copy_list(M.saved())
    local at = nil
    for i, p in next do if p.name == name then at = i end end
    if at then next[at] = preset else table.insert(next, preset) end
    print("Bioma: " .. (if at then "replacing" else "saving") .. " the layout preset \"" .. name .. "\"")
    config.set_many({ { "presets.saved", next }, { "presets.active", name } })
    return true
end

-- Putting one back: its three lists and its name, in one write.
function M.apply(name: string): boolean
    local preset = M.find(name)
    if not preset then return false end
    print("Bioma: applying the layout preset \"" .. name .. "\"")
    local pairs = {}
    for _, key in M.keys do table.insert(pairs, { key, config.copy_list(preset[key] or {}) }) end
    table.insert(pairs, { "presets.active", name })
    config.set_many(pairs)
    return true
end

-- NEW: a desktop with nothing on it, to be composed from scratch. Nothing
-- is saved until it is given a name.
function M.blank()
    print("Bioma: starting an empty layout")
    local pairs = {}
    for _, key in M.keys do table.insert(pairs, { key, g.array({}) }) end
    table.insert(pairs, { "presets.active", "" })
    config.set_many(pairs)
end

-- Forgetting one changes nothing on the screen: the layout stays as it is,
-- kept under no name if it was the one in use.
function M.remove(name: string): boolean
    local next = g.array({})
    local found = false
    for _, p in config.copy_list(M.saved()) do
        if p.name == name then found = true else table.insert(next, p) end
    end
    if not found then return false end
    print("Bioma: removing the layout preset \"" .. name .. "\"")
    local pairs: { { any } } = { { "presets.saved", next } }
    if M.active() == name then table.insert(pairs, { "presets.active", "" }) end
    config.set_many(pairs)
    return true
end

return M
