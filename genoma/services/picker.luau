--!strict
-- A file or a folder chosen by hand, through the desktop's own file chooser
-- (org.freedesktop.portal.FileChooser). One picker for the whole shell: the
-- VPN profile now, the wallpaper folder, a note and a file to open as their
-- cells come over.
--
-- Bioma on Quickshell asks zenity, which is the same GTK chooser the
-- portal shows where the portal's chooser is GTK's (niri's portals.conf):
-- the dialog does not change, and no program is started for it. Where the
-- desktop has chosen another chooser, that one comes, as for every other
-- application.
--
-- The portal answers in two steps: the call returns a request's path at
-- once, and the choice arrives later as that request's Response signal
-- (0 chosen, 1 cancelled, 2 ended otherwise).
local g = require("@genoma")

local M = {}

local listening: any = nil
local waiting: { [string]: (string?) -> () } = {}
local next_token = 0

-- One watch for every request's answer, matched to its call by path.
local function listen()
    if listening then return end
    listening = g.dbus.watch {
        bus = "session",
        interface = "org.freedesktop.portal.Request",
        member = "Response",
        on_signal = function(code: number, results: any, ...)
            -- The signal's own path is not among its arguments: the one
            -- request in flight is the one answered.
            local path, done = next(waiting)
            if not path or not done then return end
            waiting[path] = nil
            local uris = if type(results) == "table" then results.uris else nil
            local uri = if code == 0 and type(uris) == "table" then uris[1] else nil
            done(if uri then M.path_of(uri) else nil)
        end,
    }
end

-- file:///home/a%20b → /home/a b
function M.path_of(uri: string): string
    local path = string.gsub(uri, "^file://", "")
    path = string.gsub(path, "%%(%x%x)", function(hex: string) return string.char(tonumber(hex, 16) :: number) end)
    return path
end

-- `t`: title, directory (a folder rather than a file), filters
-- ({ { name, { "*.ovpn", … } }, … }), on_chosen(path or nil when cancelled).
function M.choose(t: { [string]: any })
    if next(waiting) then return end
    listen()
    next_token += 1
    local options: { [string]: any } = {
        handle_token = g.dbus.variant("s", "bioma" .. next_token),
        modal = g.dbus.variant("b", true),
    }
    if t.directory then options.directory = g.dbus.variant("b", true) end
    if t.filters then
        local list = {}
        for _, filter in t.filters do
            local patterns = {}
            for _, p in filter[2] do table.insert(patterns, { 0, p }) end
            table.insert(list, { filter[1], patterns })
        end
        options.filters = g.dbus.variant("a(sa(us))", list)
    end
    g.dbus.call {
        bus = "session",
        destination = "org.freedesktop.portal.Desktop",
        path = "/org/freedesktop/portal/desktop",
        interface = "org.freedesktop.portal.FileChooser",
        method = "OpenFile",
        signature = "ssa{sv}",
        args = { "", t.title or "", options },
        reply = function(ok: boolean, handle: any)
            if not ok then
                print("Picker: the portal refused — " .. tostring(handle))
                t.on_chosen(nil)
                return
            end
            waiting[tostring(handle)] = t.on_chosen
        end,
    }
end

-- Whether a choice is being made: a second is not opened over it.
function M.busy(): boolean return next(waiting) ~= nil end

-- The dialog closed from here, as a cancel. A request closed by its
-- caller sends no Response, so the answer is given here.
function M.cancel()
    for path, done in waiting do
        waiting[path] = nil
        done(nil)
        g.dbus.call {
            bus = "session",
            destination = "org.freedesktop.portal.Desktop",
            path = path,
            interface = "org.freedesktop.portal.Request",
            method = "Close",
            reply = function() end,
        }
    end
end

return M
