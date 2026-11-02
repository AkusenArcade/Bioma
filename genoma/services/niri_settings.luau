--!strict
-- A few of niri's settings (services/NiriSettings.qml at 11bb81e): the
-- gaps, the focus ring, the focus following the pointer, the named
-- workspaces, what starts with the session, and what the window rules say
-- about each application.
--
-- Read here from niri's files; written by Bioma on Quickshell while the two
-- run side by side (`qs ipc call niri …`), which rewrites the file each
-- thing came from and has niri validate it (genoma/PORT.md, "Who acts on the
-- desktop"). A thing is named to it by `file#start#kind`, start counted from
-- 0 as JavaScript counts.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local niri_config = require("services/niri_config")

local M = {}

M.main = niri_config.main
M.default_gaps = 16

-- Bioma's own files, which this page does not edit.
local function own(file: string): boolean
    local parts = string.split(file, "/")
    local base = parts[#parts]
    return string.sub(base, 1, 5) == "bioma" or string.sub(file, 1, #paths.root + 1) == paths.root .. "/"
end

local function items(): { any }
    local out = {}
    for _, item in niri_config.items() do
        if not own(item.file) then table.insert(out, item) end
    end
    return out
end

function M.id(item: any): string return item.file .. "#" .. (item.start - 1) .. "#" .. item.kind end

-- Every child of that name in the sections of that name, in the order niri
-- reads them: the last is the one in force.
local function named(section: string, name: string): { any }
    local out = {}
    for _, item in niri_config.items() do
        if item.kind == "section" and item.name == section then
            for _, child in item.children do
                if not child.dropped and child.name == name then table.insert(out, { file = item.file, node = child }) end
            end
        end
    end
    return out
end

-- While a slider is moving, what it said last, ahead of the file.
local pending = g.signal({} :: { [string]: number })

function M.gaps(): number
    local p = pending.value.gaps
    if p ~= nil then return p end
    local list = named("layout", "gaps")
    local last = list[#list]
    return if last and #last.node.args > 0 then tonumber(last.node.args[1].value) or M.default_gaps else M.default_gaps
end

function M.themed(): boolean
    return table.find(config.get("theme.templates", {}), "niri") ~= nil
end

function M.focus_ring(): number
    local p = pending.value.focus_ring
    if p ~= nil then return p end
    if M.themed() then return config.get("niri.focus_ring", 2) end
    local width = nil
    for _, ring in named("layout", "focus-ring") do
        for _, child in (if ring.node.children then ring.node.children.nodes else {}) do
            if not child.dropped and child.name == "width" and #child.args > 0 then width = tonumber(child.args[1].value) end
        end
    end
    return width or 4
end

function M.follows_mouse(): boolean return #named("input", "focus-follows-mouse") > 0 end

function M.workspaces(): { any }
    local out = {}
    for _, item in items() do if item.kind == "workspace" then table.insert(out, item) end end
    return out
end

-- Bioma's own line starts the shell, and switching it off from inside the
-- shell is not a setting.
local function is_shell(item: any): boolean
    return not item.sh and #item.args >= 2 and string.match(item.args[1], "/scripts/shell$") ~= nil and item.args[2] == "start"
end
function M.startup(): { any }
    local out = {}
    for _, item in items() do
        if item.kind == "spawn" and not is_shell(item) then table.insert(out, item) end
    end
    return out
end

-- A rule is an application's when one of its matches names one.
local function app_rule(item: any): boolean
    if item.kind ~= "rule" then return false end
    for _, match in item.matches do if match["app-id"] ~= nil then return true end end
    return false
end
function M.rules(): { any }
    local out = {}
    for _, item in items() do if app_rule(item) then table.insert(out, item) end end
    return out
end
function M.other_rules(): number
    local n = 0
    for _, item in items() do if item.kind == "rule" and not app_rule(item) then n += 1 end end
    return n
end

-- A rule says nothing but its matches and what this page edits: it can go.
function M.removable(rule: any): boolean return rule.others == 0 and rule.excludes == 0 end

-- ---- Writing, through Quickshell ----------------------------------------------

local writing = g.signal(0)
local said = g.signal("")
function M.busy(): boolean return writing.value > 0 end
function M.error(): string return said.value end

local function ask(args: { string }, after: (() -> ())?)
    local command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "niri" }
    for _, a in args do table.insert(command, a) end
    writing.value += 1
    said.value = ""
    g.process {
        command = command,
        on_exit = function()
            writing.value -= 1
            if after then after() end
            -- niri's refusal comes once Quickshell has validated the file.
            g.after(1.5, function()
                g.process {
                    command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "niri", "error" },
                    on_line = function(line: string) if line ~= "" then said.value = line end end,
                }
            end)
        end,
    }
end
local function figure(v: number): string return tostring(math.round(v * 1000) / 1000) end

-- A slider's value: shown at once, written once the hand rests.
local function slide(key: string, call: string, value: number)
    local next = table.clone(g.untracked(function() return pending.value end))
    next[key] = value
    pending.value = next
    ask({ call, figure(value) }, function()
        g.after(1, function()
            local now = table.clone(g.untracked(function() return pending.value end))
            if now[key] == value then
                now[key] = nil
                pending.value = now
            end
        end)
    end)
end
function M.set_gaps(value: number) slide("gaps", "gaps", value) end
function M.set_focus_ring(value: number) slide("focus_ring", "focusRing", value) end
function M.set_follows_mouse(on: boolean) ask({ "followsMouse", tostring(on) }) end

function M.add_workspace() ask({ "addWorkspace" }) end
function M.rename_workspace(ws: any, name: string) ask({ "renameWorkspace", M.id(ws), name }) end
function M.set_workspace_output(ws: any, output: string) ask({ "workspaceOutput", M.id(ws), output }) end
function M.move_workspace(ws: any, delta: number) ask({ "moveWorkspace", M.id(ws), tostring(delta) }) end
function M.remove_workspace(ws: any) ask({ "removeWorkspace", M.id(ws) }) end

-- A name is where a window rule sends windows and a key goes: neither empty
-- nor another workspace's.
function M.workspace_problem(name: string, except: any?): string
    local wanted = string.match(name, "^%s*(.-)%s*$") or ""
    if wanted == "" then return "A workspace needs a name." end
    for _, ws in M.workspaces() do
        if ws ~= except and ws.name == wanted then return "Another workspace already has this name." end
    end
    return ""
end

function M.add_startup(command: { string } | string, sh: boolean)
    if sh then
        ask({ "addStartup", tostring(command), "true" })
    else
        ask({ "addStartup", g.to_json(g.array(table.clone(command :: { string }))), "false" })
    end
end
function M.set_startup_on(item: any, on: boolean) ask({ "startupOn", M.id(item), tostring(on) }) end
function M.remove_startup(item: any) ask({ "removeStartup", M.id(item) }) end

function M.set_rule_opacity(rule: any, value: number?) ask({ "ruleOpacity", M.id(rule), figure(value or -1) }) end
function M.set_rule_width(rule: any, fraction: number?) ask({ "ruleWidth", M.id(rule), figure(fraction or -1) }) end
function M.set_rule_workspace(rule: any, name: string?) ask({ "ruleWorkspace", M.id(rule), name or "" }) end
function M.remove_rule(rule: any) ask({ "removeRule", M.id(rule) }) end
function M.add_rule(app_id: string) ask({ "addRule", app_id }) end

return M
