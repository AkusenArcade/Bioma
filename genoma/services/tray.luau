--!strict
-- The tray (services/Tray.qml at 11bb81e), on Genoma's StatusNotifierItem
-- domain: Genoma registers as a host with the watcher Bioma on Quickshell
-- serves, so the two read the same items side by side.
--
-- Not yet: an icon an application sends only as pixels (Genoma's images
-- from pixels are still to come); such an item shows the neutral glyph.
local g = require("@genoma")
local sni = require("@genoma/tray")

local M = {}

local RANK = { Hardware = 0, Communications = 1, SystemServices = 2 }
local function rank(item: any): number return RANK[item.category] or 3 end

local items = g.computed(function(): { any }
    local out = {}
    for _, it in sni.items do table.insert(out, it) end
    table.sort(out, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        -- As a person reads them, capitals or not.
        return string.lower(tostring(a.id)) < string.lower(tostring(b.id))
    end)
    return out
end)
function M.items(): { any } return items.value end
function M.count(): number return #items.value end

function M.attending(item: any): boolean return item ~= nil and item.status == "NeedsAttention" end

function M.name_of(item: any): string
    if not item then return "" end
    return if (item.title or "") ~= "" then item.title else tostring(item.id or "")
end

-- The file to draw: the name the item gives, looked up in its own theme
-- path first, then the desktop's; "" when only pixels were sent.
function M.icon_for(item: any): string
    if not item then return "" end
    local name = if item.status == "NeedsAttention" and (item.attention_icon_name or "") ~= ""
        then item.attention_icon_name else item.icon_name or ""
    if name == "" then return "" end
    if string.sub(name, 1, 1) == "/" then return name end
    local found = g.icon_path(name)
    if found then return found end
    local theme_path = item.icon_theme_path or ""
    return if theme_path ~= "" then theme_path .. "/" .. name .. ".png" else ""
end

-- A press opens the menu of an item that is only a menu, or has no action.
function M.acts(item: any): boolean return item ~= nil and not item.only_menu end
function M.opens(item: any): boolean return item ~= nil and item.has_menu and (item.only_menu or not M.acts(item)) end
function M.activate(item: any) if M.acts(item) then sni:activate(item.key) end end
function M.secondary(item: any) if M.acts(item) then sni:secondary_activate(item.key) end end
function M.scroll(item: any, steps: number) if item then sni:scroll(item.key, steps * 120) end end

-- The menu, read when it is opened and followed while it is.
function M.open_menu(item: any) if item then sni:open_menu(item.key) end end
function M.close_menu(item: any) if item then sni:close_menu(item.key) end end
function M.menu(item: any): any return if item then sni:menu(item.key) else nil end
function M.click(item: any, id: number) if item then sni:menu_click(item.key, id) end end

return M
