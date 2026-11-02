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
local timing = require("core/timing")

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

-- A new organism, Genoma's to draw, in the middle of that screen; the mode
-- begins so it can be put where it belongs, unless `quietly` (a note,
-- which has nothing to show until it has a file).
function M.add(kind: string, monitor: string, quietly: boolean)
    local list = if g.untracked(function() return active.value end)
        then g.untracked(function() return working.value end)
        else config.get("organisms", {})
    local next = named(config.copy_list(list))
    table.insert(next, { id = new_id(), type = kind, monitor = monitor, x = 0.5, y = 0.5, runtime = "genoma" })
    if g.untracked(function() return active.value end) then
        working.value = next
        return
    end
    config.set("organisms", next)
    if not quietly then M.start(next) end
end

-- Taken away, it leaves the way everything in the shell leaves, content and
-- then shape into its own centre, and only then is the list written
-- without it. Until then it is held here, by its `id`.
local retiring = g.signal({} :: { [string]: boolean })
local gone: any = nil

function M.retiring(id: string?): boolean
    return id ~= nil and retiring.value[id] == true
end

function M.remove(index: number)
    if g.untracked(function() return active.value end) then
        local next = config.copy_list(g.untracked(function() return working.value end))
        table.remove(next, index)
        working.value = next
        return
    end
    local list = named(config.copy_list(config.get("organisms", {})))
    local entry = list[index]
    if not entry then return end
    -- Named first, so the one leaving can be told by its `id`.
    if entry.id ~= config.get("organisms", {})[index].id then config.set("organisms", list) end
    local next = table.clone(g.untracked(function() return retiring.value end))
    next[entry.id] = true
    retiring.value = next
    if gone then gone:stop() end
    gone = g.after(timing.seconds.content_fade + timing.seconds.close, function()
        local leaving = g.untracked(function() return retiring.value end)
        local kept = {}
        for _, e in config.copy_list(config.get("organisms", {})) do
            if not (type(e) == "table" and leaving[e.id]) then table.insert(kept, e) end
        end
        retiring.value = {}
        config.set("organisms", named(kept))
    end)
end

-- ---- A note's file ---------------------------------------------------------

-- Chosen with zenity, from here rather than from the settings page: the
-- picker is a window, a press on it lands outside the settings and closes
-- them, and a picker owned by the page would die with it.
local home = g.env("HOME") or ""
local picker_error = g.signal("")
local picking = false

function M.picker_error(): string return picker_error.value end

-- Written with the home as `~`, so the block reads the same on a machine
-- with another user name.
function M.set_file(index: number, path: string): { any }?
    local wanted = string.match(path, "^%s*(.-)%s*$") or ""
    if wanted == "" then return nil end
    if home ~= "" and string.sub(wanted, 1, #home + 1) == home .. "/" then
        wanted = "~" .. string.sub(wanted, #home + 1)
    end
    local next = named(config.copy_list(config.get("organisms", {})))
    if not next[index] then return nil end
    next[index].file = wanted
    config.set("organisms", next)
    return next
end

function M.choose_file(index: number)
    local list = config.get("organisms", {})
    if picking or not list[index] then return end
    local current = list[index].file or ""
    -- A note that had no file yet has never been on the desktop, so once
    -- it has one the mode begins and it can be put where it belongs.
    local place_after = current == ""
    local start = if current == "" then home .. "/"
        elseif string.sub(current, 1, 1) == "~" then home .. string.sub(current, 2)
        else current
    picking = true
    local picked = ""
    g.process {
        -- 127 is the shell's own answer for a command it cannot find, so a
        -- missing zenity is told apart from a picker that was cancelled (1).
        command = { "sh", "-c", 'command -v zenity >/dev/null || exit 127; '
            .. 'exec zenity --file-selection --title="Note" '
            .. '--file-filter="Markdown | *.md *.markdown" --file-filter="All files | *" '
            .. '--filename="$1"', "sh", start },
        on_line = function(line: string) picked = line end,
        on_exit = function(code: number)
            picking = false
            picker_error.value = if code == 127 then "zenity is not installed, so there is no file picker." else ""
            if code == 0 then
                local next = M.set_file(index, picked)
                if next and place_after then M.start(next) end
            end
        end,
    }
end

return M
