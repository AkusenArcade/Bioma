--!strict
-- Each service's state as it changes, with no interface: how a service is
-- verified before a cell depends on it (`BIOMA_GENOMA_CHECK=<name>
-- scripts/genoma`). Bindings first, then reads, so nothing is read before
-- its source has filled it.
local g = require("@genoma")

local M = {}

function M.niri()
    local niri = require("services/niri")
    g.effect(function()
        local parts = {}
        for _, ws in niri.workspace_list() do
            table.insert(parts, string.format("%s:%d%s%s%s", ws.output, ws.idx, if ws.is_active then "*" else "",
                if ws.is_focused then "F" else "", if ws.active_window_id ~= -1 then "w" else ""))
        end
        print("check niri workspaces " .. table.concat(parts, " ") .. " focused output " .. niri.focused_output())
    end)
    g.effect(function()
        local count = 0
        for _ in niri.windows() do count += 1 end
        print(string.format("check niri focused %q (%s), %d windows", niri.focused_title(), niri.focused_app_id(), count))
    end)
    g.effect(function()
        print(string.format("check niri gaps %s struts %s/%s/%s/%s, overview %s, layout %q",
            tostring(niri.window_gap()), tostring(niri.strut_for("top")), tostring(niri.strut_for("bottom")),
            tostring(niri.strut_for("left")), tostring(niri.strut_for("right")), tostring(niri.overview_open()),
            niri.keyboard_layout()))
    end)
    g.effect(function()
        local count = 0
        for _ in niri.casts() do count += 1 end
        print("check niri casts " .. count)
    end)
    g.effect(function()
        local w = niri.focused_window()
        local layout = if w then niri.layout_for(w.id) else nil
        if layout and layout.size then
            print(string.format("check niri focused size %sx%s", tostring(layout.size[1]), tostring(layout.size[2])))
        end
    end)
    niri.on_screenshot(function(path: string) print("check niri screenshot " .. path) end)
end

function M.monitors()
    local monitors = require("services/monitors")
    local niri_config = require("services/niri_config")
    local screens = {}
    for _, s in g.outputs() do
        table.insert(screens, string.format("%s %q %sx%s", s.name, s.description, tostring(s.width), tostring(s.height)))
    end
    print("check monitors compositor: " .. table.concat(screens, "; ") .. " — primary " .. monitors.primary())
    g.effect(function()
        local files = {}
        for _, item in niri_config.items() do files[item.file] = (files[item.file] or 0) + 1 end
        local parts = {}
        for file, n in files do table.insert(parts, string.format("%s (%d)", file, n)) end
        print("check monitors config ready " .. tostring(niri_config.ready()) .. ": " .. table.concat(parts, ", "))
    end)
    g.effect(function()
        local parts = {}
        for _, o in monitors.outputs() do
            table.insert(parts, string.format("%s at %d,%d %dx%d @%.0f scale %s %q sections %d%s vrr %s",
                o.name, o.x, o.y, o.width, o.height, o.refresh, tostring(o.scale), o.description, #o.sections,
                if o.primary then " primary" else "", o.vrr))
        end
        for _, o in monitors.off() do
            table.insert(parts, string.format("%s OFF at %d,%d", o.name, o.x, o.y))
        end
        print("check monitors answered " .. tostring(monitors.answered()) .. ": " .. table.concat(parts, "; "))
    end)
end

function M.system_monitor()
    local sm = require("services/system_monitor")
    g.effect(function()
        print(string.format("check vitals cpu %.1f%% clock %.0f MHz (raw %.0f, %d cores, range %.0f–%.0f, fraction %.2f) "
            .. "ram %.1f%% %s/%s GB swap %.1f%%",
            sm.cpu_percent(), sm.cpu_clock(), sm.cpu_clock_raw(), sm.cores(), sm.cpu_clock_min, sm.cpu_clock_max,
            sm.cpu_clock_fraction(), sm.ram_percent(), tostring(sm.ram_used_gb()), tostring(sm.ram_total_gb()), sm.swap_percent()))
    end)
    g.effect(function()
        print(string.format("check vitals gpu %s %s %.0f%% clock %.0f MHz fraction %.2f%s vram %.1f%% temp %s %.1f°C",
            tostring(sm.gpu_present()), sm.gpu_name(), sm.gpu_percent(), sm.gpu_clock(), sm.gpu_clock_fraction(),
            if sm.gpu_asleep() then " asleep" else "", sm.vram_percent(), tostring(sm.cpu_temperature_known()), sm.cpu_temperature()))
    end)
    g.effect(function()
        print(string.format("check vitals net %s in %.0f B/s out %.0f B/s", tostring(sm.net_known()), sm.net_in(), sm.net_out()))
    end)
    g.effect(function()
        print(string.format("check vitals battery has %s level %.2f state %s detail %q on battery %s mains full %s inflow %.1f W",
            tostring(sm.has_battery()), sm.battery_level(), sm.battery_state(), sm.battery_detail(), tostring(sm.on_battery()),
            tostring(sm.battery_mains_full()), sm.battery_inflow()))
    end)
    g.effect(function()
        local list = sm.processes()
        if #list > 0 then
            print(string.format("check vitals processes %d, top %s pid %d cpu %.1f mem %d MB", #list, list[1].name, list[1].pid,
                list[1].cpu, list[1].mem_mb))
        end
    end)
    g.after(5, function() sm.set_list_processes(true) end)
    g.after(9, function() sm.set_list_processes(false) end)
end

-- The timer is started and stopped well before it would ring: ringing is a
-- critical notification and a sound on the desktop of whoever is using it.
function M.time()
    local time = require("services/time")
    g.effect(function()
        local parts = {}
        for _, zone in time.zones() do
            local t = time.in_zone(zone)
            table.insert(parts, string.format("%s (%s) %s", time.city_of(zone), time.utc_label(zone),
                if t then string.format("%02d:%02d", t.hour, t.min) else "?"))
        end
        print("check time zones " .. table.concat(parts, ", ") .. string.format(" — here %s", os.date("%H:%M")))
    end)
    g.effect(function()
        print(string.format("check time timer %d/%d running %s paused %s fraction %.3f", time.left(), time.length(),
            tostring(time.running()), tostring(time.paused()), time.fraction_left()))
    end)
    g.effect(function()
        local a = time.alarm()
        print(string.format("check time alarm %02d:%02d %s", a.hour, a.minute, if a.on then "on" else "off"))
    end)
    g.after(1, function() time.start() end)
    g.after(4.2, function() time.pause() end)
    g.after(5.5, function() time.reset() end)
    g.after(6, function()
        time.ask_known()
    end)
    g.effect(function()
        local known = time.known()
        if #known > 0 then print("check time known zones " .. #known .. ", first " .. known[1]) end
    end)
end

-- Counts only: the events are someone's own.
function M.calendar()
    local calendar = require("services/calendar")
    g.effect(function()
        local nxt = calendar.next()
        print(string.format("check calendar sources %d, %d events read %s, today %d, ongoing %d, next %s, problems %q",
            #calendar.sources(), #calendar.events(), if calendar.read_at() > 0 then os.date("%H:%M:%S", calendar.read_at() // 1000) else "never",
            #calendar.today(), #calendar.ongoing(), if nxt then os.date("%d/%m %H:%M", nxt.start // 1000) else "none", calendar.problem()))
    end)
    print(string.format("check calendar today starts %s, ends %s", os.date("%d/%m %H:%M", calendar.today_start() // 1000),
        os.date("%d/%m %H:%M", calendar.today_end() // 1000)))
end

function M.apps()
    local apps = require("core/apps")
    print("check apps entries " .. #apps.entries())
    for _, name in { "Alacritty", "xwayland-satell", "steamwebhelp", "zen-bin", "firefox", "nvim", "niri", "x" } do
        local entry = apps.entry_for(name)
        print(string.format("check apps %s → %s icon %q", name, if entry then entry.id else "nothing", apps.icon_for(name)))
    end
    local entry = apps.entry_for("Alacritty")
    if entry then print("check apps command " .. table.concat(apps.command_of(entry), " | ")) end
end

function M.media()
    local media = require("services/media")
    local audio = require("services/audio")
    local sinestesia = require("services/sinestesia")
    g.effect(function()
        local names = {}
        for _, p in media.players() do table.insert(names, p.identity .. "/" .. p.status) end
        print(string.format("check media players [%s] chosen %s: %q by %q, playing %s, length %s, art %s",
            table.concat(names, ", "), media.identity(), media.title(), media.artist(), tostring(media.playing()),
            media.format_time(media.length()), tostring(media.has_art())))
    end)
    g.effect(function()
        print(string.format("check media position %s (%.2f)", media.format_time(media.position()), media.progress()))
    end)
    local seen = 0
    g.effect(function()
        local p = audio.peak()
        if p > 0 and seen < 3 then
            seen += 1
            print(string.format("check audio peak %.3f", p))
        end
    end)
    local frames = 0
    g.effect(function()
        local l = sinestesia.left()
        if #l > 0 then
            frames += 1
            if frames % 60 == 1 then
                print(string.format("check sinestesia frame %d: %d bands a side, level %.3f, folded to 7: %s", frames, #l,
                    sinestesia.level(), table.concat((function()
                        local out = {}
                        for _, v in sinestesia.fold(l, 7) do table.insert(out, string.format("%.2f", v)) end
                        return out
                    end)(), " ")))
            end
        end
    end)
    local owner = {}
    g.after(1, function() sinestesia.hold(owner, true) end)
    g.after(4, function()
        sinestesia.hold(owner, false)
        print("check sinestesia frames in 3 s: " .. frames)
    end)
end

return M
