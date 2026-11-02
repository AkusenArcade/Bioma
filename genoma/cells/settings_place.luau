--!strict
-- What the settings pages share while they are open (cells/SettingsPlace.qml
-- and the settings cell's own properties): the monitor being looked at, so
-- choosing one on the Monitors page and going to the Structure page is
-- looking at the same screen.
local g = require("@genoma")

local M = {}

M.monitor = g.signal("")

return M
