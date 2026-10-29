--!strict
-- VPN profiles, as NetworkManager keeps them (services/Vpn.qml at 11bb81e):
-- OpenVPN and WireGuard, read with nmcli and followed through
-- `nmcli monitor`, so a profile switched by hand elsewhere shows here
-- without polling. Bioma switches, imports and removes; NetworkManager does
-- the tunnelling.
local g = require("@genoma")
local timing = require("core/timing")
local paths = require("core/paths")

local M = {}

local profiles = g.signal({})
local error_text = g.signal("")
local working = g.signal("")
local importing = g.signal(false)

function M.profiles(): { any } return profiles.value end
function M.active(): { any }
    local out = {}
    for _, p in profiles.value do
        if p.state == "activated" then table.insert(out, p) end
    end
    return out
end
function M.any_active(): boolean return #M.active() > 0 end
function M.error(): string return error_text.value end
-- The uuid being switched, until NetworkManager says it has.
function M.working(): string return working.value end
function M.busy(): boolean return working.value ~= "" or importing.value end

-- nmcli -t escapes its separator with a backslash.
local function fields(line: string): { string }
    local out, current, i = {}, {}, 1
    while i <= #line do
        local c = string.sub(line, i, i)
        if c == "\\" and i < #line then
            i += 1
            table.insert(current, string.sub(line, i, i))
        elseif c == ":" then
            table.insert(out, table.concat(current))
            current = {}
        else
            table.insert(current, c)
        end
        i += 1
    end
    table.insert(out, table.concat(current))
    return out
end

-- What NetworkManager said, without its preamble.
local function reason(lines: { string }): string
    local first = ""
    for _, l in lines do
        local t = string.match(l, "^%s*(.-)%s*$") or ""
        if t ~= "" then
            if string.sub(t, 1, 6) == "Error:" then return (string.gsub(t, "^Error:%s*", "")) end
            if first == "" then first = t end
        end
    end
    return if first ~= "" then first else "NetworkManager refused it."
end

local reading: any = nil
local again: any = nil
function M.refresh()
    if reading and reading.running then
        if again then again:stop() end
        again = g.after(timing.seconds.debounce, M.refresh)
        return
    end
    local lines = {}
    reading = g.process {
        command = { "sh", "-c",
            "nmcli -t -f NAME,UUID,TYPE connection show; echo '--'; nmcli -t -f UUID,STATE connection show --active" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function(code: number)
            if code ~= 0 then return end
            local states, out, second = {}, {}, false
            for _, line in lines do
                if line == "--" then
                    second = true
                elseif second then
                    local f = fields(line)
                    if #f >= 2 and f[1] ~= "" then states[f[1]] = f[2] end
                end
            end
            for _, line in lines do
                if line == "--" then break end
                local f = fields(line)
                if #f >= 3 and (f[3] == "vpn" or f[3] == "wireguard") then
                    table.insert(out, { name = f[1], uuid = f[2], type = f[3], state = "" })
                end
            end
            for _, p in out do p.state = states[p.uuid] or "" end
            table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
            profiles.value = out
            local w = g.untracked(function() return working.value end)
            if w ~= "" then
                local still = false
                for _, p in out do
                    if p.uuid == w and p.state ~= "activated" and p.state ~= "" then still = true end
                end
                if not still then working.value = "" end
            end
        end,
    }
end

-- Every change NetworkManager announces, debounced into one read.
local function monitor()
    g.process {
        command = { "nmcli", "monitor" },
        on_line = function()
            if again then again:stop() end
            again = g.after(timing.seconds.debounce, M.refresh)
        end,
        on_exit = function() g.after(5, monitor) end,
    }
end
monitor()
M.refresh()

function M.toggle(profile: any, on: boolean)
    if not profile or g.untracked(function() return working.value end) ~= "" then return end
    error_text.value = ""
    working.value = profile.uuid
    local complaint = {}
    g.process {
        command = { "nmcli", "connection", if on then "up" else "down", "uuid", profile.uuid },
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function(code: number)
            if code ~= 0 then
                error_text.value = reason(complaint)
                working.value = ""
            end
            M.refresh()
        end,
    }
end

function M.remove(profile: any)
    if not profile then return end
    error_text.value = ""
    local complaint = {}
    g.process {
        command = { "nmcli", "connection", "delete", "uuid", profile.uuid },
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function(code: number)
            if code ~= 0 then error_text.value = reason(complaint) end
            M.refresh()
        end,
    }
end

-- An OpenVPN file imported as a profile, with its credentials stored by
-- `scripts/vpn credentials`, which reads them from its input: a password
-- never goes on a command line every user can read.
local imported_listeners: { (string) -> () } = {}
function M.on_imported(f: (string) -> ()) table.insert(imported_listeners, f) end
local function imported(name: string)
    for _, f in imported_listeners do f(name) end
end

function M.import_profile(file: string, user: string, password: string)
    if g.untracked(function() return importing.value end) then return end
    error_text.value = ""
    importing.value = true
    local path = string.gsub(file, "^file://", "")
    local said, complaint = {}, {}
    g.process {
        command = { "nmcli", "connection", "import", "type", "openvpn", "file", path },
        env = { LC_ALL = "C.UTF-8" },
        on_line = function(line: string) table.insert(said, line) end,
        on_error_line = function(line: string) table.insert(complaint, line) end,
        on_exit = function(code: number)
            local text = table.concat(said, "\n")
            local name, uuid = string.match(text, "Connection '(.*)' %(([%x%-]+)%)")
            if code ~= 0 or not name or not uuid or #uuid ~= 36 then
                error_text.value = reason(if #complaint > 0 then complaint else said)
                importing.value = false
                return
            end
            if user == "" and password == "" then
                importing.value = false
                imported(name)
                M.refresh()
                return
            end
            local keep_complaint = {}
            local keeper = g.process {
                command = { paths.script("vpn"), "credentials", uuid },
                on_error_line = function(line: string) table.insert(keep_complaint, line) end,
                on_exit = function(kept: number)
                    importing.value = false
                    if kept ~= 0 then error_text.value = reason(keep_complaint) else imported(name) end
                    M.refresh()
                end,
            }
            keeper:write(user .. "\n" .. password .. "\n")
            keeper:close_input()
        end,
    }
end

return M
