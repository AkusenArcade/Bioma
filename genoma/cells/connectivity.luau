--!strict
-- Ethernet, Wi-Fi and the wireless devices, one glyph per live connection,
-- and the printer while it prints (cells/connectivity/Connectivity.qml at
-- 11bb81e). See docs/design/CELLS.md §11, PRD §9.11.
--
-- The only cell that composes itself: its width says how many connections
-- there are without writing a number. With none it goes rather than shrink
-- to an empty pill — offline is a condition, not a fault. Kept by an
-- `always` visibility, it shows its own mark instead, dim, as a paired
-- device not connected is drawn: present, idle (Akusen, 2026-10-23).
local g = require("@genoma")
local theme = require("core/theme")
local network = require("services/network")
local bluetooth = require("services/bluetooth")
local vpn = require("services/vpn")
local printers = require("services/printers")
local expansion = require("cells/connectivity_expansion")

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function glyph_size(): number return 18 * f() end
        local function pitch(): number return 10 * f() end

        -- What is carrying traffic, the wire first: it does not negotiate. A
        -- tunnel up is a connection too, and the one most worth seeing; a
        -- printer is not, but a job going out is traffic with an end.
        local glyphs = g.computed(function(): { string }
            local out = {}
            if network.wired_connected() then table.insert(out, "ethernet") end
            if network.wifi_connected() then table.insert(out, "wifi") end
            if bluetooth.any_connected() then table.insert(out, "wireless-link") end
            if vpn.any_active() then table.insert(out, "lock") end
            if printers.printing() then table.insert(out, "printer") end
            return out
        end)
        local function composed(): boolean return #glyphs.value > 1 end

        -- Conditional, it is there a moment when something connects that was
        -- not connected before (a different network counts). Going away is
        -- not news.
        local function connections(): { string }
            local out = {}
            if network.wired_connected() then table.insert(out, "wired:" .. network.wired_name()) end
            if network.wifi_connected() then table.insert(out, "wifi:" .. network.ssid()) end
            for _, d in bluetooth.connected_devices() do table.insert(out, "bluetooth:" .. d.address) end
            for _, p in vpn.active() do table.insert(out, "vpn:" .. p.uuid) end
            for _, q in printers.printing_queues() do table.insert(out, "printer:" .. q) end
            return out
        end
        local known: { string } = g.untracked(connections)
        g.watch(function() return table.concat(connections(), "\n") end, function()
            local now = g.untracked(connections)
            local arrived = false
            for _, key in now do
                if not table.find(known, key) then arrived = true end
            end
            known = now
            if arrived then cell.pulse() end
        end)

        -- The Wi-Fi glyph carries the signal: the arcs the strength reaches
        -- lit, the rest dim, in the panel's four steps. A live reading in
        -- the glyph's extent, never a figure and never a state colour
        -- (Akusen, 2026-09-27).
        local function wifi_arcs(): number
            local bars = network.signal_bars()
            return if bars >= 4 then 3 else math.max(0, bars - 1)
        end
        local function glyph(name: () -> string, idle: () -> boolean, size: () -> number): any
            local function wifi(): boolean return name() == "wifi" end
            local function partial(): boolean return wifi() and wifi_arcs() < 3 end
            return g.box {
                width = size,
                height = size,
                g.icon {
                    overlay = true,
                    present = partial,
                    width = size,
                    height = size,
                    icon = "wifi",
                    gradient_top = theme.line,
                    gradient_bottom = theme.line,
                },
                g.icon {
                    overlay = true,
                    width = size,
                    height = size,
                    icon = function() return if partial() then "wifi-signal-" .. wifi_arcs() else name() end,
                    gradient_top = function() return if idle() then theme.line() else theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return if idle() then theme.line() else theme.gradient_bottom(theme.primary()) end,
                },
            }
        end

        local function lead(): string return glyphs.value[1] or "wireless-link" end
        local function none(): boolean return #glyphs.value == 0 end
        local function never(): boolean return false end

        local opened = expansion.new(cell)

        return {
            panel = opened.panel,
            on_key = opened.on_key,
            wants_keyboard = opened.wants_keyboard,
            -- One glyph is a round cell, not a short bar: the configured
            -- minimum is the composed form's (Akusen, 2026-09-22).
            min_width = function()
                if not composed() then return cell.metrics().cell_height end
                local m = cell.block().min_width
                return ((m and m.value) or 64) * f()
            end,
            -- One glyph: the padding that makes the cell square round it.
            padding_leading = function()
                return if composed() then 14 * f() else (cell.metrics().cell_height - glyph_size()) / 2
            end,
            padding_trailing = function()
                return if composed() then 14 * f() else (cell.metrics().cell_height - glyph_size()) / 2
            end,
            condition = function() return if cell.pulsing() then 1 else 0 end,
            content_width = function()
                local n = #glyphs.value
                return if n > 0 then n * glyph_size() + (n - 1) * pitch() else glyph_size()
            end,
            -- The mark is whichever connection leads the row, so the glyph
            -- there a moment ago is still the one the cell wears.
            header_title = "CONNECTIVITY",
            header_mark_size = glyph_size,
            header_mark = function(mark: () -> number) return glyph(lead, none, mark) end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = pitch,
                    g.each {
                        direction = "row",
                        align = "center",
                        gap = pitch,
                        items = function() return glyphs.value end,
                        key = function(name: string) return name end,
                        row = function(name: () -> string) return glyph(name, never, glyph_size) end,
                    },
                    g.box { present = none, glyph(lead, function() return true end, glyph_size) },
                }
            end,
        }
    end,
}
