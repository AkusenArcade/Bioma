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
-- An array parsed from JSON carries the array metatable; an object does not.
local function is_object(v: any): boolean
    return type(v) == "table" and getmetatable(v) == nil
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

-- `config.get("timing.open", 250)`: the merged value at that path, or the
-- fallback. Read inside a binding, it follows the files.
function M.get(path: string, fallback: any): any
    local node = merged.value
    for key in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then return fallback end
        node = node[key]
        if node == nil then return fallback end
    end
    return node
end

-- Writing back: into the override, never the base, and only the keys
-- given; the rest of the file (its order, its `$comment` keys) is left as
-- it was. Several keys in one write, so a tissue moved between two lists is
-- never in both or neither for a reload.
function M.set_many(pairs: { { any } })
    local text = g.json_set(override_file.text, pairs)
    override_file:write(text)
end

function M.set(path: string, value: any)
    M.set_many({ { path, value } })
end

return M
