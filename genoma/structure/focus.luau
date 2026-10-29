--!strict
-- Attention (core/Focus.qml): which cell is open. One cell is open at a
-- time, so opening one closes whatever was open; a press that lands on
-- nothing of the shell closes it, and so does Escape.
--
-- The keys reach the shell on whichever surface holds the keyboard, and all
-- of them come here: the open cell is the one that hears them.
local g = require("@genoma")

local M = {}

local cells: { [number]: any } = {}
local count = 0
local open_id = g.signal(0)

local function current(): number
    return g.untracked(function() return open_id.value end)
end

-- Every cell offers itself once, and is known by the number it gets back.
function M.offer(c: any): number
    count += 1
    cells[count] = c
    return count
end

function M.any_open(): boolean return open_id.value ~= 0 end

-- The output the open cell is on, or nil.
function M.output(): string?
    local c = cells[open_id.value]
    return if c then c.output else nil
end

function M.opened(c: any)
    local was = current()
    if was ~= 0 and was ~= c.focus_id and cells[was] then
        cells[was].open.value = false
    end
    open_id.value = c.focus_id
end

function M.released(c: any)
    if current() == c.focus_id then open_id.value = 0 end
end

-- The pointer landed somewhere that belongs to nobody.
function M.dismiss()
    local c = cells[current()]
    if c then c.open.value = false end
end

-- Escape closes; the rest is the open cell's, if it wants them.
function M.key(name: string)
    if name == "Escape" then
        M.dismiss()
        return
    end
    local c = cells[current()]
    if c and c.spec.on_key then c.spec.on_key(name) end
end

return M
