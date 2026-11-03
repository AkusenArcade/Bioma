--!strict
-- Settings → Performance (cells/settings/SettingsPerformance.qml at
-- 11bb81e): the switch, what turns it on by itself, and what it quietens,
-- one switch a lever.
--
-- On from a key or while a given program runs (a game through GameMode, or
-- any application on a list), and every lever a flag of its own. The
-- application list picks from the windows open now, as the Niri page's
-- window rules do, because an app-id is read, not guessed.
local g = require("@genoma")
local config = require("core/config")
local apps = require("core/apps")
local performance = require("core/performance")
local page = require("components/page")
local switch = require("components/switch")
local niri = require("services/niri")
local workload = require("services/workload")

local M = {}

local function trimmed(s: string): string return string.match(s, "^%s*(.-)%s*$") or "" end

-- `t`: metrics(), width(), height(), keyed(handler).
function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f, line, section = p.factor, p.line, p.section

    local function patterns(): { string }
        local list = config.get("performance.apps", {})
        return if type(list) == "table" then list else {}
    end
    local function add(pattern: string)
        pattern = trimmed(pattern)
        if pattern == "" then return end
        local list = g.untracked(patterns)
        for _, q in list do
            if string.lower(q) == string.lower(pattern) then return end
        end
        local out = g.array(table.clone(list))
        table.insert(out, pattern)
        config.set("performance.apps", out)
    end
    local function remove(pattern: string)
        local out = g.array({})
        for _, q in g.untracked(patterns) do
            if q ~= pattern then table.insert(out, q) end
        end
        config.set("performance.apps", out)
    end

    local function gamemode(): boolean return config.get("performance.gamemode", true) == true end

    local function icon_of(name: string): string
        if name == "" then return "" end
        return g.icon_path(name) or ""
    end
    local function is_open(pattern: string): boolean
        for _, w in niri.windows() do
            if workload.matches(pattern, w.app_id or "") then return true end
        end
        return false
    end

    -- ---- Adding an application ----------------------------------------------------

    local adding = g.signal(false)
    local query = g.signal("")
    local search_node, search = p.field {
        text = query,
        placeholder = "Search open windows and applications, or write an app-id",
        taking = function() return adding.value end,
    }
    g.watch(function() return adding.value end, function(on: boolean)
        if on then search.set("") end
    end)

    -- The windows open now first (their app-id is what the list matches,
    -- without guessing), then the installed applications.
    local matches = g.computed(function(): { any }
        local wanted = string.lower(trimmed(query.value))
        local function fits(...: string): boolean
            if wanted == "" then return true end
            for _, word in { ... } do
                if string.find(string.lower(word or ""), wanted, 1, true) then return true end
            end
            return false
        end
        local seen: { [string]: boolean } = {}
        for _, q in patterns() do seen[string.lower(q)] = true end
        local out = {}
        for _, w in niri.windows() do
            local id = w.app_id or ""
            if id ~= "" and not seen[string.lower(id)] then
                local entry = apps.entry_for(id)
                if fits(id, if entry then entry.name else "") then
                    seen[string.lower(id)] = true
                    table.insert(out, { app_id = id, open = true,
                        name = if entry then entry.name else id, icon = if entry then entry.icon else "" })
                end
            end
        end
        local installed = {}
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

    local function take(id: string)
        add(id)
        adding.value = false
    end

    t.keyed(function(name: string, typed: string?, mods: { [string]: boolean }): boolean
        if not g.untracked(function() return adding.value end) then return false end
        if name == "Escape" then
            adding.value = false
            return true
        end
        -- Enter keeps what was written, so a pattern like steam_app_* can be
        -- given as it is.
        if name == "Return" or name == "KP_Enter" then
            take(g.untracked(function() return query.value end))
            return true
        end
        return search.key(name, typed, mods)
    end)

    local function listed(pattern: () -> string): any
        local hovered = g.signal(false)
        local function entry(): any
            local q = pattern()
            return if string.find(q, "*", 1, true) then nil else apps.entry_for(q)
        end
        return p.app {
            hovered = hovered,
            icon = function() local e = entry() return if e then icon_of(e.icon) else "" end,
            name = function() local e = entry() return if e and e.name ~= "" then e.name else pattern() end,
            detail = function() return (if is_open(pattern()) then "OPEN NOW · " else "") .. string.upper(pattern()) end,
            trailing = {
                p.remove(function() remove(g.untracked(pattern)) end, function() return hovered.value end),
            },
        }
    end

    local function offered(item: () -> any): any
        return p.app {
            icon = function() return icon_of(item().icon or "") end,
            name = function() return item().name end,
            detail = function() return (if item().open then "OPEN NOW · " else "") .. string.upper(item().app_id) end,
            on_choose = function() take(g.untracked(item).app_id) end,
        }
    end

    -- One lever: its switch, and what it does on and off.
    local function lever(label: string, key: string, when_on: () -> string, when_off: string): any
        local function on(): boolean return config.get("performance.suspend." .. key, true) ~= false end
        return section(label, switch.new {
            on = on,
            factor = f,
            on_toggle = function(value: boolean) config.set("performance.suspend." .. key, value) end,
        }, { line(function() return if on() then when_on() else when_off end) })
    end

    local steam = "* stands for anything: Steam's games are steam_app_* under XWayland and steam_proton under Proton's Wayland driver."

    return p.column {
        section("PERFORMANCE MODE", switch.new {
            on = performance.active,
            factor = f,
            on_toggle = function(value: boolean) if value then performance.on() else performance.off() end end,
        }, {
            line(function()
                local state = if performance.manual()
                    then "On by hand: it stays on, across a restart too, until it is turned off. "
                    elseif performance.active() then "On " .. performance.reason() .. ": it goes off by itself when that ends. "
                    elseif performance.refused() then "Off by hand while something on this page holds it; it comes back with the next one. "
                    else "Off: the shell runs in full. "
                return state .. "A key turns it on and off (Mod+Alt+G as shipped, moved on the Keybinds page), and so does the performance cell."
            end),
        }),
        section("GAMEMODE", switch.new {
            on = gamemode,
            factor = f,
            on_toggle = function(value: boolean) config.set("performance.gamemode", value) end,
        }, {
            line(function()
                if not gamemode() then return "Games registered with GameMode do not turn it on." end
                return "On while a game is registered with GameMode: started with gamemoderun, or with GameMode switched on in Steam or Lutris."
                    .. (if workload.games() > 0 then " One is registered now." else "")
            end),
        }),
        section("APPLICATIONS", nil, {
            line(function()
                return if #patterns() == 0
                    then "None yet. With a window of one of these open, it comes on. " .. steam
                    else "On while a window of one of these is open. " .. steam
            end),
            g.each {
                direction = "column",
                gap = function() return 10 * f() end,
                items = patterns,
                key = function(q: string) return q end,
                row = listed,
            },
            g.box {
                present = function() return adding.value end,
                direction = "column",
                gap = function() return t.metrics().gap_row end,
                search_node,
                g.each {
                    direction = "column",
                    gap = function() return t.metrics().gap_row end,
                    items = function() return matches.value end,
                    key = function(item: any) return item.app_id end,
                    row = offered,
                },
            },
            p.offer("APPLICATION", function() adding.value = not g.untracked(function() return adding.value end) end),
        }),
        lever("LIVE INDICATORS", "motion",
            function() return "Held still: the vitals keep their colour and level but stop beating, the clock's second hand ticks once a second, the media band and the download threads stop. The alarms still sound. This is most of what the shell costs at rest." end,
            "They keep moving at the rate of what they measure."),
        lever("ORGANISMS", "organisms",
            function() return "Put away, surface and all, and back when the mode goes. Placing them brings them back for as long as it lasts." end,
            "They stay on the desktop."),
        lever("WALLPAPER", "wallpaper",
            function() return "Only the picture on screen is kept: the blurred copy behind the overview is put away, and the previous picture is let go once the next one is in." end,
            "The overview keeps its blurred backdrop."),
        lever("BLUR AND SHADOWS", "blur",
            function() return "None: the glass shows what is behind it unblurred, and nothing casts a shadow." end,
            "The glass keeps its blur and the panels their shadows."),
        lever("TRANSITIONS", "transitions",
            function() return "Instant: cells and panels take their size in one frame instead of growing to it." end,
            "Cells and panels grow and shrink as they always do."),
        lever("POLLING", "polling",
            function()
                local every = math.round(performance.vitals_interval() / 1000)
                local usual = math.round(config.get("vitals.interval", 2000) / 100) / 10
                return "The vitals are read every " .. every .. " seconds instead of every " .. usual .. "."
            end,
            "The vitals are read as often as ever."),
    }
end

return M
