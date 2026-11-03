--!strict
-- Settings → Keybinds (cells/settings/SettingsKeybinds.qml at 11bb81e):
-- the keys, added, edited and removed.
--
-- Every bind niri reads, one row each, in the order niri reads them: what
-- the bind does and the keys that do it, as keycaps. A combination is
-- recorded by pressing it, not by typing it: the pencil turns the keycaps
-- into a field that listens, and the next key pressed with its modifiers is
-- the new combination, written as soon as it is pressed. While the field
-- listens niri's own shortcuts stand aside, or pressing a combination that
-- is taken would do what it is taken for. A taken combination is refused
-- where it was pressed, saying by what; Escape leaves the bind as it was,
-- and the cross that replaces the pencil removes it.
--
-- A new shortcut starts from what it does: the dashed chip opens a picker
-- on a thread (the cells first, then niri's own actions), and what is
-- chosen arrives at the end of the list already listening for its keys.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local paths = require("core/paths")
local theme = require("core/theme")
local typography = require("core/typography")
local page = require("components/page")
local field_mod = require("components/field")
local thread_mod = require("components/thread")
local keybinds = require("services/keybinds")
local registry = require("cells/registry")

local M = {}

local CLEAR = "#00000000"

-- niri names keys by their keysym at the first level, so `Mod+Shift+1`,
-- never `Mod+Shift+exclam`: the digit row and the punctuation are read by
-- where they are (the xkb keycode), letters and named keys by their name.
local BY_POSITION = {
    [10] = "1", [11] = "2", [12] = "3", [13] = "4", [14] = "5", [15] = "6", [16] = "7", [17] = "8", [18] = "9", [19] = "0",
    [20] = "Minus", [21] = "Equal", [34] = "BracketLeft", [35] = "BracketRight", [47] = "Semicolon", [48] = "Apostrophe",
    [49] = "Grave", [51] = "Backslash", [59] = "Comma", [60] = "Period", [61] = "Slash", [94] = "Less",
}
local NAMED = {
    space = "Space", Return = "Return", KP_Enter = "KP_Enter", Escape = "Escape", Tab = "Tab", ISO_Left_Tab = "Tab",
    BackSpace = "BackSpace", Delete = "Delete", Insert = "Insert", Home = "Home", End = "End",
    Prior = "Page_Up", Page_Up = "Page_Up", Next = "Page_Down", Page_Down = "Page_Down",
    Up = "Up", Down = "Down", Left = "Left", Right = "Right", Print = "Print", Pause = "Pause", Menu = "Menu",
}
local MODIFIERS = {
    Super_L = "Mod", Super_R = "Mod", Meta_L = "Mod", Meta_R = "Mod", Control_L = "Ctrl", Control_R = "Ctrl",
    Alt_L = "Alt", Alt_R = "Alt", Shift_L = "Shift", Shift_R = "Shift", ISO_Level3_Shift = "", Hyper_L = "", Hyper_R = "",
}

local function key_name(name: string, code: number): string
    local by = BY_POSITION[code]
    if by then return by end
    local named = NAMED[name]
    if named then return named end
    if string.match(name, "^XF86") then return name end
    if string.match(name, "^F%d+$") then return name end
    if string.match(name, "^%a$") then return string.upper(name) end
    return ""
end

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    local function m(): any return t.metrics() end
    local function width(): number return t.width() end
    local function list_row(): number return 38 * f() end
    local function picker_row(): number return 36 * f() end
    local function picker_width(): number return 220 * f() end
    local function field_width(): number return 230 * f() end
    local function field_height(): number return 30 * f() end
    local function chip_height(): number return 26 * f() end
    local function footer_height(): number return 44 * f() end
    local function slot_width(): number return 28 * f() end
    local function header_row(): number return 26 * f() end

    -- ---- What is being done ------------------------------------------------

    -- The bind whose keys are being recorded, by id; or "new" for the one
    -- being added, whose action is in `adding`.
    local recording = g.signal("")
    local adding = g.signal(nil :: any)
    -- What the field has heard so far: the modifiers held now, and the last
    -- combination refused, with what it belongs to.
    local held = g.signal({} :: { string })
    local refused = g.signal("")
    local refused_by = g.signal("")
    local picking = g.signal(false)
    local searching = g.signal(false)
    local hovered_file = g.signal("")
    local function listening(): boolean return recording.value ~= "" end

    local search_text = g.signal("")
    local search_node, search = field_mod.new {
        text = search_text,
        width = function() return width() - 140 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        placeholder = "Search shortcuts",
        taking = function() return searching.value end,
    }
    local filter_text = g.signal("")
    local filter_node, filter = field_mod.new {
        text = filter_text,
        width = function() return picker_width() - 12 * f() - 28 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        placeholder = "What should it do?",
        taking = function() return picking.value end,
    }

    -- What the search asks for. Words that are all names of keys are a
    -- combination, and find the binds that use every one of them; anything
    -- else is looked for in what the bind does.
    local words = g.computed(function(): { string }
        local out = {}
        for w in string.gmatch(string.lower(search_text.value), "[^%s%+]+") do
            if w == "mod" or w == "win" or w == "meta" then w = "super" elseif w == "control" then w = "ctrl" end
            table.insert(out, w)
        end
        return out
    end)
    local found = g.computed(function(): { any }
        local list = keybinds.binds()
        local ws = words.value
        if #ws == 0 then return list end
        local names: { [string]: boolean } = {}
        for _, b in list do for _, c in b.caps do names[string.lower(c)] = true end end
        local combination = true
        for _, w in ws do if not names[w] then combination = false end end
        local out = {}
        for _, b in list do
            local caps = {}
            for _, c in b.caps do table.insert(caps, string.lower(c)) end
            local label = string.lower(b.label)
            local ok = true
            for _, w in ws do
                local in_caps = table.find(caps, w) ~= nil
                if combination then ok = ok and in_caps
                else ok = ok and (in_caps or string.find(label, w, 1, true) ~= nil) end
            end
            if ok then table.insert(out, b) end
        end
        return out
    end)
    local rows = g.computed(function(): { any }
        local out = table.clone(found.value)
        local a = adding.value
        if a then table.insert(out, { id = "new", label = a.label, caps = {}, file = keybinds.main, shadowed = false }) end
        return out
    end)

    local function bind_of(id: string): any
        for _, b in g.untracked(keybinds.binds) do
            if b.id == id then return b end
        end
        return nil
    end
    local function stop()
        recording.value = ""
        adding.value = nil
        held.value = {}
        refused.value = ""
        refused_by.value = ""
    end
    local function listen(id: string)
        searching.value = false
        recording.value = id
        held.value = {}
        refused.value = ""
        refused_by.value = ""
    end
    local function edit(b: any)
        picking.value = false
        adding.value = nil
        listen(b.id)
    end
    local function drop(id: string)
        local b = bind_of(id)
        stop()
        if b then keybinds.remove(b) end
    end

    -- A combination heard in full: refused if it is taken by anything but
    -- the bind being edited, and written otherwise.
    local function heard(combination: string)
        local which = g.untracked(function() return recording.value end)
        local taken = keybinds.owner(combination, if which == "new" then nil else which)
        if taken then
            refused.value = combination
            refused_by.value = taken.label
            held.value = {}
            return
        end
        if which == "new" then
            local a = g.untracked(function() return adding.value end)
            keybinds.add(combination, a.action, a.title)
        else
            local b = bind_of(which)
            if b then keybinds.rekey(b, combination) end
        end
        stop()
    end

    -- ---- The picker's choices --------------------------------------------------

    -- Through `scripts/ipc`, which reaches the shell on either runtime.
    local function shell_call(args: { string }): { name: string, args: { string } }
        local out = { paths.root .. "/scripts/ipc" }
        for _, a in args do table.insert(out, a) end
        return { name = "spawn", args = out }
    end
    local choices = g.computed(function(): { any }
        local wanted = string.lower(string.match(filter_text.value, "^%s*(.-)%s*$") or "")
        local function keep(label: string): boolean return wanted == "" or string.find(string.lower(label), wanted, 1, true) ~= nil end
        local out = {}
        for _, pair in registry.catalogue do
            local label = pair[2]
            if keep(label) then
                table.insert(out, { group = "CELLS", label = label, title = "Bioma: " .. string.lower(label),
                    action = shell_call({ "cell", "toggle", pair[1] }) })
            end
        end
        if keep("Timer: start or pause") then
            table.insert(out, { group = "CELLS", label = "Timer: start or pause", title = "Bioma: timer", action = shell_call({ "timer", "toggle" }) })
        end
        if keep("Performance mode: on or off") then
            table.insert(out, { group = "CELLS", label = "Performance mode: on or off", title = "Bioma: performance mode",
                action = shell_call({ "performance", "toggle" }) })
        end
        for _, name in keybinds.actions() do
            local label = keybinds.humanize(name)
            if keep(label) then table.insert(out, { group = "NIRI", label = label, title = "", action = { name = name, args = {} } }) end
        end
        return out
    end)
    local function pick(on: boolean)
        stop()
        searching.value = false
        picking.value = on
        if not on then return end
        keybinds.ask_actions()
        filter.set("")
    end
    local function choose(choice: any)
        picking.value = false
        adding.value = choice
        listen("new")
    end

    -- ---- The keys ----------------------------------------------------------------

    t.keyed(function(name: string, typed: string?, mods: { [string]: any }): boolean
        if g.untracked(listening) then
            local function held_mods(): { string }
                local out = {}
                if mods.logo then table.insert(out, "Mod") end
                if mods.ctrl then table.insert(out, "Ctrl") end
                if mods.alt then table.insert(out, "Alt") end
                if mods.shift then table.insert(out, "Shift") end
                return out
            end
            local own = MODIFIERS[name]
            if own ~= nil then
                -- Its own flag is not yet in the modifiers on the press that
                -- sets it.
                local list = held_mods()
                if own ~= "" and not table.find(list, own) then table.insert(list, own) end
                local caps = keybinds.keycaps(table.concat(list, "+") .. "+")
                table.remove(caps)
                held.value = caps
                return true
            end
            local list = held_mods()
            if name == "Escape" and #list == 0 then
                stop()
                return true
            end
            local key = key_name(name, mods.code or 0)
            if key ~= "" then
                table.insert(list, key)
                heard(table.concat(list, "+"))
            end
            return true
        end
        if g.untracked(function() return picking.value end) then
            if name == "Escape" then
                picking.value = false
                return true
            end
            if name == "Return" or name == "KP_Enter" then
                local first = g.untracked(function() return choices.value end)[1]
                if first then choose(first) end
                return true
            end
            return filter.key(name, typed, mods)
        end
        if g.untracked(function() return searching.value end) then
            -- Escape empties the search first and gives the keyboard back
            -- second.
            if name == "Escape" then
                if g.untracked(function() return search_text.value end) ~= "" then search.set("") else searching.value = false end
                return true
            end
            return search.key(name, typed, mods)
        end
        return false
    end)

    -- ---- Shapes ------------------------------------------------------------------

    local function meta(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end

    local function row(r: () -> any): any
        local hovered = g.signal(false)
        local slot_hovered = g.signal(false)
        local function live(): boolean return recording.value == r().id end
        local function is_new(): boolean return r().id == "new" end
        local function refusing(): boolean return refused.value ~= "" and #held.value == 0 end
        return g.box {
            width = function() return width() - 24 * f() end,
            height = list_row,
            direction = "row",
            align = "center",
            padding_left = function() return 10 * f() end,
            gap = function() return 6 * f() end,
            on_hover = function(on: boolean)
                hovered.value = on
                if on then hovered_file.value = g.untracked(r).file
                elseif g.untracked(function() return hovered_file.value end) == g.untracked(r).file then hovered_file.value = "" end
            end,
            g.text {
                text = function() return r().label end,
                -- Overridden by a bind read later: there, and faint.
                color = function() return if r().shadowed then theme.text_faint() else theme.text() end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                max_width = function() return width() * 0.45 end,
            },
            g.box { grow = 1 },
            -- The keys, as keycaps.
            g.each {
                present = function() return not live() end,
                direction = "row",
                gap = function() return 6 * f() end,
                items = function()
                    local out = {}
                    for i, c in r().caps do table.insert(out, { i = i, c = c }) end
                    return out
                end,
                key = function(c: any) return c.i .. c.c end,
                row = function(c: () -> any) return p.keycap(function() return c().c end, function() return r().shadowed end) end,
            },
            -- Listening: the keycaps become a field.
            g.capsule {
                present = live,
                width = field_width,
                height = field_height,
                direction = "row",
                align = "center",
                padding_left = function() return 4 * f() end,
                gap = function() return 4 * f() end,
                radius = function() return metrics_mod.radius_for(field_height(), m()) end,
                fill = CLEAR,
                rim_top = function() return if refusing() then theme.alert() else theme.primary() end,
                rim_bottom = function() return if refusing() then theme.alert() else theme.primary() end,
                stroke = 1.5,
                transition = { rim_top = "transition", rim_bottom = "transition" },
                -- niri answers its own shortcuts before any surface hears
                -- them; while the field listens they stand aside for it.
                inhibit_shortcuts = live,
                g.each {
                    present = function() return #held.value > 0 end,
                    direction = "row",
                    gap = function() return 4 * f() end,
                    items = function()
                        local out = {}
                        for i, c in held.value do table.insert(out, { i = i, c = c }) end
                        return out
                    end,
                    key = function(c: any) return c.i .. c.c end,
                    row = function(c: () -> any)
                        return p.keycap(function() return c().c end, nil, function() return field_height() - 8 * f() end)
                    end,
                },
                g.box {
                    present = function() return #held.value == 0 end,
                    direction = "row",
                    align = "center",
                    padding_left = function() return 10 * f() end,
                    gap = function() return 3 * f() end,
                    g.text {
                        text = function()
                            if refusing() then
                                return table.concat(keybinds.keycaps(refused.value), " ") .. " is already " .. refused_by.value
                            end
                            return "Press a combination…"
                        end,
                        color = function() return if refusing() then theme.alert() else theme.text_muted() end,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return field_width() - 30 * f() end,
                    },
                    -- The caret: the field is listening. It does not blink.
                    g.capsule {
                        present = function() return not refusing() end,
                        width = 1,
                        height = function() return m().font_secondary + 2 * f() end,
                        crisp = true,
                        fill = theme.primary,
                        rim_top = CLEAR,
                        rim_bottom = CLEAR,
                    },
                },
            },
            -- The pencil, or (listening) the cross that removes it.
            g.box {
                role = "button",
                name = "Edit or remove",
                width = slot_width,
                height = list_row,
                align = "center",
                justify = "center",
                on_hover = function(on: boolean) slot_hovered.value = on end,
                on_click = function()
                    if g.untracked(function() return picking.value end) or g.untracked(keybinds.busy) then return end
                    if not g.untracked(live) then edit(g.untracked(r))
                    elseif g.untracked(is_new) then stop()
                    else drop(g.untracked(r).id) end
                end,
                g.icon {
                    width = function() return (if live() then 10 else 13) * f() end,
                    height = function() return (if live() then 10 else 13) * f() end,
                    icon = function() return if live() then "close" else "edit" end,
                    color = function()
                        if slot_hovered.value or live() then return theme.text() end
                        return theme.text_faint()
                    end,
                },
            },
        }
    end

    -- ---- The list, in a well, scrolling --------------------------------------------

    local function well_height(): number return t.height() - footer_height() - m().field_height - 10 * f() end
    local scroll_offset = g.signal(0)
    local function content_height(): number return #rows.value * list_row() end
    local function max_offset(): number return math.max(0, content_height() - (well_height() - 12 * f())) end
    g.watch(function() return #rows.value end, function()
        -- The row being added is at the end, and it has to be seen.
        if g.untracked(function() return adding.value end) then scroll_offset.value = g.untracked(max_offset) end
    end)

    local list_well = g.capsule {
        width = width,
        height = well_height,
        radius = function() return metrics_mod.inner_radius(m().radius_panel, 6 * f()) end,
        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
        rim_top = CLEAR,
        rim_bottom = CLEAR,
        -- Picking is about the picker; the list stays where it was, quieter.
        opacity = function() return if picking.value then 0.35 else 1 end,
        transition = { opacity = "transition" },
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = function() return 6 * f() end,
            offset_y = function() return 6 * f() end,
            width = function() return width() - 12 * f() end,
            height = function() return well_height() - 12 * f() end,
            clip = true,
            scroll_y = function() return math.clamp(scroll_offset.value, 0, max_offset()) end,
            transition = { scroll_y = "reflow" },
            on_wheel = function(_: number, dy: number)
                scroll_offset.value = math.clamp(g.untracked(function() return scroll_offset.value end) + dy * 40 * g.untracked(f), 0, g.untracked(max_offset))
            end,
            g.each {
                overlay = true,
                attach = "corner",
                direction = "column",
                items = function() return rows.value end,
                key = function(r: any) return r.id end,
                row = row,
            },
        },
        g.text {
            overlay = true,
            present = function() return #rows.value == 0 end,
            text = function() return if #words.value > 0 then "Nothing bound to that" else "Reading niri's configuration…" end,
            color = theme.text_faint,
            font = typography.expressive,
            size = function() return m().font_secondary end,
        },
    }

    -- ---- The search ------------------------------------------------------------------
    --
    -- The vitals search, the same object: a lens in the primary, no well of
    -- its own, and the count said in words on the other side.
    local search_row = g.box {
        role = "button",
        width = width,
        height = function() return m().field_height end,
        direction = "row",
        align = "center",
        gap = function() return 10 * f() end,
        padding_left = function() return 6 * f() end,
        padding_right = function() return 6 * f() end,
        on_click = function()
            stop()
            picking.value = false
            searching.value = true
        end,
        g.icon {
            width = function() return 16 * f() end,
            height = function() return 16 * f() end,
            icon = "search",
            gradient_top = function() return theme.gradient_top(theme.primary()) end,
            gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
        },
        g.box { grow = 1, search_node },
        g.text {
            text = function()
                return if #words.value == 0 then keybinds.count() .. " shortcuts" else #found.value .. " of " .. keybinds.count()
            end,
            color = theme.text_muted,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        },
    }

    -- ---- The foot of the page, and the picker hanging off it -----------------------

    local function short_path(path: string): string
        local home = g.env("HOME") or ""
        return if home ~= "" and string.sub(path, 1, #home) == home then "~" .. string.sub(path, #home + 1) else path
    end
    local function adder_width(): number
        return g.text_width { text = "+ Shortcut", font = typography.technical(), size = m().font_meta, tracking = typography.label_tracking } + 28 * f()
    end
    local function groups(): number
        local seen = {}
        for _, c in choices.value do if not table.find(seen, c.group) then table.insert(seen, c.group) end end
        return #seen
    end
    local function picker_height(): number
        return math.min(t.height() - footer_height() / 2 - chip_height() / 2,
            34 * f() + 12 * f() + math.max(1, #choices.value) * picker_row() + groups() * header_row() + 20 * f())
    end

    -- The choices with their group headings between, as one list.
    local picker_rows = g.computed(function(): { any }
        local out, last = {}, ""
        for i, c in choices.value do
            if c.group ~= last then
                table.insert(out, { key = "h" .. c.group, heading = c.group })
                last = c.group
            end
            table.insert(out, { key = c.group .. i .. c.label, choice = c })
        end
        return out
    end)
    local picker_offset = g.signal(0)
    local function picker_max(): number
        local h = 0
        for _, item in picker_rows.value do h += if item.heading then header_row() else picker_row() end
        return math.max(0, h - (picker_height() - 50 * f()))
    end
    g.watch(function() return filter_text.value end, function() picker_offset.value = 0 end)

    local function picker_item(item: () -> any): any
        local hovered = g.signal(false)
        if g.untracked(item).heading then
            return g.box {
                width = function() return picker_width() - 12 * f() end,
                height = header_row,
                align = "end",
                padding_left = function() return 8 * f() end,
                meta(function() return item().heading end, theme.text_faint),
            }
        end
        return g.box {
            role = "button",
            width = function() return picker_width() - 12 * f() end,
            height = picker_row,
            direction = "row",
            align = "center",
            padding_left = function() return 8 * f() end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function() choose(g.untracked(item).choice) end,
            g.text {
                text = function() return item().choice.label end,
                color = function() return if hovered.value then theme.primary() else theme.text() end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                max_width = function() return picker_width() - 28 * f() end,
            },
        }
    end

    local picker = g.capsule {
        name = "picker",
        overlay = true,
        attach = "corner",
        raised = true,
        present = function() return picking.value end,
        offset_x = function() return adder_width() + m().gap end,
        -- It grows up from the chip it hangs from, as far as the page goes.
        offset_y = function() return footer_height() / 2 + chip_height() / 2 - picker_height() end,
        width = picker_width,
        height = picker_height,
        radius = function() return metrics_mod.inner_radius(m().radius_panel, 6 * f()) end,
        fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.95) end,
        rim_top = theme.line,
        rim_bottom = theme.line,
        on_press = function() end,
        on_click = function() end,
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() return 6 * f() end,
            offset_y = function() return 6 * f() end,
            width = function() return picker_width() - 12 * f() end,
            height = function() return 34 * f() end,
            padding_x = function() return 14 * f() end,
            direction = "row",
            align = "center",
            radius = function() return metrics_mod.radius_for(34 * f(), m()) end,
            fill = CLEAR,
            rim_top = function() return if picking.value then theme.primary() else theme.line() end,
            rim_bottom = function() return if picking.value then theme.primary() else theme.line() end,
            filter_node,
        },
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = function() return 6 * f() end,
            offset_y = function() return 6 * f() + 34 * f() + 4 * f() end,
            width = function() return picker_width() - 12 * f() end,
            height = function() return picker_height() - 50 * f() end,
            clip = true,
            scroll_y = function() return math.clamp(picker_offset.value, 0, picker_max()) end,
            transition = { scroll_y = "reflow" },
            on_wheel = function(_: number, dy: number)
                picker_offset.value = math.clamp(g.untracked(function() return picker_offset.value end) + dy * 40 * g.untracked(f), 0, g.untracked(picker_max))
            end,
            g.each {
                overlay = true,
                attach = "corner",
                direction = "column",
                items = function() return picker_rows.value end,
                key = function(item: any) return item.key end,
                row = picker_item,
            },
        },
    }

    local foot = g.box {
        width = width,
        height = footer_height,
        direction = "row",
        align = "center",
        gap = function() return 12 * f() end,
        g.capsule {
            role = "button",
            name = "Add a shortcut",
            width = adder_width,
            height = chip_height,
            align = "center",
            justify = "center",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            rim_top = function() return if picking.value then theme.primary() else colour.alpha(theme.line(), 0.7) end,
            rim_bottom = function() return if picking.value then theme.primary() else colour.alpha(theme.line(), 0.7) end,
            dash = 3,
            dash_gap = 3,
            on_click = function()
                if not g.untracked(keybinds.busy) then pick(not g.untracked(function() return picking.value end)) end
            end,
            meta("+ Shortcut", function() return if picking.value then theme.primary() else theme.text() end),
            picker,
        },
        thread_mod.new {
            vertical = false,
            overlay = true,
            attach = "corner",
            offset_x = adder_width,
            offset_y = function() return footer_height() / 2 - metrics_mod.node_size end,
            length = function() return m().gap end,
            shown = function() return picking.value end,
            timing = function() return "grow" end,
        },
        -- What is true right now, in one line: what niri refused, how to get
        -- out of the field, which file the row under the pointer lives in,
        -- or where all of this is written.
        g.box {
            grow = 1,
            justify = "end",
            g.text {
                text = function()
                    if keybinds.error() ~= "" then return keybinds.error() end
                    if listening() then return "Esc leaves it as it was" end
                    if picking.value then return "Enter takes the first" end
                    if hovered_file.value ~= "" then return short_path(hovered_file.value) end
                    return "reads and rewrites niri's binds, where they are written"
                end,
                color = function() return if keybinds.error() ~= "" then theme.alert() else theme.text_faint() end,
                font = typography.technical,
                size = function() return m().font_meta end,
                tracking = typography.label_tracking,
                max_width = function() return width() * 0.6 end,
            },
        },
    }

    return g.box {
        width = width,
        height = t.height,
        direction = "column",
        gap = function() return 10 * f() end,
        search_row,
        list_well,
        foot,
    }
end

return M
