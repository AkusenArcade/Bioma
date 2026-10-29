--!strict
-- The palette outside the shell: which applications it is carried to
-- (services/Templates.qml), the part a choice needs.
--
-- The rendering is Bioma on Quickshell's until the switch (genoma/PORT.md,
-- "Who acts on the desktop"): this reads the catalogue and the list that is
-- on, and hands a switch to Quickshell, which writes the list, renders and,
-- switched off, undoes what it had written.
--
-- Not yet: the failures of a render, which only the renderer knows.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

-- { { id, name, category, installed } }, asked once.
local catalogue = g.signal({})
do
    local out = {}
    g.process {
        command = { paths.script("themes"), "list" },
        on_line = function(line: string) table.insert(out, line) end,
        on_exit = function(code: number)
            if code ~= 0 then return end
            local ok, data = pcall(g.parse_json, table.concat(out, "\n"))
            if ok and type(data) == "table" then catalogue.value = data end
        end,
    }
end

function M.catalogue(): { any } return catalogue.value end
function M.enabled(): { string } return config.get("theme.templates", { "niri" }) end
function M.is_on(id: string): boolean return table.find(M.enabled(), id) ~= nil end

function M.set_on(id: string, on: boolean)
    if on == g.untracked(function() return M.is_on(id) end) then return end
    g.process {
        command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "looks", "template", id,
            if on then "true" else "false" },
    }
end

return M
