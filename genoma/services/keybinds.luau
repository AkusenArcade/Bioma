--!strict
-- niri's keybinds (services/Keybinds.qml at 11bb81e): every bind niri
-- reads, in the order it reads them, across the configuration's files.
--
-- One file per bind, but one niri: the same key in two files is allowed,
-- and the one read later wins. A bind overridden that way is still listed,
-- marked `shadowed`, because it is still written down somewhere.
--
-- Writing stays Bioma on Quickshell's while the two run side by side (`qs
-- ipc call keybinds …`): it rewrites the file each bind came from and has
-- niri validate it (genoma/PORT.md, "Who acts on the desktop").
local g = require("@genoma")
local paths = require("core/paths")
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
function M.busy(): boolean return writing.value > 0 end
function M.error(): string return said.value end

local function ask(args: { string })
    local command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "keybinds" }
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
                    command = { "qs", "-p", paths.root .. "/shell.qml", "ipc", "call", "keybinds", "error" },
                    on_line = function(line: string) if line ~= "" then said.value = line end end,
                }
            end)
        end,
    }
end

function M.rekey(bind: any, key: string) ask({ "rekey", bind.id, key }) end
function M.remove(bind: any) ask({ "remove", bind.id }) end
function M.add(key: string, action: { name: string, args: { string } }, title: string)
    ask({ "add", key, g.to_json({ name = action.name, args = g.array(table.clone(action.args)) }), title })
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
