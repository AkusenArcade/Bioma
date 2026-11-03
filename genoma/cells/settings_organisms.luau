--!strict
-- Settings → Organisms (cells/settings/SettingsOrganisms.qml at 11bb81e):
-- what is on each desktop, and how to place it.
--
-- One well per monitor, its organisms as chips. A chip's × takes it away,
-- and a press on its name shows its options under the row. The dashed
-- chip adds one: it appears in the middle of that screen and the arranging
-- mode begins, because an organism nobody has placed is not where anybody
-- wants it. Where they are is never set here by figures: it is set by
-- hand, on the desktop itself. The weather's city is here too, because it
-- belongs to the weather and not to one organism.
--
-- A new organism is Genoma's to draw (`"runtime": "genoma"`), and Genoma
-- arranges, takes away and chooses a file for its own. One still drawn by
-- Quickshell is handed to Quickshell (`qs ipc call organisms …`), and so is
-- the arranging while no organism is Genoma's (genoma/PORT.md, "Who acts on
-- the desktop").
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local paths = require("core/paths")
local runtime = require("core/runtime")
local theme = require("core/theme")
local typography = require("core/typography")
local page = require("components/page")
local segmented = require("components/segmented")
local choice_mod = require("components/choice")
local switch = require("components/switch")
local monitors = require("services/monitors")
local weather = require("services/weather")
local arranging = require("structure/arranging")
local focus = require("structure/focus")

local M = {}

local CLEAR = "#00000000"

-- What an organism is called when it is spoken about rather than drawn
-- (organisms/Organisms.qml), in its order.
local KINDS = {
    { "clock", "Clock" }, { "media", "Media" }, { "vitals", "Vitals" }, { "calendar", "Calendar" },
    { "weather", "Weather" }, { "note", "Note" }, { "lava", "Lava lamp" }, { "cytoplasm", "Cytoplasm" },
    { "rings", "Growth rings" }, { "osmosis", "Osmosis" }, { "photoperiod", "Photoperiod" },
    { "vacuole", "Vacuole" }, { "sediment", "Sediment" }, { "nucleus", "Nucleus" }, { "adipose", "Adipose" },
    { "agenda", "Agenda" },
}
local function name_of(kind: string): string
    for _, k in KINDS do
        if k[1] == kind then return k[2] end
    end
    return kind
end

local function quickshell(args: { string }, on_line: ((string) -> ())?)
    local command = { paths.script("ipc"), "organisms" }
    for _, a in args do table.insert(command, a) end
    g.process { command = command, on_line = on_line }
end

-- Every block written from here carries an `id`, so a surface can tell one
-- organism from another when the list changes around it (Arranging.named).
local function named(list: { any }): { any }
    for _, entry in list do
        if type(entry) == "table" and (entry.id == nil or entry.id == "") then
            entry.id = string.format("%x%04x", os.time(), math.random(0, 0xffff))
        end
    end
    return list
end

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end
    local function chip_height(): number return 26 * f() end

    local function organisms(): { any }
        local list = config.get("organisms", {})
        return if type(list) == "table" then list else {}
    end

    -- Which organism's options are open, by its place in the list, and
    -- which monitor is choosing a new one.
    local chosen = g.signal(-1)
    local picking = g.signal("")
    g.watch(organisms, function(list: { any })
        if g.untracked(function() return chosen.value end) > #list then chosen.value = -1 end
    end)

    local function belongs(entry: any, screen: string): boolean
        local monitor = entry.monitor or "primary"
        if monitor == "all" or monitor == "*" then return true end
        if monitor == "primary" then return screen == monitors.primary() end
        return screen == monitor
    end
    local function here(screen: string): { number }
        local out = {}
        for i, entry in organisms() do
            if belongs(entry, screen) then table.insert(out, i) end
        end
        return out
    end
    local function open_on(screen: string): number
        local c = chosen.value
        return if table.find(here(screen), c) then c else -1
    end
    local function entry(i: number): any return organisms()[i] or {} end

    -- One key of one organism, written as the whole list.
    local function set_option(index: number, key: string, value: any)
        local next = named(config.copy_list(g.untracked(organisms)))
        if not next[index] then return end
        next[index][key] = value
        config.set("organisms", next)
    end

    -- Placing is done on the desktop, so the settings step out of the way.
    local function genoma(index: number): boolean return runtime.ours(g.untracked(organisms)[index]) end
    local function arrange()
        focus.dismiss()
        for _, e in g.untracked(organisms) do
            if runtime.ours(e) then
                arranging.start()
                return
            end
        end
        quickshell({ "arrange" })
    end
    local function add(kind: string, screen: string)
        picking.value = ""
        -- A note has nothing to show until it has a file, so the settings
        -- stay and open its options instead; it is placed once it has one.
        if kind == "note" then
            chosen.value = #g.untracked(organisms) + 1
            arranging.add(kind, screen, true)
            return
        end
        focus.dismiss()
        arranging.add(kind, screen, false)
    end
    local function remove(index: number)
        if g.untracked(function() return chosen.value end) == index then chosen.value = -1 end
        if genoma(index) then
            arranging.remove(index)
            return
        end
        -- Quickshell counts from 0.
        quickshell({ "remove", tostring(index - 1) })
    end

    -- ---- The fields: a note's file, the weather's city ----------------------------

    local typing = g.signal("") -- "file", "city" or ""
    local file_text = g.signal("")
    local city_text = g.signal("")
    local file_node, file_field = p.field {
        text = file_text,
        placeholder = "~/Notes/To-do.md",
        taking = function() return typing.value == "file" end,
    }
    local city_node, city_field = p.field {
        text = city_text,
        placeholder = "A city",
        taking = function() return typing.value == "city" end,
    }
    local readable = g.signal(false)
    local function file_of(i: number): string return (entry(i).file or "") end
    local function city(): string return string.match(config.get("weather.city", "") or "", "^%s*(.-)%s*$") or "" end
    local function expanded(path: string): string
        return if string.sub(path, 1, 1) == "~" then (g.env("HOME") or "") .. string.sub(path, 2) else path
    end

    -- Whether the open note's file can be read, asked the way the organism
    -- asks.
    g.effect(function()
        local c = chosen.value
        local path = if c > 0 and entry(c).type == "note" then file_of(c) else ""
        g.untracked(function()
            readable.value = false
            if path == "" then return end
            g.process {
                command = { "test", "-r", expanded(path) },
                on_exit = function(code: number) readable.value = code == 0 end,
            }
        end)
    end)

    local function start_typing(which: string)
        typing.value = which
        if which == "file" then file_field.set(file_of(g.untracked(function() return chosen.value end))) end
        if which == "city" then city_field.set(g.untracked(city)) end
    end

    t.keyed(function(name: string, typed: string?, mods: { [string]: boolean }): boolean
        local which = g.untracked(function() return typing.value end)
        if which == "" then return false end
        if name == "Escape" then
            typing.value = ""
            return true
        end
        if name == "Return" or name == "KP_Enter" then
            typing.value = ""
            if which == "city" then
                config.set("weather.city", string.match(g.untracked(function() return city_text.value end), "^%s*(.-)%s*$") or "")
            else
                local c = g.untracked(function() return chosen.value end)
                arranging.set_file(c, g.untracked(function() return file_text.value end))
            end
            return true
        end
        return (if which == "file" then file_field else city_field).key(name, typed, mods)
    end)

    -- ---- Shapes ------------------------------------------------------------------

    local function chip_text(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end
    local function chip_width(text: string): number
        return g.text_width {
            text = text, font = typography.technical(), size = m().font_meta,
            tracking = typography.label_tracking,
        }
    end

    local function organism_chip(screen: string): (() -> any) -> any
        return function(item: () -> any): any
            local function index(): number return item().index end
            local function lit(): boolean return chosen.value == index() end
            local cross_hovered = g.signal(false)
            return g.capsule {
                height = chip_height,
                direction = "row",
                align = "center",
                padding_left = function() return 10 * f() end,
                padding_right = function() return 4 * f() end,
                gap = function() return 4 * f() end,
                radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
                fill = function() return colour.alpha(theme.lift(theme.background(), if lit() then 0.05 else 0.02), 0.9) end,
                rim_top = function() return if lit() then theme.primary() else theme.line() end,
                rim_bottom = function() return if lit() then theme.primary() else theme.line() end,
                -- The name opens its options; the cross beside it takes it
                -- away. Two places that do not overlap.
                g.box {
                    role = "button",
                    height = chip_height,
                    align = "center",
                    on_click = function()
                        chosen.value = if g.untracked(lit) then -1 else g.untracked(index)
                        typing.value = ""
                    end,
                    chip_text(function() return string.upper(name_of(entry(index()).type or "")) end, theme.text),
                },
                g.box {
                    role = "button",
                    name = "Take away",
                    width = function() return 18 * f() end,
                    height = chip_height,
                    align = "center",
                    justify = "center",
                    on_hover = function(on: boolean) cross_hovered.value = on end,
                    on_click = function() remove(g.untracked(index)) end,
                    g.icon {
                        width = function() return 9 * f() end,
                        height = function() return 9 * f() end,
                        icon = "close",
                        color = function() return if cross_hovered.value then theme.alert() else theme.text() end,
                    },
                },
            }
        end
    end

    -- The dashed chip adds one: a place rather than a content.
    local function add_chip(screen: string): any
        local function choosing(): boolean return picking.value == screen end
        local function ink(): string return if choosing() then theme.primary() else colour.alpha(theme.line(), 0.7) end
        return g.capsule {
            role = "button",
            name = "Add an organism",
            width = function() return 44 * f() end,
            height = chip_height,
            align = "center",
            justify = "center",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            rim_top = ink,
            rim_bottom = ink,
            dash = 3,
            dash_gap = 3,
            on_click = function() picking.value = if g.untracked(choosing) then "" else screen end,
            g.icon {
                width = function() return 11 * f() end,
                height = function() return 11 * f() end,
                icon = "plus",
                color = function() return if choosing() then theme.primary() else theme.text_faint() end,
            },
        }
    end

    local function kind_chip(screen: string): (() -> any) -> any
        return function(item: () -> any): any
            local hovered = g.signal(false)
            local function ink(): string return if hovered.value then theme.primary() else theme.text() end
            return g.capsule {
                role = "button",
                height = chip_height,
                padding_x = function() return 11 * f() end,
                align = "center",
                justify = "center",
                radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
                fill = CLEAR,
                rim_top = function() return if hovered.value then theme.primary() else theme.line() end,
                rim_bottom = function() return if hovered.value then theme.primary() else theme.line() end,
                on_hover = function(on: boolean) hovered.value = on end,
                on_click = function() add(g.untracked(item).kind, screen) end,
                chip_text(function() return string.upper(item().name) end, ink),
            }
        end
    end

    local function options(opts: { { string } }): () -> { any }
        local list = {}
        for _, o in opts do table.insert(list, { key = o[1], label = o[2] }) end
        return function() return list end
    end
    local function choice(screen: string, opts: { { string } }, current: (any) -> string, write: (string) -> ()): any
        return segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            button_padding = function() return 10 * f() end,
            options = options(opts),
            current = function() local o = open_on(screen) return if o > 0 then current(entry(o)) else "" end,
            on_choose = write,
        }
    end
    local function option_row(screen: string, label: string, shown: (any) -> boolean, control: any): any
        return g.box {
            present = function() local o = open_on(screen) return o > 0 and shown(entry(o)) end,
            p.row(label, control),
        }
    end
    local function is(...: string): (any) -> boolean
        local kinds = { ... }
        return function(e: any) return table.find(kinds, e.type) ~= nil end
    end

    local function screen_well(screen: string): any
        local function open(): number return open_on(screen) end
        local function write(key: string, value: any) set_option(g.untracked(open), key, value) end
        local function choosing(): boolean return picking.value == screen end
        local function file_wrong(): boolean
            local o = open()
            return o > 0 and file_of(o) ~= "" and not readable.value
        end
        local function city_wrong(): boolean return weather.problem() ~= "" and city() ~= "" end
        local function edge(wrong: () -> boolean, which: string): () -> string
            return function()
                if wrong() then return theme.alert() end
                return if typing.value == which then theme.primary() else theme.line()
            end
        end
        local function field_row(label: string, node: any, which: string, wrong: () -> boolean, extra: any?): any
            return g.box {
                width = p.inner,
                height = function() return 34 * f() end,
                direction = "row",
                align = "center",
                gap = function() return 14 * f() end,
                p.label(label),
                g.capsule {
                    role = "button",
                    grow = 1,
                    height = function() return 34 * f() end,
                    padding_x = function() return 14 * f() end,
                    direction = "row",
                    align = "center",
                    justify = "start",
                    radius = function() return metrics_mod.radius_for(34 * f(), m()) end,
                    fill = CLEAR,
                    rim_top = edge(wrong, which),
                    rim_bottom = edge(wrong, which),
                    on_click = function() start_typing(which) end,
                    node,
                },
                extra or g.box {},
            }
        end

        return section(screen, nil, {
            p.flow {
                items = function()
                    local out = {}
                    for _, i in here(screen) do table.insert(out, { kind = "organism", index = i }) end
                    table.insert(out, { kind = "add", index = 0 })
                    return out
                end,
                key = function(item: any) return item.kind .. tostring(item.index) end,
                width_of = function(item: any): number
                    if item.kind == "add" then return 44 * f() end
                    return chip_width(string.upper(name_of(entry(item.index).type or ""))) + 40 * f()
                end,
                chip = function(item: () -> any): any
                    if g.untracked(item).kind == "add" then return add_chip(screen) end
                    return organism_chip(screen)(item)
                end,
            },
            -- Where what is on this desktop ends and what could be added
            -- begins.
            g.capsule {
                present = choosing,
                width = p.inner,
                height = 1,
                crisp = true,
                rim_top = function() return colour.alpha(theme.line(), 0.7) end,
                rim_bottom = function() return colour.alpha(theme.line(), 0.7) end,
                dash = 3,
                dash_gap = 3,
            },
            -- The kinds there are, while one is being added.
            g.box {
                present = choosing,
                p.flow {
                    items = function()
                        local out = {}
                        for _, k in KINDS do table.insert(out, { kind = k[1], name = k[2] }) end
                        return out
                    end,
                    key = function(item: any) return item.kind end,
                    width_of = function(item: any): number return chip_width(string.upper(item.name)) + 22 * f() end,
                    chip = kind_chip(screen),
                },
            },
            -- The options of the organism whose chip is lit.
            option_row(screen, "SIZE", function() return true end,
                choice(screen, { { "", "Membranes" }, { "compact", "Compact" }, { "normal", "Normal" }, { "comfortable", "Comfortable" } },
                    function(e: any) return e.size or "" end,
                    function(key: string) write("size", if key ~= "" then key else nil) end)),
            option_row(screen, "VISUALISER", is("media"), switch.new {
                factor = f,
                on = function() local o = open() return o > 0 and entry(o).band ~= false end,
                on_toggle = function(value: boolean) write("band", if value then nil else false) end,
            }),
            option_row(screen, "BOOT", is("adipose"), switch.new {
                factor = f,
                on = function() local o = open() return o > 0 and entry(o).system == true end,
                on_toggle = function(value: boolean) write("system", if value then true else nil) end,
            }),
            option_row(screen, "NAMES", is("cytoplasm", "vacuole", "sediment"), switch.new {
                factor = f,
                on = function() local o = open() return o > 0 and entry(o).labels ~= false end,
                on_toggle = function(value: boolean) write("labels", if value then nil else false) end,
            }),
            option_row(screen, "DEPTH", is("sediment"),
                choice(screen, { { "8", "8" }, { "16", "16" }, { "32", "32" } },
                    function(e: any) return tostring(e.depth or 16) end,
                    function(key: string) write("depth", if key == "16" then nil else tonumber(key)) end)),
            option_row(screen, "LAYOUT", is("vitals"),
                choice(screen, { { "row", "Row" }, { "square", "Square" } },
                    function(e: any) return if e.layout == "square" then "square" else "row" end,
                    function(key: string) write("layout", if key == "square" then key else nil) end)),
            option_row(screen, "COLOUR", is("lava", "cytoplasm", "adipose"),
                choice(screen, { { "state", "State" }, { "theme", "Theme" } },
                    function(e: any) return if e.colour == "theme" then "theme" else "state" end,
                    function(key: string) write("colour", if key == "theme" then key else nil) end)),
            option_row(screen, "HEIGHT", is("note"),
                choice(screen, { { "short", "2 × 1" }, { "medium", "2 × 2" }, { "tall", "2 × 3" } },
                    function(e: any) return e.height or "medium" end,
                    function(key: string) write("height", if key == "medium" then nil else key) end)),
            -- A note's file: the path, typed or chosen, and why it cannot
            -- be read when it cannot.
            g.box {
                present = function() local o = open() return o > 0 and entry(o).type == "note" end,
                direction = "column",
                gap = function() return 8 * f() end,
                field_row("FILE", g.box {
                    g.text {
                        present = function() return typing.value ~= "file" end,
                        text = function() local o = open() local path = if o > 0 then file_of(o) else "" return if path ~= "" then path else "No file yet" end,
                        color = function() local o = open() return if o > 0 and file_of(o) ~= "" then theme.text() else theme.text_faint() end,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                        max_width = function() return p.inner() * 0.6 end,
                    },
                    g.box { present = function() return typing.value == "file" end, file_node },
                }, "file", file_wrong, p.offer("CHOOSE", function()
                    -- The picker is a window: the settings step out of its way.
                    local o = g.untracked(open)
                    focus.dismiss()
                    if genoma(o) then arranging.choose_file(o) else quickshell({ "chooseFile", tostring(o - 1) }) end
                end)),
                g.box {
                    present = function() return file_wrong() or arranging.picker_error() ~= "" end,
                    direction = "row",
                    align = "center",
                    gap = function() return 8 * f() end,
                    g.icon { width = function() return 14 * f() end, height = function() return 14 * f() end, icon = "error", color = theme.alert },
                    line(function()
                        return if arranging.picker_error() ~= "" then arranging.picker_error()
                            else "This file cannot be read, so the note is not shown."
                    end, theme.alert),
                },
            },
            -- A weather organism's city: one place for every weather
            -- organism, and the photoperiod's, whose sky is over it.
            g.box {
                present = function() local o = open() return o > 0 and is("weather", "photoperiod")(entry(o)) end,
                direction = "column",
                gap = function() return 8 * f() end,
                field_row("CITY", g.box {
                    g.text {
                        present = function() return typing.value ~= "city" end,
                        text = function() return if city() ~= "" then city() else "A city" end,
                        color = function() return if city() ~= "" then theme.text() else theme.text_faint() end,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                    },
                    g.box { present = function() return typing.value == "city" end, city_node },
                }, "city", city_wrong),
                g.box {
                    present = city_wrong,
                    direction = "row",
                    align = "center",
                    gap = function() return 8 * f() end,
                    g.icon { width = function() return 14 * f() end, height = function() return 14 * f() end, icon = "error", color = theme.alert },
                    line(weather.problem, theme.alert),
                },
            },
            line(function()
                if #here(screen) == 0 then return "Nothing stands on this desktop. The dashed chip adds an organism here." end
                local o = open()
                if o <= 0 then return "Press an organism for its options, or its cross to take it away." end
                local kind = entry(o).type
                if kind == "weather" or kind == "photoperiod" then
                    if city() == "" then return "Every weather and photoperiod organism reads this city. Enter keeps it." end
                    local located = config.get("weather.latitude", nil) ~= nil and config.get("weather.located_for", "") == city()
                    if not located then return "Looking for it…" end
                    local place = config.get("weather.place", "")
                    if place == "" then place = city() end
                    if kind == "photoperiod" then
                        return "The sky over " .. place .. ", worked out here from where it is: the same place the weather reads."
                    end
                    return "Read for " .. place .. ", every " .. config.get("weather.minutes", 30) .. " minutes, from Open-Meteo: the same place for every weather organism."
                end
                return "Its size follows the membranes unless it is given its own."
            end),
        })
    end

    return p.column {
        g.each {
            direction = "column",
            gap = function() return 10 * f() end,
            items = function()
                local out = {}
                for _, o in monitors.outputs() do table.insert(out, o.name) end
                return out
            end,
            key = function(name: string) return name end,
            row = function(name: () -> string) return screen_well(g.untracked(name)) end,
        },
        -- ---- Placing ------------------------------------------------------------
        section("ARRANGE", choice_mod.new { label = "Arrange", kind = "primary", metrics = m, on_click = arrange }, {
            line(function() return "Lifts the organisms above the windows, to be dragged into place on any screen. Done, or Escape, puts them back." end),
        }),
    }
end

return M
