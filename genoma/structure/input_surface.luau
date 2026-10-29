--!strict
-- The sheet over every other monitor while a cell is open
-- (structure/InputSurface.qml). The membrane holding the open cell catches
-- on its own output; on the others this does, so a press anywhere closes
-- the cell, and Escape reaches it wherever the keyboard is.
--
-- It catches everything on its output except what the shell's other
-- surfaces there take: Genoma cuts those out of a catching surface's input,
-- so a press on another membrane's cell still reaches that cell.
local g = require("@genoma")
local focus = require("structure/focus")

local M = {}

function M.node(output: string, size: { width: number, height: number }): any
    local function catching(): boolean
        return focus.any_open() and focus.output() ~= output
    end
    return g.box {
        width = size.width,
        height = size.height,
        g.box {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            present = catching,
            catch = catching,
            -- The press is the moment the attention moved: the cell closes
            -- then, not on release.
            on_press = function() focus.dismiss() end,
            on_key = function(name: string) focus.key(name) end,
        },
    }
end

return M
