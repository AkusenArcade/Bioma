--!strict
-- The organic launcher: the same search as the simple one
-- (cells/launcher_search.luau), drawn the way Genoma can draw it. Chosen
-- in Settings → Cells; asked for in the middle of the screen only.
--
-- It starts as the field alone, a pill. As the query finds things, the
-- results gather in clusters by kind (the application's freedesktop main
-- category, the files, the calculator's sum) and each cluster comes out of
-- the pill's edge on a thread: it travels to its place on a spring and
-- overshoots, and the thread's middle follows on a looser one, so the
-- thread whips and settles behind what it holds. A cluster that has
-- nothing left to show goes back into the pill the way it came, content
-- first.
--
-- The clusters have eight places round the pill: three above, one at each
-- side, three below. Each kind prefers its own (the sum above the field,
-- the files below it, the internet top left…), and a cluster keeps its
-- place while it stays, so typing does not move what the eye has found.
--
-- The result under the pointer, or the one the keyboard has reached, lights
-- its cluster's thread, and particles run along it from the pill to the
-- cluster. Their rate is a value, never decoration: for an application, how
-- often it has been launched from here against the most launched among the
-- results; for a file, how well it answers; a sum, fully. A result never
-- launched still sends a few, so the thread reads as carrying.
--
-- Enter launches the result reached, the best answer to begin with; the
-- arrows walk the results in reading order (the clusters above, left to
-- right, then the sides, then below), Left and Right jump between clusters,
-- Ctrl+Enter shows a file where it lives, Escape closes.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local performance = require("core/performance")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local registry = require("cells/registry")
local search = require("cells/launcher_search")
local field_mod = require("components/field")
local files = require("services/files")
local calculator = require("services/calculator")
local focus = require("structure/focus")

local CLEAR = "#00000000"
local MAX_ROWS = 4

-- The eight places, in reading order: what the arrows walk.
local SLOTS = {
    { key = "tl", col = -1, row = -1 }, { key = "tc", col = 0, row = -1 }, { key = "tr", col = 1, row = -1 },
    { key = "l", col = -1, row = 0 }, { key = "r", col = 1, row = 0 },
    { key = "bl", col = -1, row = 1 }, { key = "bc", col = 0, row = 1 }, { key = "br", col = 1, row = 1 },
}
local INDEX = {} :: { [string]: number }
for i, s in SLOTS do INDEX[s.key] = i end
-- Where each kind would rather be; then the first place free.
local PREFERRED = {
    sum = { "tc" }, files = { "bc", "bl", "br" },
    internet = { "tl", "l", "tc" }, development = { "tr", "r", "tc" },
    media = { "l", "tl", "bl" }, graphics = { "r", "tr", "br" },
    office = { "bl", "l", "bc" }, system = { "br", "r", "bc" },
    utilities = { "tc", "tl", "tr" }, games = { "l", "bl", "tl" },
    science = { "tr", "r", "br" }, other = { "bc", "br", "bl" },
} :: { [string]: { string } }
local FALLBACK = { "tc", "bc", "l", "r", "tl", "tr", "bl", "br" }

local M = {}

function M.new(cell: any): any
    local function m(): any return cell.metrics() end
    local function f(): number return m().factor end
    local function inset(): number return 10 * f() end
    local function field_height(): number return 44 * f() end
    local function inner(): number return 400 * f() end
    local function body_extent(): number return inset() * 2 + field_height() end
    -- A cluster: its width, the padding round its rows, its title and rows.
    local function cluster_width(): number return 232 * f() end
    local function pad(): number return 6 * f() end
    local function title_height(): number return 26 * f() end
    local function row_height(): number return 34 * f() end
    local function portrait(): number return 22 * f() end
    -- The ring round the row reached, drawn over the portrait's slot.
    local function ring(): number return portrait() + 6 * f() end
    -- Room for the threads: beside the pill, and above and below it.
    local function gap_x(): number return 40 * f() end
    local function gap_y(): number return 72 * f() end
    local function tallest(): number return pad() * 2 + title_height() + MAX_ROWS * row_height() end

    -- ---- What it knows -----------------------------------------------------

    local query = g.signal("")
    local hovered = g.signal("") -- the result under the pointer, by key
    local reached = g.signal("") -- the result the keyboard has reached

    local results = g.computed(function(): { any }
        local q = string.lower(string.match(query.value, "^%s*(.-)%s*$") or "")
        if q == "" then return {} end
        local wanted = search.letters_of(q)
        local out = {}
        local sum = calculator.result()
        if sum ~= "" then
            table.insert(out, { kind = "sum", group = "sum", name = sum, at = {}, icon = "accessories-calculator", strength = 1 })
        end
        local list = search.applications(wanted, 60)
        local most = 0
        for _, r in list do most = math.max(most, r.used) end
        for _, r in list do
            r.group = search.group_of(r.entry)
            r.strength = if most > 0 then r.used / most else 0
            table.insert(out, r)
        end
        local found = files.results()
        local low, high = math.huge, -math.huge
        for _, file in found do
            low = math.min(low, file.score or 0)
            high = math.max(high, file.score or 0)
        end
        for _, file in found do
            table.insert(out, {
                kind = "file", group = "files", file = file, name = file.name, at = file.at, icon = file.icon,
                strength = if high > low then ((file.score or 0) - low) / (high - low) else 1,
            })
        end
        return out
    end)
    local function searching(): boolean return files.searching() or calculator.pending() end

    -- The clusters, best first: a kind ranks by the first of its results,
    -- and shows its first few.
    local groups = g.computed(function(): { any }
        local by, order = {}, {}
        for _, r in results.value do
            local grp = by[r.group]
            if not grp then
                grp = { key = r.group, label = search.group_labels[r.group] or string.upper(r.group), items = {} }
                by[r.group] = grp
                table.insert(order, grp)
            end
            if #grp.items < MAX_ROWS then table.insert(grp.items, r) end
        end
        return order
    end)

    -- Which cluster is in which place. One that stays keeps its place;
    -- a new one takes the first of its own that is free, else any.
    -- `arriving[slot]` is how many clusters arriving with it come before it
    -- in relevance: they leave the field one after another, best first.
    local kept: { [string]: number } = {}
    local arriving: { [number]: number } = {}
    local placement = g.computed(function(): { [number]: any }
        local taken, out, placed = {}, {}, {}
        local list = groups.value
        for _, grp in list do
            local s = kept[grp.key]
            if s and not taken[s] then
                taken[s] = true
                out[s] = grp
                placed[grp.key] = s
            end
        end
        local fresh = 0
        arriving = {}
        for _, grp in list do
            if not placed[grp.key] then
                local s = nil
                for _, k in PREFERRED[grp.key] or {} do
                    if not taken[INDEX[k]] then s = INDEX[k] break end
                end
                if not s then
                    for _, k in FALLBACK do
                        if not taken[INDEX[k]] then s = INDEX[k] break end
                    end
                end
                if s then
                    taken[s] = true
                    out[s] = grp
                    placed[grp.key] = s
                    arriving[s] = fresh
                    fresh += 1
                end
            end
        end
        kept = placed
        return out
    end)

    -- The results as the arrows walk them, and where each one is.
    local walk = g.computed(function(): { any }
        local out = {}
        for i = 1, #SLOTS do
            local grp = placement.value[i]
            if grp then
                for _, r in grp.items do table.insert(out, { key = search.key_of(r), slot = i, result = r }) end
            end
        end
        return out
    end)
    local function find(key: string): any
        for _, w in walk.value do if w.key == key then return w end end
        return nil
    end
    -- The best answer, until the keyboard reaches another: the first result
    -- found, if it is shown.
    local function best(): string
        local first = results.value[1]
        if first and find(search.key_of(first)) then return search.key_of(first) end
        local w = walk.value[1]
        return if w then w.key else ""
    end
    local function chosen(): string
        local r = reached.value
        if r ~= "" and find(r) then return r end
        return best()
    end
    -- The thread that carries: the pointer's result, else the keyboard's.
    local function lit_key(): string
        local h = hovered.value
        if h ~= "" and find(h) then return h end
        return chosen()
    end
    local function lit_slot(): number
        local w = find(lit_key())
        return if w then w.slot else 0
    end

    g.watch(function() return query.value end, function(q: string)
        reached.value = ""
        files.ask(q)
        calculator.ask(q)
    end)

    local function move(delta: number)
        local list = g.untracked(function() return walk.value end)
        if #list == 0 then return end
        local now = g.untracked(chosen)
        local at = 1
        for i, w in list do if w.key == now then at = i end end
        reached.value = list[(at - 1 + delta) % #list + 1].key
    end
    -- To the first result of the cluster before or after this one.
    local function jump(delta: number)
        local list = g.untracked(function() return walk.value end)
        if #list == 0 then return end
        local now = g.untracked(chosen)
        local slots, current = {}, 0
        for _, w in list do
            if #slots == 0 or slots[#slots].slot ~= w.slot then table.insert(slots, { slot = w.slot, key = w.key }) end
            if w.key == now then current = #slots end
        end
        if current == 0 then current = 1 end
        reached.value = slots[(current - 1 + delta) % #slots + 1].key
    end

    -- ---- Doing it -------------------------------------------------------------

    local handle: any = nil
    local function dismiss()
        if handle then handle.set("") end
        query.value = ""
        focus.dismiss()
    end
    local function launch(key: string, reveal: boolean)
        local w = g.untracked(function() return find(key) end)
        if not w then return end
        search.launch(w.result, reveal)
        dismiss()
    end

    -- Closed, it forgets what was typed.
    g.watch(function() return cell.placed.value end, function(on: boolean)
        if not on and g.untracked(function() return query.value end) ~= "" then
            if handle then handle.set("") end
            query.value = ""
        end
    end)

    local function on_key(name: string, typed: string?, mods: { [string]: boolean }): boolean
        if name == "Escape" then return false end
        if name == "Down" or name == "Tab" then move(1) return true end
        if name == "Up" or name == "ISO_Left_Tab" then move(-1) return true end
        -- Left and Right belong to the field while there is a caret to move
        -- and nothing found; with clusters out they walk between them.
        if (name == "Right" or name == "Left") and #g.untracked(function() return walk.value end) > 0 and not mods.shift then
            jump(if name == "Right" then 1 else -1)
            return true
        end
        if name == "Return" or name == "KP_Enter" then
            launch(g.untracked(chosen), mods.ctrl == true)
            return true
        end
        return if handle then handle.key(name, typed, mods) else false
    end

    -- ---- The pill ---------------------------------------------------------------

    local function pill(): any
        local node, h = field_mod.new {
            text = query,
            width = function() return inner() - 6 * f() - 17 * f() - 12 * f() - 6 * f() end,
            font = typography.expressive,
            size = function() return 16 * f() end,
            placeholder = "Search",
            taking = function() return true end,
        }
        handle = h
        return g.box {
            width = inner,
            height = field_height,
            direction = "row",
            align = "center",
            padding_left = function() return 6 * f() end,
            gap = function() return 12 * f() end,
            g.icon {
                width = function() return 17 * f() end,
                height = function() return 17 * f() end,
                icon = "search",
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            },
            node,
        }
    end

    -- ---- Around it ---------------------------------------------------------------

    -- Out while the cell is placed; drawn until it has gone home.
    local drawn = g.signal(false)
    local function home(): number return timing.seconds.content_fade / 2 + timing.seconds.close end
    g.watch(function() return cell.placed.value end, function(placed: boolean)
        if placed then
            drawn.value = true
            return
        end
        g.after(home(), function()
            if not g.untracked(function() return cell.placed.value end) then drawn.value = false end
        end)
    end)

    local function pill_width(): number return cell.contracted_width() end
    local function pill_height(): number return cell.contracted_height() end
    -- The frame the clusters live in, centred on the pill.
    local function frame_width(): number return 2 * (pill_width() / 2 + gap_x() + cluster_width() + 8 * f()) end
    local function frame_height(): number return 2 * (pill_height() / 2 + gap_y() + tallest() + 8 * f()) end
    local function cx(): number return frame_width() / 2 end
    local function cy(): number return frame_height() / 2 end

    -- Where a ray from the pill's centre leaves it: a rectangle rounded by
    -- the radius the pill is drawn with, which is this spec's own. The
    -- cell's corner is its tissue's when it is declared in one (DP-1's
    -- centre tissue), and a stadium worked out from that left the threads
    -- starting inside the pill.
    local function pill_exit(ux: number, uy: number): number
        local a, b = pill_width() / 2, pill_height() / 2
        local r = math.min(metrics_mod.radius_for(body_extent(), m()), a, b)
        if math.abs(uy) > 1e-6 then
            local t = b / math.abs(uy)
            if math.abs(t * ux) <= a - r then return t end
        end
        if math.abs(ux) > 1e-6 then
            local t = a / math.abs(ux)
            if math.abs(t * uy) <= b - r then return t end
        end
        -- A corner's arc: the ray against the circle at that corner.
        local cx_, cy_ = (if ux >= 0 then 1 else -1) * (a - r), (if uy >= 0 then 1 else -1) * (b - r)
        local along = ux * cx_ + uy * cy_
        return along + math.sqrt(math.max(0, along * along - (cx_ * cx_ + cy_ * cy_) + r * r))
    end

    local function cluster(i: number): (any, any, any)
        local slot = SLOTS[i]
        -- Out once its turn in the cascade has come; in at once.
        local arrived = g.signal(false)
        g.watch(function() return placement.value[i] ~= nil end, function(placed: boolean)
            if not placed then
                arrived.value = false
                return
            end
            if g.untracked(function() return arrived.value end) then return end
            local turn = (arriving[i] or 0) * timing.seconds.cluster_stagger
            if turn <= 0 then
                arrived.value = true
                return
            end
            g.after(turn, function()
                if g.untracked(function() return placement.value[i] end) then arrived.value = true end
            end)
        end)
        local function out(): boolean return cell.placed.value and arrived.value end
        -- What it shows: the cluster placed here, or the last one while it
        -- goes home; once home, nothing, so no thread's nodes stay behind
        -- on the pill.
        local held = g.signal(nil :: any)
        g.watch(function() return placement.value[i] end, function(grp: any)
            if grp then held.value = grp end
        end)
        -- Forgotten once the place has been empty for as long as going home
        -- takes, whether or not the cluster ever came out: one taken away
        -- before its turn in the cascade never went home either, and its
        -- thread's node stayed on the pill.
        local function empty(): boolean return placement.value[i] == nil end
        g.watch(empty, function(now: boolean)
            if not now then return end
            g.after(home(), function()
                if g.untracked(empty) then held.value = nil end
            end)
        end)
        local function here(): boolean return held.value ~= nil end
        local function items(): { any } return if held.value then held.value.items else {} end
        local function height(): number return pad() * 2 + title_height() + #items() * row_height() end
        local function lit(): boolean return out() and lit_slot() == i end
        local function moving(): string return if out() then timing.motion("tether", "open_flat") else "retract" end
        local function swaying(): string return if out() then timing.motion("sway", "open_flat") else "retract" end
        local function growing(): string return if out() then "open_flat" else "retract" end

        -- From the pill's centre: the middle of the cluster's edge that
        -- faces the pill (where the thread ties on), and its corner.
        local function anchor(): (number, number)
            if slot.row == 0 then return slot.col * (pill_width() / 2 + gap_x()), 0 end
            local x = slot.col * (cluster_width() + gap_x())
            return x, slot.row * (pill_height() / 2 + gap_y())
        end
        local function corner(): (number, number)
            local ax, ay = anchor()
            if slot.row == 0 then
                return (if slot.col < 0 then ax - cluster_width() else ax), -height() / 2
            end
            return ax - cluster_width() / 2, (if slot.row < 0 then ay - height() else ay)
        end
        -- Where the thread leaves the pill, toward the anchor.
        local function exit(): (number, number)
            local ax, ay = anchor()
            local len = math.max(1e-6, math.sqrt(ax * ax + ay * ay))
            local ux, uy = ax / len, ay / len
            local t = pill_exit(ux, uy)
            return ux * t, uy * t
        end
        -- The thread's resting bend: a little off the straight line,
        -- downward where it can be, so it hangs rather than points.
        local function bend(): (number, number)
            local ex, ey = exit()
            local ax, ay = anchor()
            local dx, dy = ax - ex, ay - ey
            local len = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
            local px, py = -dy / len, dx / len
            if py < 0 or (math.abs(py) < 1e-6 and px * slot.col < 0) then px, py = -px, -py end
            local sag = len * 0.12
            return (ex + ax) / 2 + px * sag, (ey + ay) / 2 + py * sag
        end
        local function strength(): number
            local w = find(lit_key())
            return if w then w.result.strength or 0 else 0
        end

        local function geometry(t: { [any]: any }): { [any]: any }
            t.overlay = true
            t.attach = "corner"
            t.present = here
            t.width = frame_width
            t.height = frame_height
            t.from_x = function() local x = exit() return cx() + x end
            t.from_y = function() local _, y = exit() return cy() + y end
            t.to_x = function() local x = if out() then (anchor()) else (exit()) return cx() + x end
            t.to_y = function()
                local y = if out() then select(2, anchor()) else select(2, exit())
                return cy() + y
            end
            t.bend_x = function() local x = if out() then (bend()) else (exit()) return cx() + x end
            t.bend_y = function()
                local y = if out() then select(2, bend()) else select(2, exit())
                return cy() + y
            end
            return t
        end

        local thread = g.thread(geometry {
            stroke = metrics_mod.thread,
            crisp = true,
            node = metrics_mod.node_size * 2,
            fill = function() return if lit() then theme.primary() else theme.line() end,
            color = function() return if lit() then theme.primary() else theme.node() end,
            growth = function() return if out() then 1 else 0 end,
            transition = {
                to_x = moving, to_y = moving, bend_x = swaying, bend_y = swaying,
                growth = function() return if out() then "grow" else "retract" end,
                fill = "colour", color = "colour",
            },
        })

        -- From the pill to the cluster while its thread is lit, as many a
        -- second as the result reached is worth (see the head of the file).
        local flow = g.emitter(geometry {
            rate = function() return if lit() then 4 + 36 * strength() else 0 end,
            lifetime = function() return timing.seconds.flow end,
            spread = 0.4,
            particle_size = function() return 3 * f() end,
            fill = theme.primary,
            transition = { to_x = moving, to_y = moving, bend_x = swaying, bend_y = swaying },
        })

        local function result_row(item: () -> any): any
            local function key(): string return search.key_of(item()) end
            local function picked(): boolean return chosen() == key() end
            local over = g.signal(false)
            local function source(): string
                local icon = item().icon or ""
                if icon == "" then return "" end
                return g.icon_path(icon) or ""
            end
            return g.capsule {
                role = "button",
                name = "Result",
                width = function() return cluster_width() - pad() * 2 end,
                height = row_height,
                direction = "row",
                align = "center",
                justify = "start",
                padding_left = function() return 6 * f() end,
                gap = function() return 10 * f() end,
                radius = function() return metrics_mod.shaped(10 * f()) end,
                fill = function()
                    if picked() then return theme.selection() end
                    return if over.value then colour.alpha(theme.text(), 0.06) else CLEAR
                end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                transition = { fill = "colour" },
                on_hover = function(on: boolean)
                    over.value = on
                    if on then hovered.value = g.untracked(key)
                    elseif g.untracked(function() return hovered.value end) == g.untracked(key) then hovered.value = "" end
                end,
                on_click = function(button: number)
                    if button == 272 then launch(g.untracked(key), false) end
                end,
                -- The row reached: its icon ringed in the primary as well
                -- as the fill (theme.selection), as the simple launcher's.
                -- The icon is sized to the ring, not the slot: 0.7 of it, as
                -- in the simple launcher, so a full-bleed square icon keeps
                -- its corners inside the ring.
                g.box {
                    width = portrait,
                    height = portrait,
                    align = "center",
                    justify = "center",
                    g.capsule {
                        overlay = true,
                        present = picked,
                        width = ring,
                        height = ring,
                        stroke = function() return 1.5 * f() end,
                        rim_top = theme.primary,
                        rim_bottom = theme.primary,
                    },
                    g.icon {
                        present = function() return source() ~= "" end,
                        width = function() return ring() * 0.7 end,
                        height = function() return ring() * 0.7 end,
                        icon = source,
                    },
                    g.icon {
                        present = function() return source() == "" end,
                        width = function() return ring() * 0.6 end,
                        height = function() return ring() * 0.6 end,
                        icon = "app-fallback",
                        color = theme.text_muted,
                    },
                },
                g.text {
                    text = function() return item().name end,
                    marks = function() return g.array(table.clone(item().at or {})) end,
                    mark_color = theme.primary,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return 14 * f() end,
                    max_width = function() return cluster_width() - pad() * 2 - 6 * f() - portrait() - 10 * f() - 8 * f() end,
                },
            }
        end

        local glass = g.capsule {
            overlay = true,
            attach = "corner",
            present = here,
            width = function() return if out() then cluster_width() else 0 end,
            height = function() return if out() then height() else 0 end,
            offset_x = function()
                if not out() then local x = exit() return cx() + x end
                local x = corner()
                return cx() + x
            end,
            offset_y = function()
                if not out() then return cy() + select(2, exit()) end
                return cy() + select(2, corner())
            end,
            radius = function() return metrics_mod.inner_radius(m().radius_panel, 4 * f()) end,
            padding = pad,
            direction = "column",
            align = "start",
            blur = performance.blurred,
            fill = function()
                local base = if lit() then theme.lift(theme.cell(), 0.04) else theme.cell()
                return colour.alpha(base, config.get("cell.opacity", 0.72))
            end,
            rim_top = function() return if lit() then theme.lift(theme.rim(), 0.10) else theme.rim() end,
            rim_bottom = function() return if lit() then theme.lift(theme.line(), 0.06) else theme.line() end,
            -- The travel bounces; the shape only grows. A spring on the size
            -- swelled each cluster past itself and over its neighbours: a
            -- panel does not overshoot (core/timing.luau).
            transition = {
                width = growing, height = growing, offset_x = moving, offset_y = moving,
                fill = "colour", rim_top = "colour", rim_bottom = "colour",
            },
            -- A press on the cluster between its rows is a press on the
            -- launcher, not outside it.
            on_click = function() end,
            -- Content arrives once the shape is out, and leaves before it
            -- goes home.
            g.box {
                direction = "column",
                align = "start",
                opacity = function() return if out() then 1 else 0 end,
                transition = { opacity = function() return if out() then "ring_content" else "content_leave" end },
                g.box {
                    height = title_height,
                    align = "center",
                    padding_left = function() return 8 * f() end,
                    g.text {
                        text = function() return if held.value then held.value.label else "" end,
                        color = function() return if lit() then theme.text() else theme.text_faint() end,
                        font = typography.technical,
                        size = function() return m().font_meta end,
                        weight = typography.weight_label,
                        tracking = typography.label_tracking,
                    },
                },
                g.each {
                    direction = "column",
                    align = "start",
                    items = items,
                    key = function(r: any) return search.key_of(r) end,
                    row = result_row,
                },
            },
        }
        return thread, flow, glass
    end

    local function around(): any
        local frame: { [any]: any } = {
            overlay = true,
            attach = "corner",
            present = function() return drawn.value end,
            width = frame_width,
            height = frame_height,
            offset_x = function() return pill_width() / 2 - cx() end,
            offset_y = function() return pill_height() / 2 - cy() end,
        }
        local glasses = {}
        for i = 1, #SLOTS do
            local thread, flow, glass = cluster(i)
            table.insert(frame, flow)
            table.insert(frame, thread)
            table.insert(glasses, glass)
        end
        for _, glass in glasses do table.insert(frame, glass) end
        -- Nothing found is a glass of its own under the pill, grown from the
        -- pill's lower edge as a cluster is and gone back into it when
        -- something answers: a line of text alone hung in the void. Only
        -- once the home has been walked: "nothing" said before the files
        -- are back would be taken back.
        local function nothing(): boolean
            return cell.placed.value and query.value ~= "" and #results.value == 0 and not searching()
        end
        local NOTHING = "Nothing answers to that"
        local function note_height(): number return 38 * f() end
        local function note_width(): number
            return g.text_width { text = NOTHING, font = typography.expressive(), size = m().font_title } + 36 * f()
        end
        local function growing(): string return if nothing() then "open_flat" else "retract" end
        -- Tied to the pill as a cluster is, by a thread from its lower edge
        -- hanging a little to one side; half a cluster's distance, since it
        -- carries nothing.
        local function note_gap(): number return gap_y() / 2 end
        local function lower_edge(): number return cy() + pill_height() / 2 end
        local function note_top(): number return lower_edge() + (if nothing() then note_gap() else 0) end
        table.insert(frame, g.thread {
            overlay = true,
            attach = "corner",
            width = frame_width,
            height = frame_height,
            from_x = cx,
            from_y = lower_edge,
            to_x = cx,
            to_y = note_top,
            bend_x = function() return cx() - (if nothing() then note_gap() * 0.12 else 0) end,
            bend_y = function() return (lower_edge() + note_top()) / 2 end,
            stroke = metrics_mod.thread,
            crisp = true,
            node = metrics_mod.node_size * 2,
            fill = theme.line,
            color = theme.node,
            growth = function() return if nothing() then 1 else 0 end,
            transition = {
                to_y = growing, bend_x = growing, bend_y = growing,
                growth = function() return if nothing() then "grow" else "retract" end,
            },
        })
        table.insert(frame, g.capsule {
            overlay = true,
            attach = "corner",
            width = function() return if nothing() then note_width() else 0 end,
            height = function() return if nothing() then note_height() else 0 end,
            offset_x = function() return cx() - (if nothing() then note_width() / 2 else 0) end,
            offset_y = note_top,
            radius = function() return metrics_mod.radius_for(note_height(), m()) end,
            align = "center",
            justify = "center",
            blur = performance.blurred,
            fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            transition = { width = growing, height = growing, offset_x = growing, offset_y = growing },
            g.text {
                text = NOTHING,
                color = theme.text_muted,
                font = typography.expressive,
                size = function() return m().font_title end,
                opacity = function() return if nothing() then 1 else 0 end,
                transition = { opacity = function() return if nothing() then "ring_content" else "content_leave" end },
            },
        })
        return g.box(frame)
    end

    return {
        interactive = false,
        wants_keyboard = true,
        fixed_visibility = registry.fixed_when_floating("launcher"),
        padding_leading = inset,
        padding_trailing = inset,
        content_width = inner,
        body_height = body_extent,
        radius = function() return metrics_mod.radius_for(body_extent(), m()) end,
        contracted = pill,
        around = around,
        -- The pill waits for the clusters to go home: their content leaves,
        -- then they retract, and the pill goes halfway through that.
        withdrawal = function() return timing.seconds.content_fade / 2 + timing.seconds.close / 2 end,
        on_key = on_key,
    }
end

return M
