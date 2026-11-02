--!strict
-- What the settings pages share while they are open (cells/SettingsPlace.qml
-- and the settings cell's own properties): the monitor being looked at, so
-- choosing one on the Monitors page and going to the Structure page is
-- looking at the same screen; and the Structure page's chosen slot, kept
-- across a close as the cell kept it.
local g = require("@genoma")

local M = {}

M.monitor = g.signal("")

-- `top`, `bottom` or `floating`, and which: a membrane's slot from 1 to 3,
-- a floating tissue by its place in the `floating` list; 0 for none.
M.slot_edge = g.signal("top")
M.slot = g.signal(0)

return M
