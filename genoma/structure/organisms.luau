--!strict
-- The organisms: the desktop's own furniture (structure/OrganismSurface.qml,
-- structure/Organism.qml and organisms/Organisms.qml at 2cafc17). See
-- docs/design/ORGANISMS.md.
--
-- One surface per monitor on the Bottom layer, above the wallpaper and
-- under every window, reserving nothing and taking no input: a click meant
-- for the desktop is never stolen. They live in the free area, the screen
-- less what the membranes hold, measured to the line the windows begin on.
--
-- An organism is not a cell: it is there because it was put there to be
-- looked at, hangs from nothing, and is born in place by growing from its
-- own centre. Its size is its template, so many units of the grid across
-- and down; it sits on the grid at a point written as `col` and `row`.
--
-- Bioma on Genoma draws the ones marked `"runtime": "genoma"`; Bioma on
-- Quickshell skips them (genoma/PORT.md).
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local performance = require("core/performance")
local theme = require("core/theme")
local runtime = require("core/runtime")
local monitors = require("services/monitors")
local niri = require("services/niri")
local arranging = require("structure/arranging")

local M = {}

-- What an organism is called when it is spoken about, and its template:
-- one size per kind, so they fall into tidy clusters (Akusen, 2026-10-07).
M.kinds = {
    clock = { name = "Clock", template = { 2, 1 } },
    media = { name = "Media", template = { 2, 2 } },
    vitals = { name = "Vitals", template = { 2, 1 } },
    calendar = { name = "Calendar", template = { 2, 2 } },
    weather = { name = "Weather", template = { 2, 1 } },
    note = { name = "Note", template = { 2, 2 } },
    lava = { name = "Lava lamp", template = { 1, 2 } },
    cytoplasm = { name = "Cytoplasm", template = { 2, 1 } },
    rings = { name = "Growth rings", template = { 2, 2 } },
    osmosis = { name = "Osmosis", template = { 1, 2 } },
    photoperiod = { name = "Photoperiod", template = { 2, 1 } },
    vacuole = { name = "Vacuole", template = { 2, 2 } },
    sediment = { name = "Sediment", template = { 2, 2 } },
    nucleus = { name = "Nucleus", template = { 2, 1 } },
    adipose = { name = "Adipose", template = { 2, 1 } },
    agenda = { name = "Agenda", template = { 2, 2 } },
}

function M.name_of(kind: string): string
    local k = M.kinds[kind]
    return if k then k.name else kind
end

-- The template of one block. Where an organism has an option for its shape,
-- the option chooses among templates: a note one, two or three units tall,
-- the vitals a row or a square, and a row of four vitals a unit wider.
function M.template(entry: any): (number, number)
    local kind = entry.type or ""
    if kind == "note" then
        return 2, if entry.height == "short" then 1 elseif entry.height == "tall" then 3 else 2
    end
    if kind == "vitals" then
        if entry.layout == "square" then return 2, 2 end
        local system = require("services/system_monitor")
        local domains = 2 + (if system.gpu_present() then 1 else 0) + (if system.has_battery() then 1 else 0)
        return if domains > 3 then 3 else 2, 1
    end
    local k = M.kinds[kind]
    if k then return k.template[1], k.template[2] end
    return 1, 1
end

-- An option of the first cell of `kind` anywhere in the layout: an organism
-- that shares a domain with a cell speaks the way that cell was told to.
function M.cell_option(kind: string, key: string, fallback: any): any
    local function look(cells: { any }?): any
        for _, cell in cells or {} do
            if cell.type == kind and cell.options and cell.options[key] ~= nil then return cell.options[key] end
        end
        return nil
    end
    for _, membrane in config.get("membranes", {}) do
        for _, tissue in membrane.tissues or {} do
            local v = look(tissue.cells)
            if v ~= nil then return v end
        end
    end
    for _, tissue in config.get("floating", {}) do
        local v = look(tissue.cells)
        if v ~= nil then return v end
    end
    return fallback
end

-- The organism type for a kind: `organisms/<kind>.luau`, or nil while it
-- is not ported yet.
local types: { [string]: any } = {}
function M.type_of(kind: string): any
    if types[kind] == nil then
        local ok, module = pcall(require, "organisms/" .. kind)
        types[kind] = if ok then module else false
        if not ok and not string.find(tostring(module), "No such file") then
            print("Bioma: organism " .. kind .. " failed to load — " .. tostring(module))
        end
    end
    return types[kind] or nil
end

-- The ones this runtime draws.
function M.list(): { any }
    local out = {}
    for i, entry in config.get("organisms", {}) do
        if type(entry) == "table" and runtime.ours(entry) then table.insert(out, { index = i, entry = entry }) end
    end
    return out
end
function M.any(): boolean
    for _, entry in config.get("organisms", {}) do
        if type(entry) == "table" and runtime.ours(entry) then return true end
    end
    return false
end

local function belongs(entry: any, output: string): boolean
    local monitor = entry.monitor or "primary"
    if monitor == "all" or monitor == "*" then return true end
    if monitor == "primary" then return output == monitors.primary() end
    return output == monitor
end
M.belongs = belongs

-- ---- The free area, and the grid ----------------------------------------------------

-- The membranes' density on this screen, else any, else normal.
local function claims(block: any, output: string): boolean
    if block.monitor == output then return true end
    return block.monitor == "primary" and monitors.primary() == output
end
local function strip_metrics(output: string): any
    local any = nil
    for _, block in config.get("membranes", {}) do
        if claims(block, output) then return metrics_mod.step(block.scale or "normal") end
        any = any or block.scale
    end
    return metrics_mod.step(any or "normal")
end
M.strip_metrics = strip_metrics

-- The distance from `side` of the screen to the line the windows begin on
-- (Strips.windowLine): a membrane there answers with its strip and niri's
-- gap; a top or bottom edge with none still holds the strip one would take.
local function window_line(output: string, side: string): number
    local base = strip_metrics(output)
    if side == "left" or side == "right" then
        for _, block in config.get("membranes", {}) do
            if claims(block, output) and block.edge == side then
                local s = metrics_mod.step(block.scale or "normal")
                return s.margin_edge + s.cell_height + s.tissue_padding * 2 + niri.window_gap() + niri.strut_for(side)
            end
        end
        return base.margin_edge
    end
    local s = base
    for _, block in config.get("membranes", {}) do
        if claims(block, output) and block.edge == side then s = metrics_mod.step(block.scale or "normal") end
    end
    return s.margin_edge + s.cell_height + s.tissue_padding * 2 + niri.window_gap() + niri.strut_for(side)
end

M.divisions = { 1, 2, 4, 8 }

-- `size` is the output's { width, height }. Returns the place: free area,
-- grid, and the arithmetic a surface and an organism share.
function M.place(output: string, size: { width: number, height: number }, grid: () -> number): any
    local p = {}
    function p.metrics(): any return strip_metrics(output) end
    function p.free(): (number, number, number, number)
        local l, r = window_line(output, "left"), window_line(output, "right")
        local t, b = window_line(output, "top"), window_line(output, "bottom")
        return l, t, math.max(0, size.width - l - r), math.max(0, size.height - t - b)
    end
    -- One module is a template's unit and the gap beside it, at the
    -- membranes' step; the wheel divides it into squares.
    function p.module(): number local m = p.metrics() return m.organism_unit + m.gap end
    function p.square(): number return p.module() / grid() end
    function p.finest(): number return p.module() / M.divisions[#M.divisions] end
    -- The free area to the finest square, what is left over shared on both
    -- sides: every division counts from the same corner.
    function p.grid(): (number, number, number, number)
        local fx, fy, fw, fh = p.free()
        local finest = p.finest()
        local w = math.floor(fw / finest + 1e-6) * finest
        local h = math.floor(fh / finest + 1e-6) * finest
        return fx + (fw - w) / 2, fy + (fh - h) / 2, math.max(0, w), math.max(0, h)
    end
    -- Where something covering w × h lands when its corner is wanted at
    -- (left, top): the nearest line of the grid as divided now, wholly
    -- inside it. In modules from the grid's corner.
    function p.point(w: number, h: number, left: number, top: number): (number, number)
        local gx, gy, gw, gh = p.grid()
        local module, square = p.module(), p.square()
        local function axis(start: number, extent: number, s: number, wanted: number): number
            local room = extent - s
            if room < 0 then return room / 2 / module end
            local most = math.floor(room / square + 1e-6)
            local at = math.clamp(math.round((wanted - start) / square), 0, most)
            return at * square / module
        end
        return axis(gx, gw, w, left), axis(gy, gh, h, top)
    end
    -- A point as written, held inside the grid as it is now but not moved
    -- onto the present division.
    function p.kept(w: number, h: number, col: number, row: number): (number, number)
        local _, _, gw, gh = p.grid()
        local module, finest = p.module(), p.finest()
        local function axis(extent: number, s: number, at: number): number
            local room = extent - s
            if room < 0 then return room / 2 / module end
            local most = math.floor(room / finest + 1e-6) * finest / module
            return math.clamp(at, 0, most)
        end
        return axis(gw, w, tonumber(col) or 0), axis(gh, h, tonumber(row) or 0)
    end
    function p.corner(col: number, row: number): (number, number)
        local gx, gy = p.grid()
        return gx + col * p.module(), gy + row * p.module()
    end

    -- ---- No two in one place ----
    --
    -- Organisms never overlap (Akusen, 2026-11-02): what each covers on the
    -- grid (its panel and half a gap round it) is its own. Every organism of
    -- the screen counts, whichever runtime draws it.
    function p.cover_of(entry: any): (number, number, number, number)
        local m = if entry.size then metrics_mod.step(entry.size) else p.metrics()
        local c, r = M.template(entry)
        local w = c * m.organism_unit + (c - 1) * m.gap + p.metrics().gap
        local h = r * m.organism_unit + (r - 1) * m.gap + p.metrics().gap
        local col, row
        if entry.col ~= nil and entry.row ~= nil then
            col, row = p.kept(w, h, entry.col, entry.row)
        else
            local fx, fy, fw, fh = p.free()
            col, row = p.point(w, h, fx + (entry.x or 0.5) * fw - w / 2, fy + (entry.y or 0.5) * fh - h / 2)
        end
        return col, row, w, h
    end
    -- What the others on this screen cover, in pixels.
    function p.others(list: { any }, except: any): { any }
        local out = {}
        for _, entry in list do
            if type(entry) == "table" and entry.id ~= except and belongs(entry, output) then
                local col, row, w, h = p.cover_of(entry)
                local x, y = p.corner(col, row)
                table.insert(out, { x = x, y = y, w = w, h = h })
            end
        end
        return out
    end
    -- The grid point nearest (col, row) where w × h overlaps none of
    -- `others`: the point itself when it is free.
    function p.free_point(w: number, h: number, col: number, row: number, others: { any }): (number, number)
        local function hits(c: number, r: number): boolean
            local x, y = p.corner(c, r)
            for _, o in others do
                if x < o.x + o.w - 0.5 and o.x < x + w - 0.5 and y < o.y + o.h - 0.5 and o.y < y + h - 0.5 then return true end
            end
            return false
        end
        if not hits(col, row) then return col, row end
        local square = p.square()
        local x0, y0 = p.corner(col, row)
        for radius = 1, 48 do
            local best, best_distance = nil, math.huge
            for dy = -radius, radius do
                for dx = -radius, radius do
                    if math.max(math.abs(dx), math.abs(dy)) == radius then
                        local c, r = p.point(w, h, x0 + dx * square, y0 + dy * square)
                        local cx, cy = p.corner(c, r)
                        local distance = (cx - x0) ^ 2 + (cy - y0) ^ 2
                        if distance < best_distance and not hits(c, r) then
                            best, best_distance = { c, r }, distance
                        end
                    end
                end
            end
            if best then return best[1], best[2] end
        end
        return col, row
    end
    return p
end

-- ---- One organism ----------------------------------------------------------------------

local CLEAR = "#00000000"

-- `a`: entry() (its block), place (the surface's), output, arranging().
-- Returns the node, and the organism's handle (centre, size, present).
function M.organism(a: { [string]: any }): (any, any)
    local entry = a.entry
    local place = a.place
    local kind = g.untracked(entry).type or ""
    local organism_type = M.type_of(kind)
    local function metrics(): any
        local e = entry()
        return if e.size then metrics_mod.step(e.size) else place.metrics()
    end
    local function f(): number return metrics().factor end
    local function cols(): number local c = M.template(entry()) return c end
    local function rows(): number local _, r = M.template(entry()) return r end
    local function unit(): number return metrics().organism_unit end
    local function span(): number return metrics().gap end
    local function target_width(): number return cols() * unit() + (cols() - 1) * span() end
    local function target_height(): number return rows() * unit() + (rows() - 1) * span() end
    -- What it covers on the grid: the panel and half the grid's gap round it.
    local function grid_gap(): number return place.metrics().gap end
    local function cover_width(): number return target_width() + grid_gap() end
    local function cover_height(): number return target_height() + grid_gap() end
    local function grid_point(): (number, number)
        local e = entry()
        if e.col ~= nil and e.row ~= nil then return place.kept(cover_width(), cover_height(), e.col, e.row) end
        -- One with no point yet (just added) goes to the nearest place
        -- nobody covers: organisms never overlap.
        local fx, fy, fw, fh = place.free()
        local col, row = place.point(cover_width(), cover_height(),
            fx + (e.x or 0.5) * fw - cover_width() / 2, fy + (e.y or 0.5) * fh - cover_height() / 2)
        local list = if arranging.active() then arranging.working() else config.get("organisms", {})
        return place.free_point(cover_width(), cover_height(), col, row, place.others(list, e.id))
    end
    local function rest(): (number, number)
        local col, row = grid_point()
        local x, y = place.corner(col, row)
        return x + cover_width() / 2, y + cover_height() / 2
    end

    -- Lifted: drawn on the arranging surface, there at once, carried by the
    -- hand. Where it was let go it slides onto its squares.
    local lifted = a.lifted == true
    local held = g.signal(nil :: { x: number, y: number }?)
    local function centre(): (number, number)
        local h = held.value
        if h then return h.x, h.y end
        return rest()
    end
    local body: any = nil
    local bleeds = false
    local inner_padding = function(): number return if bleeds then 0 else 20 * f() end
    if organism_type then
        body = organism_type.new {
            entry = entry,
            metrics = metrics,
            output = a.output,
            arranging = a.arranging,
            width = function() return target_width() - inner_padding() * 2 end,
            height = function() return target_height() - inner_padding() * 2 end,
        }
        bleeds = body.bleeds == true
    end

    -- Absent, it is still placed: while arranging it comes up in its blank
    -- form, so the hand has something to take.
    local function present(): boolean
        if not body then return false end
        if arranging.retiring(entry().id) then return false end
        if a.arranging() then return true end
        return if body.present then body.present() else true
    end
    -- Still drawn while it leaves: content first, then the shape into its
    -- own centre.
    local drawn = g.signal(false)
    local going: any = nil
    g.watch(present, function(on: boolean)
        if going then going:stop() end
        going = nil
        if on then
            drawn.value = true
        else
            going = g.after(require("core/timing").seconds.content_fade + require("core/timing").seconds.close, function()
                drawn.value = false
            end)
        end
    end)
    -- Born growing: absent for its first turn.
    local born = g.signal(lifted)
    if not lifted then g.after(0, function() born.value = true end) end
    local function shown(): boolean return born.value and present() end
    local function width(): number return if shown() then target_width() else 0 end
    local function height(): number return if shown() then target_height() else 0 end
    local function growing(): string
        if lifted then return if held.value then "instant" else "reflow" end
        return if shown() then "open_flat" else "retract"
    end

    local handle = {}
    function handle.centre(): (number, number) return rest() end
    function handle.size(): (number, number) return target_width(), target_height() end
    function handle.cover(): (number, number) return cover_width(), cover_height() end
    function handle.present(): boolean return drawn.value end
    function handle.grid_point(): (number, number) return grid_point() end

    local node = g.capsule {
        name = "organism",
        role = "group",
        overlay = true,
        attach = "corner",
        present = function() return drawn.value end,
        offset_x = function() local x = centre() return x - width() / 2 end,
        offset_y = function() local _, y = centre() return y - height() / 2 end,
        width = width,
        height = height,
        radius = function() return metrics().radius_panel end,
        blur = performance.blurred,
        fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
        rim_top = theme.rim,
        rim_bottom = theme.line,
        transition = { width = growing, height = growing, offset_x = growing, offset_y = growing },
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = inner_padding,
            offset_y = inner_padding,
            width = function() return target_width() - inner_padding() * 2 end,
            height = function() return target_height() - inner_padding() * 2 end,
            opacity = function() return if shown() then 1 else 0 end,
            transition = { opacity = function()
                if lifted then return "instant" end
                return if shown() then "organism_content" else "content_leave"
            end },
            if body then body.node() else g.box {},
        },
    }
    if not lifted then return node, handle end

    -- ---- Being placed ----
    -- Outlined a little outside the panel, dashed, because it marks a thing
    -- that can move; brighter under the pointer and in the hand. Its name and
    -- template, and where it is on the grid, on a plate in its corner.
    local hovered = g.signal(false)
    local grab: { x: number, y: number }? = nil
    local function ring(): number return 8 * f() end
    local function lit(): boolean return hovered.value or held.value ~= nil end
    local function counted(modules: number): string
        local squares = math.round(modules * arranging.grid() * 1000) / 1000
        return if squares == math.floor(squares) then tostring(squares + 1) else string.format("%.1f", squares + 1)
    end
    -- Where it would land: the nearest point no other organism covers.
    local function landing(): (number, number)
        local h = held.value
        if not h then return grid_point() end
        local cw, ch = cover_width(), cover_height()
        local col, row = place.point(cw, ch, h.x - cw / 2, h.y - ch / 2)
        return place.free_point(cw, ch, col, row, place.others(arranging.working(), entry().id))
    end
    handle.landing = landing
    handle.held = function() return held.value ~= nil end
    local plate_inset = function(): number return 10 * f() end
    return g.box {
        overlay = true,
        attach = "corner",
        -- Where it will land: its own shape, lit faintly on the squares it
        -- will cover.
        g.capsule {
            overlay = true,
            attach = "corner",
            present = function() return held.value ~= nil end,
            offset_x = function() local col, row = landing() local x = place.corner(col, row) return x + grid_gap() / 2 end,
            offset_y = function() local col, row = landing() local _, y = place.corner(col, row) return y + grid_gap() / 2 end,
            width = target_width,
            height = target_height,
            radius = function() return metrics().radius_panel end,
            fill = function() return colour.alpha(theme.primary(), 0.14) end,
            rim_top = function() return colour.alpha(theme.primary(), 0.55) end,
            rim_bottom = function() return colour.alpha(theme.primary(), 0.55) end,
            crisp = true,
        },
        node,
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() local x = centre() return x - target_width() / 2 - ring() end,
            offset_y = function() local _, y = centre() return y - target_height() / 2 - ring() end,
            width = function() return target_width() + ring() * 2 end,
            height = function() return target_height() + ring() * 2 end,
            radius = function() return metrics().radius_panel + ring() end,
            rim_top = function() return if lit() then theme.primary() else colour.alpha(theme.primary(), 0.55) end,
            rim_bottom = function() return if lit() then theme.primary() else colour.alpha(theme.primary(), 0.55) end,
            dash = 8,
            dash_gap = 6,
            transition = { offset_x = growing, offset_y = growing },
        },
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() local x = centre() return x - target_width() / 2 + plate_inset() end,
            offset_y = function() local _, y = centre() return y - target_height() / 2 + plate_inset() end,
            padding_x = plate_inset,
            padding_y = function() return plate_inset() * 0.7 end,
            direction = "column",
            align = "start",
            gap = function() return 3 * f() end,
            radius = function() return metrics_mod.radius_for(40 * f(), metrics()) end,
            fill = function() return colour.alpha(theme.background(), 0.88) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            transition = { offset_x = growing, offset_y = growing },
            g.text {
                text = function()
                    local c, r = M.template(entry())
                    return string.upper(M.name_of(kind)) .. " · " .. c .. " × " .. r
                end,
                color = theme.primary,
                font = require("core/typography").technical,
                size = function() return metrics().font_meta end,
                weight = require("core/typography").weight_label,
                tracking = require("core/typography").label_tracking,
                tabular = true,
            },
            g.text {
                text = function()
                    local col, row = landing()
                    return "COL " .. counted(col) .. " · ROW " .. counted(row)
                end,
                color = theme.text_muted,
                font = require("core/typography").technical,
                size = function() return metrics().font_meta end,
                weight = require("core/typography").weight_label,
                tracking = require("core/typography").label_tracking,
                tabular = true,
            },
        },
        -- The hand: where the press lands inside the panel is kept, so the
        -- panel does not jump to centre itself under the pointer.
        g.box {
            role = "button",
            name = "Organism",
            overlay = true,
            attach = "corner",
            cursor = function() return if held.value then "grabbing" else "grab" end,
            offset_x = function() local x = centre() return x - target_width() / 2 end,
            offset_y = function() local _, y = centre() return y - target_height() / 2 end,
            width = target_width,
            height = target_height,
            on_hover = function(on: boolean) hovered.value = on end,
            on_press = function(button: number, x: number, y: number)
                if button ~= 272 then return end
                grab = { x = x - g.untracked(target_width) / 2, y = y - g.untracked(target_height) / 2 }
            end,
            on_drag = function(x: number, y: number)
                if not grab then return end
                -- g.untracked hands back one value: the two go through a table.
                local c = g.untracked(function() return table.pack(centre()) end)
                local cx, cy = c[1], c[2]
                local left = cx - g.untracked(target_width) / 2
                local top = cy - g.untracked(target_height) / 2
                held.value = { x = left + x - grab.x, y = top + y - grab.y }
            end,
            on_release = function()
                grab = nil
                local h = g.untracked(function() return held.value end)
                if not h then return end
                a.drop(h.x, h.y, handle)
                held.value = nil
            end,
            on_click = function() end,
        },
    }, handle
end

-- ---- The surfaces ----------------------------------------------------------------------

-- The organisms of one output, read from the list being edited while the
-- mode lasts.
local function source(): { any }
    return if arranging.active() then arranging.working() else config.get("organisms", {})
end
local function rows_for(output: string, list: () -> { any }): () -> { any }
    return function()
        local out = {}
        for i, entry in list() do
            if type(entry) == "table" and runtime.ours(entry) and belongs(entry, output) then
                table.insert(out, { index = i, entry = entry })
            end
        end
        return out
    end
end
local function key_of(item: any): string
    return if item.entry.id then tostring(item.entry.id) else "@" .. item.index
end
local function entry_getter(first: any, list: () -> { any }): () -> any
    local id = first.entry.id
    return function()
        local l = list()
        if id then
            for _, e in l do if e.id == id then return e end end
        end
        return l[first.index] or first.entry
    end
end

function M.grid(): number return arranging.grid() end

-- At rest, on the Bottom layer: the organisms under the windows. While they
-- are being placed they are lifted onto the arranging surface instead.
function M.surface(output: string, size: { width: number, height: number }): any
    local place = M.place(output, size, M.grid)
    local function config_list(): { any } return config.get("organisms", {}) end
    return g.box {
        width = size.width,
        height = size.height,
        g.each {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            opacity = function() return if arranging.active() then 0 else 1 end,
            -- Kept by each block's `id`, not by its place: taken from the
            -- middle of the list, one must not hand its node to the next.
            items = rows_for(output, config_list),
            key = key_of,
            row = function(item: () -> any)
                local node = M.organism {
                    entry = entry_getter(g.untracked(item), config_list),
                    place = place,
                    output = output,
                    arranging = function() return false end,
                }
                return node
            end,
        },
    }
end

-- While they are placed: above the windows, the windows dimmed behind, the
-- free area dashed and the grid drawn; the organisms lifted and carried.
-- The wheel makes the grid finer or coarser; Done or Escape leaves.
function M.arrange_surface(output: string, size: { width: number, height: number }): any
    local place = M.place(output, size, M.grid)
    local typography = require("core/typography")
    local choice = require("components/choice")
    local function f(): number return place.metrics().factor end
    local function hairline(): number return 1 end
    -- Let go: the screen under the pointer is where it now lives, written
    -- as that screen's grid point nearest to where it was let go.
    local function drop(cx: number, cy: number, handle: any)
        local entry_id = handle.id
        if not entry_id then return end
        local target, tx, ty = output, cx, cy
        if cx < 0 or cy < 0 or cx > size.width or cy > size.height then
            local here = monitors.output_of(output)
            if here then
                local gx, gy = here.x + cx, here.y + cy
                for _, o in monitors.outputs() do
                    if gx >= o.x and gx < o.x + o.width and gy >= o.y and gy < o.y + o.height then
                        target, tx, ty = o.name, gx - o.x, gy - o.y
                    end
                end
            end
        end
        local cw, ch = handle.cover()
        local p = if target == output then place else M.place(target, (function()
            local o = monitors.output_of(target)
            return { width = if o then o.width else size.width, height = if o then o.height else size.height }
        end)(), M.grid)
        local col, row = p.point(cw, ch, tx - cw / 2, ty - ch / 2)
        col, row = p.free_point(cw, ch, col, row, p.others(g.untracked(arranging.working), entry_id))
        arranging.place(entry_id, target, col, row)
    end
    local function lines(axis: string): any
        return g.each {
            overlay = true,
            attach = "corner",
            items = function()
                local gx, gy, gw, gh = place.grid()
                local extent = if axis == "x" then gw else gh
                local square = place.square()
                local out = {}
                for i = 0, math.floor(extent / square + 1e-6) do table.insert(out, i) end
                return out
            end,
            key = function(i: number) return axis .. i end,
            row = function(i: () -> number)
                return g.capsule {
                    overlay = true,
                    attach = "corner",
                    crisp = true,
                    offset_x = function()
                        local gx = place.grid()
                        return if axis == "x" then math.round(gx + i() * place.square()) else gx
                    end,
                    offset_y = function()
                        local _, gy = place.grid()
                        return if axis == "y" then math.round(gy + i() * place.square()) else gy
                    end,
                    width = function() local _, _, gw = place.grid() return if axis == "x" then hairline() else gw end,
                    height = function() local _, _, _, gh = place.grid() return if axis == "y" then hairline() else gh end,
                    fill = function()
                        return colour.alpha(theme.primary(), if i() % arranging.grid() == 0 then 0.22 else 0.08)
                    end,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                }
            end,
        }
    end
    return g.box {
        width = size.width,
        height = size.height,
        present = arranging.active,
        catch = arranging.active,
        on_key = function(name: string)
            if name == "Escape" then arranging.finish() end
        end,
        on_wheel = function(_: number, dy: number)
            if dy ~= 0 then arranging.finer(if dy < 0 then -1 else 1) end
        end,
        on_click = function() end,
        -- The windows behind, dimmed: what is being worked on now is the
        -- desktop.
        g.capsule {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            radius = 0,
            fill = function() return colour.alpha("#000000", 0.55) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
        },
        -- Where they may go: the free area, as a place rather than a content.
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() local x = place.free() return x end,
            offset_y = function() local _, y = place.free() return y end,
            width = function() local _, _, w = place.free() return w end,
            height = function() local _, _, _, h = place.free() return h end,
            radius = function() return place.metrics().radius_panel end,
            rim_top = theme.line,
            rim_bottom = theme.line,
            dash = 10,
            dash_gap = 8,
        },
        lines("x"),
        lines("y"),
        g.each {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            items = rows_for(output, arranging.working),
            key = key_of,
            row = function(item: () -> any)
                local first = g.untracked(item)
                local node, handle = M.organism {
                    entry = entry_getter(first, arranging.working),
                    place = place,
                    output = output,
                    arranging = function() return true end,
                    lifted = true,
                    drop = function(x: number, y: number, h: any) drop(x, y, h) end,
                }
                handle.id = first.entry.id
                return node
            end,
        },
        -- Leaving: at the top of the free area, where it covers none of the
        -- places an organism is likely to be put.
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = function() local x, _, w = place.free() return x end,
            offset_y = function() local _, y = place.free() return y + 16 * f() end,
            width = function() local _, _, w = place.free() return w end,
            direction = "column",
            align = "center",
            gap = function() return 8 * f() end,
            choice.new { metrics = place.metrics, kind = "primary", label = "Done", on_click = arranging.finish },
            g.text {
                text = function()
                    local gr = arranging.grid()
                    return "GRID " .. (if gr == 1 then "1" else "1/" .. gr) .. " · SCROLL TO CHANGE"
                end,
                color = theme.text_muted,
                font = typography.technical,
                size = function() return place.metrics().font_meta end,
                weight = typography.weight_label,
                tracking = typography.label_tracking,
            },
        },
    }
end

return M
