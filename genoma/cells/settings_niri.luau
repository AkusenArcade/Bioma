--!strict
-- Settings → Niri (cells/settings/SettingsNiri.qml at 11bb81e): a few of
-- niri's settings without opening niri's files (the gaps, the focus ring,
-- the focus following the pointer, the named workspaces, what starts with
-- the session, and what the window rules say about each application).
--
-- One well per setting, a line in Spectral saying what the current choice
-- does and in which file it is written, rows that open on what they hold.
-- A window rule is shown as the application it is about, and only its
-- opacity, its width and its workspace are edited here; the rest of what it
-- says is counted and left alone. Everything is written as it is changed,
-- into niri's own files, by Bioma on Quickshell for now.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local apps = require("core/apps")
local page = require("components/page")
local slider = require("components/slider")
local switch = require("components/switch")
local choice_mod = require("components/choice")
local field_mod = require("components/field")
local niri_settings = require("services/niri_settings")
local monitors = require("services/monitors")
local niri = require("services/niri")

local M = {}

local CLEAR = "#00000000"

local function file_name(path: string): string
    local parts = string.split(path, "/")
    return parts[#parts]
end
-- The files a set of items is written in, as a sentence's end.
local function written_in(list: { any }): string
    local names = {}
    for _, item in list do
        local n = file_name(item.file)
        if not table.find(names, n) then table.insert(names, n) end
    end
    return if #names == 0 then file_name(niri_settings.main) else table.concat(names, " and ")
end

-- An app-id pattern as a person would say it: `^org\.gnome\.Nautilus$` is
-- org.gnome.Nautilus, `.*` is every window; one anchored at the start only
-- is a family of applications, shown as written.
local function plain(pattern: string): any
    if pattern == ".*" or pattern == "^.*$" then return { plain = true, all = true, id = "" } end
    local prefix = string.sub(pattern, 1, 1) == "^" and string.sub(pattern, -1) ~= "$"
    local stripped = string.gsub(string.gsub(string.gsub(pattern, "^%^", ""), "%$$", ""), "\\%.", ".")
    local fine = string.match(stripped, "^[%w_ %-][%w%._ %-]*[%w_%-]$") ~= nil
    return { plain = not prefix and fine, all = false, id = stripped }
end
local function rule_app(rule: any): any
    local first = nil
    for _, match in rule.matches do if match["app-id"] ~= nil then first = match break end end
    local pattern = first["app-id"]
    local id = plain(pattern)
    if id.all then return { name = "Every window", icon = "", pattern = pattern } end
    local entry = if id.plain then apps.entry_for(id.id) else nil
    return {
        name = if entry then entry.name elseif id.plain then id.id else pattern,
        icon = if entry and entry.icon ~= "" then (g.icon_path(entry.icon) or "") else "",
        pattern = pattern,
    }
end
local function width_words(width: any): string
    if width.kind == "proportion" then return math.round(width.value * 100) .. "% wide" end
    if width.kind == "fixed" then return math.round(width.value) .. " px wide" end
    return "as wide as it asks"
end
local function rule_summary(rule: any): string
    local out = {}
    local apps_n = 0
    for _, match in rule.matches do if match["app-id"] ~= nil then apps_n += 1 end end
    if apps_n > 1 then table.insert(out, "and " .. (apps_n - 1) .. " more") end
    -- The rule for every window gives its opacity to WINDOW OPACITY.
    if rule.opacity ~= nil and not niri_settings.every_window(rule) then
        table.insert(out, math.round(rule.opacity * 100) .. "% opaque in focus")
    end
    if rule.width ~= nil then table.insert(out, width_words(rule.width)) end
    if rule.workspace ~= nil then table.insert(out, "on " .. rule.workspace) end
    if #out == (if apps_n > 1 then 1 else 0) then table.insert(out, "nothing set here") end
    return table.concat(out, " · ")
end
-- What else the rule says, which this page leaves alone.
local function rule_rest(rule: any): { string }
    local parts = {}
    local more = #rule.matches - 1
    if more > 0 then table.insert(parts, more .. (if more == 1 then " more match" else " more matches")) end
    for _, match in rule.matches do if match.title ~= nil then table.insert(parts, "titles") break end end
    if rule.excludes > 0 then table.insert(parts, rule.excludes .. (if rule.excludes == 1 then " exclusion" else " exclusions")) end
    if rule.others > 0 then table.insert(parts, rule.others .. (if rule.others == 1 then " other setting" else " other settings")) end
    return parts
end
local function startup_app(item: any): any
    if item.sh then return { name = item.args[1] or "", icon = "", command = "sh" } end
    local program = file_name(tostring(item.args[1] or ""))
    local entry = apps.entry_for(program)
    local command = table.concat(item.args, " ")
    local name = if entry then entry.name else program
    return {
        name = name,
        icon = if entry and entry.icon ~= "" then (g.icon_path(entry.icon) or "") else "",
        -- Said once: `Telegram` started by `Telegram` is one word.
        command = if string.lower(command) == string.lower(name) then "" else command,
    }
end

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end
    local function busy(): boolean return niri_settings.busy() end
    local function muted(text: () -> string): any return line(text, theme.text_muted) end
    local function meta(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color or theme.text,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end

    -- A slider with its figure, for a value with a unit. `write` once the
    -- hand rests; `value` may be nil for one that is not set.
    local function amount(value: () -> number?, write: (number) -> (), from: number, to: number, step: number, unit: string, width: (() -> number)?): any
        local held = g.signal(nil :: number?)
        local timer: any = nil
        local function shown(): number? local h = held.value if h ~= nil then return h end return value() end
        local function w(): number return if width then width() else p.inner() end
        return g.box {
            width = w,
            height = function() return 28 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 12 * f() end,
            slider.new {
                width = function() return w() - 64 * f() - 12 * f() end,
                factor = f,
                dimmed = busy,
                value = function() local v = shown() return if v then (v - from) / (to - from) else 0 end,
                on_move = function(fraction: number)
                    local v = math.round((from + fraction * (to - from)) / step) * step
                    held.value = v
                    if timer then timer:stop() end
                    timer = g.after(timing.seconds.debounce, function()
                        timer = nil
                        write(v)
                        g.after(1.2, function()
                            if timer == nil and g.untracked(function() return held.value end) == v then held.value = nil end
                        end)
                    end)
                end,
            },
            g.box {
                width = function() return 64 * f() end,
                justify = "end",
                g.text {
                    text = function() local v = shown() return if v then tostring(math.round(v * 10) / 10) .. unit else "—" end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tabular = true,
                },
            },
        }
    end

    -- A small press on a row.
    -- A small press on a row: move (components/page.luau, p.tool).
    local TOOL_NAMES = { ["chevron-up"] = "Move up", ["chevron-down"] = "Move down", ["chevron-left"] = "Move earlier", ["chevron-right"] = "Move later" }
    local function tool(icon: string, dimmed: () -> boolean, on_click: () -> ()): any
        return p.tool(icon, TOOL_NAMES[icon] or icon, dimmed, on_click, busy)
    end

    -- A row that opens on what it holds: its icon, its name, a summary, and
    -- its tools at the end.
    local function headline(a: { [string]: any }): any
        local hovered = g.signal(false)
        return g.capsule {
            role = "button",
            width = p.inner,
            height = function() return 34 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 10 * f() end,
            padding_left = function() return 10 * f() end,
            padding_right = function() return 4 * f() end,
            radius = function() return metrics_mod.radius_for(34 * f(), m()) end,
            fill = function()
                if a.open() then return colour.alpha(theme.primary(), 0.10) end
                return if hovered.value and a.openable then colour.alpha(theme.text(), 0.05) else CLEAR
            end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = a.on_click,
            g.icon { present = function() return a.icon and a.icon() ~= "" end, width = function() return 18 * f() end, height = function() return 18 * f() end, icon = function() return if a.icon then a.icon() else "" end },
            g.text {
                text = a.name,
                color = function() return if a.faint and a.faint() then theme.text_faint() else theme.text() end,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                max_width = function() return p.inner() * 0.4 end,
            },
            g.text {
                text = a.summary,
                color = theme.text_muted,
                font = typography.technical,
                size = function() return m().font_meta end,
                tracking = typography.label_tracking,
                max_width = function() return p.inner() * 0.35 end,
            },
            g.box { grow = 1 },
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 2 * f() end,
                opacity = function() return if hovered.value or a.open() then 1 else theme.tool_rest end,
                table.unpack(a.tools or {}),
            },
            a.trailing,
        }
    end

    -- ---- Fields and the picker -----------------------------------------------------

    local typing = g.signal("") -- "workspace", "command", "search_app", "search_rule" or ""
    local texts: { [string]: any } = {}
    local fields: { [string]: any } = {}
    local nodes: { [string]: any } = {}
    local search = "Search open windows and applications"
    local placeholders = { workspace = "A name", command = "A shell command", search_app = search, search_rule = search }
    for _, which in { "workspace", "command", "search_app", "search_rule" } do
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

    local open_ws = g.signal("") -- the open workspace's id
    local open_rule = g.signal("")
    local adding_startup = g.signal("") -- "app", "command" or ""
    local adding_rule = g.signal(false)

    local function ws_by_id(id: string): any
        for _, ws in niri_settings.workspaces() do if niri_settings.id(ws) == id then return ws end end
        return nil
    end
    local function workspace_problem(): string
        if typing.value ~= "workspace" then return "" end
        return niri_settings.workspace_problem(texts.workspace.value, ws_by_id(open_ws.value))
    end

    local function commit(which: string)
        local text = g.untracked(function() return texts[which].value end)
        if which == "workspace" then
            local ws = ws_by_id(g.untracked(function() return open_ws.value end))
            if ws and niri_settings.workspace_problem(text, ws) == "" then
                local name = string.match(text, "^%s*(.-)%s*$") or ""
                if name ~= ws.name then niri_settings.rename_workspace(ws, name) end
            end
        elseif which == "command" then
            if string.match(text, "%S") then niri_settings.add_startup(text, true) end
            adding_startup.value = ""
        end
    end
    local function start(which: string, initial: string)
        local before = g.untracked(function() return typing.value end)
        if before ~= "" and before ~= which and string.sub(before, 1, 6) ~= "search" then commit(before) end
        typing.value = which
        fields[which].set(initial)
    end

    -- The windows open now first (their app-id is read, not guessed), then
    -- the installed applications.
    local function matches_for(which: string): () -> { any }
      local found = g.computed(function(): { any }
        local wanted = string.lower(string.match(texts[which].value, "^%s*(.-)%s*$") or "")
        local function fits(...: string): boolean
            if wanted == "" then return true end
            for _, w in { ... } do if string.find(string.lower(w or ""), wanted, 1, true) then return true end end
            return false
        end
        local seen, out = {}, {}
        for _, w in niri.windows() do
            local id = w.app_id or ""
            if id ~= "" and not seen[string.lower(id)] then
                local entry = apps.entry_for(id)
                if fits(id, if entry then entry.name else "") then
                    seen[string.lower(id)] = true
                    table.insert(out, { app_id = id, entry = entry, open = true, name = if entry then entry.name else id, icon = if entry then entry.icon else "" })
                end
            end
        end
        local installed = {}
        for _, e in apps.entries() do
            local id = if e.startup_class ~= "" then e.startup_class else e.id
            if id ~= "" and not seen[string.lower(id)] and fits(e.name, e.id) then
                seen[string.lower(id)] = true
                table.insert(installed, { app_id = id, entry = e, open = false, name = e.name, icon = e.icon })
            end
        end
        table.sort(installed, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
        for _, e in installed do
            if #out >= 6 then break end
            table.insert(out, e)
        end
        while #out > 6 do table.remove(out) end
        return out
      end)
      return function() return found.value end
    end
    local matches = { search_app = matches_for("search_app"), search_rule = matches_for("search_rule") }
    local function chose(choice: any)
        typing.value = ""
        if g.untracked(function() return adding_rule.value end) then
            niri_settings.add_rule(choice.app_id)
            adding_rule.value = false
        elseif g.untracked(function() return adding_startup.value end) == "app" then
            local command = if choice.entry then apps.command_of(choice.entry) else {}
            if #command > 0 then niri_settings.add_startup(command, false) end
            adding_startup.value = ""
        end
    end
    local function app_picker(which: string): any
        return g.box {
            direction = "column",
            gap = function() return m().gap_row end,
            g.capsule {
                role = "button",
                width = p.inner,
                height = function() return 28 * f() end,
                padding_x = function() return 14 * f() end,
                direction = "row",
                align = "center",
                radius = function() return metrics_mod.radius_for(28 * f(), m()) end,
                fill = CLEAR,
                rim_top = function() return if typing.value == which then theme.primary() else theme.control_edge() end,
                rim_bottom = function() return if typing.value == which then theme.primary() else theme.control_edge() end,
                on_click = function() start(which, g.untracked(function() return texts[which].value end)) end,
                nodes[which],
            },
            g.each {
                direction = "column",
                items = matches[which],
                key = function(c: any) return c.app_id end,
                row = function(c: () -> any)
                    return p.app {
                        icon = function() return if c().icon ~= "" then (g.icon_path(c().icon) or "") else "" end,
                        name = function() return c().name end,
                        detail = function() return if c().open then "OPEN NOW" else "" end,
                        on_choose = function() chose(g.untracked(c)) end,
                    }
                end,
            },
        }
    end
    local function open_picker(which: string)
        start(which, "")
    end

    t.keyed(function(name: string, typed: string?, mods: { [string]: any }): boolean
        local which = g.untracked(function() return typing.value end)
        if which == "" then return false end
        if name == "Escape" then
            typing.value = ""
            if which == "search_rule" then adding_rule.value = false end
            if which == "search_app" then adding_startup.value = "" end
            return true
        end
        if name == "Return" or name == "KP_Enter" then
            if string.sub(which, 1, 6) == "search" then
                local first = g.untracked(matches[which])[1]
                if first then chose(first) end
            else
                commit(which)
                typing.value = ""
            end
            return true
        end
        return fields[which].key(name, typed, mods)
    end)

    -- ---- The wells -----------------------------------------------------------------

    local error_line = g.box {
        present = function() return niri_settings.error() ~= "" end,
        line(function() return niri_settings.error() end, theme.alert),
    }

    local gaps = section("GAPS", nil, {
        amount(niri_settings.gaps, niri_settings.set_gaps, 0, 48, 1, " px"),
        line(function()
            local n = niri_settings.gaps()
            return (if n == 0 then "Windows touch each other and the edges of the screen. "
                else n .. " px between windows, and between them and the edges of the screen. ") .. "Written in " .. file_name(niri_settings.main) .. "."
        end),
    })

    local ring = section("FOCUS RING", nil, {
        amount(niri_settings.focus_ring, niri_settings.set_focus_ring, 1, 8, 1, " px"),
        line(function()
            local n = niri_settings.focus_ring()
            return (if n == 2 then "As wide as a cell's rim, which is how Bioma draws it. " else n .. " px around the focused window. ")
                .. (if niri_settings.themed()
                    then "Lit like a cell's edge, from the theme's niri file, which wins over a width set in niri's own."
                    else "Written in niri's files: Bioma's theme for niri is switched off in the theme cell's APPS.")
        end),
    })

    local follows = section("FOCUS FOLLOWS THE POINTER", switch.new {
        on = niri_settings.follows_mouse,
        factor = f,
        dimmed = busy,
        on_toggle = function(value: boolean) niri_settings.set_follows_mouse(value) end,
    }, {
        line(function()
            return if niri_settings.follows_mouse()
                then "The window under the pointer takes the focus as soon as the pointer is on it, without a click."
                else "A window takes the focus when it is clicked, or reached from the keyboard."
        end),
    })

    -- Every window's opacity, in focus and out of it. An application's rule
    -- below overrides the first for its windows; nothing overrides the
    -- second.
    local function opacity_row(label: string, value: () -> number, write: (number) -> ()): any
        return g.box {
            direction = "column",
            gap = function() return 6 * f() end,
            g.box { width = p.inner, direction = "row", meta(label, theme.text_muted) },
            amount(function() return value() * 100 end, function(v: number) write(v / 100) end, 10, 100, 5, "%"),
        }
    end
    local opacity = section("WINDOW OPACITY", g.box {
        present = niri_settings.owns_opacity,
        choice_mod.new { label = "CLEAR", metrics = m, dimmed = busy, on_click = function() niri_settings.clear_opacity() end },
    }, {
        opacity_row("IN FOCUS", niri_settings.focused_opacity, niri_settings.set_focused_opacity),
        opacity_row("OUT OF FOCUS", niri_settings.unfocused_opacity, niri_settings.set_unfocused_opacity),
        line(function()
            if not niri_settings.owns_opacity() then
                return "niri's own window rules decide for now. Moving a slider sets both here, for every window, "
                    .. "in bioma-windows.kdl, read after niri's own files."
            end
            return "For every window. An application's window rule below can give its windows another opacity in focus; "
                .. "out of focus they all follow this one. Written in bioma-windows.kdl, read after niri's own files."
        end),
    })

    local function workspace_row(item: () -> any): any
        local function ws(): any return item().ws end
        local function id(): string return item().id end
        local function open(): boolean return open_ws.value == id() end
        local function index(): number return item().index end
        local outputs: { [any]: any } = { direction = "row", gap = function() return 6 * f() end }
        return g.box {
            direction = "column",
            gap = function() return m().gap_row end,
            headline {
                open = open,
                openable = true,
                name = function() return ws().name end,
                summary = function() return if ws().output ~= "" then string.upper(ws().output) else "" end,
                on_click = function() open_ws.value = if g.untracked(open) then "" else g.untracked(id) end,
                tools = {
                    tool("chevron-up", function() return index() == 1 end, function() niri_settings.move_workspace(g.untracked(ws), -1) end),
                    tool("chevron-down", function() return index() == #niri_settings.workspaces() end, function() niri_settings.move_workspace(g.untracked(ws), 1) end),
                    p.remove(function() niri_settings.remove_workspace(g.untracked(ws)) end),
                },
            },
            g.box {
                present = open,
                direction = "column",
                gap = function() return m().gap_row end,
                padding_left = function() return 34 * f() end,
                g.capsule {
                    role = "button",
                    width = function() return p.inner() - 34 * f() end,
                    height = function() return 28 * f() end,
                    padding_x = function() return 14 * f() end,
                    direction = "row",
                    align = "center",
                    radius = function() return metrics_mod.radius_for(28 * f(), m()) end,
                    fill = CLEAR,
                    rim_top = function()
                        if workspace_problem() ~= "" then return theme.alert() end
                        return if typing.value == "workspace" then theme.primary() else theme.control_edge()
                    end,
                    rim_bottom = function()
                        if workspace_problem() ~= "" then return theme.alert() end
                        return if typing.value == "workspace" then theme.primary() else theme.control_edge()
                    end,
                    on_click = function() start("workspace", g.untracked(ws).name) end,
                    g.text {
                        present = function() return typing.value ~= "workspace" end,
                        text = function() return ws().name end,
                        color = theme.text,
                        font = typography.expressive,
                        size = function() return m().font_secondary end,
                    },
                    g.box { present = function() return typing.value == "workspace" end, nodes.workspace },
                },
                g.box { present = function() return workspace_problem() ~= "" end, line(workspace_problem, theme.alert) },
                p.flow {
                    items = function()
                        local out = { "" }
                        for _, o in monitors.outputs() do table.insert(out, o.name) end
                        return out
                    end,
                    key = function(name: string) return if name == "" then "any" else name end,
                    width_of = function(name: string): number
                        return 24 * f() + g.text_width { text = if name ~= "" then name else "ANY MONITOR", font = typography.technical(), size = math.round(12 * f()), tracking = 0.04 }
                    end,
                    chip = function(name: () -> string)
                        return choice_mod.new {
                            label = function() return if name() ~= "" then name() else "ANY MONITOR" end,
                            kind = function() return if ws().output == name() then "primary" else "plain" end,
                            metrics = m,
                            dimmed = busy,
                            on_click = function() niri_settings.set_workspace_output(g.untracked(ws), g.untracked(name)) end,
                        }
                    end,
                },
                muted(function()
                    return "Renaming it renames it in the window rules and the keys that go to it. Windows already on it stay where they are. Written in " .. file_name(ws().file) .. "."
                end),
            },
        }
    end

    local workspaces = section("WORKSPACES", nil, {
        g.box {
            present = function() return #niri_settings.workspaces() == 0 end,
            line(function() return "None named: niri makes a workspace as soon as one is needed and drops it when it is empty. A named one is always there, and window rules can send windows to it." end),
        },
        g.each {
            direction = "column",
            gap = function() return 4 * f() end,
            items = function()
                local out = {}
                for i, ws in niri_settings.workspaces() do table.insert(out, { index = i, id = niri_settings.id(ws), ws = ws }) end
                return out
            end,
            key = function(item: any) return item.ws.name end,
            row = workspace_row,
        },
        p.offer("NEW", function() if not g.untracked(busy) then niri_settings.add_workspace() end end),
    })

    local function startup_row(item: () -> any): any
        local function line_item(): any return item().item end
        local function app(): any return startup_app(line_item()) end
        return headline {
            open = function() return false end,
            openable = false,
            icon = function() return app().icon end,
            name = function() return app().name end,
            faint = function() return not line_item().on end,
            summary = function() return app().command end,
            tools = { p.remove(function() niri_settings.remove_startup(g.untracked(line_item)) end) },
            trailing = switch.new {
                on = function() return line_item().on end,
                factor = f,
                dimmed = busy,
                on_toggle = function(value: boolean) niri_settings.set_startup_on(g.untracked(line_item), value) end,
            },
        }
    end

    local startup = section("AT STARTUP", nil, {
        g.box {
            present = function() return #niri_settings.startup() == 0 end,
            line(function() return "Nothing but Bioma starts with the session." end),
        },
        g.each {
            direction = "column",
            gap = function() return 4 * f() end,
            items = function()
                local out = {}
                for i, it in niri_settings.startup() do table.insert(out, { key = niri_settings.id(it) .. i, item = it }) end
                return out
            end,
            key = function(it: any) return it.key end,
            row = startup_row,
        },
        g.box { present = function() return adding_startup.value == "app" end, app_picker("search_app") },
        g.box {
            present = function() return adding_startup.value == "command" end,
            direction = "column",
            gap = function() return m().gap_row end,
            g.capsule {
                role = "button",
                width = p.inner,
                height = function() return 28 * f() end,
                padding_x = function() return 14 * f() end,
                direction = "row",
                align = "center",
                radius = function() return metrics_mod.radius_for(28 * f(), m()) end,
                fill = CLEAR,
                rim_top = function() return if typing.value == "command" then theme.primary() else theme.control_edge() end,
                rim_bottom = function() return if typing.value == "command" then theme.primary() else theme.control_edge() end,
                on_click = function() start("command", "") end,
                nodes.command,
            },
            muted(function() return "Run by sh when the session starts. Enter adds it." end),
        },
        g.box {
            direction = "row",
            gap = function() return 6 * f() end,
            p.offer("APPLICATION", function()
                adding_rule.value = false
                adding_startup.value = if g.untracked(function() return adding_startup.value end) == "app" then "" else "app"
                if g.untracked(function() return adding_startup.value end) == "app" then open_picker("search_app") end
            end),
            p.offer("COMMAND", function()
                adding_startup.value = if g.untracked(function() return adding_startup.value end) == "command" then "" else "command"
                if g.untracked(function() return adding_startup.value end) == "command" then start("command", "") end
            end),
        },
        muted(function()
            return "Switched off, a line is commented out and kept. Changes take effect at the next login. Written in " .. written_in(niri_settings.startup()) .. "."
        end),
    })

    local function rule_row(item: () -> any): any
        local function rule(): any return item().rule end
        local function id(): string return item().id end
        local function open(): boolean return open_rule.value == id() end
        local function app(): any return rule_app(rule()) end
        local inner = function() return p.inner() - 34 * f() end
        local function setting(label: string, body: any, clear: (() -> ())?, has: (() -> boolean)?): any
            return g.box {
                direction = "column",
                gap = function() return 6 * f() end,
                g.box {
                    width = inner,
                    direction = "row",
                    align = "center",
                    meta(label, theme.text_muted),
                    g.box { grow = 1 },
                    g.box {
                        present = function() return clear ~= nil and (has == nil or has()) end,
                        choice_mod.new { label = "CLEAR", metrics = m, dimmed = busy, on_click = function() if clear then clear() end end },
                    },
                },
                body,
            }
        end
        return g.box {
            direction = "column",
            gap = function() return m().gap_row end,
            headline {
                open = open,
                openable = true,
                icon = function() return app().icon end,
                name = function() return app().name end,
                summary = function() return rule_summary(rule()) end,
                on_click = function() open_rule.value = if g.untracked(open) then "" else g.untracked(id) end,
                tools = {
                    g.box {
                        present = function() return niri_settings.removable(rule()) end,
                        p.remove(function() niri_settings.remove_rule(g.untracked(rule)) end),
                    },
                },
            },
            g.box {
                present = open,
                direction = "column",
                gap = function() return 10 * f() end,
                padding_left = function() return 34 * f() end,
                -- In focus only: out of focus every window follows WINDOW
                -- OPACITY. The rule for every window has its opacity there.
                g.box {
                    present = function() return not niri_settings.every_window(rule()) end,
                    setting("OPACITY IN FOCUS",
                        amount(function() local o = rule().opacity return if o ~= nil then o * 100 else nil end,
                            function(v: number) niri_settings.set_rule_opacity(g.untracked(rule), v / 100) end, 10, 100, 5, "%", inner),
                        function() niri_settings.set_rule_opacity(g.untracked(rule), nil) end,
                        function() return rule().opacity ~= nil end),
                },
                setting("WIDTH WHEN IT OPENS", g.box {
                    direction = "column",
                    gap = function() return 4 * f() end,
                    amount(function() local w = rule().width return if w and w.kind == "proportion" then w.value * 100 else nil end,
                        function(v: number) niri_settings.set_rule_width(g.untracked(rule), v / 100) end, 10, 100, 5, "%", inner),
                    g.box {
                        present = function() local w = rule().width return w == nil or w.kind ~= "proportion" end,
                        muted(function()
                            local w = rule().width
                            return if w and w.kind == "fixed" then math.round(w.value) .. " px for now: moving the slider makes it a share of the screen."
                                else "As wide as the window asks for now: moving the slider makes it a share of the screen."
                        end),
                    },
                }, function() niri_settings.set_rule_width(g.untracked(rule), nil) end, function() return rule().width ~= nil end),
                setting("OPENS ON", p.flow {
                    items = function()
                        local out = { "" }
                        for _, ws in niri_settings.workspaces() do table.insert(out, ws.name) end
                        return out
                    end,
                    key = function(name: string) return if name == "" then "where" else name end,
                    width_of = function(name: string): number
                        return 24 * f() + g.text_width { text = if name ~= "" then string.upper(name) else "WHERE IT IS OPENED", font = typography.technical(), size = math.round(12 * f()), tracking = 0.04 }
                    end,
                    chip = function(name: () -> string)
                        return choice_mod.new {
                            label = function() return if name() ~= "" then string.upper(name()) else "WHERE IT IS OPENED" end,
                            kind = function() return if (rule().workspace or "") == name() then "primary" else "plain" end,
                            metrics = m,
                            dimmed = busy,
                            on_click = function()
                                local n = g.untracked(name)
                                niri_settings.set_rule_workspace(g.untracked(rule), if n ~= "" then n else nil)
                            end,
                        }
                    end,
                }),
                muted(function()
                    local rest = rule_rest(rule())
                    local a = app()
                    return (if #rest > 0 then "The rule also has " .. table.concat(rest, ", ") .. ", left as they are. " else "")
                        .. (if a.name == "Every window" then "Applies to every window. " else "Applies to windows whose app-id matches " .. a.pattern .. ". ")
                        .. "Written in " .. file_name(rule().file) .. "."
                end),
            },
        }
    end

    local rules = section("WINDOW RULES", nil, {
        g.box {
            present = function() return #niri_settings.rules() == 0 end,
            line(function() return "No rules for an application yet. A rule can give its windows their own opacity in focus, open them at a width, or send them to a workspace." end),
        },
        g.each {
            direction = "column",
            gap = function() return 4 * f() end,
            items = function()
                local out = {}
                for i, r in niri_settings.rules() do table.insert(out, { key = niri_settings.id(r) .. i, id = niri_settings.id(r), rule = r }) end
                return out
            end,
            key = function(item: any) return item.key end,
            row = rule_row,
        },
        g.box { present = function() return adding_rule.value end, app_picker("search_rule") },
        p.offer("APPLICATION", function()
            adding_startup.value = ""
            adding_rule.value = not g.untracked(function() return adding_rule.value end)
            if g.untracked(function() return adding_rule.value end) then open_picker("search_rule") end
        end),
        g.box {
            present = function() return niri_settings.other_rules() > 0 end,
            muted(function()
                local n = niri_settings.other_rules()
                return n .. (if n == 1 then " more rule matches" else " more rules match")
                    .. " windows by something other than their application (focus, title, floating) and " .. (if n == 1 then "is" else "are") .. " edited in niri's files."
            end),
        },
    })

    return p.column { error_line, gaps, ring, follows, opacity, workspaces, startup, rules }
end

return M
