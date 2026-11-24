--!strict
-- Who is taking the microphone, a camera or the screen (services/
-- Privacy.qml at 11bb81e). Read only while a cell holds it.
--
-- A capture is a PipeWire link from a device's source to an application's
-- stream; a sink's monitor captured is sound already leaving, not the
-- room, and is left out. Most applications open a camera directly rather
-- than through PipeWire, so `scripts/cameras` watches the device nodes;
-- an open that only asks a device what it can do comes and goes within a
-- moment, so a holder is believed after `privacy.camera_confirm`. A screen
-- is the compositor's cast: niri says which program and what, Hyprland
-- only that one runs. Otherwise it is a PipeWire video source that is no
-- device, the portal's (Umbriel's "umbriel-screen-capture"), read like a
-- microphone: by its links.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local audio = require("services/audio")
local compositor = require("services/compositor")

local M = {}

local holders: { [any]: boolean } = {}
local held = g.signal(0)
function M.hold(owner: any, wanted: boolean)
    if (holders[owner] == true) == wanted then return end
    holders[owner] = if wanted then true else nil
    local n = 0
    for _ in holders do n += 1 end
    held.value = n
end
local function active(): boolean return held.value > 0 end

local function app_of(n: any): string
    local p = n.properties or {}
    return p["application.name"] or p["node.description"] or (if n.description ~= "" then n.description else n.name) or ""
end
local function device_of(n: any): string
    if n.description ~= "" then return n.description end
    if n.nickname ~= "" then return n.nickname end
    return n.name or ""
end

-- A video source that is a device, a camera; one that is not, a screen
-- someone shares.
local function is_camera(n: any): boolean
    local p = n.properties or {}
    return p["device.api"] ~= nil or p["media.role"] == "Camera"
end

-- Uses of one medium through PipeWire's links, one per application and device.
local function from_links(source_kind: string, target_kind: string, kind: string, wanted: ((any) -> boolean)?): { any }
    local out, seen = {}, {}
    if not active() then return out end
    for _, link in audio.links() do
        local source, target = audio.node(link.output), audio.node(link.input)
        if source and target and source.kind == source_kind and target.kind == target_kind
            and (wanted == nil or wanted(source)) then
            local app = app_of(target)
            local key = kind .. ":" .. app .. ":" .. source.id
            if not seen[key] then
                seen[key] = true
                table.insert(out, { kind = kind, app = app, detail = device_of(source), key = key })
            end
        end
    end
    return out
end

local microphone = g.computed(function() return from_links("source", "input-stream", "microphone") end)

-- The cameras' holders, and since when each.
local holding = g.signal({})
local since: { [string]: number } = {}
local tick = g.signal(0)
g.effect(function()
    if not active() then return end
    g.untracked(function()
        local function watch()
            g.process {
                command = { paths.script("cameras") },
                on_line = function(line: string)
                    local ok, list = pcall(g.parse_json, line)
                    if not ok or type(list) ~= "table" then return end
                    local now, next_since = g.now(), {}
                    for _, h in list do
                        local key = tostring(h.pid) .. ":" .. tostring(h.device)
                        next_since[key] = since[key] or now
                    end
                    since = next_since
                    holding.value = list
                    if #list > 0 then
                        g.after(config.get("privacy.camera_confirm", 1500) / 1000 + 0.05, function() tick.value += 1 end)
                    end
                end,
                on_exit = function() g.after(5, function() if g.untracked(active) then watch() end end) end,
            }
        end
        watch()
    end)
end)

local camera = g.computed(function(): { any }
    local out = from_links("video-source", "video-stream", "camera", is_camera)
    local _ = tick.value
    local confirm, now, seen = config.get("privacy.camera_confirm", 1500) / 1000, g.now(), {}
    for _, h in holding.value do
        local started = since[tostring(h.pid) .. ":" .. tostring(h.device)] or now
        local key = "camera:" .. tostring(h.name) .. ":" .. tostring(h.device)
        if now - started >= confirm and not seen[key] then
            seen[key] = true
            table.insert(out, { kind = "camera", app = h.name or "", detail = h.label or "", key = key })
        end
    end
    return out
end)

-- A cast's program, by its pid, asked of ps once.
local names = g.signal({})
local function casts(): { any }
    local out = {}
    if not active() then return out end
    for _, c in compositor.casts() do
        if c.active ~= false then table.insert(out, c) end
    end
    return out
end
g.watch(function()
    local pids = {}
    for _, c in casts() do
        if c.pid and g.untracked(function() return names.value end)[tostring(c.pid)] == nil then table.insert(pids, tostring(c.pid)) end
    end
    return table.concat(pids, ",")
end, function(pids: string)
    if pids == "" then return end
    local found = table.clone(g.untracked(function() return names.value end))
    g.process {
        command = { "ps", "-o", "pid=,comm=", "-p", pids },
        on_line = function(line: string)
            local pid, name = string.match(line, "^%s*(%d+)%s+(.-)%s*$")
            if pid then found[pid] = name end
        end,
        on_exit = function() names.value = found end,
    }
end)
local function target_of(c: any): string
    if c.output then return c.output end
    if c.window then
        local w = compositor.windows()[c.window]
        return if w then (if w.title ~= "" then w.title else w.app_id) else "A window"
    end
    return ""
end
local screen = g.computed(function(): { any }
    local out = {}
    -- The shares PipeWire shows that no cast of the compositor's names by
    -- its node. Where there are any, a cast that names neither a node nor
    -- a program (Hyprland's) is one of them, told better here.
    local named: { [number]: boolean } = {}
    for _, c in casts() do
        if c.node then named[c.node] = true end
    end
    local shares = from_links("video-source", "video-stream", "screen", function(n: any): boolean
        return not is_camera(n) and not named[n.id]
    end)
    for _, c in casts() do
        if #shares > 0 and not c.node and not c.pid then continue end
        local app = if c.pid then names.value[tostring(c.pid)] or "" else ""
        if app == "" and c.node then
            for _, link in audio.links() do
                if link.output == c.node then
                    local target = audio.node(link.input)
                    if target then app = app_of(target) end
                end
            end
        end
        table.insert(out, { kind = "screen", app = if app ~= "" then app else "Screen", detail = target_of(c),
            key = "screen:" .. tostring(c.id) })
    end
    for _, u in shares do
        table.insert(out, { kind = "screen", app = if u.app ~= "" then u.app else "Screen", detail = "", key = u.key })
    end
    return out
end)

function M.uses(): { any }
    local out = {}
    for _, list in { microphone.value, camera.value, screen.value } do
        for _, u in list do table.insert(out, u) end
    end
    return out
end
function M.in_use(): boolean return #M.uses() > 0 end

return M
