--!strict
-- Bioma on Genoma (genoma/PORT.md). Step 0 of the port: the configuration's
-- two layers are read, and the blocks marked `"runtime": "genoma"` are
-- found; nothing is drawn yet. Drawing them is the layout engine's, steps 1
-- and 2.
local g = require("@genoma")

local function read(path: string): any
    local f = g.file { path = path, watch = false }
    local text = f.text
    if not text then return nil end
    local ok, value = pcall(g.parse_json, text)
    if not ok then
        print("config: " .. path .. " is not JSON: " .. tostring(value))
        return nil
    end
    return value
end

local base = read("../config/default.json") or {}
-- `$XDG_CONFIG_HOME/bioma/override.json`, else `~/.config/bioma/…`, as
-- core/Config.qml reads it.
local override = read("$XDG_CONFIG_HOME/bioma/override.json") or read("~/.config/bioma/override.json") or {}

-- A key set in the override replaces the base's (core/Config.qml merges the
-- same way for the lists of blocks).
local function layer(key: string): any
    local v = override[key]
    if v == nil then return base[key] end
    return v
end

local owned = 0
for _, kind in { "membranes", "floating" } do
    for i, block in layer(kind) or {} do
        if block.runtime == "genoma" then
            owned += 1
            print(string.format("genoma owns %s %d: %s on %s", kind, i, block.edge or block.anchor or "?", block.monitor or "primary"))
        end
    end
end
print(string.format("Bioma on Genoma: %d blocks to draw (none drawn yet, step 0)", owned))

-- No output yet: an empty list of outputs makes no surface.
return g.surface {
    outputs = {},
    namespace = "bioma-genoma",
    function(_output: string) return g.box {} end,
}
