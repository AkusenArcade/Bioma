--!strict
-- What a new bind can spawn, for every compositor's keybinds: an
-- application as its Exec without field codes, inside the terminal when it
-- asks for one, as words. The terminal is asked once, the first time a
-- picker opens.
local g = require("@genoma")
local apps = require("core/apps")
local paths = require("core/paths")

local M = {}

-- The default terminal, as Mod+T opens it (scripts/terminal: the command
-- after it as it is): a bind follows the choice in Settings → Apps, made
-- before it or after.
local terminal = g.signal({ paths.script("terminal") } :: { string })
function M.ask() end

-- Nil when there is nothing to run.
function M.of(entry: any): { name: string, args: { string } }?
    local words = apps.command_of(entry)
    if #words == 0 then return nil end
    if entry.terminal then
        local t = terminal.value
        if #t == 0 then return nil end
        local out = table.clone(t)
        for _, w in words do table.insert(out, w) end
        words = out
    end
    return { name = "spawn", args = words }
end

-- The words as one shell command line, each quoted only when it needs to
-- be: Hyprland and Umbriel spawn a string through the shell.
function M.command_line(words: { string }): string
    local out = {}
    for _, w in words do
        if w ~= "" and string.match(w, "^[%w%%%+,%-%./:=@_]+$") then
            table.insert(out, w)
        else
            table.insert(out, "'" .. string.gsub(w, "'", "'\\''") .. "'")
        end
    end
    return table.concat(out, " ")
end

return M
