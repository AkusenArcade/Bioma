--!strict
-- Settings → Apps (PRD §9.12, added 2026-11-27): the default applications.
--
-- One well a role — browser, mail, terminal, files, text, images, video,
-- music, PDF, archives — each choosing among the applications that open its
-- types, and written for every type of the role the chosen one opens, into
-- the user's mimeapps.list (@genoma/mime), as GNOME's Default Applications
-- does. The terminal has no type: it is the head of xdg-terminals.list,
-- which xdg-terminal-exec reads, and which Bioma's own Mod+T
-- (scripts/terminal) reads too where xdg-terminal-exec is not installed.
-- "Other" gives one type alone, named by a file's name, its extension or
-- the type itself.
local g = require("@genoma")
local apps = require("@genoma/apps")
local mime = require("@genoma/mime")
local typography = require("core/typography")
local theme = require("core/theme")
local metrics_mod = require("core/metrics")
local page = require("components/page")
local dropdown = require("components/dropdown")
local field_mod = require("components/field")

local M = {}

local CLEAR = "#00000000"

type Role = { key: string, label: string, types: { string }, says: (name: string) -> string }

-- The first type of each is the one asked who opens it; the others follow
-- the choice where the chosen application opens them too.
local ROLES: { Role } = {
    {
        key = "browser", label = "BROWSER",
        types = { "x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml" },
        says = function(n: string) return `Links and web pages open in {n}.` end,
    },
    {
        key = "mail", label = "MAIL",
        types = { "x-scheme-handler/mailto" },
        says = function(n: string) return `An address to write to opens a new message in {n}.` end,
    },
    {
        key = "files", label = "FILES",
        types = { "inode/directory" },
        says = function(n: string) return `Folders open in {n}.` end,
    },
    {
        key = "text", label = "TEXT",
        types = { "text/plain", "text/markdown", "application/x-shellscript" },
        says = function(n: string) return `Plain text, notes and scripts open in {n}.` end,
    },
    {
        key = "images", label = "IMAGES",
        types = { "image/png", "image/jpeg", "image/webp", "image/gif", "image/svg+xml", "image/avif", "image/bmp", "image/tiff" },
        says = function(n: string) return `Pictures open in {n}.` end,
    },
    {
        key = "video", label = "VIDEO",
        types = { "video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg" },
        says = function(n: string) return `Videos play in {n}.` end,
    },
    {
        key = "music", label = "MUSIC",
        types = { "audio/mpeg", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus", "audio/x-wav", "audio/mp4" },
        says = function(n: string) return `Songs and recordings play in {n}.` end,
    },
    {
        key = "pdf", label = "PDF",
        types = { "application/pdf" },
        says = function(n: string) return `Documents in PDF open in {n}.` end,
    },
    {
        key = "archives", label = "ARCHIVES",
        types = { "application/zip", "application/x-tar", "application/x-compressed-tar", "application/x-xz-compressed-tar",
            "application/x-zstd-compressed-tar", "application/x-7z-compressed", "application/vnd.rar", "application/gzip" },
        says = function(n: string) return `Archives open in {n}.` end,
    },
}

-- What is written changes the answers: every reading follows it.
local changed = g.signal(0)

-- An application's icon as a file, or "".
local function picture_of(id: string): string
    local app = if id ~= "" then apps:find(id) else nil
    local icon = app and app.icon
    if icon == nil or icon == "" then return "" end
    if string.sub(icon, 1, 1) == "/" then return icon end
    return g.icon_path(icon) or ""
end

local function options_of(list: { any }): { { key: string, label: string } }
    local out: { { key: string, label: string } } = {}
    local seen: { [string]: boolean } = {}
    for _, app in list do
        if not seen[app.id] then
            seen[app.id] = true
            table.insert(out, { key = app.id, label = app.name })
        end
    end
    table.sort(out, function(a, b) return string.lower(a.label) < string.lower(b.label) end)
    return out
end

local function name_of(id: string?): string
    local app = if id and id ~= "" then apps:find(id) else nil
    return if app then app.name else ""
end

-- The applications that open a type, and the one that does when nobody
-- chooses.
local function openers(type_: string): { any }
    local _ = changed.value
    local ok, list = pcall(function() return mime:apps(type_) end)
    return if ok and list then list else {}
end
local function default_of(type_: string): string
    local _ = changed.value
    local ok, app = pcall(function() return mime:default(type_) end)
    return if ok and app then app.id else ""
end

-- Chosen for a role: every type of it the application opens.
local function choose(role: Role, id: string)
    for _, type_ in role.types do
        for _, app in openers(type_) do
            if app.id == id then
                pcall(function() mime:set_default(type_, id) end)
                break
            end
        end
    end
    changed.value += 1
end

-- ---- The terminal: xdg-terminals.list ---------------------------------------------

local config_home = g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")
local terminals_file = g.file { path = config_home .. "/xdg-terminals.list" }

local function terminals(): { any }
    local out: { any } = {}
    for _, app in apps.list do
        -- (Genoma gives the categories in lower case.)
        for _, c in app.categories do
            if string.lower(c) == "terminalemulator" then
                table.insert(out, app)
                break
            end
        end
    end
    return out
end

-- The head of the list, as an application id; else the one $TERMINAL names.
local function terminal_now(): string
    for line in string.gmatch(terminals_file.text or "", "[^\n]+") do
        local entry = string.match(line, "^%s*(.-)%s*$") or ""
        if entry ~= "" and string.sub(entry, 1, 1) ~= "#" then
            local id = string.gsub(string.match(entry, "^[^:]+") or entry, "%.desktop$", "")
            return id
        end
    end
    local named = g.env("TERMINAL") or ""
    named = string.match(named, "([^/]+)$") or named
    if named == "" then return "" end
    for _, app in terminals() do
        local first = string.match(app.exec or "", "^%s*(%S+)") or ""
        if (string.match(first, "([^/]+)$") or first) == named or app.id == named then return app.id end
    end
    return ""
end

-- The chosen one at the head; what the person wrote stays, comments too.
local function set_terminal(id: string)
    local entry = id .. ".desktop"
    local out: { string } = {}
    for line in string.gmatch(terminals_file.text or "", "[^\n]+") do
        local e = string.match(line, "^%s*(.-)%s*$") or ""
        if string.match(e, "^[^:]+") ~= entry then table.insert(out, line) end
    end
    local at = 1
    while at <= #out and (string.match(out[at], "^%s*#") or string.match(out[at], "^%s*$")) do at += 1 end
    table.insert(out, at, entry)
    terminals_file:write(table.concat(out, "\n") .. "\n")
end

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section
    local function m(): any return t.metrics() end
    local dropdowns: { any } = {}

    local function picker(options: () -> { { key: string, label: string } }, current: () -> string, on_choose: (string) -> ()): any
        local node, handle = dropdown.new {
            metrics = m,
            width = function() return 210 * f() end,
            rows = 8,
            options = function()
                local list = options()
                local now = current()
                if now ~= "" then
                    for _, o in list do
                        if o.key == now then return list end
                    end
                    local with = table.clone(list)
                    table.insert(with, 1, { key = now, label = name_of(now) ~= "" and name_of(now) or now })
                    return with
                end
                return if #list > 0 then list else { { key = "", label = "None installed" } }
            end,
            current = current,
            picture = picture_of,
            on_choose = function(key: string) if key ~= "" then on_choose(key) end end,
        }
        table.insert(dropdowns, handle)
        return node
    end

    local function role_well(role: Role): any
        local function current(): string return default_of(role.types[1]) end
        return section(role.label, picker(function() return options_of(openers(role.types[1])) end, current, function(id: string) choose(role, id) end), {
            line(function()
                local n = name_of(current())
                return if n ~= "" then role.says(n) else "Nothing is chosen: each program asks, or picks for itself."
            end),
        })
    end

    local wells: { any } = {}
    for i, role in ROLES do
        table.insert(wells, role_well(role))
        -- The terminal after the mail: the three that are reached for most.
        if role.key == "mail" then
            table.insert(wells, section("TERMINAL", picker(function() return options_of(terminals()) end, terminal_now, set_terminal), {
                line(function()
                    local n = name_of(terminal_now())
                    if n == "" then return "Nothing is chosen: Bioma's Mod+T and the programs that ask for a terminal try the usual ones." end
                    return `Bioma's Mod+T, the file manager's terminal and programs run in a terminal open {n}.`
                end),
            }))
        end
    end

    -- ---- Other: one type alone ----------------------------------------------------------

    local typing = g.signal(false)
    local asked = g.signal("")
    local field_node, field = field_mod.new {
        text = asked,
        width = function() return p.inner() - 28 * f() end,
        font = typography.technical,
        size = function() return m().font_meta end,
        placeholder = "report.md, .md or text/markdown",
        taking = function() return typing.value end,
    }
    -- The type what was typed names: a type as it is, else what a name or
    -- an extension says.
    local function asked_type(): string
        local text = string.match(asked.value, "^%s*(.-)%s*$") or ""
        if text == "" then return "" end
        if string.find(text, "/", 1, true) and not string.find(text, "%.") then return string.lower(text) end
        local name = if string.sub(text, 1, 1) == "." then "file" .. text elseif string.find(text, "%.") then text else "file." .. text
        local ok, found = pcall(function() return mime:of_name(name) end)
        return if ok and found then found else ""
    end
    local function chip_height(): number return 28 * f() end
    local function edge(): string return if typing.value then theme.primary() else theme.control_edge() end
    local other = section("OTHER", nil, {
        g.capsule {
            role = "button",
            name = "A file's name, an extension or a type",
            width = p.inner,
            height = chip_height,
            padding_x = function() return 14 * f() end,
            direction = "row",
            align = "center",
            justify = "start",
            radius = function() return metrics_mod.radius_for(chip_height(), m()) end,
            fill = CLEAR,
            rim_top = edge,
            rim_bottom = edge,
            on_click = function() typing.value = true end,
            g.text {
                present = function() return not typing.value end,
                text = function() return if asked.value ~= "" then asked.value else "report.md, .md or text/markdown" end,
                color = function() return if asked.value ~= "" then theme.text() else theme.text_faint() end,
                font = typography.technical,
                size = function() return m().font_meta end,
            },
            g.box { present = function() return typing.value end, field_node },
        },
        g.box {
            present = function() return asked_type() ~= "" end,
            width = p.inner,
            direction = "row",
            align = "center",
            justify = "between",
            g.text {
                text = function()
                    local ty = asked_type()
                    local ok, said = pcall(function() return mime:description(ty) end)
                    return string.upper(if ok and said and said ~= "" then said else ty)
                end,
                color = theme.text,
                font = typography.technical,
                size = function() return m().font_meta end,
                tracking = typography.label_tracking,
                max_width = function() return p.inner() - 230 * f() end,
                ellipsize = "end",
            },
            picker(function() return options_of(openers(asked_type())) end, function() return default_of(asked_type()) end, function(id: string)
                pcall(function() mime:set_default(asked_type(), id) end)
                changed.value += 1
            end),
        },
        line(function()
            if asked.value == "" then return "One kind of file alone, apart from its role: write a file's name, its extension or its type." end
            local ty = asked_type()
            if ty == "" then return "Nothing is known by that name." end
            local n = name_of(default_of(ty))
            return if n ~= "" then `{ty} opens in {n}.` else `Nothing opens {ty} yet.`
        end),
    })
    table.insert(wells, other)

    t.keyed(function(name: string, typed: string?, mods: { [string]: boolean }): boolean
        if name == "Escape" then
            for _, d in dropdowns do
                if g.untracked(function() return d.open.value end) then
                    d.close()
                    return true
                end
            end
        end
        if not g.untracked(function() return typing.value end) then return false end
        if name == "Escape" or name == "Return" or name == "KP_Enter" then
            typing.value = false
            return true
        end
        return field.key(name, typed, mods)
    end)

    return p.column(wells)
end

return M
