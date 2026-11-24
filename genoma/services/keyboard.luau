--!strict
-- The keyboard's layouts (services/Keyboard.qml at 11bb81e): which the
-- compositor has loaded and which is on, and the switch between them, from
-- Genoma's `compositor.keyboard` (niri's, Hyprland's or Umbriel's event
-- stream); the catalogue this machine knows, from `scripts/xkb`; and the
-- list written back, as an include of the compositor's own (niri's,
-- Hyprland's or Umbriel's), when one is added or removed here.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local compositor = require("@genoma/compositor")
local running = require("services/compositor").name()

local M = {}

function M.loaded(): { string } return compositor.keyboard.layouts end
function M.current(): string return compositor.keyboard.name or "" end
function M.current_index(): number return compositor.keyboard.current or 0 end

-- A change of layout seen, not the first one read.
local listeners: { () -> () } = {}
function M.on_switched(f: () -> ()) table.insert(listeners, f) end
local last_seen = ""
g.watch(M.current, function(now: string)
    if last_seen ~= "" and now ~= "" and now ~= last_seen then
        for _, f in listeners do f() end
    end
    if now ~= "" then last_seen = now end
end)

local catalogue = g.signal({})
do
    local lines = {}
    g.process {
        command = { paths.script("xkb"), "list" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function()
            local ok, list = pcall(g.parse_json, table.concat(lines, "\n"))
            if ok and type(list) == "table" then catalogue.value = list end
        end,
    }
end
function M.catalogue(): { any } return catalogue.value end

-- The loaded layouts with their codes, matched back by xkeyboard-config's
-- names, which are also niri's and Umbriel's. Hyprland says the codes
-- alone: the variant is the one written from here, when the codes are the
-- same, else the plain layout.
function M.layouts(): { any }
    local by_name, by_code = {}, {}
    for _, e in catalogue.value do
        by_name[e.name] = e
        by_code[e.layout .. ":" .. (e.variant or "")] = e
    end
    local kept = config.get("keyboard.layouts", {})
    local out = {}
    for i, name in M.loaded() do
        local known = by_name[name]
        if not known then
            local mine = kept[i]
            local variant = if mine and mine.layout == name then mine.variant or "" else ""
            known = by_code[name .. ":" .. variant] or by_code[name .. ":"]
        end
        table.insert(out, { name = if known then known.name else name,
            layout = if known then known.layout else "", variant = if known then known.variant else "" })
    end
    return out
end

function M.code_of(entry: any): string
    if not entry then return "" end
    if (entry.layout or "") ~= "" then return string.upper(entry.layout) end
    return string.upper(string.sub(entry.name or "", 1, 2))
end
function M.current_code(): string return M.code_of(M.layouts()[M.current_index()]) end

function M.switch_to(index: number)
    if index < 1 or index > #g.untracked(M.loaded) or index == g.untracked(M.current_index) then return end
    compositor:switch_layout(index)
end
function M.next() compositor:switch_layout("next") end

-- ---- Writing the list --------------------------------------------------------

local error_text = g.signal("")
function M.error(): string return error_text.value end

local function codes(): { any }
    local out = g.array()
    for _, e in g.untracked(M.layouts) do
        if e.layout ~= "" then table.insert(out, { layout = e.layout, variant = e.variant }) end
    end
    return out
end

-- The list in the compositor's words: niri's xkb block, Hyprland's
-- kb_layout and kb_variant, Umbriel's [input.keyboard].
local function include(list: { any }): string
    local function quote(v: string): string return '"' .. string.gsub(v, '["\\]', "") .. '"' end
    local layouts, variants = {}, {}
    for _, e in list do
        table.insert(layouts, e.layout)
        table.insert(variants, e.variant or "")
    end
    local layout, variant = quote(table.concat(layouts, ",")), quote(table.concat(variants, ","))
    if running == "hyprland" then
        return "-- Written by Bioma's keyboard cell. Changing layouts there rewrites it.\n"
            .. "hl.config({\n    input = {\n        kb_layout = " .. layout .. ",\n        kb_variant = " .. variant .. ",\n    },\n})\n"
    end
    if running == "umbriel" then
        return "# Written by Bioma's keyboard cell. Changing layouts there rewrites it.\n\n"
            .. "[input.keyboard]\nlayout = " .. layout .. "\nvariant = " .. variant .. "\n"
    end
    return "// Written by Bioma's keyboard cell. Changing layouts there rewrites it.\n"
        .. "input {\n    keyboard {\n        xkb {\n"
        .. "            layout " .. layout .. "\n"
        .. "            variant " .. variant .. "\n"
        .. "        }\n    }\n}"
end
local SCRIPTS = { niri = { "niri-include", "niri" }, hyprland = { "hypr-include", "Hyprland" }, umbriel = { "umbriel-include", "Umbriel" } }

-- A change asked for here is made here: the list into the configuration and
-- the compositor's include that loads it.
local function write(list: { any })
    if #list == 0 then return end
    local script = SCRIPTS[running]
    if not script then
        error_text.value = "Bioma does not write this compositor's layouts."
        return
    end
    config.set("keyboard.layouts", list)
    error_text.value = ""
    local complaint = {}
    local writer = g.process {
        command = { paths.script(script[1]), "keyboard" },
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function()
            local reason = string.match(table.concat(complaint, " "), "^%s*(.-)%s*$") or ""
            if reason ~= "" then error_text.value = script[2] .. " refused it: " .. reason end
        end,
    }
    writer:write(include(list))
    writer:close_input()
end

function M.add(entry: any)
    if not entry then return end
    local list = codes()
    for _, e in list do
        if e.layout == entry.layout and e.variant == (entry.variant or "") then return end
    end
    table.insert(list, { layout = entry.layout, variant = entry.variant or "" })
    write(list)
end

function M.remove(index: number)
    local list = codes()
    if #list <= 1 or index < 1 or index > #list then return end
    table.remove(list, index)
    write(list)
end

return M
