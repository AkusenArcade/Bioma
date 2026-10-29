--!strict
-- The desktop's look outside the palette: its icon theme and its cursor
-- (services/Looks.qml).
--
-- Neither is the shell's to keep: they are the desktop's settings, read
-- through `scripts/looks list`. Until the switch (genoma/PORT.md, "Who acts
-- on the desktop") a choice made here is handed to Bioma on Quickshell, which
-- sets the desktop and rebuilds Bioma's own themes in the palette; this reads
-- the desktop again after. The base under Bioma's icon themes is
-- configuration, written here and followed there.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

-- { { id, name, slotted } }, by the themes' own names; and what the desktop
-- is set to, the theme as listed and the live name (a slot, for Bioma's).
local listed = g.signal({ icons = {}, cursors = {}, current = {} })

local reading: any = nil
function M.refresh()
    if reading and reading.running then return end
    local out = {}
    reading = g.process {
        command = { paths.script("looks"), "list" },
        on_line = function(line: string) table.insert(out, line) end,
        on_exit = function(code: number)
            if code ~= 0 then return end
            local ok, data = pcall(g.parse_json, table.concat(out, "\n"))
            if ok and type(data) == "table" then
                listed.value = { icons = data.icons or {}, cursors = data.cursors or {}, current = data.current or {} }
            end
        end,
    }
end
M.refresh()

function M.icons(): { any } return listed.value.icons end
function M.cursors(): { any } return listed.value.cursors end
function M.icon_theme(): string return listed.value.current.icons or "" end
function M.cursor_theme(): string return listed.value.current.cursor or "" end
function M.cursor_size(): number return listed.value.current.size or 24 end

-- Sizes worth offering; the one set now is kept among them whatever it is.
function M.sizes(): { number }
    local out = { 24, 32, 48 }
    local now = M.cursor_size()
    if now > 0 and not table.find(out, now) then table.insert(out, now) end
    table.sort(out)
    return out
end

function M.icon_base(): string
    local base = config.get("theme.icon_base", "")
    return if base ~= "" then base else "Adwaita"
end

function M.name_of(list: { any }, id: string): string
    for _, t in list do
        if t.id == id then return t.name end
    end
    return id
end
function M.is_slotted(list: { any }, id: string): boolean
    for _, t in list do
        if t.id == id then return t.slotted == true end
    end
    return false
end

-- ---- Choosing: Quickshell acts --------------------------------------------------

local function ask(...: string)
    local args = { ... }
    local command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "looks" }
    for _, a in args do table.insert(command, a) end
    g.process {
        command = command,
        on_exit = function()
            -- The desktop says what it took.
            g.after(0.3, M.refresh)
        end,
    }
end

function M.set_icons(id: string)
    if id == "" or id == g.untracked(M.icon_theme) then return end
    ask("icons", id)
end
function M.set_icon_base(id: string)
    if id == "" or id == g.untracked(M.icon_base) or M.is_slotted(g.untracked(M.icons), id) then return end
    config.set("theme.icon_base", id)
end
function M.set_cursor(id: string, size: number)
    local theme = if id ~= "" then id else g.untracked(M.cursor_theme)
    local px = if size > 0 then size else g.untracked(M.cursor_size)
    if theme == g.untracked(M.cursor_theme) and px == g.untracked(M.cursor_size) then return end
    ask("cursor", theme, tostring(px))
end

return M
