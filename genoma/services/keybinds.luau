--!strict
-- niri's keybinds (services/Keybinds.qml at 11bb81e): every bind niri
-- reads, in the order it reads them, across the configuration's files.
--
-- One file per bind, but one niri: the same key in two files is allowed,
-- and the one read later wins. A bind overridden that way is still listed,
-- marked `shadowed`, because it is still written down somewhere.
--
-- Writing rewrites the file each bind came from and has niri validate it.
-- Bioma on Genoma alone writes (M6 step 7a); beside Quickshell, Quickshell
-- does (`keybinds …` through scripts/ipc; genoma/PORT.md, "Who acts on the
-- desktop").
local g = require("@genoma")
local paths = require("core/paths")
local runtime = require("core/runtime")
local niri_config = require("services/niri_config")
local kdl = require("services/niri_kdl")

local M = {}

M.main = niri_config.main

local binds = g.computed(function(): { any }
    local found = {}
    for _, item in niri_config.items() do
        if item.kind == "bind" then
            local text = niri_config.text_of(item.file) or ""
            table.insert(found, {
                -- Quickshell's id for it: where it is (counted from 0, as
                -- JavaScript counts) and what it is bound to.
                id = item.file .. "#" .. (item.start - 1) .. "#" .. item.key,
                file = item.file,
                key = item.key,
                key_raw = string.sub(text, item.key_start, item.key_end - 1),
                start = item.start,
                ["end"] = item["end"],
                key_start = item.key_start,
                key_end = item.key_end,
                props = item.props,
                action = item.action,
                label = kdl.describe(item),
                caps = kdl.keycaps(item.key),
                norm = kdl.normalize(item.key),
                shadowed = false,
            })
        end
    end
    local last = {}
    for i, b in found do last[b.norm] = i end
    for i, b in found do b.shadowed = last[b.norm] ~= i end
    return found
end)
function M.binds(): { any } return binds.value end
function M.count(): number return #binds.value end

-- The bind that answers a combination, leaving out the one being edited,
-- which may keep its own key.
function M.owner(key: string, except: string?): any
    local norm = kdl.normalize(key)
    local list = binds.value
    for i = #list, 1, -1 do
        local b = list[i]
        if b.norm == norm and b.id ~= except then return b end
    end
    return nil
end

function M.keycaps(key: string): { string } return kdl.keycaps(key) end
function M.humanize(name: string): string return kdl.humanize(name) end

-- ---- Writing, through Quickshell ----------------------------------------------

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

local function ask(args: { string })
    local command = { paths.script("ipc"), "keybinds" }
    for _, a in args do table.insert(command, a) end
    writing.value += 1
    said.value = ""
    g.process {
        command = command,
        on_exit = function()
            writing.value -= 1
            -- niri's refusal comes once Quickshell has validated the file.
            g.after(1.5, function()
                g.process {
                    command = { paths.script("ipc"), "keybinds", "error" },
                    on_line = function(line: string) if line ~= "" then said.value = line end end,
                }
            end)
        end,
    }
end

-- The text a bind was read from must still be there: an edit made against a
-- file somebody else has changed since would land in the wrong place.
local function current(bind: any): string?
    local text = niri_config.text_of(bind.file)
    if not text or string.sub(text, bind.key_start, bind.key_end - 1) ~= bind.key_raw then
        niri_config.set_error("The file changed under this bind. Try again.")
        return nil
    end
    return text
end
local function commit(file: string, text: string) niri_config.write(file, text, kdl.block_of(text)) end

function M.rekey(bind: any, key: string)
    if not g.untracked(runtime.alone) then ask({ "rekey", bind.id, key }) return end
    local text = current(bind)
    if text then commit(bind.file, kdl.with_key(text, bind, key)) end
end
function M.remove(bind: any)
    if not g.untracked(runtime.alone) then ask({ "remove", bind.id }) return end
    local text = current(bind)
    if text then commit(bind.file, kdl.without(text, bind)) end
end
-- A new bind goes into niri's own file, at the end of its block: the one
-- file here nothing else rewrites.
function M.add(key: string, action: { name: string, args: { string } }, title: string)
    if not g.untracked(runtime.alone) then
        ask({ "add", key, g.to_json({ name = action.name, args = g.array(table.clone(action.args)) }), title })
        return
    end
    local text = niri_config.text_of(M.main)
    if not text then
        niri_config.set_error("niri's configuration could not be read.")
        return
    end
    local scanned = kdl.scan(text)
    local last = nil
    for _, item in scanned.items do if item.kind == "bind" then last = item end end
    commit(M.main, kdl.with_added(text, scanned.block, kdl.line(key, action, title), last))
end

-- ---- What a new bind can do -------------------------------------------------
--
-- niri's own actions, asked of niri, so the list is the one this build
-- knows, minus those that need an argument, which a picker cannot supply.
-- Read once, the first time somebody asks.
local actions = g.signal({} :: { string })
local asked = false
function M.actions(): { string } return actions.value end
function M.ask_actions()
    if asked then return end
    asked = true
    local out = {}
    g.process {
        command = { "bash", "-c",
            "niri msg action --help | awk '/^Actions:/{f=1;next} /^[A-Z]/{f=0} f && /^  [a-z]/{print $1}' "
            .. "| while read -r name; do "
            .. "  usage=$(niri msg action \"$name\" --help 2>/dev/null | grep -m1 '^Usage:'); "
            .. "  case \"$usage\" in *'<'*) ;; *) echo \"$name\";; esac; "
            .. "done" },
        on_line = function(line: string)
            local name = string.match(line, "^%s*(.-)%s*$") or ""
            if name ~= "" then table.insert(out, name) end
        end,
        on_exit = function() actions.value = out end,
    }
end

return M
