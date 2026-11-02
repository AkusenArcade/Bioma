--!strict
-- Layout presets (core/Presets.qml at 11bb81e), the part read so far: what
-- a list offers, the user's first, then Bioma's own from config/presets/
-- in their files' `order`. Applying and saving come with the Structure
-- page.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

local folder = g.folder { path = paths.root .. "/config/presets" }
local shipped = g.signal({} :: { any })
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
            if ok and type(data) == "table" and data.name then
                table.insert(out, { name = data.name, line = data.line or "", order = data.order or 0, shipped = true })
            end
        end
        table.sort(out, function(a, b) return a.order < b.order end)
        g.untracked(function() shipped.value = out end)
    end)
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

function M.active(): string return config.get("presets.active", "") end

return M
