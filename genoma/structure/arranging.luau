--!strict
-- Placing the organisms (structure/Arranging.qml at 2cafc17).
--
-- At rest an organism takes no input, so it is moved in a mode of its own:
-- every organism surface comes up above the windows, takes the pointer, and
-- lets its organisms be dragged; leaving puts them back under the windows
-- and writes where they now are. What is edited is a working copy of the
-- list, written once, on leaving.
--
-- The grid's module is one unit of a template and the gap beside it, and
-- the wheel divides it into 1, 2, 4 or 8 squares: every organism's edges
-- land on the lines (Akusen, 2026-10-07). The wheel changes how finely they
-- are placed, never how large they are.
local g = require("@genoma")
local config = require("core/config")

local M = {}

M.divisions = { 1, 2, 4, 8 }

local active = g.signal(false)
local working = g.signal({} :: { any })
local grid = g.signal(2)

function M.active(): boolean return active.value end
function M.working(): { any } return working.value end
function M.grid(): number return grid.value end

local function stored_grid(): number
    local wanted = config.get("arrange.grid", 2)
    return if table.find(M.divisions, wanted) then wanted else 2
end

function M.finer(steps: number)
    local at = table.find(M.divisions, g.untracked(function() return grid.value end)) or 2
    grid.value = M.divisions[math.clamp(at + steps, 1, #M.divisions)]
end

local function new_id(): string
    return string.format("%x%04x", os.time(), math.random(0, 0xffff))
end
-- Every block written from here carries an `id`, so a surface can tell one
-- organism from another when the list changes around it.
local function named(list: { any }): { any }
    for _, entry in list do
        if type(entry) == "table" and (entry.id == nil or entry.id == "") then entry.id = new_id() end
    end
    return list
end

function M.start(from: { any }?)
    if g.untracked(function() return active.value end) then return end
    g.batch(function()
        working.value = named(config.copy_list(from or config.get("organisms", {})))
        grid.value = stored_grid()
        active.value = true
    end)
end

function M.finish()
    if not g.untracked(function() return active.value end) then return end
    local pairs = {}
    local now = g.untracked(function() return working.value end)
    if g.to_json(now) ~= g.to_json(config.get("organisms", {})) then
        table.insert(pairs, { "organisms", named(config.copy_list(now)) })
    end
    local wanted = g.untracked(function() return grid.value end)
    if wanted ~= stored_grid() then table.insert(pairs, { "arrange.grid", wanted }) end
    if #pairs > 0 then config.set_many(pairs) end
    active.value = false
end

function M.toggle()
    if g.untracked(function() return active.value end) then M.finish() else M.start() end
end

-- An organism dropped: the grid point its corner landed on, in modules from
-- the grid's corner, on the screen it now belongs to. One that was on every
-- screen stays on every screen.
function M.place(id: string, monitor: string, col: number, row: number)
    local next = config.copy_list(g.untracked(function() return working.value end))
    for _, entry in next do
        if entry.id == id then
            entry.col = math.round(col * 1000) / 1000
            entry.row = math.round(row * 1000) / 1000
            entry.x = nil
            entry.y = nil
            if monitor ~= "" and entry.monitor ~= "all" and entry.monitor ~= "*" then entry.monitor = monitor end
        end
    end
    working.value = next
end

return M
