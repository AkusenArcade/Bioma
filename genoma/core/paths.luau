--!strict
-- Where Bioma's own files are, from this directory: the scripts and the
-- configuration it shares with Bioma on Quickshell (Quickshell.shellPath).
local g = require("@genoma")

local M = {}

-- The repository, the directory above genoma/.
M.root = string.gsub(g.dir, "/genoma/?$", "")

function M.script(name: string): string return M.root .. "/scripts/" .. name end

return M
