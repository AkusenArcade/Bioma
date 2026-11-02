--!strict
-- Settings → Actions (cells/settings/SettingsActions.qml at 11bb81e): the
-- macros the ring at the pointer runs.
--
-- Four wells, top to bottom, the order a macro is made in. The macros, as
-- the round capsules the ring shows, in the ring's order, and a dashed NEW.
-- The one chosen: its name, its icon, RUN to try it and DELETE. Its steps,
-- one row each, read as a sentence; a press opens the row on what that step
-- holds, and the arrows beside it move it or remove it. And the steps that
-- can be added, one dashed chip for each kind. Everything is written as it
-- is changed. Running stays Bioma on Quickshell's (`actions run`).
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local apps = require("core/apps")
local presets = require("core/presets")
local page = require("components/page")
local segmented = require("components/segmented")
local slider = require("components/slider")
local choice_mod = require("components/choice")
local field_mod = require("components/field")
local actions = require("services/actions")
local monitors = require("services/monitors")
local wallpaper = require("services/wallpaper")
local picker = require("services/picker")

local M = {}

local CLEAR = "#00000000"

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end
    local function chip_height(): number return 28 * f() end
    local function capsule(): number return 36 * f() end
    local function step_row(): number return 34 * f() end

    -- ---- The list ------------------------------------------------------------

    -- Read raw, so a position on this page is a position in what is written.
    local function macros(): { any }
        local list = config.get("actions.macros", {})
        return if type(list) == "table" then list else {}
    end
    local selected = g.signal(1)
    local function macro(): any return macros()[selected.value] end
    local function steps(): { any } local mc = macro() return if mc and type(mc.steps) == "table" then mc.steps else {} end
    -- The step whose row is open, or 0.
    local editing = g.signal(0)
    local deleting = g.signal(false)
    g.watch(function() return selected.value end, function()
        editing.value = 0
        deleting.value = false
    end)

    local function change(mutate: ({ any }) -> ())
        local list = config.copy_list(g.untracked(macros))
        for _, mc in list do
            if type(mc.steps) == "table" then mc.steps = config.copy_list(mc.steps) end
        end
        mutate(list)
        actions.write_list(list)
    end
    local function free_name(base: string): string
        local name, n = base, 1
        local function taken(x: string): boolean
            for _, mc in g.untracked(macros) do if mc.name == x then return true end end
            return false
        end
        while taken(name) do
            n += 1
            name = base .. " " .. n
        end
        return name
    end
    local function add_macro()
        local count = #g.untracked(macros)
        if count >= actions.ring_size then return end
        local icon = actions.icons[(count % #actions.icons) + 1]
        change(function(list) table.insert(list, { name = free_name("Action"), icon = icon, steps = g.array({}) }) end)
        selected.value = count + 1
    end
    local function move_macro(delta: number)
        local at = g.untracked(function() return selected.value end)
        local to = at + delta
        if not g.untracked(macro) or to < 1 or to > #g.untracked(macros) then return end
        change(function(list) table.insert(list, to, table.remove(list, at)) end)
        selected.value = to
    end
    local function delete_macro()
        if not g.untracked(macro) then return end
        if not g.untracked(function() return deleting.value end) then
            deleting.value = true
            return
        end
        local at = g.untracked(function() return selected.value end)
        deleting.value = false
        change(function(list) table.remove(list, at) end)
        selected.value = math.max(1, math.min(at, #g.untracked(macros) - 1))
    end
    local function set_icon(name: string)
        local at = g.untracked(function() return selected.value end)
        change(function(list) list[at].icon = name end)
    end
    local function set_step(index: number, patch: { [string]: any })
        local at = g.untracked(function() return selected.value end)
        change(function(list)
            local step = list[at].steps[index]
            if step then for k, v in patch do step[k] = v end end
        end)
    end
    local function add_step(kind: string)
        local k = actions.kinds[kind]
        if not g.untracked(macro) or not k then return end
        local at = g.untracked(function() return selected.value end)
        change(function(list)
            local mc = list[at]
            mc.steps = mc.steps or g.array({})
            table.insert(mc.steps, k.fresh())
        end)
        editing.value = #g.untracked(steps)
    end
    local function move_step(index: number, delta: number)
        local to = index + delta
        if to < 1 or to > #g.untracked(steps) then return end
        local at = g.untracked(function() return selected.value end)
        change(function(list) local s = list[at].steps table.insert(s, to, table.remove(s, index)) end)
        if g.untracked(function() return editing.value end) == index then editing.value = to end
    end
    local function remove_step(index: number)
        local at = g.untracked(function() return selected.value end)
        change(function(list) table.remove(list[at].steps, index) end)
        local e = g.untracked(function() return editing.value end)
        if e == index then editing.value = 0 elseif e > index then editing.value = e - 1 end
    end

    -- ---- Fields: the name, a launch's search, a file's path, a command ----------

    local typing = g.signal("") -- "name", "search", "path", "command" or ""
    local texts: { [string]: any } = {}
    local fields: { [string]: any } = {}
    local nodes: { [string]: any } = {}
    local placeholders = {
        name = "A name for the ring", search = "Search applications",
        path = "A file, or ~/a/file", command = "A shell command",
    }
    for _, which in { "name", "search", "path", "command" } do
        texts[which] = g.signal("")
        nodes[which], fields[which] = field_mod.new {
            text = texts[which],
            width = function() return p.inner() - 80 * f() end,
            font = typography.expressive,
            size = function() return m().font_secondary end,
            placeholder = placeholders[which],
            taking = function() return typing.value == which end,
        }
    end

    -- A name is the macro's address (the ring says it, the key runs it), so
    -- it is neither empty nor another macro's.
    local function shown_name(): string local mc = macro() return if mc then tostring(mc.name or "") else "" end
    local function name_problem(): string
        local name = string.match(if typing.value == "name" then texts.name.value else shown_name(), "^%s*(.-)%s*$") or ""
        if name == "" then return "A quick action needs a name." end
        for i, mc in macros() do
            if i ~= selected.value and mc.name == name then return "Another quick action already has this name." end
        end
        return ""
    end
    local function commit(which: string)
        local text = g.untracked(function() return texts[which].value end)
        local e = g.untracked(function() return editing.value end)
        if which == "name" then
            if g.untracked(name_problem) == "" then
                local name = string.match(text, "^%s*(.-)%s*$") or ""
                local at = g.untracked(function() return selected.value end)
                if name ~= g.untracked(shown_name) then change(function(list) list[at].name = name end) end
            end
        elseif which == "path" and e > 0 then
            set_step(e, { path = string.match(text, "^%s*(.-)%s*$") or "" })
        elseif which == "command" and e > 0 then
            set_step(e, { command = text })
        end
    end
    local function start(which: string, initial: string)
        local before = g.untracked(function() return typing.value end)
        if before ~= "" and before ~= "search" then commit(before) end
        typing.value = which
        fields[which].set(initial)
    end
    g.watch(function() return editing.value end, function() typing.value = "" end)

    t.keyed(function(name: string, typed: string?, mods: { [string]: any }): boolean
        local which = g.untracked(function() return typing.value end)
        if which == "" then return false end
        if name == "Escape" then
            typing.value = ""
            return true
        end
        if name == "Return" or name == "KP_Enter" then
            commit(which)
            typing.value = ""
            return true
        end
        return fields[which].key(name, typed, mods)
    end)

    -- ---- Shapes ------------------------------------------------------------------

    local function meta(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color or theme.text,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end
    local function muted(text: () -> string): any return line(text, theme.text_muted) end

    -- A round capsule with a glyph: a macro in the ring, or an icon to give it.
    local function glyph(icon: () -> string, chosen: () -> boolean, size: () -> number, on_click: () -> ()): any
        local hovered = g.signal(false)
        local function edge(): string
            if chosen() then return theme.primary() end
            return if hovered.value then theme.text() else theme.line()
        end
        return g.capsule {
            role = "button",
            width = size,
            height = size,
            radius = function() return size() / 2 end,
            align = "center",
            justify = "center",
            fill = function() return if chosen() then colour.alpha(theme.primary(), 0.14) else CLEAR end,
            rim_top = edge,
            rim_bottom = edge,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = on_click,
            g.icon {
                width = function() return 20 * f() end,
                height = function() return 20 * f() end,
                icon = icon,
                color = theme.text,
                gradient_top = function() return if chosen() then theme.gradient_top(theme.primary()) else theme.text() end,
                gradient_bottom = function() return if chosen() then theme.gradient_bottom(theme.primary()) else theme.text() end,
            },
        }
    end

    -- A small press on a row: move.
    local function tool(icon: string, dimmed: () -> boolean, on_click: () -> ()): any
        local hovered = g.signal(false)
        return g.box {
            role = "button",
            width = function() return 22 * f() end,
            height = function() return 22 * f() end,
            align = "center",
            justify = "center",
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = function() if not g.untracked(dimmed) then on_click() end end,
            g.icon {
                width = function() return 11 * f() end,
                height = function() return 11 * f() end,
                icon = icon,
                color = function()
                    local c = if hovered.value and not dimmed() then theme.primary() else theme.text()
                    return colour.alpha(c, if dimmed() then 0.3 else 1)
                end,
            },
        }
    end

    local function outlined(which: string, shown: () -> string, wrong: () -> boolean, width: (() -> number)?): any
        local function edge(): string
            if wrong() then return theme.alert() end
            return if typing.value == which then theme.primary() else theme.line()
        end
        return g.capsule {
            role = "button",
            width = width or p.inner,
            height = chip_height,
            padding_x = function() return 14 * f() end,
            direction = "row",
            align = "center",
            justify = "start",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = CLEAR,
            rim_top = edge,
            rim_bottom = edge,
            on_click = function() start(which, g.untracked(shown)) end,
            g.text {
                present = function() return typing.value ~= which end,
                text = function() local s = shown() return if s ~= "" then s else placeholders[which] end,
                color = function() return if shown() ~= "" then theme.text() else theme.text_faint() end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                max_width = function() return (if width then width() else p.inner()) - 30 * f() end,
            },
            g.box { present = function() return typing.value == which end, nodes[which] },
        }
    end

    -- A slider with its figure, for a value with a unit. Written at most once
    -- a debounce while the hand moves, and again at rest.
    local function amount(index: () -> number, key: string, fallback: number, from: number, to: number, step: number, unit: string): any
        local held = g.signal(nil :: number?)
        local timer: any = nil
        local function value(): number
            local h = held.value
            if h ~= nil then return h end
            local s = steps()[index()]
            return if s and s[key] ~= nil then s[key] else fallback
        end
        local function put(v: number) set_step(g.untracked(index), { [key] = v }) end
        return g.box {
            width = function() return p.inner() - 44 * f() end,
            height = chip_height,
            direction = "row",
            align = "center",
            gap = function() return 12 * f() end,
            slider.new {
                width = function() return p.inner() - 44 * f() - 64 * f() - 12 * f() end,
                factor = f,
                dimmed = function() return false end,
                value = function() return (value() - from) / (to - from) end,
                on_move = function(fraction: number)
                    local v = math.round((from + fraction * (to - from)) / step) * step
                    if v == g.untracked(value) then return end
                    held.value = v
                    if timer then return end
                    put(v)
                    timer = g.after(timing.seconds.debounce, function()
                        timer = nil
                        local last = g.untracked(function() return held.value end)
                        if last ~= nil then put(last) end
                        g.after(timing.seconds.debounce, function()
                            if timer == nil and g.untracked(function() return held.value end) == last then held.value = nil end
                        end)
                    end)
                end,
            },
            g.box {
                width = function() return 64 * f() end,
                justify = "end",
                g.text {
                    text = function() return tostring(math.round(value() * 10) / 10) .. unit end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tabular = true,
                },
            },
        }
    end

    local function on_off(index: () -> number): any
        return segmented.new {
            metrics = m,
            options = function() return { { key = "on", label = "ON" }, { key = "off", label = "OFF" } } end,
            current = function() local s = steps()[index()] return if s and s.on then "on" else "off" end,
            on_choose = function(key: string) set_step(g.untracked(index), { on = key == "on" }) end,
        }
    end

    -- ---- What each kind of step is edited with -------------------------------------

    local editors: { [string]: (() -> number) -> any } = {}

    editors.launch = function(index)
        local matches = g.computed(function(): { any }
            local query = string.lower(string.match(texts.search.value, "^%s*(.-)%s*$") or "")
            local out = {}
            for _, e in apps.entries() do
                if query == "" or string.find(string.lower(e.name), query, 1, true) or string.find(string.lower(e.id), query, 1, true) then
                    table.insert(out, e)
                end
            end
            table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
            while #out > 5 do table.remove(out) end
            return out
        end)
        return g.box {
            direction = "column",
            gap = function() return 8 * f() end,
            outlined("search", function() return "" end, function() return false end, function() return p.inner() - 44 * f() end),
            g.each {
                direction = "column",
                items = function() return matches.value end,
                key = function(e: any) return e.id end,
                row = function(e: () -> any)
                    return p.app {
                        icon = function() return if e().icon ~= "" then (g.icon_path(e().icon) or "") else "" end,
                        name = function() return e().name end,
                        detail = function() local s = steps()[index()] return if s and s.app == e().id then "CHOSEN" else "" end,
                        on_choose = function() set_step(g.untracked(index), { app = g.untracked(e).id }) end,
                    }
                end,
            },
            muted(function() return "It opens wherever niri's window rules put it: an open-on-workspace rule places it on a workspace." end),
        }
    end

    editors.open = function(index)
        local choosing = g.signal(false)
        local function path(): string local s = steps()[index()] return if s then tostring(s.path or "") else "" end
        return g.box {
            direction = "column",
            gap = function() return 8 * f() end,
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 8 * f() end,
                outlined("path", path, function() return false end, function() return p.inner() - 44 * f() - 100 * f() end),
                choice_mod.new {
                    label = function() return if choosing.value then "CHOOSING" else "CHOOSE" end,
                    metrics = m,
                    dimmed = function() return choosing.value end,
                    on_click = function()
                        choosing.value = true
                        picker.choose {
                            title = "A file to open",
                            on_chosen = function(chosen: string?)
                                choosing.value = false
                                if chosen and chosen ~= "" then set_step(g.untracked(index), { path = chosen }) end
                            end,
                        }
                    end,
                },
            },
            muted(function() return "Opened in the application that opens files of its kind." end),
        }
    end

    editors.volume = function(index) return amount(index, "percent", 50, 0, 100, 5, "%") end
    editors.brightness = function(index) return amount(index, "percent", 70, 1, 100, 5, "%") end
    editors.timer = function(index) return amount(index, "minutes", 25, 5, 120, 5, " min") end
    editors.wait = function(index) return amount(index, "seconds", 2, 0.5, 30, 0.5, " s") end
    editors.quiet = on_off
    editors.performance = on_off

    editors.profile = function(index)
        return segmented.new {
            metrics = m,
            options = function()
                return { { key = "saver", label = "SAVER" }, { key = "balanced", label = "BALANCED" }, { key = "performance", label = "PERFORMANCE" } }
            end,
            current = function() local s = steps()[index()] return if s then s.profile or "balanced" else "balanced" end,
            on_choose = function(key: string) set_step(g.untracked(index), { profile = key }) end,
        }
    end

    editors.settings = function(index)
        local function entry(): any return steps()[index()] or {} end
        local function groups(): { string } return entry().groups or {} end
        local row: { [any]: any } = { direction = "row", gap = function() return 6 * f() end }
        for _, group in actions.groups do
            table.insert(row, choice_mod.new {
                label = group.label,
                kind = function() return if table.find(groups(), group.key) then "primary" else "plain" end,
                metrics = m,
                on_click = function()
                    local current = g.untracked(groups)
                    local on = table.find(current, group.key) ~= nil
                    local next = g.array({})
                    for _, k in current do if k ~= group.key then table.insert(next, k) end end
                    if not on then table.insert(next, group.key) end
                    -- A group taken out takes its values with it; one put in
                    -- is captured as it is now.
                    local values = table.clone(g.untracked(entry).values or {})
                    if on then
                        for _, path in group.paths do values[path] = nil end
                    else
                        for k, v in actions.capture({ group.key }) do values[k] = v end
                    end
                    set_step(g.untracked(index), { groups = next, values = values })
                end,
            })
        end
        table.insert(row, choice_mod.new {
            label = "CAPTURE NOW",
            metrics = m,
            on_click = function() set_step(g.untracked(index), { values = actions.capture(g.untracked(groups)) }) end,
        })
        return g.box {
            direction = "column",
            gap = function() return 8 * f() end,
            g.box(row),
            line(function()
                if #groups() == 0 then return "Nothing is kept: choose what this step puts back." end
                local s = actions.summary(entry())
                return "Puts back " .. string.lower(string.sub(s, 1, 1)) .. string.sub(s, 2) .. ". CAPTURE NOW keeps the settings as they are this moment instead."
            end),
        }
    end

    editors.monitor = function(index)
        local function entry(): any return steps()[index()] or {} end
        return g.box {
            direction = "column",
            gap = function() return 8 * f() end,
            segmented.new {
                metrics = m,
                options = function()
                    local out = {}
                    for _, o in monitors.outputs() do table.insert(out, { key = o.name, label = o.name }) end
                    for _, o in monitors.off() do table.insert(out, { key = o.name, label = o.name }) end
                    return out
                end,
                current = function() return entry().output or "" end,
                on_choose = function(key: string) set_step(g.untracked(index), { output = key }) end,
            },
            on_off(index),
            muted(function() return "One monitor at a time, and never the last one on: a quick action cannot leave the desktop dark." end),
        }
    end

    editors.preset = function(index)
        return p.flow {
            items = presets.all,
            key = function(pr: any) return pr.name end,
            width_of = function(pr: any): number
                return g.text_width { text = string.upper(pr.name), font = typography.technical(), size = math.round(12 * f()), tracking = 0.04 } + 24 * f()
            end,
            chip = function(pr: () -> any)
                return choice_mod.new {
                    label = function() return string.upper(pr().name) end,
                    kind = function() local s = steps()[index()] return if s and s.name == pr().name then "primary" else "plain" end,
                    metrics = m,
                    on_click = function() set_step(g.untracked(index), { name = g.untracked(pr).name }) end,
                }
            end,
        }
    end

    editors.wallpaper = function(index)
        return g.box {
            direction = "column",
            gap = function() return 8 * f() end,
            p.flow {
                items = wallpaper.favourites,
                key = function(path: string) return path end,
                width_of = function(): number return 88 * f() end,
                chip = function(path: () -> string)
                    local hovered = g.signal(false)
                    local function chosen(): boolean local s = steps()[index()] return s ~= nil and s.path == path() end
                    return g.capsule {
                        role = "button",
                        width = function() return 88 * f() end,
                        height = function() return 54 * f() end,
                        radius = function() return 6 * f() end,
                        fill = CLEAR,
                        rim_top = function() if chosen() then return theme.primary() end return if hovered.value then theme.text() else CLEAR end,
                        rim_bottom = function() if chosen() then return theme.primary() end return if hovered.value then theme.text() else CLEAR end,
                        on_hover = function(on: boolean) hovered.value = on end,
                        on_click = function() set_step(g.untracked(index), { path = g.untracked(path) }) end,
                        g.image {
                            overlay = true,
                            src = function() return wallpaper.thumbnail(path()) end,
                            width = function() return 82 * f() end,
                            height = function() return 48 * f() end,
                            fit = "cover",
                            radius = function() return 4 * f() end,
                        },
                    }
                end,
            },
            muted(function()
                return if #wallpaper.favourites() > 0 then "One of the favourites, starred in the theme cell's grid."
                    else "No favourites yet. Star wallpapers in the theme cell's grid and they are offered here."
            end),
        }
    end

    editors.command = function(index)
        local function command(): string local s = steps()[index()] return if s then tostring(s.command or "") else "" end
        return g.box {
            direction = "column",
            gap = function() return 8 * f() end,
            outlined("command", command, function() return false end, function() return p.inner() - 44 * f() end),
            muted(function() return "Run by sh, in the background. Enter keeps it." end),
        }
    end

    -- ---- The wells -----------------------------------------------------------------

    local ring = section("QUICK ACTIONS", nil, {
        p.flow {
            gap = function() return 8 * f() end,
            items = function()
                local out = {}
                for i, mc in macros() do table.insert(out, { kind = "macro", index = i, name = mc.name }) end
                if #macros() < actions.ring_size then table.insert(out, { kind = "new", index = 0 }) end
                return out
            end,
            key = function(item: any) return if item.kind == "new" then "new" else item.index .. tostring(item.name) end,
            width_of = function(item: any): number
                if item.kind == "new" then
                    return 42 * f() + g.text_width { text = "NEW", font = typography.technical(), size = m().font_meta, tracking = typography.label_tracking }
                end
                return capsule()
            end,
            chip = function(item: () -> any)
                if g.untracked(item).kind == "new" then return g.box { height = capsule, align = "center", p.offer("NEW", add_macro) } end
                return glyph(function() return actions.icon_of(macros()[item().index]) end,
                    function() return item().index == selected.value end, capsule,
                    function() selected.value = g.untracked(item).index end)
            end,
        },
        line(function()
            local n, size = #macros(), actions.ring_size
            if n == 0 then return "None yet. A quick action is a list of steps run one after the other, from a ring that comes to the pointer on Mod+Alt+Space." end
            if n > size then return "The first " .. size .. " are in the ring, in this order; the rest run from a key of their own." end
            if n == size then return "The ring is full: " .. size .. ", clockwise from the top. Delete one to write another." end
            return "In the ring in this order, clockwise from the top. Each also runs from a key of its own: qs ipc call actions run and its name."
        end),
    })

    local icons_row = p.flow {
        items = function() return actions.icons end,
        key = function(name: string) return name end,
        width_of = function(): number return 32 * f() end,
        chip = function(name: () -> string)
            return glyph(name, function() local mc = macro() return mc ~= nil and actions.icon_of(mc) == name() end,
                function() return 32 * f() end, function() set_icon(g.untracked(name)) end)
        end,
    }

    local chosen = section(function()
        return if selected.value <= actions.ring_size then "IN THE RING · " .. selected.value else "NOT IN THE RING"
    end, g.box {
        direction = "row",
        align = "center",
        gap = function() return 6 * f() end,
        tool("chevron-left", function() return selected.value <= 1 end, function() move_macro(-1) end),
        tool("chevron-right", function() return selected.value >= #macros() end, function() move_macro(1) end),
        choice_mod.new {
            label = "RUN",
            metrics = m,
            dimmed = function() return #steps() == 0 end,
            on_click = function() local mc = g.untracked(macro) if mc then actions.run(mc.name) end end,
        },
        choice_mod.new {
            label = function() return if deleting.value then "DELETE?" else "DELETE" end,
            kind = function() return if deleting.value then "alert" else "plain" end,
            metrics = m,
            on_click = delete_macro,
        },
    }, {
        outlined("name", shown_name, function() return name_problem() ~= "" end),
        g.box {
            present = function() return name_problem() ~= "" end,
            direction = "row",
            align = "center",
            gap = function() return 6 * f() end,
            g.icon { width = function() return 12 * f() end, height = function() return 12 * f() end, icon = "error", color = theme.alert },
            g.text { text = name_problem, color = theme.alert, font = typography.expressive, size = function() return m().font_secondary end },
        },
        icons_row,
    }, function() return macro() ~= nil end)

    local function step_line(item: () -> any): any
        local hovered = g.signal(false)
        local function index(): number return item().index end
        local function open(): boolean return editing.value == index() end
        local function step(): any return steps()[index()] or {} end
        return g.box {
            direction = "column",
            gap = function() return 8 * f() end,
            g.capsule {
                role = "button",
                width = p.inner,
                height = step_row,
                direction = "row",
                align = "center",
                padding_left = function() return 10 * f() end,
                padding_right = function() return 4 * f() end,
                radius = function() return metrics_mod.radius_for(step_row(), m()) end,
                fill = function()
                    if open() then return colour.alpha(theme.primary(), 0.10) end
                    return if hovered.value then colour.alpha(theme.text(), 0.05) else CLEAR
                end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function() editing.value = if g.untracked(open) then 0 else g.untracked(index) end,
                g.box { width = function() return 18 * f() end, meta(function() return tostring(index()) end, theme.text_muted) },
                g.box { width = function() return 118 * f() end, meta(function() return actions.label_of(step()) end) },
                g.text {
                    text = function() return actions.describe(step()) end,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    max_width = function() return p.inner() - 136 * f() - 90 * f() end,
                },
                g.box { grow = 1 },
                g.box {
                    direction = "row",
                    gap = function() return 2 * f() end,
                    opacity = function() return if hovered.value or open() then 1 else 0 end,
                    tool("chevron-up", function() return index() == 1 end, function() move_step(g.untracked(index), -1) end),
                    tool("chevron-down", function() return index() == #steps() end, function() move_step(g.untracked(index), 1) end),
                    p.remove(function() remove_step(g.untracked(index)) end),
                },
            },
            g.box {
                present = open,
                padding_left = function() return 34 * f() end,
                g.each {
                    items = function()
                        local s = step()
                        return if open() and editors[s.type or ""] then { (s.type or "") .. index() } else {}
                    end,
                    key = function(k: string) return k end,
                    row = function()
                        return editors[g.untracked(step).type](index)
                    end,
                },
            },
        }
    end

    local steps_well = section("STEPS", nil, {
        g.box {
            present = function() return #steps() == 0 end,
            line(function() return "No steps yet: add them below. They run from the top, each once the one before has finished." end),
        },
        g.each {
            direction = "column",
            gap = function() return 8 * f() end,
            items = function()
                local out = {}
                for i, s in steps() do table.insert(out, { index = i, type = s.type }) end
                return out
            end,
            key = function(item: any) return item.index .. tostring(item.type) end,
            row = step_line,
        },
    }, function() return macro() ~= nil end)

    local adder = section("ADD A STEP", nil, {
        p.flow {
            items = function() return actions.order end,
            key = function(k: string) return k end,
            width_of = function(k: string): number
                return 42 * f() + g.text_width { text = actions.kinds[k].label, font = typography.technical(), size = m().font_meta, tracking = typography.label_tracking }
            end,
            chip = function(k: () -> string)
                return p.offer(actions.kinds[g.untracked(k)].label, function() add_step(g.untracked(k)) end)
            end,
        },
    }, function() return macro() ~= nil end)

    return p.column { ring, chosen, steps_well, adder }
end

return M
