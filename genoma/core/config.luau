--!strict
-- Layered configuration (core/Config.qml).
--
--   1. config/default.json  — base layer, hand-written, in the repository
--   2. override.json        — written by the settings UI, loaded last, wins
--
-- Both files are watched. Consumers read `config.get`, never a file, and a
-- binding that reads it follows the configuration.
local g = require("@genoma")
local registry = require("cells/registry")

local M = {}

local home = (g.env("XDG_CONFIG_HOME") or (g.env("HOME") or "") .. "/.config")
M.override_path = home .. "/bioma/override.json"

local base_file = g.file { path = "../config/default.json" }
local override_file = g.file { path = M.override_path }

local function parse(text: string?, label: string): any
    if not text then return nil end
    local ok, value = pcall(g.parse_json, text)
    if not ok then
        print("Bioma: " .. label .. " is not valid JSON — " .. tostring(value))
        return nil
    end
    return value
end

-- Objects merge key by key; arrays and scalars are replaced wholesale. An
-- override that declares a tissue list means that list, not an append.
-- A list parsed from JSON is a plain table (g.parse_json leaves it
-- unmarked, so table.clone takes it), so an object is a table with a key
-- that is not a position. An empty table is taken as a list: an override
-- that empties a list (`"floating": []`) empties it.
local function is_object(v: any): boolean
    if type(v) ~= "table" or getmetatable(v) ~= nil then return false end
    return next(v) ~= nil and #v == 0
end

function M.merge(base: any, override: any): any
    if override == nil then return base end
    if not is_object(base) or not is_object(override) then return override end
    local out = {}
    for k, v in base do out[k] = v end
    for k, v in override do out[k] = M.merge(base[k], v) end
    return out
end

-- The layout as the shell reads it today: old names replaced, retired cells
-- dropped (each parse is a fresh table, so this edits nothing shared).
local function current(merged: any): any
    for _, key in { "membranes", "floating" } do
        if type(merged[key]) == "table" then
            merged[key] = registry.renamed(merged[key])
        end
    end
    return merged
end

local merged = g.computed(function()
    local base = parse(base_file.text, "config/default.json")
    if base == nil then return {} end
    local override = parse(override_file.text, "override.json")
    return current(M.merge(base, override))
end)

-- Whether the override file exists: absent, this is the first start on this
-- account (services/Setup.qml).
function M.override_exists(): boolean
    return override_file.text ~= nil
end

-- The base layer alone (core/Presets.qml reads the default's membranes).
local base_values = g.computed(function()
    local base = parse(base_file.text, "config/default.json")
    return if base then current(base) else {}
end)

function M.values(): any
    return merged.value or {}
end

function M.base_values(): any
    return base_values.value or {}
end

local function lookup(path: string): any
    local node = merged.value
    for key in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
        if node == nil then return nil end
    end
    return node
end

local function same(a: any, b: any): boolean
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in a do
        if not same(v, b[k]) then return false end
    end
    for k in b do
        if a[k] == nil then return false end
    end
    return true
end

-- One memo per path, made the first time it is asked for and kept by the
-- load: a binding follows its own key, and a write that leaves that key as
-- it was wakes nothing. Read straight from the merged files, every write
-- to the override (a palette, a slider) ran every binding that read any key
-- (Akusen, 2026-11-03). A table equal to the last is handed back as the
-- last, so a list nobody changed does not count as changed.
local memos: { [string]: any } = {}
local function memo_for(path: string): any
    local m = memos[path]
    if m then return m end
    m = g.lasting(function()
        local last: any = nil
        return g.computed(function(): any
            local now = lookup(path)
            if type(now) == "table" and same(now, last) then return last end
            last = now
            return now
        end)
    end)
    memos[path] = m
    return m
end

-- `config.get("timing.open", 250)`: the merged value at that path, or the
-- fallback. Read inside a binding, it follows the files.
function M.get(path: string, fallback: any): any
    local value = memo_for(path).value
    if value == nil then return fallback end
    return value
end

-- Writing back: into the override, never the base, and only the keys
-- given; the rest of the file (its order, its `$comment` keys) is left as
-- it was. Several keys in one write, so a tissue moved between two lists is
-- never in both or neither for a reload.
function M.set_many(pairs: { { any } })
    local text = g.json_set(override_file.text, pairs)
    override_file:write(text)
end

-- A deep copy of a configured list (the membranes, the floating blocks),
-- to change and write back whole: a list is one value to the merge. The
-- lists inside it stay lists even when empty (a tissue with no cells is
-- `[]`, never `{}`), and so do a preset's.
local LISTS = { tissues = true, cells = true, favourites = true, membranes = true, floating = true, organisms = true }
local function copy(value: any, list: boolean): any
    if type(value) ~= "table" then return value end
    local out = if list then g.array({}) else {}
    for k, v in value do
        out[k] = copy(v, type(k) == "string" and LISTS[k] == true)
    end
    return out
end
function M.copy_list(value: any): { any }
    return copy(if type(value) == "table" then value else {}, true)
end

function M.set(path: string, value: any)
    M.set_many({ { path, value } })
end

return M
