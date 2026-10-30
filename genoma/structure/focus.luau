--!strict
-- Attention (core/Focus.qml): which cell is open. One cell is open at a
-- time, so opening one closes whatever was open; a press that lands on
-- nothing of the shell closes it, and so does Escape.
--
-- The keys reach the shell on whichever surface holds the keyboard, and all
-- of them come here: the open cell is the one that hears them.
--
-- And the register a shortcut reaches: every cell answers to its name
-- (Akusen, 2026-09-23). On a membrane it opens where it is, in a floating
-- tissue it appears there, and placed nowhere on the monitor it is summoned
-- into the middle by that monitor's host.
local g = require("@genoma")
local registry = require("cells/registry")

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

-- A cell that leaves for good: a summoned one, once it has gone.
function M.withdraw(c: any)
    cells[c.focus_id] = nil
    if current() == c.focus_id then open_id.value = 0 end
end

function M.any_open(): boolean return open_id.value ~= 0 end

-- The open cell, or nil.
function M.open_cell(): any return cells[open_id.value] end

-- Whether the shell holds the keyboard: an open cell with a field to type
-- in makes its surface take it, and then no window has it.
function M.holds_keyboard(): boolean
    local c = cells[open_id.value]
    return c ~= nil and c.spec.wants_keyboard == true
end

-- A dialog of the desktop's that a cell asks for (the file chooser) is a
-- window of its own, under the cell. So the cell steps aside: it closes
-- while the dialog is up, keeping what it was doing, and opens again once
-- the dialog has answered, chosen or cancelled (Akusen, 2026-10-29: open
-- over the chooser, it covered it). `show(done)` opens the dialog and calls
-- `done` when it answers. While aside, `c.aside` is true, so the cell's
-- expansion keeps its state through the close.
function M.aside(c: any, show: (done: () -> ()) -> ())
    c.aside = true
    c.open.value = false
    show(function()
        c.aside = false
        c.open.value = true
    end)
end

-- Whether `c` holds the attention: open, or summoned with no panel to open.
function M.is(c: any): boolean return open_id.value == c.focus_id end

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

-- The pointer landed somewhere that belongs to nobody. Closing is not only
-- `open = false`: a cell whose whole content is itself never opened, and
-- leaves by no longer being asked for.
function M.dismiss()
    local c = cells[current()]
    if not c then return end
    c.open.value = false
    c.visibility.set_invoked(false)
    M.released(c)
end

-- ---- Cells that answer to a name -----------------------------------------

-- The cell of `domain` on `output` (any output when nil). The one that exists
-- only when asked for wins over one that is simply placed.
function M.cell_for(domain: string, output: string?): any
    local best, rank = nil, -1
    for _, c in cells do
        if c.domain == domain and (output == nil or c.output == output) then
            local asked = if g.untracked(c.visibility.type) == "invoked" then 2 else 1
            if asked > rank then best, rank = c, asked end
        end
    end
    return best
end

-- Where a cell with no place of its own appears: one host per monitor.
local hosts: { [string]: any } = {}

function M.offer_host(output: string, host: any) hosts[output] = host end

local function host_for(output: string?): any
    if output and hosts[output] then return hosts[output] end
    for _, h in hosts do return h end
    return nil
end

-- What a shortcut does. Asking twice puts it away: open, it closes; there
-- because it was asked for, it goes.
function M.invoke(domain: string, output: string?): boolean
    domain = registry.canonical(domain)
    local c = M.cell_for(domain, output)
    if c then
        if c.open.value or c.visibility.invoked() then
            c.open.value = false
            c.visibility.set_invoked(false)
            M.released(c)
            return true
        end
        -- Asked for, it is shown whatever its visibility says, and arriving
        -- is opening for a cell with a panel; one without claims the
        -- attention, so a press outside sends it off.
        c.visibility.set_invoked(true)
        if c.has_panel then c.open.value = true else M.opened(c) end
        return true
    end
    if registry.comes_to_pointer(domain) then return M.seek(domain, output) end
    local h = host_for(output)
    if not h then return false end
    if h.summoned() == domain then
        h.retire()
        return true
    end
    return h.summon(domain)
end

-- ---- At the pointer -------------------------------------------------------
--
-- A cell that comes to the pointer has to be summoned on the monitor the
-- pointer is on, which is not always the one the keyboard is pointed at,
-- and Wayland tells a client neither. So for a moment every monitor's input
-- surface takes input over the whole screen: niri tells a surface that
-- starts taking input under a pointer that has not moved where that pointer
-- is, and the first answer names the monitor and the point. The host there
-- summons the cell around it. No answer within `locate` — the pointer is
-- over a membrane, or a window niri keeps above the shell — and it comes up
-- in the middle of the monitor the keyboard is on.
local seeking = g.signal("")
local seeking_output: string? = nil
local seek_timer: any = nil

function M.seeking(): boolean return seeking.value ~= "" end

function M.seek(domain: string, output: string?): boolean
    -- Asked twice, it goes, from whichever monitor it came up on.
    for _, h in hosts do
        if h.summoned() == domain then
            h.retire()
            return true
        end
    end
    if next(hosts) == nil then return false end
    -- An open cell catches its whole monitor and would hide the pointer
    -- from the question; the ring is the attention now anyway.
    M.dismiss()
    seeking_output = output
    seeking.value = domain
    if seek_timer then seek_timer:stop() end
    seek_timer = g.after(require("core/timing").seconds.locate, function()
        seek_timer = nil
        M.found(seeking_output, nil, nil)
    end)
    return true
end

-- The answer, from the input surface the pointer was found over; no point
-- when it was not found.
function M.found(output: string?, x: number?, y: number?)
    local domain = g.untracked(function() return seeking.value end)
    if domain == "" then return end
    if seek_timer then
        seek_timer:stop()
        seek_timer = nil
    end
    seeking.value = ""
    local h = host_for(output)
    if h then h.summon_at(domain, x, y) end
end

function M.retire(domain: string, output: string?): boolean
    domain = registry.canonical(domain)
    local c = M.cell_for(domain, output)
    if c then
        c.open.value = false
        if g.untracked(c.visibility.type) == "invoked" then c.visibility.set_invoked(false) end
        return true
    end
    if registry.comes_to_pointer(domain) then
        for _, h in hosts do
            if h.summoned() == domain then
                h.retire()
                return true
            end
        end
        return false
    end
    local h = host_for(output)
    if h and h.summoned() == domain then
        h.retire()
        return true
    end
    return false
end

-- What a keybind file can be written against: every cell Bioma on Genoma
-- can build, placed or not.
function M.domains(): { string }
    local seen, out = {}, {}
    local function add(d: string)
        if not seen[d] and not registry.internal[d] then
            seen[d] = true
            table.insert(out, d)
        end
    end
    for _, d in registry.ported do add(d) end
    for _, c in cells do add(c.domain) end
    table.sort(out)
    return out
end

-- The open cell hears every key first, with the text it types and the
-- modifiers held; one it does not take, Escape closes: a field that is
-- being typed into lets go of the keys on Escape, and only the next Escape
-- closes the cell.
function M.key(name: string, text: string?, mods: { [string]: boolean }?)
    local c = cells[current()]
    local taken = c ~= nil and c.spec.on_key ~= nil and c.spec.on_key(name, text, mods or {}) == true
    if name == "Escape" and not taken then M.dismiss() end
end

return M
