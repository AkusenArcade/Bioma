--!strict
-- A few of niri's settings (services/NiriSettings.qml at 11bb81e): the
-- gaps, the focus ring, the focus following the pointer, the named
-- workspaces, what starts with the session, and what the window rules say
-- about each application.
--
-- Read here from niri's files, and written to the file each thing came
-- from, once niri has validated it. Bioma on Genoma alone writes (M6 step
-- 7a); beside Quickshell, Quickshell does (`niri …` through scripts/ipc,
-- genoma/PORT.md, "Who acts on the desktop"), a thing named to it by
-- `file#start#kind`, start counted from 0 as JavaScript counts.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local runtime = require("core/runtime")
local timing = require("core/timing")
local niri_config = require("services/niri_config")
local kdl = require("services/niri_kdl")

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
-- reads them: the last is the one in force. `list` is everything niri
-- reads, or only the person's part of it.
local function named(section: string, name: string, list: { any }?): { any }
    local out = {}
    for _, item in list or niri_config.items() do
        if item.kind == "section" and item.name == section then
            for _, child in item.children do
                if not child.dropped and child.name == name then
                    table.insert(out, { file = item.file, section = item, node = child })
                end
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
function M.removable(rule: any): boolean
    if rule.others ~= 0 or rule.excludes ~= 0 then return false end
    for _, match in rule.matches do
        local keys = 0
        for _ in match do keys += 1 end
        if keys ~= 1 or match["app-id"] == nil then return false end
    end
    return true
end

-- ---- Writing ------------------------------------------------------------------

local writing = g.signal(0)
local said = g.signal("")
function M.busy(): boolean
    if runtime.alone() then return niri_config.busy() end
    return writing.value > 0
end
function M.error(): string
    if runtime.alone() then return niri_config.error() end
    return said.value
end

-- Beside Quickshell: asked of it.
local function ask(args: { string }, after: (() -> ())?)
    local command = { paths.script("ipc"), "niri" }
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
                    command = { paths.script("ipc"), "niri", "error" },
                    on_line = function(line: string) if line ~= "" then said.value = line end end,
                }
            end)
        end,
    }
end
local function quick_figure(v: number): string return tostring(math.round(v * 1000) / 1000) end

-- Alone: written here. One change at a time, each computed against the text
-- as it is read now; a press made while niri is still checking the last one
-- is dropped.
local function alone(): boolean return g.untracked(runtime.alone) end
local function busy_now(): boolean return g.untracked(niri_config.busy) end

-- The item as the files say it now: one no longer there was read from a
-- text that has changed since, and its offsets point somewhere else.
local function signature(item: any): string
    if not item then return "" end
    if item.kind == "rule" then
        return g.to_json({ item.matches, item.opacity or false, item.width or false, item.workspace or false, item.others })
    end
    if item.kind == "workspace" then return item.name .. "\0" .. item.output end
    if item.kind == "spawn" then return table.concat(item.args, "\0") .. "\0" .. tostring(item.sh) .. tostring(item.on) end
    return ""
end
local function current(item: any): any
    local said_now = signature(item)
    for _, other in g.untracked(niri_config.items) do
        if item and other.file == item.file and other.kind == item.kind and other.start == item.start
            and other["end"] == item["end"] and signature(other) == said_now then
            return other
        end
    end
    niri_config.set_error("The file changed under this setting. Try again.")
    return nil
end

local function commit(file: string, change: (string) -> string)
    local text = niri_config.text_of(file)
    if not text then
        niri_config.set_error("niri's configuration could not be read.")
        return
    end
    local next = change(text)
    if next ~= text then niri_config.write(file, next, kdl.standalone(next)) end
end
local function edits(file: string, list: { any })
    if #list > 0 then commit(file, function(text: string) return kdl.spliced(text, list) end) end
end
-- Edits gathered across files, { [file] = { edit } }, one file after another.
local function edits_across(by_file: { [string]: { any } })
    for file, list in by_file do edits(file, list) end
end
local function add_edit(by_file: { [string]: { any } }, file: string, edit: any)
    by_file[file] = by_file[file] or {}
    table.insert(by_file[file], edit)
end

-- A new top-level entry beside the last one like it (`like`, or else the
-- last of its kind), or at the end of niri's own file when there is none.
local function place(kind: string, entry: string, apart: boolean, like: { any }?)
    local found = like
    if not found or #found == 0 then
        found = {}
        for _, item in g.untracked(items) do if item.kind == kind then table.insert(found, item) end end
    end
    local last = found[#found]
    if last then
        commit(last.file, function(text: string) return kdl.spliced(text, { kdl.after(text, last, entry, apart) }) end)
    else
        commit(M.main, function(text: string) return kdl.spliced(text, { kdl.appending(text, entry) }) end)
    end
end

-- A child of a section, beside the section's last child; or a section of
-- its own at the end of niri's file.
local function add_to_section(name: string, entry: string)
    local found = nil
    for _, item in g.untracked(items) do
        if item.kind == "section" and item.name == name then found = item end
    end
    if found then
        local kids = {}
        for _, child in found.children do if not child.dropped then table.insert(kids, child) end end
        commit(found.file, function(text: string) return kdl.with_child(text, found, entry, kids[#kids]) end)
    else
        commit(M.main, function(text: string)
            return kdl.spliced(text, { kdl.appending(text, name .. " {\n    " .. entry .. "\n}") })
        end)
    end
end

-- Every `focus-ring { width }` in the person's files.
local function ring_widths(list: { any }): { any }
    local out = {}
    for _, ring in named("layout", "focus-ring", list) do
        for _, child in (if ring.node.children then ring.node.children.nodes else {}) do
            if not child.dropped and child.name == "width" then table.insert(out, { file = ring.file, node = child }) end
        end
    end
    return out
end

local function write_gaps(value: number)
    local entry = "gaps " .. value
    local mine = named("layout", "gaps", g.untracked(items))
    if #mine == 0 then
        add_to_section("layout", entry)
        return
    end
    -- Every one of them, so the number on the page is the number in every
    -- file: one left behind comes back the day the later file is gone.
    local by_file = {}
    for _, found in mine do
        add_edit(by_file, found.file, kdl.replacing(niri_config.text_of(found.file) or "", found.node, entry))
    end
    edits_across(by_file)
end

local function write_focus_ring(value: number)
    if g.untracked(M.themed) then
        config.set("niri.focus_ring", value)
        return
    end
    local entry = "width " .. value
    local mine = ring_widths(g.untracked(items))
    if #mine == 0 then
        add_to_section("layout", "focus-ring { " .. entry .. "; }")
        return
    end
    local by_file = {}
    for _, found in mine do
        add_edit(by_file, found.file, kdl.replacing(niri_config.text_of(found.file) or "", found.node, entry))
    end
    edits_across(by_file)
end

-- A slider's value: shown at once, written once the hand rests, and kept
-- until niri has read it back, so the slider does not jump to the old
-- value in between.
local resting: any = nil
local function slide(key: string, call: string, value: number)
    local next = table.clone(g.untracked(function() return pending.value end))
    next[key] = value
    pending.value = next
    if not alone() then
        ask({ call, quick_figure(value) }, function()
            g.after(1, function()
                local now = table.clone(g.untracked(function() return pending.value end))
                if now[key] == value then
                    now[key] = nil
                    pending.value = now
                end
            end)
        end)
        return
    end
    if resting then resting:stop() end
    local function rest()
        resting = g.after(timing.seconds.blur_settle, function()
            resting = nil
            if busy_now() then rest() return end
            local asked = g.untracked(function() return pending.value end)
            if asked.gaps ~= nil then write_gaps(asked.gaps) end
            if asked.focus_ring ~= nil then write_focus_ring(asked.focus_ring) end
            local function settle()
                g.after(0.1, function()
                    if busy_now() then settle() return end
                    pending.value = {}
                end)
            end
            settle()
        end)
    end
    rest()
end
function M.set_gaps(value: number) slide("gaps", "gaps", math.round(value)) end
function M.set_focus_ring(value: number) slide("focus_ring", "focusRing", math.round(value)) end

function M.set_follows_mouse(on: boolean)
    if not alone() then ask({ "followsMouse", tostring(on) }) return end
    if busy_now() or on == g.untracked(M.follows_mouse) then return end
    local mine = g.untracked(items)
    if not on then
        local by_file = {}
        for _, found in named("input", "focus-follows-mouse", mine) do
            add_edit(by_file, found.file, kdl.switching_off(niri_config.text_of(found.file) or "", found.node))
        end
        edits_across(by_file)
        return
    end
    -- The line that was switched off, if there is one, comes back as it
    -- was, with its `max-scroll-amount` if it had one.
    local commented = nil
    for _, section in mine do
        if section.kind == "section" and section.name == "input" then
            for _, note in section.commented or {} do
                if note.node.name == "focus-follows-mouse" then commented = { file = section.file, note = note } end
            end
            for _, child in section.children do
                if child.dropped and child.name == "focus-follows-mouse" then
                    commented = { file = section.file, note = { start = child.start, body_start = child.name_start } }
                end
            end
        end
    end
    if commented then
        edits(commented.file, { kdl.switching_on(commented.note) })
    else
        add_to_section("input", "focus-follows-mouse")
    end
end

-- ---- Workspaces -------------------------------------------------------------------

-- A name is where a window rule sends windows and a key goes: neither empty
-- nor another workspace's. niri compares names without case; the one being
-- renamed is told by its place in its file.
function M.workspace_problem(name: string, except: any?): string
    local wanted = string.match(name, "^%s*(.-)%s*$") or ""
    if wanted == "" then return "A workspace needs a name." end
    for _, ws in M.workspaces() do
        local itself = except ~= nil and ws.file == except.file and ws.start == except.start
        if not itself and string.lower(ws.name) == string.lower(wanted) then return "Another workspace already has this name." end
    end
    return ""
end

local function free_workspace(): string
    local n = #g.untracked(M.workspaces) + 1
    while g.untracked(function() return M.workspace_problem("Workspace " .. n, nil) end) ~= "" do n += 1 end
    return "Workspace " .. n
end

function M.add_workspace()
    if not alone() then ask({ "addWorkspace" }) return end
    if busy_now() then return end
    local list = g.untracked(M.workspaces)
    local last = list[#list]
    place("workspace", "workspace " .. kdl.quote(free_workspace()), last ~= nil and last.open >= 0)
end

-- The new name everywhere the old one is used: the rules that open windows
-- on it and the binds that go to it.
function M.rename_workspace(ws: any, name: string)
    if not alone() then ask({ "renameWorkspace", M.id(ws), name }) return end
    local wanted = string.match(name, "^%s*(.-)%s*$") or ""
    if busy_now() or wanted == ws.name then return end
    ws = current(ws)
    if not ws or g.untracked(function() return M.workspace_problem(wanted, ws) end) ~= "" then return end
    local by_file = {}
    local quoted = kdl.quote(wanted)
    add_edit(by_file, ws.file, { start = ws.name_start, ["end"] = ws.name_end, text = quoted })
    for _, item in g.untracked(items) do
        local text = niri_config.text_of(item.file) or ""
        if item.kind == "rule" and item.workspace ~= nil then
            for _, child in item.children do
                if child.name == "open-on-workspace" and #child.args > 0 and child.args[1].value == ws.name then
                    add_edit(by_file, item.file, { start = child.args[1].start, ["end"] = child.args[1]["end"], text = quoted })
                end
            end
        elseif item.kind == "bind" and item.action and string.find(item.action.name, "workspace", 1, true)
            and table.find(item.action.args, ws.name) then
            for _, found in kdl.naming(text, item.start, item["end"], ws.name) do
                found.text = quoted
                add_edit(by_file, item.file, found)
            end
        end
    end
    edits_across(by_file)
end

function M.set_workspace_output(ws: any, output: string)
    if not alone() then ask({ "workspaceOutput", M.id(ws), output }) return end
    if busy_now() or output == ws.output then return end
    ws = current(ws)
    if not ws then return end
    local text = niri_config.text_of(ws.file) or ""
    local entry = "open-on-output " .. kdl.quote(output)
    if ws.output_node then
        edits(ws.file, { if output ~= "" then kdl.replacing(text, ws.output_node, entry) else kdl.removing(text, ws.output_node) })
    elseif output ~= "" and ws.open >= 0 then
        commit(ws.file, function(t: string) return kdl.with_child(t, ws, entry, ws.children[#ws.children]) end)
    elseif output ~= "" then
        edits(ws.file, { kdl.replacing(text, ws, "workspace " .. kdl.quote(ws.name) .. " {\n    " .. entry .. "\n}") })
    end
end

-- A workspace changes places with its neighbour, only one in the same file:
-- across files the order is the order of the includes.
function M.move_workspace(ws: any, delta: number)
    if not alone() then ask({ "moveWorkspace", M.id(ws), tostring(delta) }) return end
    if busy_now() then return end
    ws = current(ws)
    if not ws then return end
    local list = g.untracked(M.workspaces)
    local here = nil
    for i, other in list do if other.file == ws.file and other.start == ws.start then here = i end end
    local other = if here then list[here + delta] else nil
    if not other or other.file ~= ws.file then return end
    local text = niri_config.text_of(ws.file) or ""
    edits(ws.file, {
        { start = ws.start, ["end"] = ws["end"], text = string.sub(text, other.start, other["end"] - 1) },
        { start = other.start, ["end"] = other["end"], text = string.sub(text, ws.start, ws["end"] - 1) },
    })
end

function M.remove_workspace(ws: any)
    if not alone() then ask({ "removeWorkspace", M.id(ws) }) return end
    if busy_now() then return end
    ws = current(ws)
    if ws then edits(ws.file, { kdl.removing(niri_config.text_of(ws.file) or "", ws) }) end
end

-- ---- At startup --------------------------------------------------------------------

-- `command` is the words of a command, or one line for the shell.
function M.add_startup(command: { string } | string, sh: boolean)
    if not alone() then
        if sh then
            ask({ "addStartup", tostring(command), "true" })
        else
            ask({ "addStartup", g.to_json(g.array(table.clone(command :: { string }))), "false" })
        end
        return
    end
    if busy_now() then return end
    local entry
    if sh then
        local line = string.match(tostring(command), "^%s*(.-)%s*$") or ""
        if line == "" then return end
        entry = kdl.spawn_line(line, true)
    else
        if #(command :: { string }) == 0 then return end
        entry = kdl.spawn_line(command, false)
    end
    place("spawn", entry, false, g.untracked(M.startup))
end

function M.set_startup_on(item: any, on: boolean)
    if not alone() then ask({ "startupOn", M.id(item), tostring(on) }) return end
    if busy_now() or on == item.on then return end
    item = current(item)
    if not item then return end
    local text = niri_config.text_of(item.file) or ""
    edits(item.file, { if on then kdl.switching_on(item) else kdl.switching_off(text, item) })
end

function M.remove_startup(item: any)
    if not alone() then ask({ "removeStartup", M.id(item) }) return end
    if busy_now() then return end
    item = current(item)
    if item then edits(item.file, { kdl.removing(niri_config.text_of(item.file) or "", item) }) end
end

-- ---- Window rules ----------------------------------------------------------------------

local function set_rule(rule: any, name: string, entry: string?)
    if busy_now() then return end
    rule = current(rule)
    if not rule then return end
    local text = niri_config.text_of(rule.file) or ""
    local present = nil
    for _, child in rule.children do if child.name == name then present = child end end
    if entry == nil then
        if present then edits(rule.file, { kdl.removing(text, present) }) end
    elseif present then
        edits(rule.file, { kdl.replacing(text, present, entry :: string) })
    else
        commit(rule.file, function(t: string) return kdl.with_child(t, rule, entry :: string, rule.children[#rule.children]) end)
    end
end

function M.set_rule_opacity(rule: any, value: number?)
    if not alone() then ask({ "ruleOpacity", M.id(rule), quick_figure(value or -1) }) return end
    set_rule(rule, "opacity", if value == nil then nil else "opacity " .. kdl.figure(value))
end
function M.set_rule_width(rule: any, fraction: number?)
    if not alone() then ask({ "ruleWidth", M.id(rule), quick_figure(fraction or -1) }) return end
    set_rule(rule, "default-column-width",
        if fraction == nil then nil else "default-column-width { proportion " .. kdl.figure(fraction) .. "; }")
end
function M.set_rule_workspace(rule: any, name: string?)
    if not alone() then ask({ "ruleWorkspace", M.id(rule), name or "" }) return end
    set_rule(rule, "open-on-workspace", if name == nil or name == "" then nil else "open-on-workspace " .. kdl.quote(name))
end
function M.remove_rule(rule: any)
    if not alone() then ask({ "removeRule", M.id(rule) }) return end
    if busy_now() or not M.removable(rule) then return end
    rule = current(rule)
    if rule then edits(rule.file, { kdl.removing(niri_config.text_of(rule.file) or "", rule) }) end
end

-- An application's windows, by the id they report: matched whole, so `zen`
-- is not also `zen-beta`; beside the other rules for an application, since
-- the last rule of all can be a file's catch-all, included after them.
function M.add_rule(app_id: string)
    if not alone() then ask({ "addRule", app_id }) return end
    if busy_now() or app_id == "" then return end
    local pattern = "^" .. string.gsub(app_id, "[%.%*%+%?%^%$%{%}%(%)|%[%]\\]", "\\%0") .. "$"
    place("rule", kdl.rule_block(pattern), true, g.untracked(M.rules))
end

-- ---- Window opacity ---------------------------------------------------------------------

-- Every window's opacity, in focus and out of it, and an application's rule
-- giving its windows another one in focus only. niri takes a window's
-- opacity from the last rule that matches it, so this order cannot live
-- among the person's rules: wherever an application's rule stands, the
-- rule for every window out of focus would have to come after it. Both are
-- written in Bioma's own file, included last (scripts/niri-include): out of
-- focus nothing overrides them; in focus the windows of every application
-- with an opacity of its own are excluded, and keep that one.
--
-- "In focus" is niri's `is-active`, the window with the lit focus ring:
-- one on each monitor, not only the one taking the keys.

local function is_true(v: any): boolean return v == true or v == "true" or v == "#true" end
local function is_false(v: any): boolean return v == false or v == "false" or v == "#false" end
local function keys_of(t: any): number
    local n = 0
    for _ in t do n += 1 end
    return n
end

-- A rule for every window: its matches say only `app-id=".*"`.
function M.every_window(rule: any): boolean
    if rule.kind ~= "rule" or rule.excludes ~= 0 or #rule.matches == 0 then return false end
    for _, match in rule.matches do
        local id = match["app-id"]
        if keys_of(match) ~= 1 or (id ~= ".*" and id ~= "^.*$") then return false end
    end
    return true
end
-- A rule for every window out of focus: its matches say only `is-active=false`
-- (or `is-focused=false`).
local function every_unfocused(rule: any): boolean
    if rule.kind ~= "rule" or rule.excludes ~= 0 or #rule.matches == 0 then return false end
    for _, match in rule.matches do
        if keys_of(match) ~= 1 then return false end
        local v = match["is-active"]
        if v == nil then v = match["is-focused"] end
        if v == nil or not is_false(v) then return false end
    end
    return true
end
-- The opacity the last of the person's rules of that kind says.
local function said_by(test: (any) -> boolean): number?
    local found = nil
    for _, item in items() do
        if item.kind == "rule" and item.opacity ~= nil and test(item) then found = item.opacity end
    end
    return found
end

-- What the page chose, or nil while niri's own rules decide (false in the
-- override, since a JSON null is not written).
local function chosen(key: string): number?
    local v = config.get("niri." .. key, false)
    return if type(v) == "number" then v else nil
end
function M.owns_opacity(): boolean
    return chosen("focused_opacity") ~= nil or chosen("unfocused_opacity") ~= nil
end
-- Until the page chooses, what the person's rules say: the rule for every
-- window, the rule for every window out of focus, or else fully opaque.
function M.focused_opacity(): number
    return chosen("focused_opacity") or said_by(M.every_window) or 1
end
function M.unfocused_opacity(): number
    return chosen("unfocused_opacity") or said_by(every_unfocused) or M.focused_opacity()
end
-- Choosing one keeps the other as it is shown, so moving one slider does
-- not move what the other window looks like.
local function choose(key: string, other: string, value: number, other_value: number)
    local pairs = { { "niri." .. key, math.round(value * 100) / 100 } }
    if chosen(other) == nil then table.insert(pairs, { "niri." .. other, math.round(other_value * 100) / 100 }) end
    config.set_many(pairs)
end
function M.set_focused_opacity(value: number)
    choose("focused_opacity", "unfocused_opacity", value, g.untracked(M.unfocused_opacity))
end
function M.set_unfocused_opacity(value: number)
    choose("unfocused_opacity", "focused_opacity", value, g.untracked(M.focused_opacity))
end
-- Back to niri's own rules.
function M.clear_opacity()
    config.set_many({ { "niri.focused_opacity", false }, { "niri.unfocused_opacity", false } })
end

-- A match of a person's rule as an `exclude` line.
local BOOLEAN_MATCHES = {
    ["is-active"] = true, ["is-focused"] = true, ["is-active-in-column"] = true, ["is-floating"] = true,
    ["is-urgent"] = true, ["is-window-cast-target"] = true, ["at-startup"] = true,
}
local function exclude_line(match: { [string]: any }): string
    local names = {}
    for name in match do table.insert(names, name) end
    table.sort(names)
    local words = { "exclude" }
    for _, name in names do
        local v = match[name]
        local text = if BOOLEAN_MATCHES[name] then (if is_true(v) then "true" else "false") else kdl.quote(v)
        table.insert(words, name .. "=" .. text)
    end
    return table.concat(words, " ")
end

local WINDOWS_HEAD = "// Written by Bioma's settings cell (NIRI, WINDOW OPACITY). Changing it rewrites this file."
local function windows_body(): string
    if not M.owns_opacity() then return WINDOWS_HEAD .. "\n// niri's own rules decide." end
    local lines = { WINDOWS_HEAD, "", "window-rule {", "    match is-active=true" }
    local seen = {}
    for _, rule in M.rules() do
        if rule.opacity ~= nil and not M.every_window(rule) then
            for _, match in rule.matches do
                local line = exclude_line(match)
                if not seen[line] then
                    seen[line] = true
                    table.insert(lines, "    " .. line)
                end
            end
        end
    end
    table.insert(lines, "    opacity " .. kdl.figure(M.focused_opacity()))
    table.insert(lines, "}")
    table.insert(lines, "")
    table.insert(lines, "window-rule {")
    table.insert(lines, "    match is-active=false")
    table.insert(lines, "    opacity " .. kdl.figure(M.unfocused_opacity()))
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

-- One write at a time; a body that arrives meanwhile is written after it,
-- the latest only, and one already written is not written again.
local windows_written: string? = nil
local windows_writing, windows_next = false, nil :: string?
local function write_windows(body: string)
    if body == windows_written then return end
    if windows_writing then
        windows_next = body
        return
    end
    windows_writing = true
    local said_now = {}
    -- The load's, not the effect's: the write changes niri's files, the
    -- effect runs again, and a process it owned would go with its run
    -- before saying it had finished.
    local p = g.lasting(function() return g.process {
        command = { paths.script("niri-include"), "windows" },
        on_error_line = function(line: string) table.insert(said_now, line) end,
        on_exit = function()
            windows_writing = false
            local reason = string.match(table.concat(said_now, "\n"), "^%s*(.-)%s*$") or ""
            if reason ~= "" then niri_config.set_error("niri refused it: " .. reason) else windows_written = body end
            if windows_next then
                local again = windows_next :: string
                windows_next = nil
                write_windows(again)
            end
        end,
    } end)
    p:write(body)
    p:close_input()
end

-- Kept in step with the applications' rules, which name the windows the
-- rule for every window in focus leaves out, from start to end of the
-- session. Nothing is written for a person who never chose, unless the
-- file is already there to be emptied.
local windows_file = kdl.resolve("bioma-windows.kdl", kdl.directory_of(M.main), g.env("HOME") or "")
function M.start()
    g.effect(function()
        if not niri_config.read_all() then return end
        local body = windows_body()
        if not M.owns_opacity() and niri_config.text_of(windows_file) == nil then return end
        g.untracked(function() write_windows(body) end)
    end)
end

return M
