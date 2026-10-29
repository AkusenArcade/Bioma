--!strict
-- The keyboard's layouts (services/Keyboard.qml at 11bb81e): which niri has
-- loaded and which is on, from its event stream; the catalogue this machine
-- knows, from `scripts/xkb`; and the list written back, as a niri include,
-- when one is added or removed here.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local niri = require("services/niri")

local M = {}

function M.loaded(): { string } return niri.layout_names() end
function M.current(): string return niri.keyboard_layout() end
function M.current_index(): number return table.find(niri.layout_names(), niri.keyboard_layout()) or 0 end

-- A change of layout seen, not the first one read.
local listeners: { () -> () } = {}
function M.on_switched(f: () -> ()) table.insert(listeners, f) end
local last_seen = ""
g.watch(niri.keyboard_layout, function(now: string)
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
-- names, which are also niri's.
function M.layouts(): { any }
    local by_name = {}
    for _, e in catalogue.value do by_name[e.name] = e end
    local out = {}
    for _, name in niri.layout_names() do
        local known = by_name[name]
        table.insert(out, { name = name, layout = if known then known.layout else "", variant = if known then known.variant else "" })
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
    if index < 1 or index > #niri.layout_names() or index == g.untracked(M.current_index) then return end
    niri.switch_layout(tostring(index - 1))
end
function M.next() niri.switch_layout("next") end

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

local function kdl(list: { any }): string
    local function quote(v: string): string return '"' .. string.gsub(v, '["\\]', "") .. '"' end
    local layouts, variants = {}, {}
    for _, e in list do
        table.insert(layouts, e.layout)
        table.insert(variants, e.variant or "")
    end
    return "// Written by Bioma's keyboard cell. Changing layouts there rewrites it.\n"
        .. "input {\n    keyboard {\n        xkb {\n"
        .. "            layout " .. quote(table.concat(layouts, ",")) .. "\n"
        .. "            variant " .. quote(table.concat(variants, ",")) .. "\n"
        .. "        }\n    }\n}"
end

-- A change asked for here is made here: the list into the configuration and
-- the niri include that loads it.
local function write(list: { any })
    if #list == 0 then return end
    config.set("keyboard.layouts", list)
    error_text.value = ""
    local complaint = {}
    local writer = g.process {
        command = { paths.script("niri-include"), "keyboard" },
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function()
            local reason = string.match(table.concat(complaint, " "), "^%s*(.-)%s*$") or ""
            if reason ~= "" then error_text.value = "niri refused it: " .. reason end
        end,
    }
    writer:write(kdl(list))
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
