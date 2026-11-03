--!strict
-- The desktop's look outside the palette: its icon theme, its cursor, and
-- how strong niri's blur is (services/Looks.qml at 8ed8892).
--
-- Neither is the shell's to keep. The icon theme is the desktop's setting
-- (gsettings, qt5ct and qt6ct's own); the cursor is the same setting for the
-- toolkits and niri's `cursor` section, written as `bioma-cursor.kdl`
-- through `scripts/niri-include`. So what is shown is read from the desktop
-- (`scripts/looks list`), and nothing is written until something is chosen.
--
-- Bioma's own cursors and icons are drawn in the palette (`scripts/cursors`,
-- `scripts/icon-theme`): rebuilt whenever the palette settles and installed
-- as themes. niri and the toolkits keep a theme loaded by its name, so the
-- desktop is set to one of a theme's two slots, `<id>.a` or `<id>.b`, and
-- moved to the other after a rebuild.
--
-- Bioma on Genoma alone acts (M6 step 7a, `start`); beside Quickshell, a
-- choice made here is handed to Quickshell, which sets the desktop and
-- rebuilds the themes, and this reads the desktop again after.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics = require("core/metrics")
local paths = require("core/paths")
local runtime = require("core/runtime")
local theme = require("core/theme")
local timing = require("core/timing")

local M = {}

-- { { id, name, slotted } }, by the themes' own names; and what the desktop
-- is set to: the theme as listed and the live name (a slot, for Bioma's).
local listed = g.signal({ icons = {}, cursors = {}, current = {} })
-- What was set from here and not yet read back.
local chosen = g.signal({} :: { [string]: any })
-- The last thing that was refused, in its own words.
local refused = g.signal("")
function M.error(): string return refused.value end

local adopt: () -> ()

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
                g.batch(function()
                    listed.value = { icons = data.icons or {}, cursors = data.cursors or {}, current = data.current or {} }
                    chosen.value = {}
                end)
                adopt()
            end
        end,
    }
end
M.refresh()

local function current(key: string, fallback: any): any
    local c = chosen.value[key]
    if c ~= nil then return c end
    local v = listed.value.current[key]
    return if v ~= nil and v ~= "" then v else fallback
end

function M.icons(): { any } return listed.value.icons end
function M.cursors(): { any } return listed.value.cursors end
function M.icon_theme(): string return current("icons", "") end
function M.cursor_theme(): string return current("cursor", "") end
function M.cursor_size(): number return current("size", 24) end
local function icon_live(): string return current("iconsLive", M.icon_theme()) end
local function cursor_live(): string return current("live", M.cursor_theme()) end

-- Sizes worth offering; the one set now is kept among them whatever it is.
function M.sizes(): { number }
    local out = { 24, 32, 48 }
    local now = M.cursor_size()
    if now > 0 and not table.find(out, now) then table.insert(out, now) end
    table.sort(out)
    return out
end

-- The theme Bioma's icon themes sit on: applications and every icon they do
-- not draw come from it.
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

-- The name to set the desktop to for `id`: itself, or the slot it is not on
-- now, so niri and the toolkits load it afresh.
local function live_name(list: { any }, id: string, live: string): string
    if not M.is_slotted(list, id) then return id end
    return if live == id .. ".a" then id .. ".b" else id .. ".a"
end

-- ---- Setting --------------------------------------------------------------------

local function ask(...: string)
    local command = { paths.script("ipc"), "looks" }
    for _, a in { ... } do table.insert(command, a) end
    g.process {
        command = command,
        on_exit = function() g.after(0.3, M.refresh) end,
    }
end

local function remember(values: { [string]: any })
    local next_chosen = table.clone(g.untracked(function() return chosen.value end))
    for k, v in values do next_chosen[k] = v end
    chosen.value = next_chosen
end

-- One writer at a time for each niri include; a body that arrives while
-- one is written is written after it, the latest only.
local function include_writer(name: string): (string) -> ()
    local writing, next_body = false, nil :: string?
    local function write(body: string)
        if writing then
            next_body = body
            return
        end
        writing = true
        local said = {}
        local p = g.process {
            command = { paths.script("niri-include"), name },
            on_error_line = function(line: string) table.insert(said, line) end,
            on_exit = function()
                writing = false
                local reason = string.match(table.concat(said, "\n"), "^%s*(.-)%s*$") or ""
                if reason ~= "" then refused.value = "niri refused it: " .. reason end
                if next_body then
                    local again = next_body :: string
                    next_body = nil
                    write(again)
                end
            end,
        }
        p:write(body)
        p:close_input()
    end
    return write
end
local write_cursor = include_writer("cursor")
local write_blur = include_writer("blur")

local function apply_icons(id: string)
    local live = live_name(g.untracked(M.icons), id, g.untracked(icon_live))
    remember({ icons = id, iconsLive = live })
    refused.value = ""
    g.process { command = { paths.script("looks"), "icons", live } }
end

local function apply_cursor(id: string, px: number)
    local live = live_name(g.untracked(M.cursors), id, g.untracked(cursor_live))
    remember({ cursor = id, live = live, size = px })
    refused.value = ""
    g.process { command = { paths.script("looks"), "cursor", live, tostring(px) } }
    local quoted = '"' .. string.gsub(live, '["\\]', "") .. '"'
    write_cursor("// Written by Bioma's theme cell (DESKTOP). Choosing a cursor there rewrites it.\n"
        .. "cursor {\n    xcursor-theme " .. quoted .. "\n    xcursor-size " .. px .. "\n}")
end

function M.set_icons(id: string)
    if id == "" or id == g.untracked(M.icon_theme) then return end
    if not g.untracked(runtime.alone) then
        ask("icons", id)
        return
    end
    -- Leaving a theme of somebody else's for one of Bioma's: what was on the
    -- desktop becomes what Bioma's sits on, so the applications look as
    -- they did.
    local icons, now = g.untracked(M.icons), g.untracked(M.icon_theme)
    if M.is_slotted(icons, id) and now ~= "" and not M.is_slotted(icons, now) and now ~= g.untracked(M.icon_base) then
        config.set("theme.icon_base", now)
    end
    apply_icons(id)
end
function M.set_icon_base(id: string)
    if id == "" or id == g.untracked(M.icon_base) or M.is_slotted(g.untracked(M.icons), id) then return end
    config.set("theme.icon_base", id)
end
function M.set_cursor(id: string, size: number)
    local theme_id = if id ~= "" then id else g.untracked(M.cursor_theme)
    local px = if size > 0 then size else g.untracked(M.cursor_size)
    if theme_id == g.untracked(M.cursor_theme) and px == g.untracked(M.cursor_size) then return end
    if not g.untracked(runtime.alone) then
        ask("cursor", theme_id, tostring(px))
        return
    end
    apply_cursor(theme_id, px)
end

-- How strong the glass is: niri's own `blur` section, global, written as
-- `bioma-blur.kdl` last, so it overrides the user's `passes` and `offset`
-- and leaves the rest of their section alone. Only when the step is moved.
function M.set_blur(strength: number)
    local steps = metrics.blur_steps
    local index = math.clamp(math.floor(strength + 0.5), 1, #steps)
    if not g.untracked(runtime.alone) then
        ask("blur", tostring(index))
        return
    end
    if index == g.untracked(metrics.blur_strength) then return end
    config.set("cell.blurStrength", index)
    local step = steps[index]
    write_blur("// Written by Bioma's settings cell (APPEARANCE). Moving the blur slider rewrites it.\n"
        .. "blur {\n    passes " .. step.passes .. "\n    offset " .. string.format("%.1f", step.offset) .. "\n}")
end

-- ---- Bioma's cursors and icons --------------------------------------------------

-- The colours they are drawn in, from the palette's targets, not the
-- animated values that pass through every colour in between.
local drawn = g.computed(function(): { [string]: string }
    local bg, p = theme.target("background"), theme.target("primary")
    local dark = theme.target_is_dark()
    local function hex(c: string): string return string.sub(colour.format(colour.parse(c)), 1, 7) end
    -- A folder's back, behind its primary face: the same hue, in shade.
    local ph, ps, pl = colour.hsl(colour.parse(p))
    local function shade(s: number, l: number): string
        return string.sub(colour.format(colour.hsla(math.max(0, ph), math.max(0, ps - s), math.max(0, pl - l), 1)), 1, 7)
    end
    return {
        background = hex(bg),
        text = hex(theme.target("text")),
        primary = hex(p),
        cell = hex(theme.lift_away(bg, 0.075, dark)),
        raised = hex(theme.lift_away(bg, 0.12, dark)),
        rim = hex(theme.structural_with(bg, p, if dark then 0.55 else 0.50)),
        line = hex(theme.structural_with(bg, p, if dark then 0.32 else 0.72)),
        grad_top = hex(theme.gradient_top(p)),
        grad_bottom = hex(theme.gradient_bottom(p)),
        back_top = shade(0.1, 0.18),
        back_bottom = shade(0.2, 0.3),
    }
end)
local cursor_request = g.computed(function(): string
    local sweep = timing.curves.sweep
    return g.to_json({
        colours = drawn.value,
        loader = { ms = math.floor(timing.seconds.loader * 1000 + 0.5), ease = g.array({ sweep[1], sweep[2], sweep[3], sweep[4] }) },
    })
end)
local icon_request = g.computed(function(): string
    return g.to_json({ colours = drawn.value, base = M.icon_base() })
end)

-- Runs a builder with a request; one that arrives while it runs is built
-- after it, the latest only. `built` when the builder made something new.
local function builder(script: string, built: () -> ()): (string) -> ()
    local running, next_request = false, nil :: string?
    local function build(request: string)
        if running then
            next_request = request
            return
        end
        running = true
        local out, said = {}, {}
        local p = g.process {
            command = { paths.script(script), "build" },
            on_line = function(line: string) table.insert(out, line) end,
            on_error_line = function(line: string) table.insert(said, line) end,
            on_exit = function()
                running = false
                local ok, report = pcall(g.parse_json, table.concat(out, "\n"))
                if ok and type(report) == "table" and report.built == true then built() end
                local reason = string.match(table.concat(said, "\n"), "^%s*(.-)%s*$") or ""
                if reason ~= "" then print("Bioma: scripts/" .. script .. " — " .. reason) end
                if next_request then
                    local again = next_request :: string
                    next_request = nil
                    build(again)
                end
            end,
        }
        p:write(request)
        p:close_input()
    end
    return build
end

-- New themes appear in the list; the one on the desktop, if it is ours, is
-- moved to its other slot so the new colours show.
local build_cursors = builder("cursors", function()
    M.refresh()
    if g.untracked(cursor_live) ~= g.untracked(M.cursor_theme) then
        apply_cursor(g.untracked(M.cursor_theme), g.untracked(M.cursor_size))
    end
end)
local build_icons = builder("icon-theme", function()
    M.refresh()
    if g.untracked(icon_live) ~= g.untracked(M.icon_theme) then apply_icons(g.untracked(M.icon_theme)) end
end)

-- ---- The first start --------------------------------------------------------------
--
-- Bioma's own looks are put on the desktop once, the first time they have
-- been built: a fresh install comes up in its own icons and cursor. Once
-- (`looks_adopted` is written either way), and never over one of Bioma's
-- themes already chosen.
local settled = false
local started = false
adopt = function()
    if not started or not settled or config.get("theme.looks_adopted", false) then return end
    local icons, cursors = g.untracked(M.icons), g.untracked(M.cursors)
    if not M.is_slotted(icons, "bioma-icons") or not M.is_slotted(cursors, "bioma") then return end
    if not M.is_slotted(icons, g.untracked(M.icon_theme)) then
        M.set_icons("bioma-icons")
    end
    if not M.is_slotted(cursors, g.untracked(M.cursor_theme)) then
        local size = g.untracked(M.cursor_size)
        apply_cursor("bioma", if size > 0 then size else 24)
    end
    config.set("theme.looks_adopted", true)
end

function M.start()
    if started then return end
    started = true
    -- Once the shell has settled, and again whenever the palette rests.
    g.after(timing.seconds.settle, function()
        settled = true
        build_cursors(g.untracked(function() return cursor_request.value end))
        build_icons(g.untracked(function() return icon_request.value end))
        adopt()
    end)
    local cursor_wait: any, icon_wait: any = nil, nil
    g.watch(function() return cursor_request.value end, function(request: string)
        if not settled then return end
        if cursor_wait then cursor_wait:stop() end
        cursor_wait = g.after(timing.seconds.debounce, function() build_cursors(request) end)
    end)
    g.watch(function() return icon_request.value end, function(request: string)
        if not settled then return end
        if icon_wait then icon_wait:stop() end
        icon_wait = g.after(timing.seconds.debounce, function() build_icons(request) end)
    end)
end

return M
