--!strict
-- The keybinds of the compositor that runs, through the one service that
-- speaks its configuration: niri's (services/keybinds_niri.luau),
-- Hyprland's (keybinds_hyprland) or Umbriel's (keybinds_umbriel). All
-- three answer the same: `binds()` in the order the compositor reads them,
-- each with `id`, `file`, `key` (niri's spelling, "Mod+Shift+Space"),
-- `label`, `caps`, `norm` and `shadowed`, and `fixed` when it is read but
-- cannot be rewritten here; `owner`, `rekey`, `remove`, `add`, `actions`
-- and `spawn_of`, `busy` and `error`; `main`, the file a new bind goes to;
-- `group`, the picker's heading for the compositor's own actions; and
-- `where`, a line saying what the page reads and writes.
--
-- Elsewhere (the standard protocols alone) there is no configuration to
-- read: an empty list that refuses every change.
local name = require("services/compositor").name()

if name == "hyprland" then return require("services/keybinds_hyprland") end
if name == "umbriel" then return require("services/keybinds_umbriel") end
if name == "niri" then return require("services/keybinds_niri") end

local kdl = require("services/niri_kdl")
local M = {}
M.main = ""
M.group = ""
M.where = "this compositor's keys are not Bioma's to read"
function M.binds(): { any } return {} end
function M.count(): number return 0 end
function M.owner(_key: string, _except: string?): any return nil end
function M.keycaps(key: string): { string } return kdl.keycaps(key) end
function M.humanize(n: string): string return kdl.humanize(n) end
function M.busy(): boolean return false end
function M.error(): string return "" end
function M.rekey(_bind: any, _key: string) end
function M.remove(_bind: any) end
function M.add(_key: string, _action: any, _title: string) end
function M.actions(): { string } return {} end
function M.ask_actions() end
function M.spawn_of(_entry: any): any return nil end
return M
