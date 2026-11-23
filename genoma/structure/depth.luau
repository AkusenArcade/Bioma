--!strict
-- Depth (Settings → Appearance → DEPTH, off unless chosen): where the
-- pointer is over the desktop, shared by the two layers that move with
-- it. The organisms' surface takes the pointer where no window is
-- (structure/organisms.luau) and writes it here; the wallpaper
-- (structure/wallpaper.luau), on the Background layer, takes no pointer
-- of its own and reads it.
--
-- Both layers move against the pointer, the nearer the faster: the
-- organisms, floating above the wallpaper, more; the wallpaper, far
-- behind, less. Their difference is the depth (Akusen, 2026-11-18). It is
-- one desktop, not one per screen: the pointer is placed in the box of
-- every monitor, and every screen leans by the same amount at once. A
-- still hand is a still desktop; on a window, everything settles back
-- where it was put, unless ON WINDOWS is chosen too. On the shell itself
-- (a cell on a membrane at the screen's edge, an open cell) the desktop
-- holds where the pointer left it: those are other surfaces, and the
-- desktop hears only that the pointer left, not where it went (Akusen,
-- 2026-11-18: everything snapped back at the edges). And at the screen's
-- very edge, where no window reaches (niri keeps its gap): the pointer
-- that leaves there has gone to another program's strip on the edge
-- (lan-mouse's, on the left of his screen), not to a window.
--
-- On windows: no Wayland client hears the pointer over another's surface,
-- and niri 26.04 does not say where it is. What stands in for it is the
-- focused window, from niri's event stream: where it lies, on which
-- screen. With focus following the mouse that is close to the hand;
-- without it, the desktop moves when the focus does. A floating window
-- says where it is; a tiled one only its column and row (niri does not
-- tell the view's scroll), so it stands at its column's share of the
-- screen's width and its row's of the height.
local g = require("@genoma")
local config = require("core/config")
local monitors = require("services/monitors")
local niri = require("services/niri")
local arranging = require("structure/arranging")

local M = {}

-- How far each layer moves, at most, each way, logical units: negative
-- is against the pointer.
M.ORGANISMS = -16
M.WALLPAPER = -6

-- The pointer over the desktop, in the layout's logical units, and the
-- screen it is on; nil when it is on no desktop. Made for the load, not
-- for whichever binding asks first: one made inside a binding went with
-- it when it ran again, and the pointer was written into a signal nobody
-- read.
local pointer = g.lasting(function() return g.signal(nil :: { x: number, y: number, output: string, edge: boolean }?) end)

-- How near the screen's edge a pointer leaving the desktop is still at
-- the edge: inside niri's gap, where no window is, logical units.
local function edge_band(): number
    return math.max(4, niri.window_gap() / 2)
end

-- Chosen in the settings: what sizes the layers. The wallpaper is decoded
-- a little past the screen so it has room to move, and that room stays
-- while the organisms are placed: a picture sized again is a picture
-- decoded again, and the screen showed black under the grid until it was
-- (Akusen, 2026-11-23: black blinks entering and leaving the arrange mode).
function M.chosen(): boolean
    return config.get("appearance.depth", false) == true
end
-- Moving now: not while the organisms are placed, where they follow the
-- hand that carries them instead.
function M.on(): boolean
    return M.chosen() and not arranging.active()
end
function M.on_windows(): boolean
    return config.get("appearance.depth_windows", false) == true
end

-- The focused window, as a point in the layout's logical units, nil
-- without one.
local function focused_point(): { x: number, y: number }?
    local w = niri.focused_window()
    if not w then return nil end
    local ws = niri.workspaces()[w.workspace_id]
    if not ws then return nil end
    local o = nil
    for _, candidate in monitors.outputs() do
        if candidate.name == ws.output then o = candidate end
    end
    if not o then return nil end
    local layout = niri.layout_for(w.id)
    if layout and type(layout.position_in_view) == "table" and type(layout.tile_size) == "table" then
        return {
            x = o.x + layout.position_in_view[1] + layout.tile_size[1] / 2,
            y = o.y + layout.position_in_view[2] + layout.tile_size[2] / 2,
        }
    end
    if layout and layout.column then
        local columns, rows = 1, 1
        for _, other in niri.windows_on_workspace(w.workspace_id) do
            local l = niri.layout_for(other.id)
            if l and l.column then
                columns = math.max(columns, l.column)
                if l.column == layout.column then rows = math.max(rows, l.row or 1) end
            end
        end
        return {
            x = o.x + o.width * (layout.column - 0.5) / columns,
            y = o.y + o.height * ((layout.row or 1) - 0.5) / rows,
        }
    end
    return { x = o.x + o.width / 2, y = o.y + o.height / 2 }
end

-- The cells the pointer is on, by identity: while there is one, or a
-- cell is open, the pointer is on the shell.
local on_cells: { [any]: boolean } = {}
local function on_shell(): boolean
    if next(on_cells) ~= nil then return true end
    return require("structure/focus").any_open()
end

-- The pointer has left the desktop and not come back: once it is on
-- neither the desktop nor the shell, the desktop settles. Asked a moment
-- after the leaving, because the surface it went to hears it after.
local left = false
local LEAVING = 0.12
local function settle_if_gone()
    g.after(LEAVING, function()
        if left and not on_shell() then
            left = false
            pointer.value = nil
        end
    end)
end

-- An open cell closing, with the pointer off the desktop, is the shell
-- letting it go too. Watched from the first pointer on: structure/focus
-- is required late, as the cells that require this module are its.
local watching = false
local function watch_open()
    if watching then return end
    watching = true
    g.lasting(function()
        g.watch(require("structure/focus").any_open, function(open: boolean)
            if not open and left then settle_if_gone() end
        end)
    end)
end

-- The organisms' surface on `output`, as the pointer moves over its
-- desktop (`at` local to that screen) or leaves it (nil). Leaving one
-- screen counts only if the pointer is still that screen's: entering the
-- next may come first.
function M.set(output: string, at: { x: number, y: number }?)
    if at then
        for _, o in g.untracked(monitors.outputs) do
            if o.name == output then
                watch_open()
                left = false
                local band = edge_band()
                local edge = at.x < band or at.y < band or at.x > o.width - band or at.y > o.height - band
                pointer.value = { x = o.x + at.x, y = o.y + at.y, output = output, edge = edge }
                return
            end
        end
        return
    end
    local now = g.untracked(function() return pointer.value end)
    if now and now.output == output and not now.edge then
        left = true
        settle_if_gone()
    end
end

-- A cell, as the pointer comes onto it or leaves it (structure/cell.luau).
function M.cell_hovered(cell: any, on: boolean)
    on_cells[cell] = if on then true else nil
    if not on and left then settle_if_gone() end
end


-- How far a layer `amount` deep is moved along `axis` ("x" or "y"): the
-- pointer's distance from the middle of every monitor's box, -1 to 1,
-- times `amount`. The same on every screen.
function M.lean(axis: string, amount: number): number
    if not M.on() then return 0 end
    local p = pointer.value
    if not p and M.on_windows() then p = focused_point() end
    if not p then return 0 end
    local lo, hi = math.huge, -math.huge
    for _, o in monitors.outputs() do
        if axis == "x" then
            lo, hi = math.min(lo, o.x), math.max(hi, o.x + o.width)
        else
            lo, hi = math.min(lo, o.y), math.max(hi, o.y + o.height)
        end
    end
    if hi <= lo then return 0 end
    local mid, half = (lo + hi) / 2, (hi - lo) / 2
    local at = if axis == "x" then p.x else p.y
    return math.clamp((at - mid) / half, -1, 1) * amount
end

return M
