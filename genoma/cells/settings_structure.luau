--!strict
-- Settings → Structure (cells/settings/SettingsStructure.qml at 2cafc17):
-- how the shell is laid out, which tissues exist on which edge, and what
-- is in them.
--
-- **Structure is composed, not listed.** Six slots drawn where they will
-- actually be, three on the top membrane and three on the bottom, say at a
-- glance what a list of tissues with percentages beside them never would,
-- and they are the only form in which "add a tissue" has an obvious place:
-- the empty slot. An unlit slot is dashed; a press lights it, and emptying
-- it switches it off. What floats over the screen sits between the two
-- edges, nine places in three rows, the screen in small.
--
-- The chosen slot feeds the detail below it through a thread, the same
-- sentence the categories use, one level down. See docs/design/CELLS.md
-- §12.
--
-- Every change rewrites the whole list: an array is one value to the
-- merge, so what lands in the override is the layout as it stands with one
-- thing different in it.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local performance = require("core/performance")
local presets = require("core/presets")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local registry = require("cells/registry")
local place = require("cells/settings_place")
local page = require("components/page")
local segmented = require("components/segmented")
local choice_mod = require("components/choice")
local slider = require("components/slider")
local thread_mod = require("components/thread")
local field_mod = require("components/field")
local scroller_mod = require("components/scroller")
local monitors = require("services/monitors")
local setup = require("services/setup")

local M = {}

local CLEAR = "#00000000"
local LEFT = 272

local PLACES = { "start", "centre", "end" }
local RANK = { start = 1, centre = 2, ["end"] = 3 }
local ANCHORS = { "top-left", "top", "top-right", "left", "centre", "right", "bottom-left", "bottom", "bottom-right" }

-- Below this a tissue is a sliver that can no longer be seen or pressed.
local MIN_SHARE = 5
local PRESET_ROWS = 8

-- The same rule the membrane places tissues by, so a slot is drawn where
-- the tissue will actually be. The page writes the anchor out explicitly
-- from then on: an empty middle slot must not move the two beside it.
local function place_of(tissue: any, index: number, count: number): string
    if tissue.anchor then return tissue.anchor end
    if tissue.growth == "symmetric" then return "centre" end
    if index == 1 then return "start" end
    if index == count then return "end" end
    return "centre"
end

-- `center` is how the default layer spells it, and the surface reads both.
local function anchor_of(block: any): string
    local anchor = if block and block.anchor then block.anchor else "centre"
    return if anchor == "center" then "centre" else anchor
end

-- Where an anchor sits on the small screen: its row and its column from 0,
-- the columns lined up with a membrane's three tissues.
local function spot_of(anchor: string): (number, number)
    local i = table.find(ANCHORS, anchor)
    if not i then return 1, 1 end
    return (i - 1) // 3, (i - 1) % 3
end

local function sum_of(tissues: { any }): number
    local total = 0
    for _, t in tissues do total += t.percentage or 0 end
    return total
end

local function everywhere(block: any): boolean
    return block.monitor == "all" or block.monitor == "*"
end

-- `t`: metrics(), width(), height(), keyed(handler), output (the screen
-- the settings are open on).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    local function m(): any return t.metrics() end
    local function meta(): number return m().font_meta end

    local function slot_height(): number return 26 * f() end
    local function slot_gap(): number return 14 * f() end
    local function slot_width(): number return math.max(0, (t.width() - 2 * slot_gap()) / 3) end
    local function chip_height(): number return 26 * f() end
    local function head(): number return 22 * f() end
    local function head_spacing(): number return 12 * f() end
    local function thread_length(): number return m().gap end

    -- ---- What is declared ----------------------------------------------------

    local function membranes(): { any }
        local list = config.get("membranes", {})
        return if type(list) == "table" then list else {}
    end
    local function floats(): { any }
        local list = config.get("floating", {})
        return if type(list) == "table" then list else {}
    end

    -- The one chosen on the Monitors page or in the tabs, else the one the
    -- settings were opened on.
    local function monitor(): string
        local list = monitors.outputs()
        for _, wanted in { place.monitor.value, t.output or "" } do
            for _, o in list do
                if o.name == wanted then return wanted end
            end
        end
        local primary = monitors.primary()
        if primary ~= "" then return primary end
        return if #list > 0 then list[1].name else ""
    end

    -- A block may name a monitor or say `primary`, the one niri focuses at
    -- startup.
    local function claims_on(block: any, screen: string): boolean
        if not block then return false end
        if block.monitor == screen then return true end
        return block.monitor == "primary" and monitors.primary() == screen
    end
    local function claims(block: any): boolean return claims_on(block, monitor()) end

    local function membrane_for(edge: string): any
        for _, block in membranes() do
            if claims(block) and block.edge == edge then return block end
        end
        return nil
    end
    local function tissue_in(block: any, where: string): any
        local tissues = block.tissues or {}
        for i, tissue in tissues do
            if place_of(tissue, i, #tissues) == where then return tissue end
        end
        return nil
    end
    local function tissue_at(edge: string, where: string): any
        local block = membrane_for(edge)
        return if block then tissue_in(block, where) else nil
    end

    -- What a percentage is worth on this membrane, in logical units.
    local function step_of(edge: string): any
        local block = membrane_for(edge)
        return metrics_mod.step(if block and block.scale then block.scale else "normal")
    end
    local function usable_on(edge: string): number
        local o = monitors.output_of(monitor())
        if not o then return 0 end
        return math.max(0, o.width - step_of(edge).margin_edge * 2)
    end

    -- A floating block names a monitor, says `primary` or `all`; with
    -- nothing named it is the primary's.
    local function float_shown_here(block: any): boolean
        local screen = block.monitor or "primary"
        if screen == "all" or screen == "*" then return true end
        return claims({ monitor = screen })
    end
    local function floats_here(): { any }
        local out = {}
        for i, block in floats() do
            if float_shown_here(block) then table.insert(out, { index = i, block = block }) end
        end
        return out
    end
    -- One tissue per anchor on a monitor: two in one corner are drawn on
    -- top of each other.
    local function float_at(anchor: string): any
        for _, entry in floats_here() do
            if anchor_of(entry.block) == anchor then return entry end
        end
        return nil
    end

    -- ---- The chosen slot -----------------------------------------------------

    local function chosen_edge(): string return place.slot_edge.value end
    local function chosen_slot(): number return place.slot.value end
    local function floating_chosen(): boolean return chosen_edge() == "floating" end
    local function chosen_place(): string
        if floating_chosen() or chosen_slot() < 1 then return "" end
        return PLACES[chosen_slot()] or ""
    end
    local function chosen(): any
        if floating_chosen() then
            for _, entry in floats_here() do
                if entry.index == chosen_slot() then return entry.block end
            end
            return nil
        end
        local where = chosen_place()
        return if where ~= "" then tissue_at(chosen_edge(), where) else nil
    end

    local picking = g.signal(false)
    local presets_open = g.signal(false)
    local naming = g.signal(false)
    local preset_armed = g.signal("")
    local preset_removing = g.signal("")
    g.watch(function() return chosen() == nil end, function(none: boolean)
        if none then picking.value = false end
    end)
    g.watch(function() return presets_open.value end, function(open: boolean)
        if not open then
            preset_armed.value = ""
            preset_removing.value = ""
        end
    end)

    -- A share held under the hand while the width slider moves.
    local held_share = g.signal(nil :: number?)

    -- A new choice draws the thread out again from the new slot, rather
    -- than moving it there whole.
    local redrawing = g.signal(false)
    local function choose(edge: string, index: number)
        local same = g.untracked(function() return chosen_edge() == edge and chosen_slot() == index end)
        g.batch(function()
            if not same then redrawing.value = true end
            place.slot_edge.value = edge
            place.slot.value = index
            picking.value = false
            held_share.value = nil
        end)
        if not same then g.after(0, function() redrawing.value = false end) end
    end
    local function unchoose() place.slot.value = 0 end

    -- ---- Writing it back -----------------------------------------------------

    local function edit(change: (any) -> boolean)
        local copy = config.copy_list(membranes())
        if not change(copy) then return end
        config.set("membranes", registry.renamed(copy))
    end
    local function edit_floats(change: (any) -> boolean)
        local copy = config.copy_list(floats())
        if not change(copy) then return end
        config.set("floating", registry.renamed(copy))
    end

    -- A membrane the configuration has never mentioned arrives Fixed, and a
    -- horizontal edge that is Fixed cedes its strip.
    local function fresh_block(edge: string): any
        return {
            monitor = monitor(),
            edge = edge,
            reserve_space = edge == "top" or edge == "bottom",
            auto_hide = false,
            scale = "normal",
            tissues = g.array({}),
        }
    end
    local function block_in(copy: { any }, edge: string, make: boolean): any
        for _, block in copy do
            if claims(block) and block.edge == edge then return block end
        end
        if not make then return nil end
        local block = fresh_block(edge)
        table.insert(copy, block)
        return block
    end
    local function order(block: any)
        table.sort(block.tissues, function(a: any, b: any)
            return (RANK[a.anchor or "centre"] or 2) < (RANK[b.anchor or "centre"] or 2)
        end)
    end

    -- ---- Room ------------------------------------------------------------------
    --
    -- The page refuses what will not fit rather than letting somebody build a
    -- membrane with cells missing from it.

    local function room_for(edge: string, tissue: any, extra: string?): number
        local cells = {}
        for _, entry in (if tissue and tissue.cells then tissue.cells else {}) do table.insert(cells, entry) end
        if extra then table.insert(cells, { type = extra, enabled = true }) end
        return registry.room_for(cells, step_of(edge))
    end
    -- A floating tissue has no ceiling: nothing shares its surface.
    local function fits(edge: string, tissue: any, extra: string): boolean
        if edge == "floating" then return true end
        local granted = (if tissue and tissue.percentage then tissue.percentage else 0) / 100 * usable_on(edge)
        return room_for(edge, tissue, extra) <= granted + 0.5
    end
    -- The narrowest this tissue may be declared and still hold what is in
    -- it, which is what the width slider is not allowed below.
    local function floor_for(edge: string, tissue: any): number
        local usable = usable_on(edge)
        if usable <= 0 then return 0 end
        return math.ceil(room_for(edge, tissue, nil) / usable * 100)
    end
    local function share_floor(edge: string, tissue: any): number
        return math.max(MIN_SHARE, floor_for(edge, tissue))
    end

    -- ---- Shares that add up ------------------------------------------------------
    --
    -- **The tissues of a membrane share it whole**: their percentages always
    -- add up to 100 (Akusen, 2026-10-09). A tissue widened takes from its
    -- neighbour, one switched off leaves its share to its neighbours, one
    -- switched on divides the membrane in equal parts. None is pushed below
    -- what its cells need.

    local function places_in(tissues: { any }): { [string]: any }
        local at = {}
        for i, tissue in tissues do at[place_of(tissue, i, #tissues)] = tissue end
        return at
    end

    -- `amount` handed to the neighbours of `from`, or taken from them when
    -- it is negative, down to their floors: a corner's neighbour is the
    -- centre, then the other corner; the centre's are the two corners, half
    -- each.
    local function absorb(edge: string, tissues: { any }, from: string, amount: number)
        local at = places_in(tissues)
        local wanted = ({ start = { "centre", "end" }, ["end"] = { "centre", "start" }, centre = { "start", "end" } })[from] or {}
        local neighbours = {}
        for _, name in wanted do
            if at[name] and name ~= from then table.insert(neighbours, at[name]) end
        end
        if #neighbours == 0 or amount == 0 then return end
        local split = from == "centre" and #neighbours == 2

        if amount > 0 then
            local first = if split then amount // 2 else amount
            neighbours[1].percentage = (neighbours[1].percentage or 0) + first
            if split then neighbours[2].percentage = (neighbours[2].percentage or 0) + amount - first end
            return
        end

        local need = -amount
        local function room(tissue: any): number
            return math.max(0, (tissue.percentage or 0) - share_floor(edge, tissue))
        end
        local wants = if split then { math.ceil(need / 2), need // 2 } else { need, 0 }
        for i, tissue in neighbours do
            local taken = math.min(wants[i] or 0, room(tissue))
            tissue.percentage -= taken
            need -= taken
        end
        for _, tissue in neighbours do
            local taken = math.min(need, room(tissue))
            tissue.percentage -= taken
            need -= taken
        end
    end

    -- Equal parts, each at least its floor; what does not divide goes to
    -- the centre first: 33, 34, 33. False when the floors alone pass 100.
    local function equalize(edge: string, tissues: { any }): boolean
        local count = #tissues
        if count == 0 then return true end
        local floors, fixed = {}, {}
        for i, tissue in tissues do
            floors[i] = share_floor(edge, tissue)
            fixed[i] = false
        end
        local left, free, moved = 100, count, true
        while moved and free > 0 do
            moved = false
            for i = 1, count do
                if not fixed[i] and floors[i] > left / free then
                    fixed[i] = true
                    left -= floors[i]
                    free -= 1
                    moved = true
                end
            end
        end
        if left < 0 then return false end

        local base = if free > 0 then left // free else 0
        local rest = if free > 0 then left - base * free else left
        local rank = { centre = 0, start = 1, ["end"] = 2 }
        local ordered = {}
        for i = 1, count do table.insert(ordered, i) end
        table.sort(ordered, function(a: number, b: number)
            local ra = rank[place_of(tissues[a], a, count)] or 0
            local rb = rank[place_of(tissues[b], b, count)] or 0
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        for i = 1, count do tissues[i].percentage = if fixed[i] then floors[i] else base end
        -- To the equal parts when there are any, to the floors when every
        -- tissue is held at its own.
        local takers = {}
        for _, i in ordered do
            if free == 0 or not fixed[i] then table.insert(takers, i) end
        end
        local k = 0
        while rest > 0 do
            local i = takers[k % #takers + 1]
            tissues[i].percentage += 1
            rest -= 1
            k += 1
        end
        return true
    end

    -- ---- Changing the layout ----------------------------------------------------

    local function light(edge: string, where: string)
        edit(function(copy: any): boolean
            local block = block_in(copy, edge, true)
            if tissue_in(block, where) then return false end
            block.tissues = block.tissues or g.array({})
            table.insert(block.tissues, {
                anchor = where,
                percentage = 0,
                growth = if where == "centre" then "symmetric" else "inward",
                orientation = "horizontal",
                cells = g.array({}),
            })
            order(block)
            equalize(edge, block.tissues)
            return true
        end)
    end

    -- Emptying a slot switches it off, and a membrane with no tissues left
    -- is not a membrane: it goes, rather than staying as a surface with
    -- nothing on it.
    local function clear(edge: string, where: string)
        print("Bioma: removing the " .. where .. " tissue of the " .. edge .. " membrane on " .. monitor())
        edit(function(copy: any): boolean
            local block = block_in(copy, edge, false)
            if not block then return false end
            local kept = g.array({})
            local tissues = block.tissues or {}
            for i, tissue in tissues do
                if place_of(tissue, i, #tissues) ~= where then table.insert(kept, tissue) end
            end
            block.tissues = kept
            if #kept == 0 then
                table.remove(copy, table.find(copy, block) :: number)
            else
                absorb(edge, kept, where, 100 - sum_of(kept))
            end
            return true
        end)
        if chosen_edge() == edge and chosen_place() == where then unchoose() end
    end

    -- Widening one narrows its neighbour by as much, and the other way
    -- round: the slider moves two tissues. It stops where the others reach
    -- their floors, and a tissue alone on its membrane has all of it.
    local function set_percentage(edge: string, where: string, value: number)
        edit(function(copy: any): boolean
            local block = block_in(copy, edge, false)
            local tissue = if block then tissue_in(block, where) else nil
            if not tissue then return false end
            local tissues = block.tissues
            local others = {}
            local ceiling = 100
            for _, other in tissues do
                if other ~= tissue then
                    table.insert(others, other)
                    ceiling -= share_floor(edge, other)
                end
            end
            local wanted = math.max(share_floor(edge, tissue), math.min(ceiling, math.round(value)))
            if #others == 0 then
                if tissue.percentage == 100 then return false end
            elseif tissue.percentage == wanted and sum_of(tissues) == 100 then
                return false
            end
            tissue.percentage = if #others == 0 then 100 else wanted
            absorb(edge, tissues, where, 100 - sum_of(tissues))
            return true
        end)
    end

    local function set_mode(edge: string, key: string)
        edit(function(copy: any): boolean
            local block = block_in(copy, edge, false)
            if not block then return false end
            block.auto_hide = key == "hide"
            -- Auto-hide implies reserving nothing: a strip kept for a
            -- membrane that has slid out of view is a strip nobody can use.
            block.reserve_space = key == "fixed" and edge ~= "left" and edge ~= "right"
            return true
        end)
    end

    -- The chosen tissue, wherever it lives, changed in a copy of its list
    -- and written back whole.
    local function edit_chosen(change: (any) -> boolean)
        if floating_chosen() then
            local index = chosen_slot()
            edit_floats(function(copy: any): boolean
                local tissue = copy[index]
                return if tissue then change(tissue) else false
            end)
            return
        end
        local edge, where = chosen_edge(), chosen_place()
        edit(function(copy: any): boolean
            local block = block_in(copy, edge, false)
            local tissue = if block then tissue_in(block, where) else nil
            return if tissue then change(tissue) else false
        end)
    end

    -- A new block carries its kind and nothing else: what the condition
    -- means is the domain's, and stays that way.
    local function add_cell(kind: string)
        edit_chosen(function(tissue: any): boolean
            tissue.cells = tissue.cells or g.array({})
            table.insert(tissue.cells, {
                type = kind,
                enabled = true,
                visibility = { type = if registry.allows(kind, "always") then "always" else "conditional" },
            })
            return true
        end)
        picking.value = false
    end
    local function remove_cell(index: number)
        edit_chosen(function(tissue: any): boolean
            if not tissue.cells or not tissue.cells[index] then return false end
            table.remove(tissue.cells, index)
            return true
        end)
    end

    local function add_float_at(anchor: string)
        if float_at(anchor) then return end
        local at = #floats() + 1
        edit_floats(function(copy: any): boolean
            table.insert(copy, { anchor = anchor, monitor = monitor(), orientation = "vertical", cells = g.array({}) })
            return true
        end)
        choose("floating", at)
    end
    local function remove_float(index: number)
        print("Bioma: removing floating tissue " .. index .. " on " .. monitor())
        edit_floats(function(copy: any): boolean
            if not copy[index] then return false end
            table.remove(copy, index)
            return true
        end)
        unchoose()
    end

    -- **One place per cell per monitor.** A cell is in one tissue of one
    -- membrane or in one floating slot, and that place is where a keybind
    -- opens it: two would make the keybind a guess.
    local function placed_here(): { string }
        local out = {}
        for _, block in membranes() do
            if claims(block) then
                for _, tissue in block.tissues or {} do
                    for _, entry in tissue.cells or {} do table.insert(out, registry.canonical(entry.type)) end
                end
            end
        end
        for _, entry in floats_here() do
            for _, cell in entry.block.cells or {} do table.insert(out, registry.canonical(cell.type)) end
        end
        return out
    end
    local function absent(): { string }
        local out = {}
        if chosen() == nil then return out end
        local taken = placed_here()
        for _, pair in registry.catalogue do
            local kind = pair[1]
            if not table.find(taken, kind) and not registry.internal[kind] and not registry.comes_to_pointer(kind) then
                table.insert(out, kind)
            end
        end
        return out
    end

    -- ---- Moving a tissue, or copying it --------------------------------------------
    --
    -- MOVE or COPY takes the chosen tissue in hand, and every free place on
    -- the page becomes somewhere to put it: the dashed slots on either edge
    -- and the free floating anchors, on this monitor or, through the tabs,
    -- on another. What goes is the tissue whole, less whatever the monitor
    -- it lands on already has: one place per cell per monitor.

    local transfer = g.signal("") -- "" | "move" | "copy"
    local transfer_from = g.signal(nil :: any)

    local function end_transfer()
        g.batch(function()
            transfer.value = ""
            transfer_from.value = nil
        end)
    end
    local function start_transfer(kind: string)
        local tissue = chosen()
        if transfer.value == kind or not tissue then
            end_transfer()
            return
        end
        g.batch(function()
            transfer_from.value = {
                monitor = monitor(),
                edge = chosen_edge(),
                place = chosen_place(),
                float_index = if floating_chosen() then chosen_slot() else 0,
                tissue = config.copy_list({ tissue })[1],
            }
            transfer.value = kind
            picking.value = false
        end)
    end
    local function moving(): boolean return transfer.value == "move" end

    -- Whether the tissue in hand is drawn on the monitor the page shows:
    -- what it gives up there, a move takes out of the way.
    local function source_here(): boolean
        local from = transfer_from.value
        if not from then return false end
        return if from.edge == "floating" then float_shown_here(from.tissue) else from.monitor == monitor()
    end
    local function is_source(edge: string, where: string): boolean
        local from = transfer_from.value
        return from ~= nil and from.edge == edge and from.place == where and from.monitor == monitor()
    end
    local function is_float_source(index: number): boolean
        local from = transfer_from.value
        return from ~= nil and from.edge == "floating" and from.float_index == index
    end

    -- The cells that go, for a landing on this monitor.
    local function transfer_cells(): { any }
        local from = transfer_from.value
        if not from then return {} end
        local taken = placed_here()
        if moving() and source_here() then
            for _, entry in from.tissue.cells or {} do
                local at = table.find(taken, registry.canonical(entry.type))
                if at then table.remove(taken, at) end
            end
        end
        local out = {}
        for _, entry in from.tissue.cells or {} do
            if not table.find(taken, registry.canonical(entry.type)) then table.insert(out, entry) end
        end
        return out
    end
    local function total_cells(): number
        local from = transfer_from.value
        return if from then #(from.tissue.cells or {}) else 0
    end
    -- Nothing to carry: every cell is here already.
    local function transfer_empty(): boolean
        return transfer_from.value ~= nil and #transfer_cells() == 0 and total_cells() > 0
    end

    -- The share a tissue landing here would be given, or -1 where it will
    -- not fit. Landing is lighting a slot: the membrane is divided in equal
    -- parts again, so a slot says NO ROOM only when the floors alone would
    -- pass 100.
    local function share_at(edge: string, where: string): number
        if not transfer_from.value or transfer_empty() then return -1 end
        if usable_on(edge) <= 0 then return -1 end
        local block = membrane_for(edge)
        local tissues = if block then block.tissues or {} else {}
        local after = {}
        for i, tissue in tissues do
            local at = place_of(tissue, i, #tissues)
            if not (moving() and is_source(edge, at)) then
                table.insert(after, { anchor = at, cells = tissue.cells or {}, percentage = tissue.percentage or 0 })
            end
        end
        local landing = { anchor = where, cells = transfer_cells(), percentage = 0 }
        table.insert(after, landing)
        if not equalize(edge, after) then return -1 end
        return if landing.percentage >= share_floor(edge, landing) then landing.percentage else -1
    end

    -- The one write, of both lists at once when both change.
    local function put_down(edge: string, where: string)
        local from = transfer_from.value
        if not from or transfer_empty() then return end
        local share = if edge == "floating" then 0 else share_at(edge, where)
        if edge ~= "floating" and share < 0 then return end

        local list = config.copy_list(membranes())
        local floating = config.copy_list(floats())
        local list_changed, floats_changed = false, false

        if moving() then
            if from.edge == "floating" then
                table.remove(floating, from.float_index)
                floats_changed = true
            else
                for at, block in list do
                    if claims_on(block, from.monitor) and block.edge == from.edge then
                        local tissues = block.tissues or {}
                        local kept = g.array({})
                        for i, tissue in tissues do
                            if place_of(tissue, i, #tissues) ~= from.place then table.insert(kept, tissue) end
                        end
                        block.tissues = kept
                        if #kept == 0 then
                            table.remove(list, at)
                        else
                            absorb(from.edge, kept, from.place, 100 - sum_of(kept))
                        end
                        list_changed = true
                        break
                    end
                end
            end
        end

        -- What a tissue is, apart from where it is.
        local tissue: { [string]: any } = { cells = config.copy_list(transfer_cells()) }
        for _, key in { "padding", "opacity" } do
            if from.tissue[key] ~= nil then tissue[key] = from.tissue[key] end
        end
        local chosen_index = 0
        if edge == "floating" then
            -- Everywhere stays everywhere when it only changes anchor.
            tissue.anchor = where
            tissue.monitor = if from.edge == "floating" and everywhere(from.tissue) then from.tissue.monitor else monitor()
            tissue.orientation = "vertical"
            table.insert(floating, tissue)
            chosen_index = #floating
            floats_changed = true
        else
            local block = block_in(list, edge, true)
            tissue.anchor = where
            tissue.percentage = share
            tissue.growth = if where == "centre" then "symmetric" else "inward"
            tissue.orientation = "horizontal"
            block.tissues = block.tissues or g.array({})
            table.insert(block.tissues, tissue)
            order(block)
            equalize(edge, block.tissues)
            chosen_index = table.find(PLACES, where) or 0
            list_changed = true
        end

        print(string.format("Bioma: %s a tissue from %s %s%s to %s %s %s — %d of %d cells",
            if moving() then "moving" else "copying", from.monitor, from.edge,
            if from.place ~= "" then " " .. from.place else "", monitor(), edge, where,
            #tissue.cells, total_cells()))

        local pairs = {}
        if list_changed then table.insert(pairs, { "membranes", registry.renamed(list) }) end
        if floats_changed then table.insert(pairs, { "floating", registry.renamed(floating) }) end
        config.set_many(pairs)

        end_transfer()
        choose(edge, chosen_index)
    end

    -- ---- Presets ---------------------------------------------------------------
    --
    -- A press that would throw away a layout kept under no name arms first
    -- and acts on the second press; leaving the row disarms it.

    local BLANK = "\0new"

    -- Another layout replaces this one whole: whatever was chosen or in hand
    -- on the page belonged to the old one.
    local function leave(change: () -> ())
        end_transfer()
        picking.value = false
        unchoose()
        change()
    end

    local function choose_preset(name: string)
        preset_removing.value = ""
        if presets.active() == name and not presets.changed() then
            presets_open.value = false
            return
        end
        if not presets.kept() and preset_armed.value ~= name then
            preset_armed.value = name
            return
        end
        preset_armed.value = ""
        presets_open.value = false
        leave(function() presets.apply(name) end)
    end

    local function forget_preset(name: string)
        preset_armed.value = ""
        if preset_removing.value ~= name then
            preset_removing.value = name
            return
        end
        preset_removing.value = ""
        presets.remove(name)
        if #presets.saved() <= 1 then presets_open.value = false end
    end

    local name_text = g.signal("")
    local name_node, name_field = field_mod.new {
        text = name_text,
        width = function() return 220 * f() - 28 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        placeholder = "A name for this layout",
        taking = function() return naming.value end,
    }
    local function start_naming()
        g.batch(function()
            presets_open.value = false
            picking.value = false
            preset_armed.value = ""
            preset_removing.value = ""
            naming.value = true
        end)
        end_transfer()
        name_field.set(presets.active())
    end
    local function finish_naming()
        if presets.save_as(g.untracked(function() return name_text.value end)) then naming.value = false end
    end

    t.keyed(function(name: string, typed: string?, mods: { [string]: boolean }): boolean
        if not g.untracked(function() return naming.value end) then return false end
        if name == "Escape" then
            naming.value = false
            return true
        end
        if name == "Return" or name == "KP_Enter" then
            finish_naming()
            return true
        end
        return name_field.key(name, typed, mods)
    end)

    -- ---- Shapes ------------------------------------------------------------------

    local function meta_text(text: string | () -> string, color: any, weight: number?): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = meta,
            weight = weight,
            tracking = typography.label_tracking,
        }
    end
    local function title(text: string, lit: () -> boolean): any
        return meta_text(text, function() return if lit() then theme.text() else theme.text_faint() end, typography.weight_label)
    end
    local function width_of(text: string): number
        return g.text_width { text = text, font = typography.technical(), size = meta(), tracking = typography.label_tracking }
    end
    local function icon(name: string, size: number, color: any, present: (() -> boolean)?): any
        return g.icon {
            present = present,
            width = function() return size * f() end,
            height = function() return size * f() end,
            icon = name,
            color = color,
        }
    end
    local function lit_fill(bright: () -> boolean): () -> string
        return function()
            return colour.alpha(theme.lift(theme.background(), if bright() then 0.04 else 0.015), 0.9)
        end
    end
    local function dashed_colour(target: () -> boolean): () -> string
        return function() return if target() then theme.primary() else colour.alpha(theme.line(), 0.7) end
    end

    -- The two faces of a place: dashed while free, outlined once a tissue
    -- is there.
    local function faces(w: () -> number, h: () -> number, lit: () -> boolean, rim: () -> string, fill: () -> string, dash: () -> string): { any }
        local function radius(): number return metrics_mod.shaped(11 * f()) end
        return {
            g.capsule {
                overlay = true,
                present = function() return not lit() end,
                width = w,
                height = h,
                radius = radius,
                rim_top = dash,
                rim_bottom = dash,
                dash = 3,
                dash_gap = 3,
            },
            g.capsule {
                overlay = true,
                present = lit,
                width = w,
                height = h,
                radius = radius,
                fill = fill,
                rim_top = rim,
                rim_bottom = rim,
            },
        }
    end

    -- One membrane's slot: its place, what is in it, and what a press
    -- does to it.
    local function slot(edge: string, index: number): any
        local where = PLACES[index]
        local function tissue(): any return tissue_at(edge, where) end
        local function lit(): boolean return tissue() ~= nil end
        local function is_chosen(): boolean return chosen_edge() == edge and chosen_slot() == index end
        local function source(): boolean return transfer.value ~= "" and is_source(edge, where) end
        local function share(): number
            return if transfer.value ~= "" and not lit() then share_at(edge, where) else -1
        end
        local function target(): boolean return share() >= 0 end
        local function offer(): string
            if transfer.value == "" or lit() then return "" end
            if transfer_empty() then return "ALREADY HERE" end
            local s = share()
            if s < 0 then return "NO ROOM" end
            local n, total = #transfer_cells(), total_cells()
            return tostring(s) .. "%" .. (if n < total then "  ·  " .. n .. " OF " .. total else "")
        end
        local node: { [any]: any } = {
            role = "button",
            name = edge .. " " .. where,
            width = slot_width,
            height = slot_height,
            align = "center",
            justify = "center",
            on_click = function()
                if g.untracked(function() return transfer.value end) ~= "" then
                    if g.untracked(target) then
                        put_down(edge, where)
                    elseif g.untracked(lit) then
                        end_transfer()
                        choose(edge, index)
                    end
                    return
                end
                if not g.untracked(lit) then light(edge, where) end
                choose(edge, index)
            end,
        }
        for _, face in faces(slot_width, slot_height, lit,
            function() return if is_chosen() or source() then theme.primary() else theme.line() end,
            lit_fill(is_chosen), dashed_colour(target)) do
            table.insert(node, face)
        end
        table.insert(node, g.text {
            present = function() return offer() ~= "" end,
            text = offer,
            color = function() return if target() then theme.primary() else theme.text_faint() end,
            font = typography.technical,
            size = meta,
            tracking = typography.label_tracking,
            tabular = true,
        })
        -- Lit, it says what is in it: the percentage and how many cells,
        -- which is the whole of a tissue.
        table.insert(node, g.text {
            present = lit,
            text = function()
                local tt = tissue()
                if not tt then return "" end
                return tostring(tt.percentage or 0) .. "%  ·  " .. #(tt.cells or {})
            end,
            color = function() return if is_chosen() then theme.text() else theme.text_muted() end,
            font = typography.technical,
            size = meta,
            tabular = true,
        })
        table.insert(node, icon("plus", 11, theme.text_faint, function() return not lit() and offer() == "" end))
        return g.box(node)
    end

    -- One floating place. Lit, it says what is in it, the first cell and
    -- how many more, and ALL when the tissue is on every monitor; dashed,
    -- it is free and a press puts a tissue there.
    local function float_slot(anchor: string, label: string, h: () -> number): any
        local function entry(): any return float_at(anchor) end
        local function lit(): boolean return entry() ~= nil end
        local function is_chosen(): boolean
            local e = entry()
            return e ~= nil and floating_chosen() and chosen_slot() == e.index
        end
        local function source(): boolean
            local e = entry()
            return transfer.value ~= "" and e ~= nil and is_float_source(e.index)
        end
        -- The pointer is not offered as a place (Akusen, 2026-10-15): it
        -- shows only a tissue already put there.
        local function target(): boolean
            return transfer.value ~= "" and not lit() and not transfer_empty() and anchor ~= "pointer"
        end
        local function content(): string
            if not lit() and transfer.value ~= "" then
                if transfer_empty() then return "ALREADY HERE" end
                local n, total = #transfer_cells(), total_cells()
                local part = if n < total then n .. " OF " .. total else ""
                if label ~= "" and part ~= "" then return label .. "  ·  " .. part end
                return label .. part
            end
            if not lit() then return label end
            local block = entry().block
            local cells = block.cells or {}
            local first = if #cells > 0 then string.upper(registry.name_of(cells[1].type)) else "EMPTY"
            local more = if #cells > 1 then " +" .. (#cells - 1) else ""
            local all = if everywhere(block) then "  ·  ALL" else ""
            return (if label ~= "" then label .. "  ·  " else "") .. first .. more .. all
        end
        local node: { [any]: any } = {
            role = "button",
            name = "floating " .. anchor,
            width = slot_width,
            height = h,
            align = "center",
            justify = "center",
            on_click = function()
                if g.untracked(function() return transfer.value end) ~= "" then
                    if g.untracked(target) then
                        put_down("floating", anchor)
                    elseif g.untracked(lit) then
                        end_transfer()
                        choose("floating", g.untracked(entry).index)
                    end
                    return
                end
                if g.untracked(lit) then
                    choose("floating", g.untracked(entry).index)
                elseif anchor ~= "pointer" then
                    add_float_at(anchor)
                end
            end,
        }
        for _, face in faces(slot_width, h, lit,
            function() return if is_chosen() or source() then theme.primary() else theme.line() end,
            lit_fill(is_chosen), dashed_colour(target)) do
            table.insert(node, face)
        end
        table.insert(node, g.text {
            present = function() return content() ~= "" end,
            text = content,
            color = function()
                if target() then return theme.primary() end
                if is_chosen() then return theme.text() end
                return if lit() then theme.text_muted() else theme.text_faint()
            end,
            font = typography.technical,
            size = meta,
            tracking = typography.label_tracking,
            tabular = true,
            max_width = function() return slot_width() - 16 * f() end,
        })
        table.insert(node, icon("plus", 11, function() return if target() then theme.primary() else theme.text_faint() end,
            function() return not lit() and content() == "" end))
        return g.box(node)
    end

    -- A word in a pill, outlined; `lit` while what it says is under way,
    -- `alarm` for one that takes something away.
    local function pill(a: { [string]: any }): any
        local hovered = g.signal(false)
        local function h(): number return 22 * f() end
        local function ink(): string
            if a.alarm and hovered.value then return theme.alert() end
            return theme.text()
        end
        local node: { [any]: any } = {
            role = "button",
            name = a.label,
            height = h,
            padding_left = function() return (if a.icon then 8 else 11) * f() end,
            padding_right = function() return 11 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 7 * f() end,
            radius = function() return metrics_mod.radius_for(h(), m()) end,
            fill = function()
                if a.lit and a.lit() then return colour.alpha(theme.primary(), 0.16) end
                if a.alarm and hovered.value then return colour.alpha(theme.alert(), 0.16) end
                return CLEAR
            end,
            rim_top = function()
                if a.lit and a.lit() then return theme.primary() end
                if hovered.value then return if a.alarm then theme.alert() else theme.text() end
                return theme.line()
            end,
            rim_bottom = function()
                if a.lit and a.lit() then return theme.primary() end
                if hovered.value then return if a.alarm then theme.alert() else theme.text() end
                return theme.line()
            end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = a.on_click,
        }
        if a.icon then table.insert(node, icon(a.icon, 9, ink)) end
        table.insert(node, meta_text(a.label, ink))
        return g.capsule(node)
    end

    -- ---- The preset row ------------------------------------------------------------
    --
    -- Saved layouts, above the monitor tabs because a preset is every
    -- monitor at once: the dropdown puts one back, the dashed chip starts
    -- from nothing, SAVE AS keeps what is on the page under a name.

    local function font_control(): number return math.round(12 * f()) end
    local function drop_width(): number return 240 * f() end
    local function list_padding(): number return 6 * f() end
    local function row_height(): number return m().row_height end
    local function control_text(text: string | () -> string, color: any, max: (() -> number)?): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = font_control,
            weight = typography.weight_label,
            tracking = 0.04,
            max_width = max,
        }
    end

    -- What the dropdown says: the preset in use, or that the layout is kept
    -- under no name.
    local function preset_label(): string
        local active = presets.active()
        if active ~= "" then return active end
        return if presets.empty() then "EMPTY" else "UNSAVED"
    end
    local function usable(): boolean return #presets.all() > 0 end

    local list_scroll = scroller_mod.new {
        viewport = function() return math.min(#presets.all(), PRESET_ROWS) * row_height() end,
        content = function() return #presets.all() * row_height() end,
        step = row_height,
        factor = f,
    }
    local function list_width(): number
        local longest = 0
        for _, preset in presets.all() do
            longest = math.max(longest, g.text_width {
                text = preset.name or "", font = typography.technical(), size = font_control(),
                weight = typography.weight_label, tracking = 0.04,
            })
        end
        return math.min(math.max(drop_width(), longest + 72 * f() + list_padding() * 2), t.width() - 76 * f())
    end
    local function list_height(): number
        return math.min(#presets.all(), PRESET_ROWS) * row_height() + list_padding() * 2
    end
    -- There while it grows and while it goes, gone once it has.
    local list_out = g.signal(false)
    local putting_away: any = nil
    g.watch(function() return presets_open.value end, function(on: boolean)
        if putting_away then putting_away:stop() end
        putting_away = nil
        if on then
            list_out.value = true
        else
            putting_away = g.after(timing.seconds.close + timing.seconds.content_fade, function() list_out.value = false end)
        end
    end)

    -- One row of the list: the one in use marked with a dot, a cross to
    -- forget one; a row that would lose a layout, or forget a preset, asks
    -- first in its own place, and the second press answers.
    local function preset_row(item: () -> any): any
        local function preset(): any return item().preset end
        local function name(): string return preset().name or "" end
        local function shipped(): boolean return preset().shipped == true end
        local function current(): boolean return presets.active() == name() end
        local function armed(): boolean return preset_armed.value == name() end
        local function removing(): boolean return preset_removing.value == name() end
        local function alarmed(): boolean return armed() or removing() end
        local over = g.signal(false)
        local cross_over = g.signal(false)
        local function disarm()
            preset_armed.value = ""
            preset_removing.value = ""
        end
        return g.capsule {
            role = "button",
            overlay = true,
            attach = "corner",
            offset_y = function() return (item().index - 1) * row_height() end,
            width = function() return list_width() - list_padding() * 2 end,
            height = row_height,
            direction = "row",
            align = "center",
            padding_left = function() return 10 * f() end,
            padding_right = function() return 4 * f() end,
            gap = function() return 6 * f() end,
            radius = function() return metrics_mod.radius_for(row_height(), m()) end,
            fill = function()
                if alarmed() then return colour.alpha(theme.alert(), 0.12) end
                return if over.value then colour.alpha(theme.text(), 0.06) else CLEAR
            end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            on_hover = function(on: boolean)
                over.value = on
                if not on and g.untracked(alarmed) then disarm() end
            end,
            -- While it asks, the row **is** the question: a press anywhere
            -- on it answers.
            on_click = function()
                if g.untracked(removing) then forget_preset(g.untracked(name)) else choose_preset(g.untracked(name)) end
            end,
            -- Where the user's end and Bioma's begin.
            g.capsule {
                overlay = true,
                attach = "corner",
                present = function() return shipped() and item().index > 1 and item().index == #presets.saved() + 1 end,
                offset_x = function() return -4 * f() end,
                width = function() return list_width() - list_padding() * 2 - 12 * f() end,
                height = 1,
                crisp = true,
                rim_top = function() return colour.alpha(theme.line(), 0.7) end,
                rim_bottom = function() return colour.alpha(theme.line(), 0.7) end,
                dash = 3,
                dash_gap = 3,
            },
            control_text(function()
                if removing() then return "FORGET " .. string.upper(name()) .. "?" end
                if armed() then return "DISCARD CHANGES?" end
                return name()
            end, function()
                if alarmed() then return theme.alert() end
                return if current() then theme.text() else theme.text_muted()
            end, function() return list_width() - list_padding() * 2 - 60 * f() end),
            g.box { grow = 1 },
            -- The choice is exclusive, so the mark may be a dot.
            g.capsule {
                opacity = function() return if current() then 1 else 0 end,
                width = function() return 6 * f() end,
                height = function() return 6 * f() end,
                fill = theme.primary,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
            },
            -- Bioma's own: no cross, because it cannot be forgotten. The
            -- cross takes the press for itself: the row's own would put back
            -- the preset it was asked to forget.
            g.box {
                role = "button",
                name = "Forget",
                opacity = function() return if shipped() then 0 else 1 end,
                width = function() return 22 * f() end,
                height = row_height,
                align = "center",
                justify = "center",
                on_hover = function(on: boolean) cross_over.value = on end,
                on_click = function()
                    if g.untracked(shipped) then
                        choose_preset(g.untracked(name))
                    else
                        forget_preset(g.untracked(name))
                    end
                end,
                icon("close", 9, function()
                    return if removing() or cross_over.value then theme.alert() else theme.text_faint()
                end),
            },
        }
    end

    local drop_hovered = g.signal(false)
    local function drop_edge(): string
        if presets_open.value then return theme.primary() end
        if not usable() then return colour.alpha(theme.line(), 0.5) end
        return if drop_hovered.value then theme.text() else theme.line()
    end
    -- Always the same width and in the same place: only what it says
    -- changes. The name is elided here; the list shows it whole.
    local dropdown = g.capsule {
        role = "button",
        name = "Presets",
        width = drop_width,
        height = chip_height,
        direction = "row",
        align = "center",
        gap = function() return 8 * f() end,
        padding_left = function() return 12 * f() end,
        padding_right = function() return 12 * f() end,
        radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
        fill = CLEAR,
        rim_top = drop_edge,
        rim_bottom = drop_edge,
        on_hover = function(on: boolean) drop_hovered.value = on end,
        on_click = function()
            if not g.untracked(usable) then return end
            local open = not g.untracked(function() return presets_open.value end)
            if open then
                end_transfer()
                picking.value = false
            end
            presets_open.value = open
        end,
        control_text(preset_label, function()
            return if presets.active() ~= "" then theme.text() else theme.text_muted()
        end, function() return drop_width() - (if presets.active() ~= "" and presets.changed() then 110 else 45) * f() end),
        g.box { grow = 1 },
        -- Whether the page still matches the preset in use, said beside the
        -- name rather than after it, where an elided name would take it.
        g.text {
            present = function() return presets.active() ~= "" and presets.changed() end,
            text = "CHANGED",
            color = theme.text_muted,
            font = typography.technical,
            size = meta,
            tracking = typography.label_tracking,
        },
        icon("chevron-down", 9, function() return colour.alpha(theme.text(), if usable() then 0.6 else 0.25) end),
        g.capsule {
            name = "list",
            role = "group",
            overlay = true,
            attach = "corner",
            raised = true,
            present = function() return list_out.value end,
            offset_y = function() return chip_height() + 6 * f() end,
            width = list_width,
            height = list_height,
            radius = function() return m().radius_well end,
            growth = function() return if presets_open.value then 1 else 0 end,
            transition = { growth = function() return if presets_open.value then "grow" else "close" end },
            blur = performance.blurred,
            fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            -- Glass over the page: what is under it does not answer.
            on_press = function() end,
            on_click = function() end,
            g.box {
                overlay = true,
                attach = "corner",
                offset_x = list_padding,
                offset_y = list_padding,
                width = function() return list_width() - list_padding() * 2 end,
                height = function() return list_height() - list_padding() * 2 end,
                clip = true,
                scroll_y = list_scroll.offset,
                on_wheel = list_scroll.wheel,
                opacity = function() return if presets_open.value then 1 else 0 end,
                transition = { opacity = function() return if presets_open.value then "content_enter" else "content_leave" end },
                g.each {
                    overlay = true,
                    attach = "corner",
                    items = function()
                        local out = {}
                        for i, preset in presets.all() do table.insert(out, { index = i, preset = preset }) end
                        return out
                    end,
                    key = function(item: any) return (if item.preset.shipped then "s:" else "u:") .. (item.preset.name or "") end,
                    row = preset_row,
                },
                list_scroll.bar(function() return list_width() - list_padding() * 2 - 7 * f() end),
            },
        },
    }

    -- A place rather than a content, like every dashed shape on this page:
    -- what is there once it is pressed is nothing.
    local blank_hovered = g.signal(false)
    local function blank_armed(): boolean return preset_armed.value == BLANK end
    local function blank_ink(): string
        if blank_armed() then return theme.alert() end
        return if blank_hovered.value then theme.primary() else theme.text()
    end
    local function blank_edge(): string
        if blank_armed() then return theme.alert() end
        return if blank_hovered.value then theme.primary() else colour.alpha(theme.line(), 0.7)
    end
    local blank_chip = g.capsule {
        role = "button",
        name = "New layout",
        height = chip_height,
        padding_left = function() return 11 * f() end,
        padding_right = function() return 15 * f() end,
        direction = "row",
        align = "center",
        gap = function() return 7 * f() end,
        radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
        rim_top = blank_edge,
        rim_bottom = blank_edge,
        dash = 3,
        dash_gap = 3,
        on_hover = function(on: boolean)
            blank_hovered.value = on
            if not on and g.untracked(blank_armed) then preset_armed.value = "" end
        end,
        on_click = function()
            presets_open.value = false
            if presets.empty() and presets.active() == "" then return end
            if not presets.kept() and not g.untracked(blank_armed) then
                preset_armed.value = BLANK
                return
            end
            preset_armed.value = ""
            leave(presets.blank)
        end,
        icon("plus", 9, blank_ink),
        meta_text(function() return if blank_armed() then "DISCARD CHANGES?" else "NEW" end, blank_ink),
    }

    -- Naming it, in place of the chips: the name of the one in use is
    -- offered, so keeping a change to it is SAVE AS and Enter.
    local naming_row = g.box {
        present = function() return naming.value end,
        direction = "row",
        align = "center",
        gap = function() return 8 * f() end,
        g.capsule {
            role = "button",
            width = function() return 220 * f() end,
            height = chip_height,
            padding_x = function() return 14 * f() end,
            direction = "row",
            align = "center",
            justify = "start",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = CLEAR,
            rim_top = theme.primary,
            rim_bottom = theme.primary,
            name_node,
        },
        -- Saying what it will do: a name already in the list is that preset
        -- written over, unless the name is one of Bioma's, which cannot be.
        choice_mod.new {
            metrics = m,
            label = function()
                local wanted = name_text.value
                if presets.reserved(wanted) then return "TAKEN" end
                local trimmed = string.match(wanted, "^%s*(.-)%s*$") or ""
                for _, preset in presets.saved() do
                    if preset.name == trimmed then return "REPLACE" end
                end
                return "SAVE"
            end,
            kind = "primary",
            dimmed = function() return presets.reserved(name_text.value) end,
            on_click = finish_naming,
        },
        choice_mod.new { metrics = m, label = "CANCEL", on_click = function() naming.value = false end },
    }

    local preset_row_node = g.box {
        width = t.width,
        height = chip_height,
        direction = "row",
        align = "center",
        g.box {
            width = function() return 76 * f() end,
            title("PRESET", function() return #presets.all() > 0 end),
        },
        g.box {
            present = function() return not naming.value end,
            direction = "row",
            align = "center",
            gap = function() return 6 * f() end,
            dropdown,
            blank_chip,
            -- Lit while there is something kept nowhere: a layout changed
            -- since its preset, or one that never had a name.
            choice_mod.new {
                metrics = m,
                label = "SAVE AS",
                kind = function() return if presets.changed() then "primary" else "plain" end,
                on_click = start_naming,
            },
        },
        naming_row,
        g.box { grow = 1 },
        -- The walk-through again, from WELCOME, in this same panel: the
        -- first start is where a layout is chosen, so a second one is asked
        -- for here. It leaves the saved presets alone.
        g.box {
            choice_mod.new {
            metrics = m,
            label = "SETUP",
            on_click = function()
                presets_open.value = false
                naming.value = false
                setup.restart(t.output)
            end,
            },
        },
    }

    -- ---- The rows --------------------------------------------------------------

    local function edge_row(edge: string): any
        local function block(): any return membrane_for(edge) end
        local slots: { [any]: any } = { direction = "row", gap = slot_gap }
        for i = 1, 3 do table.insert(slots, slot(edge, i)) end
        return g.box {
            width = t.width,
            height = function() return head() + head_spacing() + slot_height() end,
            direction = "column",
            align = "start",
            gap = head_spacing,
            g.box {
                width = t.width,
                height = head,
                direction = "row",
                align = "center",
                justify = "between",
                title(string.upper(edge), function() return block() ~= nil end),
                -- Fixed or auto-hiding is the **membrane's** answer, not a
                -- tissue's: it governs the whole edge, the dock included.
                g.box {
                    present = function() return block() ~= nil end,
                    segmented.new {
                        metrics = m,
                        font_size = meta,
                        button_height = head,
                        button_padding = function() return 10 * f() end,
                        options = function() return { { key = "fixed", label = "Fixed" }, { key = "hide", label = "Auto-hide" } } end,
                        current = function()
                            local b = block()
                            return if b and b.auto_hide == true then "hide" else "fixed"
                        end,
                        on_choose = function(key: string) set_mode(edge, key) end,
                    },
                },
            },
            g.box(slots),
        }
    end

    local function float_height(): number
        return head() + head_spacing() + 3 * slot_height() + 2 * 6 * f()
    end
    -- What floats over the screen sits between its two edges, where it
    -- actually is: nine slots in three rows. The pointer is not a place on
    -- the screen, so it is a slot of its own beside the name, shown only
    -- while a tissue is there (Akusen, 2026-10-15).
    local function float_group(): any
        local grid: { [any]: any } = { direction = "column", gap = function() return 6 * f() end }
        for row = 0, 2 do
            local line: { [any]: any } = { direction = "row", gap = slot_gap }
            for column = 1, 3 do table.insert(line, float_slot(ANCHORS[row * 3 + column], "", slot_height)) end
            table.insert(grid, g.box(line))
        end
        return g.box {
            width = t.width,
            height = float_height,
            direction = "column",
            align = "start",
            gap = head_spacing,
            g.box {
                width = t.width,
                height = head,
                direction = "row",
                align = "center",
                justify = "between",
                title("FLOATING", function() return #floats_here() > 0 end),
                g.box {
                    present = function() return float_at("pointer") ~= nil end,
                    float_slot("pointer", "POINTER", head),
                },
            },
            g.box(grid),
        }
    end

    local function several(): boolean return #monitors.outputs() > 1 end
    local function monitor_height(): number return head() + head_spacing() + head() + 6 * f() end
    -- One monitor at a time: six slots are already the most a person can
    -- hold in their eye, and two monitors' worth side by side would be
    -- twelve.
    local monitor_group = g.box {
        present = several,
        width = t.width,
        height = monitor_height,
        direction = "column",
        align = "start",
        gap = head_spacing,
        g.box { height = head, align = "center", title("MONITOR", function() return true end) },
        segmented.new {
            metrics = m,
            font_size = meta,
            button_height = head,
            button_padding = function() return 12 * f() end,
            options = function()
                local out = {}
                for _, o in monitors.outputs() do table.insert(out, { key = o.name, label = o.name }) end
                return out
            end,
            current = monitor,
            on_choose = function(key: string)
                place.monitor.value = key
                unchoose()
            end,
        },
    }

    -- ---- Where each row ends, for the thread ------------------------------------------

    local function gap(): number return 10 * f() end
    local function top_y(): number
        return chip_height() + gap() + 9 * f() + gap() + (if several() then monitor_height() + gap() else 0)
    end
    local function edge_height(): number return head() + head_spacing() + slot_height() end
    local function float_y(): number return top_y() + edge_height() + gap() end
    local function bottom_y(): number return float_y() + float_height() + gap() end
    local function layout_end(): number return bottom_y() + edge_height() end
    local function chosen_bottom(): number
        if floating_chosen() then
            local c = chosen()
            local anchor = if c then anchor_of(c) else "centre"
            if anchor == "pointer" then return float_y() + head() end
            local row = spot_of(anchor)
            return float_y() + head() + head_spacing() + (row + 1) * slot_height() + row * 6 * f()
        end
        return (if chosen_edge() == "bottom" then bottom_y() else top_y()) + edge_height()
    end
    local function chosen_column(): number
        if floating_chosen() then
            local c = chosen()
            local anchor = if c then anchor_of(c) else "centre"
            if anchor == "pointer" then return 2 end
            local _, column = spot_of(anchor)
            return column
        end
        return math.max(0, chosen_slot() - 1)
    end

    -- ---- The chosen tissue ---------------------------------------------------------

    local function well_padding(): number return 12 * f() end
    local function well_inner(): number return t.width() - well_padding() * 2 end

    -- The chips are uniform and laid out by hand: one of them follows the
    -- pointer while it is carried, and equal widths make "which slot is the
    -- hand over" the same arithmetic the dock uses.
    local function cells_here(): { any }
        local c = chosen()
        return if c and c.cells then c.cells else {}
    end
    -- Two cells of one domain in one tissue are told apart by what their
    -- block asks of them: the notification column is an urgent cell above
    -- an ordinary one.
    local function chip_label(entry: any): string
        local shown = entry.options and entry.options.show
        return string.upper(registry.name_of(entry.type) .. (if shown then " · " .. tostring(shown) else ""))
    end
    local function chip_spacing(): number return 8 * f() end
    local function chip_width(): number
        local widest = 0
        for _, entry in cells_here() do widest = math.max(widest, width_of(chip_label(entry))) end
        return math.max(62 * f(), widest + 40 * f())
    end
    local function pitch_x(): number return chip_width() + chip_spacing() end
    local function pitch_y(): number return chip_height() + chip_spacing() end
    local function per_row(): number
        return math.max(1, math.floor((well_inner() + chip_spacing()) / pitch_x()))
    end
    local function chip_rows(): number return math.max(1, math.ceil((#cells_here() + 1) / per_row())) end
    local function slot_x(i: number): number return ((i - 1) % per_row()) * pitch_x() end
    local function slot_y(i: number): number return ((i - 1) // per_row()) * pitch_y() end

    -- ---- Carrying one ----
    local held = g.signal(0)
    local gap_at = g.signal(0)
    local grip_x, grip_y = g.signal(0), g.signal(0)
    local grab_x, grab_y = 0, 0
    local function carrying(): boolean return held.value > 0 end
    -- Where a chip sits while another is being carried: the ones between the
    -- hole it left and the slot it is over move by one.
    local function resting(i: number): number
        local h, gp = held.value, gap_at.value
        if h <= 0 or i == h then return i end
        if h < gp and i > h and i <= gp then return i - 1 end
        if h > gp and i >= gp and i < h then return i + 1 end
        return i
    end
    local function take(i: number, x: number, y: number)
        grab_x, grab_y = x - g.untracked(function() return slot_x(i) end), y - g.untracked(function() return slot_y(i) end)
        g.batch(function()
            held.value = i
            gap_at.value = i
            grip_x.value = x
            grip_y.value = y
        end)
    end
    -- The slot follows the pointer and may cross as many as the hand does.
    local function carry(x: number, y: number)
        if not g.untracked(carrying) then return end
        g.batch(function()
            grip_x.value = x
            grip_y.value = y
        end)
        local column = math.round((x - grab_x) / g.untracked(pitch_x))
        local row = math.round((y - grab_y) / g.untracked(pitch_y))
        local n = #g.untracked(cells_here)
        gap_at.value = math.clamp(row * g.untracked(per_row) + column + 1, 1, math.max(1, n))
    end
    -- The one write, refused unless the result is the same cells in a
    -- different order: a tissue's contents are not worth losing to a bug.
    local function drop()
        local from, to = g.untracked(function() return held.value end), g.untracked(function() return gap_at.value end)
        g.batch(function()
            held.value = 0
            gap_at.value = 0
        end)
        if from <= 0 or to <= 0 or from == to then return end
        edit_chosen(function(tissue: any): boolean
            local cells = tissue.cells or {}
            if from > #cells or to > #cells then return false end
            local before = {}
            for _, entry in cells do table.insert(before, entry.type) end
            local moved = table.remove(cells, from)
            table.insert(cells, to, moved)
            local after = {}
            for _, entry in cells do table.insert(after, entry.type) end
            table.sort(before)
            table.sort(after)
            if table.concat(before, "\0") ~= table.concat(after, "\0") then
                print("Bioma: the settings cell refused a reorder that changed the tissue")
                return false
            end
            return true
        end)
    end

    local function cell_chip(item: () -> any): any
        local function index(): number return item().index end
        local function carried(): boolean return held.value == index() end
        local cross_over = g.signal(false)
        local pressed: { number }? = nil
        local moved = false
        local function x(): number return if carried() then grip_x.value - grab_x else slot_x(resting(index())) end
        local function y(): number return if carried() then grip_y.value - grab_y else slot_y(resting(index())) end
        local function edge(): string return if carried() then theme.primary() else theme.line() end
        return g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = x,
            offset_y = y,
            width = chip_width,
            height = chip_height,
            direction = "row",
            align = "center",
            padding_left = function() return 10 * f() end,
            padding_right = function() return 4 * f() end,
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = function() return colour.alpha(theme.lift(theme.background(), if carried() then 0.05 else 0.02), 0.9) end,
            rim_top = edge,
            rim_bottom = edge,
            transition = {
                offset_x = function() return if carried() then "instant" else "transition" end,
                offset_y = function() return if carried() then "instant" else "transition" end,
            },
            -- Carried from where it was touched, not by its middle, and it
            -- may cross several slots in one movement.
            g.box {
                role = "button",
                name = "Cell",
                grow = 1,
                height = chip_height,
                align = "center",
                justify = "start",
                -- A drag is told from the chip as it was at the press, so
                -- where it was then is kept with the press.
                on_press = function(button: number, px: number, py: number)
                    moved = false
                    pressed = if button == LEFT
                        then { px, py, g.untracked(x) + 10 * g.untracked(f), g.untracked(y) }
                        else nil
                end,
                on_drag = function(px: number, py: number)
                    if not pressed then return end
                    local ox, oy = pressed[3], pressed[4]
                    if not moved and math.abs(px - pressed[1]) + math.abs(py - pressed[2]) > 6 then
                        moved = true
                        take(g.untracked(index), ox + pressed[1], oy + pressed[2])
                        return
                    end
                    if moved then carry(ox + px, oy + py) end
                end,
                on_release = function()
                    pressed = nil
                    if moved then drop() end
                end,
                on_click = function() moved = false end,
                g.text {
                    text = function() return chip_label(item().entry) end,
                    color = theme.text,
                    font = typography.technical,
                    size = meta,
                    tracking = typography.label_tracking,
                    max_width = function() return chip_width() - 32 * f() end,
                },
            },
            g.box {
                role = "button",
                name = "Remove",
                width = function() return 18 * f() end,
                height = chip_height,
                align = "center",
                justify = "center",
                on_hover = function(on: boolean) cross_over.value = on end,
                on_click = function() remove_cell(g.untracked(index)) end,
                icon("close", 9, function() return if cross_over.value then theme.alert() else theme.text() end),
            },
        }
    end

    -- The dashed chip adds one, a place rather than a content, exactly like
    -- the empty slot above. It keeps the slot after the last cell.
    local adder = g.capsule {
        role = "button",
        name = "Add a cell",
        overlay = true,
        attach = "corner",
        offset_x = function() return slot_x(#cells_here() + 1) end,
        offset_y = function() return slot_y(#cells_here() + 1) end,
        transition = { offset_x = "transition", offset_y = "transition" },
        width = function() return 44 * f() end,
        height = chip_height,
        align = "center",
        justify = "center",
        radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
        rim_top = dashed_colour(function() return picking.value end),
        rim_bottom = dashed_colour(function() return picking.value end),
        dash = 3,
        dash_gap = 3,
        on_click = function() picking.value = not g.untracked(function() return picking.value end) end,
        icon("plus", 11, function() return if picking.value then theme.primary() else theme.text_faint() end),
    }

    -- The kinds that can still be placed, as chips under the tissue's own:
    -- only what is nowhere on this monitor yet. One that will not fit stays
    -- in the row, dimmed and saying so: seeing that the tissue is full is
    -- the answer, and hiding it would look like the cell not existing.
    local function kind_label(kind: string): string
        return string.upper(registry.name_of(kind)) .. (if fits(chosen_edge(), chosen(), kind) then "" else " · NO ROOM")
    end
    local function kind_chip(item: () -> string): any
        local hovered = g.signal(false)
        local function room(): boolean return fits(chosen_edge(), chosen(), item()) end
        local function edge(): string
            if not room() then return colour.alpha(theme.line(), 0.5) end
            return if hovered.value then theme.primary() else theme.line()
        end
        return g.capsule {
            role = "button",
            height = chip_height,
            padding_x = function() return 11 * f() end,
            align = "center",
            justify = "center",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = CLEAR,
            rim_top = edge,
            rim_bottom = edge,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function()
                if g.untracked(room) then add_cell(g.untracked(item)) end
            end,
            meta_text(function() return kind_label(item()) end, function()
                if not room() then return theme.text_faint() end
                return if hovered.value then theme.primary() else theme.text()
            end),
        }
    end
    -- How many rows the kinds take, measured as the flow lays them out.
    local function kind_rows(): number
        local list = absent()
        if #list == 0 then return 1 end
        local rows, used = 1, 0
        local room, spacing = p.inner(), 6 * f()
        for _, kind in list do
            local w = width_of(kind_label(kind)) + 22 * f()
            if used > 0 and used + spacing + w > room then
                rows += 1
                used = 0
            end
            used += (if used > 0 then spacing else 0) + w
        end
        return rows
    end

    -- What the tissue may be, and what it may not: the slider stops at the
    -- width its own cells need.
    local function alone(): boolean
        if floating_chosen() or chosen() == nil then return false end
        local block = membrane_for(chosen_edge())
        return block ~= nil and #(block.tissues or {}) == 1
    end
    local function floor(): number
        local c = chosen()
        return if c and not floating_chosen() then floor_for(chosen_edge(), c) else 0
    end
    local function share(): number
        local h = held_share.value
        if h ~= nil then return h end
        local c = chosen()
        return if c then c.percentage or 0 else 0
    end
    -- A share under the hand: shown at once, written at most once a
    -- debounce while it moves and once more when it rests.
    local share_timer: any = nil
    local function slide(value: number)
        local edge, where = chosen_edge(), chosen_place()
        if value == g.untracked(share) then return end
        held_share.value = value
        if share_timer then return end
        set_percentage(edge, where, value)
        share_timer = g.after(timing.seconds.debounce, function()
            share_timer = nil
            local last = g.untracked(function() return held_share.value end)
            if last == nil then return end
            set_percentage(edge, where, last)
            g.after(timing.seconds.debounce, function()
                if share_timer == nil and g.untracked(function() return held_share.value end) == last then held_share.value = nil end
            end)
        end)
    end

    local douser_label = "REMOVE TISSUE"
    local function douser_width(): number return 8 * f() * 2 + 9 * f() + 7 * f() + width_of(douser_label) + 6 * f() end
    local function floor_room(): number return width_of("the whole edge") end
    local function slider_width(): number
        return math.max(120 * f(), well_inner() - douser_width() - 14 * f() - floor_room() - 14 * f() - 44 * f() - 10 * f() - 70 * f())
    end

    local width_row = g.box {
        width = well_inner,
        height = function() return 30 * f() end,
        direction = "row",
        align = "center",
        -- A floating tissue has no share of anything to set, and its place
        -- is the slot it was chosen from; what is left to say is where that
        -- is and on which monitors.
        g.box {
            present = floating_chosen,
            meta_text(function()
                local c = chosen()
                if not c or not floating_chosen() then return "" end
                local screen = c.monitor or "primary"
                local where = if screen == "all" or screen == "*" then "EVERY MONITOR"
                    elseif screen == "primary" then "PRIMARY MONITOR" else screen
                return string.upper(anchor_of(c)) .. "  ·  " .. where
            end, theme.text_muted),
        },
        g.box {
            present = function() return not floating_chosen() end,
            direction = "row",
            align = "center",
            gap = function() return 10 * f() end,
            g.box { width = function() return 60 * f() end, meta_text("WIDTH", theme.text) },
            slider.new {
                width = slider_width,
                factor = f,
                dimmed = function() return false end,
                value = function() return share() / 100 end,
                on_move = function(fraction: number)
                    slide(math.max(g.untracked(floor), math.round(fraction * 100)))
                end,
            },
            g.box {
                width = function() return 44 * f() end,
                g.text {
                    text = function() return tostring(share()) .. "%" end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tabular = true,
                },
            },
        },
        g.box { grow = 1 },
        -- The floor, said rather than only enforced: a slider that stops
        -- with no reason given reads as a slider that is broken.
        g.box {
            present = function() return not floating_chosen() and (alone() or floor() > 0) end,
            padding_right = function() return 14 * f() end,
            meta_text(function() return if alone() then "the whole edge" else floor() .. "% needed" end, theme.text_faint),
        },
        -- Switching the tissue off, here rather than on the slot itself:
        -- a cross inside the slot put two presses under one.
        pill {
            label = douser_label,
            icon = "close",
            alarm = true,
            on_click = function()
                if g.untracked(floating_chosen) then
                    remove_float(g.untracked(chosen_slot))
                else
                    clear(g.untracked(chosen_edge), g.untracked(chosen_place))
                end
            end,
        },
    }

    local function well_height(): number
        local content = well_padding() * 2 + 30 * f() + 6 * f() + 22 * f() + 12 * f() + chip_rows() * pitch_y()
        if picking.value then content += 2 * f() + 1 + 10 * f() + kind_rows() * chip_height() + (kind_rows() - 1) * 6 * f() end
        return math.max(t.height() - layout_end() - thread_length(), content)
    end

    local detail = g.capsule {
        present = function() return chosen() ~= nil end,
        width = t.width,
        height = well_height,
        padding = well_padding,
        direction = "column",
        align = "start",
        justify = "start",
        radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
        rim_top = CLEAR,
        rim_bottom = CLEAR,
        width_row,
        -- Taking the tissue somewhere else: moved, or copied to another
        -- monitor. Lit while the tissue is in hand; pressed again, it puts
        -- it back.
        g.box { height = function() return 6 * f() end },
        g.box {
            width = well_inner,
            direction = "row",
            justify = "end",
            gap = function() return 8 * f() end,
            pill { label = "MOVE", lit = function() return transfer.value == "move" end, on_click = function() start_transfer("move") end },
            pill { label = "COPY", lit = function() return transfer.value == "copy" end, on_click = function() start_transfer("copy") end },
        },
        g.box { height = function() return 12 * f() end },
        -- The cells in the tissue, in the order they sit in on the membrane,
        -- from the anchor inward. Dragging one changes that order.
        g.box {
            width = well_inner,
            height = function() return chip_rows() * pitch_y() end,
            g.each {
                overlay = true,
                attach = "corner",
                -- Keyed by what the cell is, not where: a reorder moves the
                -- chips rather than building new ones under the pointer.
                items = function()
                    local out, seen = {}, {}
                    for i, entry in cells_here() do
                        local name = tostring(entry.type) .. ":" .. tostring(entry.options and entry.options.show or "")
                        seen[name] = (seen[name] or 0) + 1
                        table.insert(out, { index = i, entry = entry, key = name .. ":" .. seen[name] })
                    end
                    return out
                end,
                key = function(item: any) return item.key end,
                row = cell_chip,
            },
            adder,
        },
        -- Where what is in the tissue ends and what could be added begins.
        g.capsule {
            present = function() return picking.value end,
            width = well_inner,
            height = 1,
            crisp = true,
            rim_top = function() return colour.alpha(theme.line(), 0.7) end,
            rim_bottom = function() return colour.alpha(theme.line(), 0.7) end,
            dash = 3,
            dash_gap = 3,
        },
        g.box { present = function() return picking.value end, height = function() return 10 * f() end },
        g.text {
            present = function() return picking.value and #absent() == 0 end,
            text = "Every cell is on this monitor.",
            color = theme.text_faint,
            font = typography.expressive,
            size = function() return 14 * f() end,
            italic = true,
        },
        g.box {
            present = function() return picking.value and #absent() > 0 end,
            p.flow {
                items = absent,
                key = function(kind: string) return kind end,
                width_of = function(kind: string): number return width_of(kind_label(kind)) + 22 * f() end,
                chip = kind_chip,
            },
        },
    }

    -- The thread from the chosen slot to what it opens. It leaves the slot
    -- itself and runs *under* the rows below it, so it is never read as
    -- hanging from a slot that was not chosen.
    local link = thread_mod.new {
        vertical = true,
        overlay = true,
        attach = "corner",
        offset_x = function()
            return chosen_column() * (slot_width() + slot_gap()) + slot_width() / 2 - metrics_mod.node_size
        end,
        offset_y = chosen_bottom,
        length = function() return math.max(0, layout_end() + thread_length() - chosen_bottom()) end,
        shown = function() return chosen() ~= nil and not redrawing.value end,
        timing = function() return "grow" end,
        closing = function() return "instant" end,
    }

    return g.box {
        width = t.width,
        direction = "column",
        align = "start",
        link,
        g.box {
            width = t.width,
            direction = "column",
            align = "start",
            gap = gap,
            preset_row_node,
            -- The presets are every monitor at once, and what follows is one
            -- monitor: a hairline says the page changes subject here.
            g.box {
                width = t.width,
                height = function() return 9 * f() end,
                align = "center",
                g.capsule {
                    width = t.width,
                    height = 1,
                    crisp = true,
                    fill = function() return colour.alpha(theme.line(), 0.7) end,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                },
            },
            monitor_group,
            edge_row("top"),
            float_group(),
            edge_row("bottom"),
        },
        g.box { height = thread_length },
        detail,
        -- With nothing chosen the page says what to do once, rather than
        -- showing a large empty area under the slots.
        g.box { present = function() return chosen() == nil end, height = function() return 20 * f() end },
        g.box {
            present = function() return chosen() == nil end,
            width = t.width,
            justify = "center",
            g.text {
                text = function()
                    return if transfer.value ~= "" then "Pick a free place for it — here, or on another monitor"
                        else "Pick a tissue to see what is in it"
                end,
                color = theme.text_faint,
                font = typography.expressive,
                size = function() return m().font_title end,
            },
        },
    }
end

return M
