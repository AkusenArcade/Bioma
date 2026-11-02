--!strict
-- The setup's last step (cells/settings/SetupKeys.qml at 2cafc17): the keys
-- to know. See docs/design/SETUP.md, step 7.
--
-- Bioma says nothing at rest, so someone new does not know where to start.
-- Seven keys, read from their own bioma-binds.kdl by the titles niri's
-- hotkey overlay shows them under (what is drawn is what is bound), and
-- the overlay itself for the rest.
local g = require("@genoma")
local theme = require("core/theme")
local typography = require("core/typography")
local page = require("components/page")
local setup = require("services/setup")

local M = {}

function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    local function m(): any return t.metrics() end
    setup.note("keys", "Seven to start with")

    local function key_row(item: () -> any): any
        return g.box {
            width = p.inner,
            height = function() return 28 * f() end,
            direction = "row",
            align = "center",
            gap = function() return 12 * f() end,
            g.box {
                width = function() return 170 * f() end,
                direction = "row",
                align = "center",
                gap = function() return 4 * f() end,
                g.each {
                    direction = "row",
                    align = "center",
                    gap = function() return 4 * f() end,
                    items = function()
                        local out = {}
                        for i, cap in item().caps do table.insert(out, { i = i, cap = cap }) end
                        return out
                    end,
                    key = function(c: any) return tostring(c.i) end,
                    row = function(c: () -> any)
                        return g.box {
                            direction = "row",
                            align = "center",
                            gap = function() return 4 * f() end,
                            g.text {
                                present = function() return c().i > 1 end,
                                text = "+",
                                color = theme.text_muted,
                                font = typography.technical,
                                size = function() return m().font_meta end,
                            },
                            p.keycap(function() return c().cap end),
                        }
                    end,
                },
                g.text {
                    present = function() return #item().caps == 0 end,
                    text = "NOT BOUND",
                    color = theme.text_faint,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tracking = typography.label_tracking,
                },
            },
            g.text {
                text = function() return item().line end,
                color = theme.text,
                font = typography.expressive,
                size = function() return m().font_secondary end,
                max_width = function() return p.inner() - 182 * f() end,
            },
        }
    end

    return p.column {
        p.section("TO START WITH", nil, {
            g.each {
                direction = "column",
                align = "start",
                gap = function() return 10 * f() end,
                items = setup.keys,
                key = function(k: any) return k.name end,
                row = key_row,
            },
            p.line(function() return "Every key, at any time: Mod+Shift+/, niri's own list, where each of Bioma's has a title." end, theme.text_muted),
        }),
    }
end

return M
