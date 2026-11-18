--!strict
-- Bioma's greeter (greeter.qml at 2cafc17), on Genoma: a second entry point
-- of the same interface, run by greetd before anyone is logged in as
-- `genoma <this directory> greeter.luau`.
--
-- It is the lock screen's threshold (components/gate.luau) with greetd in
-- place of PAM: the same wallpaper and mode, the same palette and
-- appearance, the same clock, so that logging in and unlocking are one
-- gesture. The interactive elements are only on the primary monitor
-- (Akusen, 2026-09-24).
--
-- It runs as the `greeter` user, who cannot read the person's home, from the
-- copy the shell keeps up to date (scripts/greeter-sync): these files, the
-- configuration under `config/` (XDG_CONFIG_HOME points there), the
-- wallpapers, the fonts, and `user.json`, who to greet.
--
-- In the corner of the primary screen, the machine's own commands: restart,
-- restart into the firmware's setup, shut down (Akusen, 2026-11-02). Nobody
-- is logged in yet, so nothing is lost and nothing asks twice: the session
-- cell confirms only where something would be lost. Beside them, the
-- sessions installed, to choose which one starts (Akusen, 2026-11-18):
-- niri, Hyprland, Umbriel, whatever /usr/share/wayland-sessions offers.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local gate_mod = require("components/gate")
local light = require("components/light")
local paths = require("core/paths")

-- The shell's own glyphs, by name.
g.icon_dir(paths.root .. "/assets/icons")

-- A test, from inside a session (BIOMA_GREETER_TEST=<output>): the greeter
-- on that output alone, above the windows but taking no keyboard, its
-- password typed over IPC, its commands only said.
local test = g.env("BIOMA_GREETER_TEST") or ""

-- Where the copy is: the session script says so; run from the repository
-- for a test, it is the directory above this one.
local home = g.env("BIOMA_GREETER_DIR") or (string.gsub(g.dir, "/genoma/?$", ""))

-- ---- Who ----------------------------------------------------------------------

local user_file = g.file { path = home .. "/user.json" }
local user = g.computed(function(): any
    local ok, data = pcall(g.parse_json, user_file.text or "")
    return if ok and type(data) == "table" then data else {}
end)
local function login(): string return user.value.login or "" end
local function full_name(): string
    local u = user.value
    return if u.fullName and u.fullName ~= "" then u.fullName else login()
end
local function avatar(): string
    local u = user.value
    return if u.avatar and u.avatar ~= "" then home .. "/" .. u.avatar else ""
end
-- ---- Which session ---------------------------------------------------------------

-- The sessions installed, as display managers find them: each .desktop in
-- /usr/share/wayland-sessions that is not hidden, by name.
local SESSIONS = "/usr/share/wayland-sessions"
local session_folder = g.folder { path = SESSIONS }
local session_files: { [string]: any } = {}
local function session_file(name: string): any
    local f = session_files[name]
    if not f then
        f = g.lasting(function() return g.file { path = SESSIONS .. "/" .. name } end)
        session_files[name] = f
    end
    return f
end
-- The words of an Exec line, its field codes dropped.
local function words(exec: string): { string }
    local out = {}
    for w in string.gmatch(exec, "%S+") do
        if not string.match(w, "^%%%a$") then table.insert(out, w) end
    end
    return out
end
local sessions = g.computed(function(): { any }
    local out = {}
    for _, entry in session_folder.entries or {} do
        local name = if type(entry) == "table" then entry.name else entry
        if type(name) == "string" and string.match(name, "%.desktop$") then
            local text = session_file(name).text or ""
            local fields: { [string]: string } = {}
            local in_entry = false
            for line in string.gmatch(text, "[^\n]+") do
                local group = string.match(line, "^%[(.-)%]")
                if group then
                    in_entry = group == "Desktop Entry"
                elseif in_entry then
                    local k, v = string.match(line, "^([%w%-]+)%s*=%s*(.*)$")
                    if k and fields[k] == nil then fields[k] = v end
                end
            end
            if fields.Exec and fields.Hidden ~= "true" and fields.NoDisplay ~= "true" then
                table.insert(out, {
                    id = string.gsub(name, "%.desktop$", ""),
                    name = fields.Name or name,
                    command = words(fields.Exec),
                    desktop = fields.DesktopNames or "",
                })
            end
        end
    end
    table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return out
end)

-- The one chosen here, until the machine restarts (the greeter can write
-- nowhere that lasts); otherwise the one the person was last in, as the
-- shell recorded it (scripts/greeter-sync), or the first.
local CHOSEN = (g.env("XDG_STATE_HOME") or "/tmp") .. "/bioma-greeter-session"
local chosen_file = g.file { path = CHOSEN }
local chosen = g.signal("")
local function current(): any?
    local list = sessions.value
    local wanted = if chosen.value ~= "" then chosen.value else string.match(chosen_file.text or "", "^%s*(.-)%s*$") or ""
    if wanted == "" then wanted = user.value.sessionId or "" end
    for _, s in list do
        if s.id == wanted then return s end
    end
    -- An older copy names only the command it starts.
    local recorded = user.value.session
    if type(recorded) == "table" and recorded[1] then
        for _, s in list do
            if s.command[1] == recorded[1] then return s end
        end
    end
    return list[1]
end
local function choose(id: string)
    chosen.value = id
    pcall(function() chosen_file:write(id) end)
end

-- What greetd starts once the password is right, and what it tells the
-- session about itself, as display managers do.
local function session(): { string }
    local s = current()
    if s and #s.command > 0 then return s.command end
    local recorded = user.value.session
    return if type(recorded) == "table" and #recorded > 0 then recorded else { "niri-session" }
end
local function session_env(): { string }
    local s = current()
    if not s or s.desktop == "" then return {} end
    local first = string.match(s.desktop, "^[^;:]+") or s.desktop
    return {
        "XDG_SESSION_DESKTOP=" .. string.lower(first),
        "XDG_CURRENT_DESKTOP=" .. string.gsub(s.desktop, ";", ":"),
    }
end

-- ---- What it shows ------------------------------------------------------------

-- The density and the clock's format, as the shell has them.
local density = gate_mod.density
local twenty_four = gate_mod.twenty_four

-- The screen the keyboard is on, asked of niri once: niri hands the keys to
-- the focused output, at a greeter the one marked focus-at-startup.
local primary = g.signal(test)
if test == "" then g.process {
    command = { "niri", "msg", "--json", "focused-output" },
    on_line = function(line: string)
        local ok, data = pcall(g.parse_json, line)
        if ok and type(data) == "table" and data.name then primary.value = data.name end
    end,
} end

-- ---- Checking the password -------------------------------------------------------

local password = g.signal("")
local checking = g.signal(false)
local failed = g.signal(false)
local reason = g.signal("")
local leaving = g.signal(false)
local launched = false

local greetd: any
greetd = g.greetd {
    on_auth_message = function(_: string, kind: string)
        if kind == "secret" or kind == "visible" then
            greetd:respond(g.untracked(function() return password.value end))
        else
            greetd:respond(nil)
        end
    end,
    -- The password was right. The gate welcomes the person in and fades to
    -- black, and only then is the session started: it opens on a black
    -- screen, so that is where the greeter ends.
    on_ready = function()
        g.batch(function()
            checking.value = false
            leaving.value = true
        end)
    end,
    on_launched = function() g.quit(0) end,
    on_failure = function()
        g.batch(function()
            checking.value = false
            failed.value = true
            reason.value = "That is not the password"
        end)
        greetd:cancel_session()
    end,
    on_error = function(why: string)
        print("Bioma greeter: greetd error — " .. tostring(why))
        g.batch(function()
            checking.value = false
            failed.value = true
            reason.value = "The password could not be checked"
        end)
        pcall(function() greetd:cancel_session() end)
    end,
}

local gate = {
    active = function(): string return primary.value end,
    password = password,
    checking = function(): boolean return checking.value end,
    failed = function(): boolean return failed.value end,
    failed_reset = function() failed.value = false end,
    reason = function(): string return reason.value end,
    leaving = function(): boolean return leaving.value end,
    full_name = full_name,
    avatar = avatar,
    density = density,
    twenty_four = twenty_four,
    submit = function()
        if g.untracked(function() return checking.value or leaving.value or password.value == "" end) then return end
        if not greetd.available then
            failed.value = true
            reason.value = "greetd is not running"
            return
        end
        g.batch(function()
            checking.value = true
            failed.value = false
        end)
        greetd:create_session(g.untracked(login))
    end,
    -- Called by every screen's gate once the welcome is dark. The first one
    -- starts the session; not waiting on the primary one means a greeter
    -- with no focused output still lets the person in.
    entered = function()
        if launched then return end
        launched = true
        if greetd.available then
            greetd:start_session(g.untracked(session), g.untracked(session_env))
        else
            g.quit(0)
        end
    end,
}

-- ---- The machine's commands ---------------------------------------------------------

-- What logind lets the greeter do, asked once: a command it refuses is not
-- offered, and the firmware's setup only where the machine has one.
local can = g.signal({} :: { [string]: boolean })
local function ask(method: string)
    g.dbus.call {
        bus = "system",
        destination = "org.freedesktop.login1",
        path = "/org/freedesktop/login1",
        interface = "org.freedesktop.login1.Manager",
        method = method,
        reply = function(ok: boolean, answer: any)
            local next = table.clone(g.untracked(function() return can.value end))
            next[method] = ok and (answer == "yes" or answer == "challenge")
            can.value = next
        end,
    }
end
ask("CanReboot")
ask("CanPowerOff")
ask("CanRebootToFirmwareSetup")

local function logind(method: string, signature: string, args: { any }, after: (() -> ())?)
    if test ~= "" then
        print("Bioma greeter (test): would call logind " .. method .. " " .. g.to_json(args))
        if after then after() end
        return
    end
    g.dbus.call {
        bus = "system",
        destination = "org.freedesktop.login1",
        path = "/org/freedesktop/login1",
        interface = "org.freedesktop.login1.Manager",
        method = method,
        signature = signature,
        args = args,
        reply = function(ok: boolean, why: any)
            if not ok then print("Bioma greeter: " .. method .. " refused — " .. tostring(why)) return end
            if after then after() end
        end,
    }
end

local COMMANDS = {
    { id = "restart", label = "RESTART", icon = "restart", can = "CanReboot",
        run = function() logind("Reboot", "b", { false }) end },
    { id = "firmware", label = "FIRMWARE SETUP", icon = "firmware", can = "CanRebootToFirmwareSetup",
        run = function() logind("SetRebootToFirmwareSetup", "b", { true }, function() logind("Reboot", "b", { false }) end) end },
    { id = "shutdown", label = "SHUT DOWN", icon = "power", can = "CanPowerOff",
        run = function() logind("PowerOff", "b", { false }) end },
}
local function offered(): { any }
    local out = {}
    for _, c in COMMANDS do
        if can.value[c.can] then table.insert(out, c) end
    end
    return out
end

-- Which corner menu is open: "" none, "power" or "session". One at a time.
local open = g.signal("")

-- A glyph in the corner, in a cell of its own, and its rows growing out of
-- it upward: a panel of rows, each numbered, as the session cell's are.
-- `t`: id, icon, slot (0 the corner, 1 the cell beside it), items() (each
-- { id, label, icon? }), run(item), marked(item)? (the one in use, drawn
-- as chosen), width (the panel's, logical units at the normal step),
-- least (shown only with more items than this).
local function corner_menu(size: any, t: { [string]: any }): (any, (string, string?) -> boolean)
    local function m(): any return metrics_mod.step(density()) end
    local function f(): number return m().factor end
    local function cell(): number return metrics_mod.cell_height * f() end
    local function edge(): number return metrics_mod.margin_edge() * f() end
    local function row(): number return 44 * f() end
    local function panel_width(): number return t.width * f() end
    local function panel_height(): number return #t.items() * row() + 16 * f() end
    local function is_open(): boolean return open.value == t.id end
    local function shown(): boolean return is_open() and not leaving.value end
    -- The glyph's right edge: the corner, or a cell and a gap in from it.
    local function right(): number return size.width - edge() - t.slot * (cell() + m().gap / 2) end
    local function present(): boolean return #t.items() > (t.least or 0) end

    local function key_box(n: () -> number): any
        return g.capsule {
            width = function() return 18 * f() end,
            height = function() return 18 * f() end,
            radius = function() return 6 * f() end,
            fill = "#00000000",
            rim_top = theme.line,
            rim_bottom = theme.line,
            align = "center",
            justify = "center",
            g.text { text = function() return tostring(n()) end, color = theme.text_muted, font = typography.technical,
                size = function() return math.round(11 * f()) end, tabular = true },
        }
    end
    local function item_row(item: () -> any): any
        local hover = g.signal(false)
        local function marked(): boolean return t.marked ~= nil and t.marked(item().item) end
        return g.capsule {
            width = function() return panel_width() - 16 * f() end,
            height = row,
            radius = function() return metrics_mod.radius_for(row(), m()) end,
            fill = function()
                if hover.value then return colour.alpha(theme.primary(), 0.12) end
                return if marked() then colour.alpha(theme.primary(), 0.07) else "#00000000"
            end,
            rim_top = function() return if marked() then colour.alpha(theme.primary(), 0.5) else "#00000000" end,
            rim_bottom = function() return if marked() then colour.alpha(theme.primary(), 0.3) else "#00000000" end,
            transition = { fill = "colour", rim_top = "colour", rim_bottom = "colour" },
            padding_x = function() return 14 * f() end,
            direction = "row",
            align = "center",
            justify = "between",
            cursor = "pointer",
            on_hover = function(on: boolean) hover.value = on end,
            on_click = function() t.run(g.untracked(item).item) end,
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 12 * f() end,
                g.icon { width = function() return 20 * f() end, height = function() return 20 * f() end,
                    present = function() return item().item.icon ~= nil end,
                    icon = function() return item().item.icon or "" end,
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end },
                g.text { text = function() return item().item.label end,
                    color = function() return if marked() then theme.primary() else theme.text() end,
                    transition = { color = "colour" },
                    font = typography.technical,
                    size = function() return math.round(13 * f()) end, weight = 500 },
            },
            key_box(function() return item().n end),
        }
    end
    local function items(): { any }
        local out = {}
        for i, c in t.items() do table.insert(out, { n = i, item = c }) end
        return out
    end

    local node = g.box {
        overlay = true,
        attach = "corner",
        width = size.width,
        height = size.height,
        -- The panel, its corner on the glyph's: it grows from there.
        g.capsule(light.glass({
            overlay = true,
            attach = "corner",
            present = present,
            offset_x = function() return right() - (if shown() then panel_width() else cell()) end,
            offset_y = function()
                return size.height - edge() - cell() - m().gap / 2 - (if shown() then panel_height() else 0)
            end,
            width = function() return if shown() then panel_width() else cell() end,
            height = function() return if shown() then panel_height() else 0 end,
            radius = function() return m().radius_panel end,
            opacity = function() return if shown() then 1 else 0 end,
            transition = {
                offset_x = "open_flat", offset_y = "open_flat", width = "open_flat", height = "open_flat", opacity = "fade",
            },
            fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            clip = true,
            direction = "column",
            align = "center",
            justify = "center",
            g.box {
                opacity = function() return if shown() then 1 else 0 end,
                transition = { opacity = "content_enter" },
                direction = "column",
                g.each { direction = "column", items = items, key = function(it: any) return it.item.id end, row = item_row },
            },
        }, f, {
            width = function() return if shown() then panel_width() else cell() end,
            height = function() return if shown() then panel_height() else 0 end,
            radius = function() return m().radius_panel end,
            factor = f,
            lit = shown,
        })),
        -- The glyph.
        g.capsule(light.glass({
            overlay = true,
            attach = "corner",
            present = function() return present() and not leaving.value end,
            offset_x = function() return right() - cell() end,
            offset_y = function() return size.height - edge() - cell() end,
            width = cell,
            height = cell,
            radius = function() return metrics_mod.radius_for(cell(), m()) end,
            fill = function() return colour.alpha(theme.cell(), config.get("cell.opacity", 0.72)) end,
            rim_top = function() return if is_open() then theme.primary() else theme.rim() end,
            rim_bottom = function() return if is_open() then theme.primary() else theme.line() end,
            transition = { rim_top = "colour", rim_bottom = "colour" },
            align = "center",
            justify = "center",
            cursor = "pointer",
            on_click = function()
                open.value = if g.untracked(is_open) then "" else t.id
            end,
            g.icon {
                width = function() return 20 * f() end,
                height = function() return 20 * f() end,
                icon = t.icon,
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            },
        }, f, {
            width = cell,
            height = cell,
            radius = function() return metrics_mod.radius_for(cell(), m()) end,
            factor = f,
        })),
    }
    -- While open, the panel has the keys: a number runs its row, Escape
    -- closes it.
    local function key(name: string, typed: string?): boolean
        if not g.untracked(shown) then return false end
        if name == "Escape" then
            open.value = ""
            return true
        end
        local n = tonumber(typed or "") or tonumber(string.match(name, "^KP_(%d)$") or "")
        local list = g.untracked(t.items)
        if n and list[n] then
            t.run(list[n])
            return true
        end
        return true
    end
    return node, key
end

-- The machine's commands, in the corner.
local function commands(size: any): (any, (string, string?) -> boolean)
    return corner_menu(size, {
        id = "power",
        icon = "power",
        slot = 0,
        width = 300,
        items = function()
            local out = {}
            for _, c in offered() do table.insert(out, { id = c.id, label = c.label, icon = c.icon, command = c }) end
            return out
        end,
        run = function(item: any) item.command.run() end,
    })
end

-- The sessions, beside them: only where there is more than one to choose.
-- Choosing one marks it and closes the panel; the password field keeps
-- the keys.
local function session_menu(size: any): (any, (string, string?) -> boolean)
    return corner_menu(size, {
        id = "session",
        icon = "workspaces",
        slot = 1,
        width = 300,
        least = 1,
        items = function()
            local out = {}
            for _, s in sessions.value do table.insert(out, { id = s.id, label = string.upper(s.name) }) end
            return out
        end,
        marked = function(item: any)
            local c = current()
            return c ~= nil and c.id == item.id
        end,
        run = function(item: any)
            choose(item.id)
            open.value = ""
        end,
    })
end

if test ~= "" then
    g.ipc("greeter", {
        type = function(text: string): string
            password.value = text
            return "typed"
        end,
        submit = function(): string
            gate.submit()
            return "submitted"
        end,
        power = function(): string
            open.value = if g.untracked(function() return open.value end) == "power" then "" else "power"
            return if g.untracked(function() return open.value end) == "power" then "open" else "closed"
        end,
        sessions = function(): string
            open.value = if g.untracked(function() return open.value end) == "session" then "" else "session"
            local names = {}
            for _, s in g.untracked(function() return sessions.value end) do table.insert(names, s.id) end
            return table.concat(names, " ")
        end,
        session = function(): string
            local c = g.untracked(current)
            if not c then return "none" end
            return c.id .. " " .. table.concat(c.command, " ") .. " | " .. table.concat(g.untracked(session_env), " ")
        end,
        choose = function(id: string): string
            choose(id)
            return id
        end,
        run = function(n: string): string
            local c = g.untracked(offered)[tonumber(n) or 0]
            if not c then return "no such command" end
            c.run()
            return c.id
        end,
    })
end

-- ---- The surfaces -------------------------------------------------------------------

return g.surface {
    full = true,
    anchor = { "top", "bottom", "left", "right" },
    outputs = if test ~= "" then { test } else "all",
    reserve = false,
    above_zones = true,
    layer = if test ~= "" then "top" else "overlay",
    namespace = "bioma-greeter",
    function(output: string, size: any)
        size = size or { width = 1920, height = 1080 }
        local gate_node, gate_keys = gate_mod.new { gate = gate, output = output, size = size, welcomes = true }
        local commands_node, commands_key = commands(size)
        local sessions_node, sessions_key = session_menu(size)
        local function here(): boolean return primary.value == output end
        return g.box {
            width = size.width,
            height = size.height,
            -- Only the primary screen takes the keys.
            catch = function() return here() and test == "" end,
            on_key = function(name: string, text: string?, mods: any)
                if commands_key(name, text) then return end
                if sessions_key(name, text) then return end
                gate_keys.key(name, text, mods)
            end,
            g.capsule {
                overlay = true, attach = "corner", width = size.width, height = size.height, radius = 0,
                fill = theme.background, rim_top = "#00000000", rim_bottom = "#00000000",
            },
            g.box { overlay = true, attach = "corner", gate_node },
            g.box { overlay = true, attach = "corner", present = here, sessions_node },
            g.box { overlay = true, attach = "corner", present = here, commands_node },
        }
    end,
}
