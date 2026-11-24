--!strict
-- Settings → Hyprland or Umbriel: the page that stands where NIRI does when
-- another compositor runs (cells/settings_niri.luau is niri's), with what
-- that compositor can be told from here (services/compositor_settings.luau):
-- the gaps, the border, the focus following the pointer, Umbriel's hot
-- corners, num lock, the mouse and the touchpad, the layouts (everywhere, by
-- monitor and by workspace), the window opacity and the window rules.
--
-- One well per setting, as on NIRI, and a line in Spectral saying what the
-- current choice does. Every choice is written into one file of Bioma's,
-- which wins over the same setting in the compositor's own files; a
-- setting never touched here is left to them.
local g = require("@genoma")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local page = require("components/page")
local slider = require("components/slider")
local switch = require("components/switch")
local choice_mod = require("components/choice")
local segmented = require("components/segmented")
local field_mod = require("components/field")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local apps = require("core/apps")
local compositor = require("services/compositor")
local monitors = require("services/monitors")
local settings = require("services/compositor_settings")

local M = {}

local CLEAR = "#00000000"

local CORNER_LABELS = { top_left = "TOP LEFT", top_right = "TOP RIGHT", bottom_left = "BOTTOM LEFT", bottom_right = "BOTTOM RIGHT" }

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end
    local function busy(): boolean return settings.busy() end
    local function meta(text: string | () -> string, color: any): any
        return g.text {
            text = text,
            color = color or theme.text,
            font = typography.technical,
            size = function() return m().font_meta end,
            tracking = typography.label_tracking,
        }
    end
    -- Where the choice is: Bioma's file once one is made here, the
    -- compositor's own files until then.
    local function written(...: string): string
        for _, id in { ... } do
            if settings.chosen(id) then return "Written in " .. settings.file .. "." end
        end
        return "As " .. settings.title .. "'s own files say; a change here goes in " .. settings.file .. "."
    end

    -- A slider with its figure (settings_niri.luau's): written once the
    -- hand rests.
    local function amount_of(value: () -> number?, set: (number) -> (), from: number, to: number, step: number, unit: string, width: (() -> number)?): any
        local function w(): number return if width then width() else p.inner() end
        local held = g.signal(nil :: number?)
        local timer: any = nil
        local function shown(): number?
            local h = held.value
            if h ~= nil then return h end
            return value()
        end
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
                        set(v)
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
                    text = function()
                        local v = shown()
                        if v == nil then return "—" end
                        local r = math.round(v * 10) / 10
                        if r == 0 then r = 0 end -- not -0
                        return tostring(r) .. unit
                    end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    tabular = true,
                },
            },
        }
    end
    local function amount(id: string, from: number, to: number, step: number, unit: string, scale: number?): any
        local k = scale or 1
        return amount_of(function()
            local v = settings.value(id)
            return if type(v) == "number" then v * k else nil
        end, function(v: number) settings.set(id, v / k) end, from, to, step, unit)
    end
    local function on(id: string): boolean return settings.value(id) == true end
    local function toggle(id: string): any
        return switch.new {
            on = function() return on(id) end,
            factor = f,
            dimmed = busy,
            on_toggle = function(value: boolean) settings.set(id, value) end,
        }
    end
    local function labelled(label: string, body: any): any
        return g.box {
            direction = "column",
            gap = function() return 6 * f() end,
            g.box { width = p.inner, direction = "row", meta(label, theme.text_muted) },
            body,
        }
    end

    local error_line = g.box {
        present = function() return settings.error() ~= "" end,
        line(function() return settings.error() end, theme.alert),
    }

    local gaps = section("GAPS", nil, {
        amount("gaps", 0, 48, 1, " px"),
        line(function()
            local n = settings.value("gaps") or 0
            return (if n == 0 then "Windows touch each other and the edges of the screen. "
                else n .. " px between windows, and between them and the edges of the screen. ") .. written("gaps")
        end),
    })

    local border = section("BORDER", nil, {
        amount("border", 0, 8, 1, " px"),
        line(function()
            local n = settings.value("border") or 0
            return (if n == 0 then "No border marks the focused window. " else n .. " px around every window, lit on the focused one. ") .. written("border")
        end),
    })

    local follows = section("FOCUS FOLLOWS THE POINTER", toggle("follows"), {
        line(function()
            return (if on("follows")
                then "The window under the pointer takes the focus as soon as the pointer is on it, without a click. "
                else "A window takes the focus when it is clicked, or reached from the keyboard. ") .. written("follows")
        end),
    })

    -- Umbriel's four corners, standing where they are.
    local function corner_chip(corner: string): any
        local id = "corner_" .. corner
        return choice_mod.new {
            id = "corner-" .. corner,
            label = CORNER_LABELS[corner],
            kind = function() return if on(id) then "primary" else "plain" end,
            metrics = m,
            dimmed = busy,
            on_click = function() settings.set(id, not g.untracked(function() return on(id) end)) end,
        }
    end
    local function corner_column(top: string, bottom: string, align: string): any
        return g.box { direction = "column", align = align, gap = function() return 6 * f() end, corner_chip(top), corner_chip(bottom) }
    end
    local hot_corners = section("HOT CORNERS", nil, {
        g.box {
            width = p.inner,
            direction = "row",
            justify = "between",
            corner_column("top_left", "bottom_left", "start"),
            corner_column("top_right", "bottom_right", "end"),
        },
        line(function()
            local names = {}
            for _, c in settings.corners do
                if on("corner_" .. c) then table.insert(names, string.lower(CORNER_LABELS[c])) end
            end
            if #names == 0 then return "No corner opens the overview; its key still does. " .. written("corner_top_left", "corner_top_right", "corner_bottom_left", "corner_bottom_right") end
            local list = if #names == 1 then names[1] else table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
            return "Pushing the pointer into the " .. list .. " corner of a screen opens the overview. " .. written("corner_top_left", "corner_top_right", "corner_bottom_left", "corner_bottom_right")
        end),
    }, function() return settings.supports("corner_top_left") end)

    local numlock = section("NUM LOCK AT START", toggle("numlock"), {
        line(function()
            return (if on("numlock")
                then "The keypad types figures from the moment the session starts. "
                else "The keypad moves the cursor until num lock is pressed. ") .. written("numlock")
        end),
    })

    local mouse = section("MOUSE", nil, {
        labelled("SPEED", amount("mouse_speed", -1, 1, 0.1, "")),
        p.row("FLAT ACCELERATION", toggle("mouse_flat")),
        p.row("NATURAL SCROLLING", toggle("mouse_natural")),
        p.row("LEFT-HANDED", toggle("mouse_left")),
        line(function()
            local speed = settings.value("mouse_speed") or 0
            return (if speed == 0 then "At libinput's own speed" elseif speed > 0 then "Faster than libinput's own speed" else "Slower than libinput's own speed")
                .. (if on("mouse_flat") then ", the pointer moving as far as the hand does at any pace. " else ", the pointer going further when the hand moves fast. ")
                .. (if on("mouse_natural") then "Scrolling is reversed: the content moves with the hand. " else "Scrolling down goes down the page. ")
                .. (if on("mouse_left") then "The buttons are swapped for the left hand. " else "")
                .. written("mouse_speed", "mouse_flat", "mouse_natural", "mouse_left")
        end),
    })

    local touchpad = section("TOUCHPAD", nil, {
        p.row("TAP TO CLICK", toggle("tap")),
        p.row("NATURAL SCROLLING", toggle("touchpad_natural")),
        p.row("OFF WHILE TYPING", toggle("typing")),
        line(function()
            return (if on("tap") then "A tap clicks. " else "Only a press clicks. ")
                .. (if on("touchpad_natural") then "Scrolling is reversed: the content moves with the fingers. " else "Scrolling down goes down the page. ")
                .. (if on("typing") then "It goes quiet while the keyboard is in use. " else "")
                .. written("tap", "touchpad_natural", "typing")
        end),
    }, settings.has_touchpad)

    local opacity = section("WINDOW OPACITY", nil, {
        labelled("IN FOCUS", amount("opacity_focused", 10, 100, 5, "%", 100)),
        labelled("OUT OF FOCUS", amount("opacity_unfocused", 10, 100, 5, "%", 100)),
        line(function() return "Every window's opacity, with and without the focus. " .. written("opacity_focused", "opacity_unfocused") end),
    }, function() return settings.supports("opacity_focused") end)

    -- ---- Layouts -----------------------------------------------------

    local LAYOUT_LABELS = { dwindle = "Dwindle", master = "Master", scrolling = "Scrolling", monocle = "Monocle", stacking = "Stacking" }
    local LAYOUT_SAYS = {
        dwindle = "each new window halves the one in focus",
        master = "one large window, the others stacked beside it",
        scrolling = "columns in a strip that scrolls, as on niri",
        monocle = "one window at a time, filling the screen",
        stacking = "windows where they are put, one over another",
    }
    local function layout_choice(current: () -> string, choose: (string) -> (), same: boolean): any
        return segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            button_height = function() return 26 * f() end,
            button_padding = function() return 10 * f() end,
            options = function()
                local out = {}
                if same then table.insert(out, { key = "", label = "Same" }) end
                for _, key in settings.layouts do table.insert(out, { key = key, label = LAYOUT_LABELS[key] }) end
                return out
            end,
            current = current,
            on_choose = function(key: string) if key ~= g.untracked(current) then choose(key) end end,
        }
    end
    local function layout_rows(of: string, names: () -> { string }, label: ((string) -> string)?): any
        return g.each {
            direction = "column",
            gap = function() return 6 * f() end,
            items = names,
            key = function(which: string) return which end,
            row = function(which: () -> string)
                return p.row(function() return if label then label(which()) else which() end, layout_choice(
                    function() return settings.layout_for(of, which()) or "" end,
                    function(key: string) settings.set_layout(of, g.untracked(which), if key ~= "" then key else nil) end,
                    true))
            end,
        }
    end
    -- What can be chosen for: there now, or chosen before.
    local function named(of: string, here: () -> { string }): () -> { string }
        local list = g.computed(function(): { string }
            local out = here()
            for _, n in settings.layout_names(of) do
                if not table.find(out, n) then table.insert(out, n) end
            end
            table.sort(out, function(a, b)
                local x, y = tonumber(a), tonumber(b)
                if x and y then return x < y end
                if x or y then return x ~= nil end
                return a < b
            end)
            return out
        end)
        return function() return list.value end
    end
    -- A workspace by the name it has, or else by its id: Hyprland's number,
    -- which is not the place it has on its monitor, or Umbriel's "DP-1:2".
    local function workspace_names(): { string }
        local out = {}
        for _, ws in compositor.workspace_list() do
            local n = if ws.name ~= "" then ws.name else ws.id
            if not table.find(out, n) and string.sub(n, 1, 8) ~= "special:" then table.insert(out, n) end
        end
        return out
    end
    -- Where it is now, beside it.
    local function workspace_label(which: string): string
        local output, index = string.match(which, "^(.*):(%d+)$")
        if output then return index .. "  ·  " .. output end
        for _, ws in compositor.workspace_list() do
            if (if ws.name ~= "" then ws.name else ws.id) == which then return which .. "  ·  " .. ws.output end
        end
        return which
    end
    local function layout_shown(): string return tostring(settings.value("layout") or "dwindle") end

    local layout = section("LAYOUT", nil, {
        p.row("EVERYWHERE", layout_choice(layout_shown, function(key: string) settings.set("layout", key) end, false)),
        line(function()
            return (LAYOUT_LABELS[layout_shown()] or layout_shown()) .. ": " .. (LAYOUT_SAYS[layout_shown()] or "a layout of " .. settings.title .. "'s own") .. ". " .. written("layout")
        end),
        labelled("BY MONITOR", layout_rows("monitors", named("monitors", function()
            local out = {}
            for _, o in monitors.outputs() do table.insert(out, o.name) end
            return out
        end))),
        labelled("BY WORKSPACE", layout_rows("workspaces", named("workspaces", workspace_names), workspace_label)),
        line(function()
            return "A workspace's own wins over its monitor's, and a monitor's over everywhere's. A workspace is here while it is open. Written in " .. settings.file .. "."
        end, theme.text_muted),
    }, settings.has_layouts)

    -- ---- Window rules --------------------------------------------------

    local adding = g.signal(false)
    local open_rule = g.signal("")
    local query = g.signal("")
    local query_node, query_field = field_mod.new {
        text = query,
        width = function() return p.inner() - 80 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        placeholder = "Search open windows and applications",
        taking = function() return adding.value end,
    }
    -- The windows open now first (their class is read, not guessed), then
    -- the installed applications (cells/settings_niri.luau's).
    local matches = g.computed(function(): { any }
        if not adding.value then return {} end
        local wanted = string.lower(string.match(query.value, "^%s*(.-)%s*$") or "")
        local function fits(...: string): boolean
            if wanted == "" then return true end
            for _, w in { ... } do if string.find(string.lower(w or ""), wanted, 1, true) then return true end end
            return false
        end
        local seen, out, installed = {}, {}, {}
        for _, w in compositor.windows() do
            local id = w.app_id or ""
            if id ~= "" and not seen[string.lower(id)] then
                local entry = apps.entry_for(id)
                if fits(id, if entry then entry.name else "") then
                    seen[string.lower(id)] = true
                    table.insert(out, { app_id = id, open = true, name = if entry then entry.name else id, icon = if entry then entry.icon else "" })
                end
            end
        end
        for _, e in apps.entries() do
            local id = if e.startup_class ~= "" then e.startup_class else e.id
            if id ~= "" and not seen[string.lower(id)] and fits(e.name, e.id) then
                seen[string.lower(id)] = true
                table.insert(installed, { app_id = id, open = false, name = e.name, icon = e.icon })
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
    local function chose(choice: any)
        adding.value = false
        settings.add_rule(choice.app_id)
        open_rule.value = choice.app_id
    end
    t.keyed(function(key: string, typed: string?, mods: { [string]: any }): boolean
        if not g.untracked(function() return adding.value end) then return false end
        if key == "Escape" then
            adding.value = false
            return true
        end
        if key == "Return" or key == "KP_Enter" then
            local first = g.untracked(function() return matches.value end)[1]
            if first then chose(first) end
            return true
        end
        return query_field.key(key, typed, mods)
    end)

    local function rule_row(item: () -> string): any
        local app = g.untracked(item)
        local entry = apps.entry_for(app)
        local function rule(): any return settings.rule_of(app) or { app = app } end
        local function open(): boolean return open_rule.value == app end
        local hovered = g.signal(false)
        local function inner(): number return p.inner() - 34 * f() end
        local function set(field: string, value: any) settings.set_rule(app, field, value) end
        local function summary(): string
            local r, out = rule(), {}
            if r.opacity then table.insert(out, math.round(r.opacity * 100) .. "% opaque in focus") end
            if r.floating then table.insert(out, "floating") end
            if r.width then table.insert(out, math.round(r.width * 100) .. "% wide") end
            if r.workspace then table.insert(out, "on " .. r.workspace) end
            return if #out > 0 then table.concat(out, " · ") else "nothing set yet"
        end
        -- A line as wide as what is under a rule, not as the well.
        local function said(text: string): any
            return g.text {
                text = text,
                color = theme.text_muted,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                max_width = inner,
                wrap = true,
            }
        end
        local function setting(label: string, body: any, field: string?): any
            return g.box {
                direction = "column",
                align = "start",
                gap = function() return 6 * f() end,
                g.box {
                    width = inner,
                    direction = "row",
                    align = "center",
                    meta(label, theme.text_muted),
                    g.box { grow = 1 },
                    g.box {
                        present = function() return field ~= nil and rule()[field] ~= nil end,
                        choice_mod.new { label = "CLEAR", metrics = m, dimmed = busy, on_click = function() set(field :: string, nil) end },
                    },
                },
                body,
            }
        end
        return g.box {
            direction = "column",
            align = "start",
            gap = function() return m().gap_row end,
            g.capsule {
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
                    if open() then return colour.alpha(theme.primary(), 0.10) end
                    return if hovered.value then colour.alpha(theme.text(), 0.05) else CLEAR
                end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                on_hover = function(over: boolean) hovered.value = over end,
                on_click = function() open_rule.value = if g.untracked(open) then "" else app end,
                g.icon {
                    present = function() return entry ~= nil and entry.icon ~= "" end,
                    width = function() return 18 * f() end,
                    height = function() return 18 * f() end,
                    icon = if entry and entry.icon ~= "" then (g.icon_path(entry.icon) or "") else "",
                },
                g.text {
                    text = if entry then entry.name else app,
                    color = theme.text,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    max_width = function() return p.inner() * 0.4 end,
                },
                g.text {
                    text = summary,
                    color = theme.text_muted,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tracking = typography.label_tracking,
                    max_width = function() return p.inner() * 0.4 end,
                },
                g.box { grow = 1 },
                g.box {
                    opacity = function() return if hovered.value or open() then 1 else theme.tool_rest end,
                    p.remove(function() settings.remove_rule(app) end),
                },
            },
            g.box {
                present = open,
                direction = "column",
                align = "start",
                gap = function() return 10 * f() end,
                padding_left = function() return 34 * f() end,
                setting("OPACITY IN FOCUS",
                    amount_of(function() local o = rule().opacity return if o then o * 100 else nil end,
                        function(v: number) set("opacity", v / 100) end, 10, 100, 5, "%", inner),
                    "opacity"),
                g.box {
                    width = inner,
                    direction = "row",
                    align = "center",
                    meta("FLOATING", theme.text_muted),
                    g.box { grow = 1 },
                    switch.new {
                        on = function() return rule().floating == true end,
                        factor = f,
                        dimmed = busy,
                        on_toggle = function(value: boolean) set("floating", if value then true else nil) end,
                    },
                },
                setting("WIDTH WHEN IT OPENS", g.box {
                    direction = "column",
                    align = "start",
                    gap = function() return 4 * f() end,
                    amount_of(function() local w = rule().width return if w then w * 100 else nil end,
                        function(v: number) set("width", v / 100) end, 10, 100, 5, "%", inner),
                    said("A share of the screen, where the layout is scrolling."),
                }, "width"),
                setting("OPENS ON", p.flow {
                    width = inner,
                    items = function()
                        local out = { "" }
                        for i = 1, 9 do table.insert(out, tostring(i)) end
                        for _, n in workspace_names() do
                            if not string.match(n, ":%d+$") and not table.find(out, n) then table.insert(out, n) end
                        end
                        local chosen = rule().workspace
                        if chosen and not table.find(out, chosen) then table.insert(out, chosen) end
                        return out
                    end,
                    key = function(n: string) return if n == "" then "where" else n end,
                    chip = function(n: () -> string)
                        return choice_mod.new {
                            label = function() return if n() ~= "" then string.upper(n()) else "WHERE IT IS OPENED" end,
                            kind = function() return if (rule().workspace or "") == n() then "primary" else "plain" end,
                            metrics = m,
                            dimmed = busy,
                            on_click = function()
                                local chosen = g.untracked(n)
                                set("workspace", if chosen ~= "" then chosen else nil)
                            end,
                        }
                    end,
                }),
                said("For windows whose class is " .. app .. ", as they open (opacity at once). Written in " .. settings.file .. "."),
            },
        }
    end

    local rules = section("WINDOW RULES", nil, {
        g.box {
            present = function() return #settings.rules() == 0 end,
            line(function() return "No rules for an application yet. A rule can give its windows their own opacity in focus, open them floating or at a width, or send them to a workspace." end),
        },
        g.each {
            direction = "column",
            gap = function() return 4 * f() end,
            items = function()
                local out = {}
                for _, r in settings.rules() do table.insert(out, r.app) end
                return out
            end,
            key = function(app: string) return app end,
            row = rule_row,
        },
        g.box {
            present = function() return adding.value end,
            direction = "column",
            gap = function() return m().gap_row end,
            g.capsule {
                width = p.inner,
                height = function() return 28 * f() end,
                padding_x = function() return 14 * f() end,
                direction = "row",
                align = "center",
                radius = function() return metrics_mod.radius_for(28 * f(), m()) end,
                fill = CLEAR,
                rim_top = theme.primary,
                rim_bottom = theme.primary,
                query_node,
            },
            g.each {
                direction = "column",
                items = function() return matches.value end,
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
        },
        p.offer("APPLICATION", function()
            query_field.set("")
            adding.value = not g.untracked(function() return adding.value end)
        end),
        line(function() return "The rules of your own in " .. settings.main .. " are left to it." end, theme.text_muted),
    }, settings.has_rules)

    settings.look()
    return p.column { error_line, gaps, border, follows, layout, hot_corners, numlock, mouse, touchpad, opacity, rules }
end

return M
