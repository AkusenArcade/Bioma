--!strict
-- A few of Hyprland's and Umbriel's settings without opening their files:
-- services/niri_settings.luau's counterpart, smaller, for the page that
-- takes NIRI's place on them (cells/settings_compositor.luau).
--
-- niri's files are read as text and rewritten where each setting stands.
-- Hyprland's are a Lua program and Umbriel's merge by rules of their own,
-- so here the compositor is asked what it runs with (`hyprctl getoption`,
-- `umbriel config get`), what is chosen is kept in Bioma's configuration
-- (`compositor.<name>.<setting>`), and the choices are written as one file
-- of Bioma's: `bioma-settings.lua`, required last from hyprland.lua
-- (scripts/hypr-include), or `bioma-settings.toml`, included from
-- config.toml, the same settings there taken out of it
-- (scripts/umbriel-include). A setting never chosen here is not written,
-- and stays whatever the compositor's own files say.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

local name = require("services/compositor").name()
M.name = name
M.label = if name == "hyprland" then "HYPRLAND" elseif name == "umbriel" then "UMBRIEL" else string.upper(name)
M.title = if name == "hyprland" then "Hyprland" elseif name == "umbriel" then "Umbriel" else name
M.file = if name == "hyprland" then "bioma-settings.lua" elseif name == "umbriel" then "bioma-settings.toml" else ""

M.corners = { "top_left", "top_right", "bottom_left", "bottom_right" }

-- Each setting: its kind and, per compositor, where it is read and how it
-- is written. `hyprland.read` is getoption's name; `.write(v)` the part of
-- `hl.config` it sets. `umbriel` is the key, read and written as it is.
local function bool(v: any): boolean
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    if type(v) == "string" then return v == "true" or v == "1" end
    return false
end
local function number(v: any): number?
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(string.match(v, "^%s*(%-?[%d%.]+)")) end
    return nil
end

local SETTINGS: { [string]: any } = {
    gaps = {
        kind = "number", default = 8,
        hyprland = { read = "general:gaps_out", write = function(v: number) return { general = { gaps_in = math.round(v / 2), gaps_out = v } } end },
        umbriel = { key = "layout.gap" },
    },
    -- How a workspace arranges its windows, where nothing below says otherwise.
    layout = {
        kind = "text", default = "dwindle",
        hyprland = { read = "general:layout", write = function(v: string) return { general = { layout = v } } end },
        umbriel = { key = "layout.mode" },
    },
    border = {
        kind = "number", default = 2,
        hyprland = { read = "general:border_size", write = function(v: number) return { general = { border_size = v } } end },
        umbriel = { key = "appearance.border_width" },
    },
    follows = {
        kind = "bool", default = false,
        hyprland = { read = "input:follow_mouse", write = function(v: boolean) return { input = { follow_mouse = if v then 1 else 0 } } end },
        umbriel = { key = "input.focus.follows_mouse", from = function(v: any) return v == "sloppy" or v == "always" end,
            to = function(v: boolean) return if v then "sloppy" else "off" end },
    },
    numlock = {
        kind = "bool", default = false,
        hyprland = { read = "input:numlock_by_default", write = function(v: boolean) return { input = { numlock_by_default = v } } end },
        umbriel = { key = "input.keyboard.numlock_toggle" },
    },
    mouse_speed = {
        kind = "number", default = 0,
        hyprland = { read = "input:sensitivity", write = function(v: number) return { input = { sensitivity = v } } end },
        umbriel = { key = "input.mouse.sensitivity" },
    },
    mouse_flat = {
        kind = "bool", default = false,
        hyprland = { read = "input:accel_profile", from = function(v: any) return v == "flat" end,
            write = function(v: boolean) return { input = { accel_profile = if v then "flat" else "adaptive" } } end },
        umbriel = { key = "input.mouse.accel_profile", from = function(v: any) return v == "flat" end,
            to = function(v: boolean) return if v then "flat" else "adaptive" end },
    },
    mouse_natural = {
        kind = "bool", default = false,
        hyprland = { read = "input:natural_scroll", write = function(v: boolean) return { input = { natural_scroll = v } } end },
        umbriel = { key = "input.mouse.natural_scroll" },
    },
    mouse_left = {
        kind = "bool", default = false,
        hyprland = { read = "input:left_handed", write = function(v: boolean) return { input = { left_handed = v } } end },
        umbriel = { key = "input.mouse.left_handed" },
    },
    tap = {
        kind = "bool", default = true,
        hyprland = { read = "input:touchpad:tap_to_click", write = function(v: boolean) return { input = { touchpad = { tap_to_click = v } } } end },
        umbriel = { key = "input.touchpad.tap" },
    },
    touchpad_natural = {
        kind = "bool", default = false,
        hyprland = { read = "input:touchpad:natural_scroll", write = function(v: boolean) return { input = { touchpad = { natural_scroll = v } } } end },
        umbriel = { key = "input.touchpad.natural_scroll" },
    },
    typing = {
        kind = "bool", default = true,
        hyprland = { read = "input:touchpad:disable_while_typing", write = function(v: boolean) return { input = { touchpad = { disable_while_typing = v } } } end },
        umbriel = { key = "input.touchpad.disable_while_typing" },
    },
    opacity_focused = {
        kind = "number", default = 1,
        hyprland = { read = "decoration:active_opacity", write = function(v: number) return { decoration = { active_opacity = v } } end },
        -- A window rule, which nothing is read from (`window_rules`).
        umbriel = { rule = true },
    },
    opacity_unfocused = {
        kind = "number", default = 1,
        hyprland = { read = "decoration:inactive_opacity", write = function(v: number) return { decoration = { inactive_opacity = v } } end },
        umbriel = { rule = true },
    },
}
for _, c in M.corners do
    SETTINGS["corner_" .. c] = {
        kind = "bool", default = false,
        umbriel = { key = "hot_corners." .. c .. ".enabled", extra = { ["hot_corners." .. c .. ".action"] = "overview-open" } },
    }
end

function M.supports(id: string): boolean
    local s = SETTINGS[id]
    return s ~= nil and s[name] ~= nil
end

-- ---- What the compositor runs with -------------------------------------------------

local live = g.signal({} :: { [string]: any })
local reading = false
local again = false
function M.refresh()
    if reading then
        again = true
        return
    end
    local ids, names = {}, {}
    for id, s in SETTINGS do
        local how = s[name]
        if how and not how.rule then
            table.insert(ids, id)
            table.insert(names, if name == "hyprland" then how.read else how.key)
        end
    end
    if #ids == 0 then return end
    reading = true
    local script = if name == "hyprland"
        then 'for o in "$@"; do printf "%s\\t" "$o"; hyprctl getoption "$o" -j 2>/dev/null | tr -d "\\n"; echo; done'
        else 'for k in "$@"; do printf "%s\\t" "$k"; umbriel config get "$k" 2>/dev/null | tr -d "\\n"; echo; done'
    local command = { "sh", "-c", script, "read" }
    for _, n in names do table.insert(command, n) end
    local raw: { [string]: string } = {}
    g.process {
        command = command,
        on_line = function(line: string)
            local key, value = string.match(line, "^([^\t]+)\t(.*)$")
            if key then raw[key] = value end
        end,
        on_exit = function()
            reading = false
            local out = {}
            for i, id in ids do
                local text = raw[names[i]]
                local v: any = nil
                if text and text ~= "" then
                    local ok, parsed = pcall(g.parse_json, text)
                    if name == "hyprland" and ok and type(parsed) == "table" then
                        v = if parsed.custom ~= nil then parsed.custom elseif parsed.css ~= nil then parsed.css
                            elseif parsed.str ~= nil then parsed.str elseif parsed.bool ~= nil then parsed.bool
                            elseif parsed.float ~= nil then parsed.float else parsed.int
                    elseif ok then
                        v = parsed
                    else
                        v = text
                    end
                end
                local how = SETTINGS[id][name]
                if v ~= nil and how.from then v = how.from(v)
                elseif v ~= nil and SETTINGS[id].kind == "number" then v = number(v)
                elseif v ~= nil and SETTINGS[id].kind == "bool" then v = bool(v) end
                out[id] = v
            end
            live.value = out
            if again then
                again = false
                M.refresh()
            end
        end,
    }
end

local function key_of(id: string): string return "compositor." .. name .. "." .. id end

-- What is chosen here, or what the compositor runs with, or its default.
function M.value(id: string): any
    local chosen = config.get(key_of(id), nil)
    if chosen ~= nil then return chosen end
    local v = live.value[id]
    if v ~= nil then return v end
    return SETTINGS[id].default
end
function M.chosen(id: string): boolean return config.get(key_of(id), nil) ~= nil end

-- ---- Writing ---------------------------------------------------------------------

local busy = g.signal(false)
local refused = g.signal("")
function M.busy(): boolean return busy.value end
function M.error(): string return refused.value end

local function number_text(v: number): string
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.2f", v)
end

local function lua_value(v: any, indent: string): string
    if type(v) == "table" then
        local keys = {}
        for k in v do table.insert(keys, k) end
        table.sort(keys)
        local out = { "{" }
        for _, k in keys do table.insert(out, indent .. "    " .. k .. " = " .. lua_value(v[k], indent .. "    ") .. ",") end
        table.insert(out, indent .. "}")
        return table.concat(out, "\n")
    end
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" then return number_text(v) end
    return tostring(v)
end
local function toml_value(v: any): string
    if type(v) == "string" then return '"' .. string.gsub(string.gsub(v, "\\", "\\\\"), '"', '\\"') .. '"' end
    if type(v) == "number" then return number_text(v) end
    return tostring(v)
end

local function merge(into: { [string]: any }, part: { [string]: any })
    for k, v in part do
        if type(v) == "table" and type(into[k]) == "table" then merge(into[k], v) else into[k] = v end
    end
end

-- ---- Layouts by monitor and workspace -------------------------------------------
--
-- `compositor.<name>.layouts`, { monitors = { ["DP-1"] = … }, workspaces =
-- { ["3"] = … } }: Hyprland's workspace rules, Umbriel's `[output.….layout]`
-- and `[[workspace]]`. A monitor's is for every workspace on it; a workspace's
-- wins over its monitor's. A workspace is called by the name the person gave
-- it, else by its id: Hyprland's number, Umbriel's "DP-1:2".

M.layouts = if name == "umbriel" then { "scrolling", "dwindle", "master", "stacking" } else { "dwindle", "master", "scrolling", "monocle" }
-- The file a person writes, which Bioma's are included from.
M.main = if name == "umbriel" then "config.toml" else "hyprland.lua"
function M.has_layouts(): boolean return name == "hyprland" or name == "umbriel" end
local function layouts_key(): string return "compositor." .. name .. ".layouts" end
local function layouts(): any return config.get(layouts_key(), {}) end
-- `of`: "monitors" or "workspaces"; nil where none is chosen.
function M.layout_for(of: string, which: string): string? return (layouts()[of] or {})[which] end
-- Everything chosen in one of the two, by name, sorted.
function M.layout_names(of: string): { string }
    local out = {}
    for k in layouts()[of] or {} do table.insert(out, k) end
    table.sort(out)
    return out
end

-- Hyprland's word for a workspace. A number is said as a range of one: a rule
-- with the same words as one in hyprland.lua is folded into it where it
-- stands, and a monitor's rule, which comes after, would win over it.
local function workspace_selector(which: string): string
    return if string.match(which, "^%d+$") then "r[" .. which .. "-" .. which .. "]" else "name:" .. which
end
local function layout_rules(): string
    local out = {}
    for _, monitor in M.layout_names("monitors") do
        table.insert(out, string.format("hl.workspace_rule({ workspace = %q, layout = %q })", "m[" .. monitor .. "]", M.layout_for("monitors", monitor)))
    end
    for _, ws in M.layout_names("workspaces") do
        table.insert(out, string.format("hl.workspace_rule({ workspace = %q, layout = %q })", workspace_selector(ws), M.layout_for("workspaces", ws)))
    end
    return if #out > 0 then "\n" .. table.concat(out, "\n") .. "\n" else ""
end

-- ---- Window rules ----------------------------------------------------------------
--
-- `compositor.<name>.rules`, a list of { app, opacity, floating, width,
-- workspace }, each one application's. Bioma's own only: the rules in the
-- compositor's own file are a person's (Hyprland's a program's), and stay there.

function M.has_rules(): boolean return name == "hyprland" or name == "umbriel" end
local function rules_key(): string return "compositor." .. name .. ".rules" end
function M.rules(): { any } return config.get(rules_key(), {}) end
function M.rule_of(app: string): any
    for _, r in M.rules() do if r.app == app then return r end end
    return nil
end

local function escaped(app: string): string
    return (string.gsub(app, "[%.%^%$%*%+%?%(%)%[%]%{%}%|\\]", "\\%0"))
end
local function window_rules(): string
    local out = {}
    for _, r in M.rules() do
        local parts = {}
        -- In focus only, as on niri: out of focus it follows every window's.
        -- `override`, so that it is the figure and not a share of the other.
        if r.opacity then
            table.insert(parts, string.format("opacity = \"%s override %s override\"", number_text(r.opacity), number_text(M.value("opacity_unfocused"))))
        end
        if r.floating then table.insert(parts, "float = true") end
        if r.width then table.insert(parts, "scrolling_width = " .. number_text(r.width)) end
        if r.workspace then table.insert(parts, string.format("workspace = %q", if string.match(r.workspace, "^%d+$") then r.workspace else "name:" .. r.workspace)) end
        if #parts > 0 then
            table.insert(out, string.format("hl.window_rule({ name = %q, match = { class = %q }, %s })",
                "bioma " .. r.app, "^" .. escaped(r.app) .. "$", table.concat(parts, ", ")))
        end
    end
    return if #out > 0 then "\n" .. table.concat(out, "\n") .. "\n" else ""
end

-- Umbriel's, in TOML. Its window rules are merged and the later wins, so every
-- window's opacity comes before an application's.
local function umbriel_workspaces(): { string }
    local out = {}
    for _, ws in M.layout_names("workspaces") do
        table.insert(out, "[[workspace]]")
        local output, index = string.match(ws, "^(.*):(%d+)$")
        if output then
            table.insert(out, "index = " .. index)
            table.insert(out, "output = " .. toml_value(output))
        else
            table.insert(out, "name = " .. toml_value(ws))
        end
        table.insert(out, "layout.mode = " .. toml_value(M.layout_for("workspaces", ws)))
        table.insert(out, "")
    end
    return out
end
local function umbriel_rules(): { string }
    local out = {}
    local function rule(app: string?, focused: boolean?, parts: { string })
        if #parts == 0 then return end
        table.insert(out, "[[window_rule]]")
        if app then table.insert(out, "match.app_id = " .. toml_value("^" .. escaped(app) .. "$")) end
        if focused ~= nil then table.insert(out, "match.is_focused = " .. tostring(focused)) end
        for _, part in parts do table.insert(out, part) end
        table.insert(out, "")
    end
    for _, id in { "opacity_focused", "opacity_unfocused" } do
        local v = config.get(key_of(id), nil)
        if v ~= nil then rule(nil, id == "opacity_focused", { "opacity = " .. number_text(v) }) end
    end
    for _, r in M.rules() do
        local parts = {}
        if r.floating then table.insert(parts, "default_floating = true") end
        if r.width then table.insert(parts, "default_scrolling_extent = " .. number_text(r.width)) end
        if r.workspace then table.insert(parts, "default_workspace = " .. (if string.match(r.workspace, "^%d+$") then r.workspace else toml_value(r.workspace))) end
        rule(r.app, nil, parts)
        if r.opacity then rule(r.app, true, { "opacity = " .. number_text(r.opacity) }) end
    end
    return out
end

-- The whole file, from every choice made.
local function body(): string?
    local head = "Written by Bioma's settings cell (" .. M.label .. "). Changing a setting there rewrites it."
    if name == "hyprland" then
        local all = {}
        for id, s in SETTINGS do
            local v = config.get(key_of(id), nil)
            if v ~= nil and s.hyprland then merge(all, s.hyprland.write(v)) end
        end
        return "-- " .. head .. "\n\nhl.config(" .. lua_value(all, "") .. ")\n" .. layout_rules() .. window_rules()
    end
    if name == "umbriel" then
        local tables: { [string]: { [string]: any } } = {}
        local function put(key: string, v: any)
            local path, leaf = string.match(key, "^(.*)%.([^%.]+)$")
            if not path then return end
            tables[path :: string] = tables[path :: string] or {}
            tables[path :: string][leaf :: string] = v
        end
        for id, s in SETTINGS do
            local v = config.get(key_of(id), nil)
            local how = s.umbriel
            if v ~= nil and how and how.key then
                put(how.key, if how.to then how.to(v) else v)
                for k, extra in how.extra or {} do put(k, extra) end
            end
        end
        for _, monitor in M.layout_names("monitors") do
            put("output." .. monitor .. ".layout.mode", M.layout_for("monitors", monitor))
        end
        local paths_list = {}
        for p in tables do table.insert(paths_list, p) end
        table.sort(paths_list)
        local out = { "# " .. head, "" }
        for _, p in paths_list do
            table.insert(out, "[" .. p .. "]")
            local leaves = {}
            for k in tables[p] do table.insert(leaves, k) end
            table.sort(leaves)
            for _, k in leaves do table.insert(out, k .. " = " .. toml_value(tables[p][k])) end
            table.insert(out, "")
        end
        for _, l in umbriel_workspaces() do table.insert(out, l) end
        for _, l in umbriel_rules() do table.insert(out, l) end
        return table.concat(out, "\n")
    end
    return nil
end

local function write()
    local text = g.untracked(body)
    if not text then return end
    busy.value = true
    local said = {}
    local p = g.process {
        command = { paths.script(if name == "hyprland" then "hypr-include" else "umbriel-include"), "settings" },
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number)
            busy.value = false
            refused.value = if code == 0 then ""
                else (if name == "hyprland" then "Hyprland" else "Umbriel") .. " refused it" .. (if #said > 0 then ": " .. said[1] else ".")
            -- The gaps, which Bioma's own surfaces keep to, asked again too.
            g.after(0.5, function()
                M.refresh()
                require("services/compositor").refresh()
            end)
        end,
    }
    p:write(text)
    p:close_input()
end

-- Kept, then the whole file written once the hand rests.
local pending: any = nil
local function write_soon()
    if pending then pending:stop() end
    pending = g.after(0.3, function()
        pending = nil
        write()
    end)
end
function M.set(id: string, value: any)
    if not M.supports(id) then return end
    if type(value) == "number" then value = math.round(value * 100) / 100 end
    config.set(key_of(id), value)
    write_soon()
end

-- One layout, or nil to leave it to what is wider.
function M.set_layout(of: string, which: string, layout: string?)
    if not M.has_layouts() then return end
    local all = table.clone(g.untracked(layouts))
    local part = table.clone(all[of] or {})
    part[which] = layout
    all[of] = part
    config.set(layouts_key(), all)
    write_soon()
end

local function set_rules(list: { any })
    config.set(rules_key(), g.array(list))
    write_soon()
end
function M.add_rule(app: string)
    if not M.has_rules() or app == "" or g.untracked(function() return M.rule_of(app) end) then return end
    local list = table.clone(g.untracked(M.rules))
    table.insert(list, { app = app })
    set_rules(list)
end
function M.remove_rule(app: string)
    local list = {}
    for _, r in g.untracked(M.rules) do if r.app ~= app then table.insert(list, r) end end
    set_rules(list)
end
-- One thing a rule says, or nil for it not to.
function M.set_rule(app: string, field: string, value: any)
    local list = {}
    for _, r in g.untracked(M.rules) do
        local copy = table.clone(r)
        if r.app == app then copy[field] = value end
        table.insert(list, copy)
    end
    set_rules(list)
end

-- ---- A touchpad ------------------------------------------------------------------

local touchpad = g.signal(false)
function M.has_touchpad(): boolean return touchpad.value end
local looked = false
function M.look()
    M.refresh()
    if looked then return end
    looked = true
    local found = false
    g.lasting(function() return g.process {
        command = { "sh", "-c", "grep -ls '^E:ID_INPUT_TOUCHPAD=1' /run/udev/data/c13:* 2>/dev/null" },
        on_line = function(line: string) if line ~= "" then found = true end end,
        on_exit = function() touchpad.value = found end,
    } end)
end

return M
