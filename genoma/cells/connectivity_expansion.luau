--!strict
-- Connectivity, opened (cells/connectivity/ConnectivityPanel.qml at
-- 11bb81e): one well per family, each with the switch that turns the
-- family off, never the cell. See docs/design/CELLS.md §11.
--
-- Two wells, two truths about choice. A radio dot marks the Wi-Fi network,
-- because you are on one at a time; the devices have none, because several
-- can be connected at once. A device says what it is with its glyph, lit
-- when connected, dim when only paired.
--
-- Not yet: the VPN, proxy and printer wells; the keyboard's travel through
-- the rows.
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local network = require("services/network")
local bluetooth = require("services/bluetooth")
local field = require("components/field")
local scroller_mod = require("components/scroller")
local sweep = require("components/sweep")
local switch = require("components/switch")

local CLEAR = "#00000000"
local SHOWN_ROWS = 3

local M = {}

function M.new(cell: any): { [string]: any }
    local function m(): any return cell.metrics() end
    local function f(): number return m().factor end
    local function panel_padding(): number return 10 * f() end
    local function content_width(): number return 340 * f() - panel_padding() * 2 end
    local function well_padding(): number return 8 * f() end
    local function well_inset(): number return 10 * f() end
    local function well_spacing(): number return 8 * f() end
    local function row_height(): number return 38 * f() end
    local function header_height(): number return 30 * f() end
    local function field_height(): number return 34 * f() end
    local function error_height(): number return 20 * f() end
    local function inner(): number return content_width() - well_inset() * 2 end

    -- The scanner costs power and is wanted only while the list is looked
    -- at: on while the panel is out. The Bluetooth search is asked for by
    -- hand, and ends with the panel all the same.
    g.watch(function() return cell.open.value end, function(open: boolean)
        network.set_scanning(open)
        if not open then bluetooth.set_discovering(false) end
    end)

    -- ---- Asking for a password ------------------------------------------------
    --
    -- The row opens into a field rather than a dialog: the network being
    -- joined stays in view above what is being typed.
    local asked = g.signal("")
    local secret = g.signal("")
    local function asking(): boolean return asked.value ~= "" end
    local function failed(): boolean return asking() and network.last_error() ~= "" end
    local function stop_asking() asked.value = "" end
    local function asked_network(): any
        for _, n in network.visible_networks() do
            if n.ssid == asked.value then return n end
        end
        return nil
    end
    local function submit()
        local n = g.untracked(asked_network)
        if n then network.join_with_password(n, g.untracked(function() return secret.value end)) end
    end
    local field_node, field_handle = field.new {
        text = secret,
        secret = true,
        width = function() return inner() - 16 * f() - 20 * f() - 90 * f() end,
        font = typography.expressive,
        size = function() return m().font_secondary end,
        taking = function() return cell.open.value and asking() end,
        on_submit = submit,
        on_release = stop_asking,
    }
    local function act(n: any)
        if n.connected then
            network.leave(n)
        elseif network.needs_password(n) then
            field_handle.set("")
            asked.value = n.ssid
        else
            network.join(n)
        end
    end
    -- A network that came up is a question answered.
    g.watch(network.wifi_connected, function(on: boolean) if on then stop_asking() end end)
    g.watch(function() return cell.open.value end, function(open: boolean) if not open then stop_asking() end end)
    local function asked_extra(): number
        return if asking() then field_height() + 8 * f() + (if failed() then error_height() else 0) else 0
    end

    -- ---- Size -------------------------------------------------------------------

    local function well_height(rows: number, extra: number): number
        return well_padding() * 2 + header_height() + math.max(1, math.min(rows, SHOWN_ROWS)) * row_height() + extra
    end
    local function devices(): { any }
        local out = {}
        for _, d in bluetooth.paired_devices() do table.insert(out, { device = d, found = false }) end
        if bluetooth.discovering() then
            for _, d in bluetooth.found_devices() do table.insert(out, { device = d, found = true }) end
        end
        return out
    end
    local function wired_shown(): boolean return network.wired_connected() end
    local function wired_height(): number return well_padding() * 2 + header_height() + row_height() end
    local function wifi_height(): number
        return well_height(if network.wifi_enabled() then #network.visible_networks() else 0, asked_extra())
    end
    local function device_height(): number return well_height(if bluetooth.enabled() then #devices() else 0, 0) end
    local function panel_height(): number
        return panel_padding() * 2 + (if wired_shown() then wired_height() + well_spacing() else 0)
            + wifi_height() + well_spacing() + device_height()
    end

    -- ---- Pieces ---------------------------------------------------------------------

    local function text(t: { [string]: any }): any
        t.font = t.font or typography.expressive
        t.size = t.size or function() return m().font_secondary end
        t.color = t.color or theme.text
        return g.text(t)
    end
    local function meta(content: () -> string): any
        return g.text {
            text = content,
            color = theme.text_muted,
            font = typography.technical,
            size = function() return m().font_meta end,
        }
    end

    -- A well's name after the glyph the family wears in the contracted cell,
    -- so the two match at a glance.
    local function section_title(title: string, glyph: string): any
        return g.box {
            direction = "row",
            align = "center",
            gap = function() return 8 * f() end,
            g.icon {
                width = function() return 14 * f() end,
                height = function() return 14 * f() end,
                icon = glyph,
                gradient_top = function() return theme.gradient_top(theme.primary()) end,
                gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
            },
            g.text {
                text = title,
                color = theme.text,
                font = typography.technical,
                size = function() return m().font_label end,
                weight = typography.weight_label,
                tracking = typography.label_tracking,
            },
        }
    end

    -- A family's header: its name, the switch that turns it off, and for one
    -- that can look for more, SEARCH beside it, the loader running while it
    -- looks — the one movement that means "nothing yet".
    local function family_header(t: { [string]: any }): any
        local search = nil
        if t.searchable then
            search = g.capsule {
                role = "button",
                name = "Search",
                present = t.on,
                height = function() return 22 * f() end,
                padding_x = function() return 10 * f() end,
                direction = "row",
                align = "center",
                gap = function() return 6 * f() end,
                radius = function() return metrics_mod.radius_for(22 * f(), m()) end,
                fill = function() return if t.searching() then colour.alpha(theme.primary(), 0.16) else CLEAR end,
                rim_top = function() return if t.searching() then theme.primary() else theme.line() end,
                rim_bottom = function() return if t.searching() then theme.primary() else theme.line() end,
                on_click = t.on_search,
                sweep.new { size = 16 * f(), present = t.searching, running = t.searching },
                g.text {
                    text = function() return if t.searching() then "STOP" else "SEARCH" end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tracking = typography.label_tracking,
                },
            }
        end
        local right: { [any]: any } = {
            direction = "row",
            align = "center",
            gap = function() return 10 * f() end,
        }
        if search then table.insert(right, search) end
        table.insert(right, switch.new { on = t.on, factor = f, on_toggle = t.on_switch, settling = t.settling })
        return g.box {
            width = inner,
            height = header_height,
            direction = "row",
            align = "center",
            justify = "between",
            section_title(t.title, t.glyph),
            g.box(right),
        }
    end

    -- A radio mark: a ring, or, chosen, the gradient with the panel showing
    -- through its middle.
    local function radio(on: () -> boolean, present: (() -> boolean)?): any
        local function size(): number return 16 * f() end
        return g.box {
            present = present,
            width = size,
            height = size,
            align = "center",
            justify = "center",
            g.capsule {
                overlay = true,
                present = function() return not on() end,
                width = size,
                height = size,
                stroke = metrics_mod.rim_width,
                rim_top = theme.line,
                rim_bottom = theme.line,
            },
            g.capsule {
                overlay = true,
                present = on,
                width = size,
                height = size,
                fill = function() return theme.gradient_top(theme.primary()) end,
                fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                g.capsule {
                    width = function() return size() / 2 end,
                    height = function() return size() / 2 end,
                    fill = theme.background,
                    rim_top = CLEAR,
                    rim_bottom = CLEAR,
                },
            },
        }
    end

    -- Four bars by height, the reached ones in the primary.
    local function strength(bars: () -> number): any
        local heights = { 5, 8, 11, 14 }
        local row: { [any]: any } = {
            direction = "row",
            align = "end",
            height = function() return 14 * f() end,
            gap = function() return 2 * f() end,
        }
        for i, h in heights do
            table.insert(row, g.capsule {
                width = function() return 3 * f() end,
                height = function() return h * f() end,
                fill = function() return if i <= bars() then theme.primary() else colour.alpha(theme.primary(), 0.22) end,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                transition = { fill = "transition" },
            })
        end
        return g.box(row)
    end

    local function well(height: () -> number, children: { any }): any
        local node: { [any]: any } = {
            width = content_width,
            height = height,
            radius = function() return metrics_mod.inner_radius(m().radius_panel, panel_padding()) end,
            fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            transition = { height = "reflow" },
        }
        for _, c in children do table.insert(node, c) end
        return g.capsule(node)
    end

    local function at(x: () -> number, y: () -> number, child: any): any
        return g.box { overlay = true, attach = "corner", offset_x = x, offset_y = y, child }
    end
    local function list_area(height: () -> number, items: () -> { any }, key: (any) -> string, row: any,
        extra: (() -> number)?, present: (() -> boolean)?): any
        local function viewport(): number return height() - well_padding() * 2 - header_height() end
        local scroll = scroller_mod.new {
            viewport = viewport,
            content = function() return #items() * row_height() + (if extra then extra() else 0) end,
            step = row_height,
            factor = f,
        }
        return g.box {
            overlay = true,
            attach = "corner",
            present = present,
            offset_y = function() return well_padding() + header_height() end,
            width = content_width,
            height = viewport,
            clip = true,
            scroll_y = scroll.offset,
            transition = { scroll_y = "reflow" },
            on_wheel = scroll.wheel,
            g.each {
                overlay = true,
                attach = "corner",
                width = content_width,
                items = items,
                key = key,
                row = row,
            },
            scroll.bar(function() return content_width() - 7 * f() end),
        }
    end
    local function empty_note(present: () -> boolean, say: () -> string): any
        return g.box {
            overlay = true,
            present = present,
            offset_y = function() return header_height() / 2 end,
            g.text {
                text = say,
                color = theme.text_muted,
                font = typography.expressive,
                size = function() return m().font_secondary end,
            },
        }
    end

    -- ---- Ethernet ---------------------------------------------------------------------

    local function speed(): string
        local s = network.wired_speed()
        if s >= 1000 then
            local gb = s / 1000
            return (if gb == math.floor(gb) then tostring(math.floor(gb)) else string.format("%.1f", gb)) .. " Gb/s"
        end
        return if s > 0 then s .. " Mb/s" else "Connected"
    end
    local wired_well = well(wired_height, {
        at(well_inset, function() return well_padding() + (header_height() - 14 * f()) / 2 end,
            section_title("ETHERNET", "ethernet")),
        at(well_inset, function() return well_padding() + header_height() end, g.box {
            width = inner,
            height = row_height,
            direction = "row",
            align = "center",
            justify = "between",
            text {
                text = function()
                    local p = network.wired_profile()
                    return if p ~= "" then p else network.wired_interface()
                end,
                max_width = function() return inner() - 90 * f() end,
            },
            meta(speed),
        }),
    })

    -- ---- Wi-Fi --------------------------------------------------------------------------

    local function network_row(item: () -> any, index: () -> number): any
        local function n(): any return item() end
        local function is_asked(): boolean return asked.value == n().ssid end
        local function y(): number
            -- Rows below the asked one move down by what it opened.
            local own = (index() - 1) * row_height()
            if asking() then
                for i, other in network.visible_networks() do
                    if other.ssid == asked.value and i < index() then return own + asked_extra() end
                end
            end
            return own
        end
        return g.box {
            overlay = true,
            attach = "corner",
            offset_x = well_inset,
            offset_y = y,
            width = inner,
            transition = { offset_y = "reflow" },
            g.box {
                role = "button",
                name = "Network",
                width = inner,
                height = row_height,
                direction = "row",
                align = "center",
                gap = function() return 12 * f() end,
                on_click = function() act(g.untracked(n)) end,
                radio(function() return n().connected end, function() return not is_asked() end),
                g.box {
                    grow = 1,
                    text {
                        text = function() return n().ssid end,
                        max_width = function() return inner() - 16 * f() - 12 * f() * 2 - 42 * f() end,
                    },
                },
                g.icon {
                    present = function() return network.is_secured(n()) end,
                    width = function() return 12 * f() end,
                    height = function() return 12 * f() end,
                    icon = "lock",
                    gradient_top = theme.text_muted,
                    gradient_bottom = theme.text_muted,
                },
                strength(function() return network.bars_for(n().strength) end),
            },
            -- The field, under the row it asks for.
            g.capsule {
                overlay = true,
                attach = "corner",
                present = is_asked,
                offset_y = function() return row_height() + 4 * f() end,
                width = inner,
                height = field_height,
                radius = function() return metrics_mod.radius_for(field_height(), m()) end,
                stroke = 1.5,
                rim_top = function() return if failed() then theme.alert() else theme.primary() end,
                rim_bottom = function() return if failed() then theme.alert() else theme.primary() end,
                direction = "row",
                align = "center",
                justify = "between",
                padding_left = function() return 16 * f() end,
                padding_right = function() return 6 * f() end,
                on_click = function() end,
                field_node,
                g.capsule {
                    role = "button",
                    name = "Connect",
                    height = function() return field_height() - 10 * f() end,
                    padding_x = function() return 14 * f() end,
                    align = "center",
                    justify = "center",
                    radius = function() return metrics_mod.radius_for(field_height() - 10 * f(), m()) end,
                    stroke = metrics_mod.rim_width,
                    rim_top = theme.line,
                    rim_bottom = theme.line,
                    on_click = submit,
                    g.text {
                        text = "Connect",
                        color = theme.text,
                        font = typography.technical,
                        size = function() return m().font_secondary end,
                        weight = typography.weight_label,
                    },
                },
            },
            g.text {
                overlay = true,
                attach = "corner",
                present = function() return is_asked() and failed() end,
                offset_x = function() return 16 * f() end,
                offset_y = function() return row_height() + 4 * f() + field_height() + 2 * f() end,
                text = network.last_error,
                color = theme.alert,
                font = typography.expressive,
                size = function() return m().font_meta end,
            },
        }
    end

    local wifi_well = well(wifi_height, {
        at(well_inset, well_padding, family_header {
            title = "WI-FI",
            glyph = "wifi",
            on = network.wifi_enabled,
            settling = function() return not network.wifi_hardware_enabled() end,
            on_switch = network.set_wifi_enabled,
        }),
        empty_note(function() return not network.wifi_enabled() end, function() return "Wi-Fi is off" end),
        list_area(wifi_height, network.visible_networks, function(n: any) return n.ssid end, network_row,
            asked_extra, network.wifi_enabled),
    })

    -- ---- Bluetooth ------------------------------------------------------------------------

    local function device_row(item: () -> any, index: () -> number): any
        local function d(): any return item().device end
        local function found(): boolean return item().found end
        local function connected(): boolean return d().connected end
        local function busy(): boolean return bluetooth.is_busy(d()) end
        local function did_fail(): boolean return found() and bluetooth.failed_address() == d().address end
        local hovered = g.signal(false)
        local function glyph(): string
            local name = string.lower(bluetooth.icon(d()))
            if string.find(name, "headset") or string.find(name, "headphone") or string.find(name, "audio") then
                return "headphones"
            end
            if string.find(name, "mouse") or string.find(name, "pointing") then return "mouse" end
            return "wireless-link"
        end
        local function state(): string
            if found() then return if bluetooth.is_pairing(d()) then "Pairing" elseif did_fail() then "Failed" else "Pair" end
            if busy() then return "Working" end
            return if connected() then "Connected" else "Paired"
        end
        local function activate()
            local device = g.untracked(d)
            if g.untracked(found) then
                bluetooth.pair_and_connect(device)
            elseif device.connected then
                bluetooth.disconnect_device(device)
            else
                bluetooth.connect_device(device)
            end
        end
        return g.box {
            role = "button",
            name = "Device",
            overlay = true,
            attach = "corner",
            offset_x = well_inset,
            offset_y = function() return (index() - 1) * row_height() end,
            width = inner,
            height = row_height,
            direction = "row",
            align = "center",
            gap = function() return 12 * f() end,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = activate,
            g.icon {
                width = function() return 18 * f() end,
                height = function() return 18 * f() end,
                icon = glyph,
                gradient_top = function() return if connected() then theme.gradient_top(theme.primary()) else theme.text_muted() end,
                gradient_bottom = function() return if connected() then theme.gradient_bottom(theme.primary()) else theme.text_muted() end,
            },
            g.box {
                grow = 1,
                text {
                    text = function() return bluetooth.describe(d()) end,
                    color = function() return if found() then theme.text_muted() else theme.text() end,
                    max_width = function() return inner() - 18 * f() - 12 * f() * 2 - 70 * f() end,
                },
            },
            meta(state),
            -- Forgetting, under the hand only, over the state it replaces.
            g.capsule {
                role = "button",
                name = "Forget",
                overlay = true,
                attach = "corner",
                present = function() return not found() and hovered.value end,
                offset_x = function() return inner() - 18 * f() end,
                offset_y = function() return (row_height() - 18 * f()) / 2 end,
                width = function() return 18 * f() end,
                height = function() return 18 * f() end,
                align = "center",
                justify = "center",
                fill = theme.background,
                rim_top = CLEAR,
                rim_bottom = CLEAR,
                on_click = function() bluetooth.forget(g.untracked(d)) end,
                g.icon {
                    width = function() return 9 * f() end,
                    height = function() return 9 * f() end,
                    icon = "close",
                    gradient_top = theme.text,
                    gradient_bottom = theme.text,
                },
            },
        }
    end

    local device_well = well(device_height, {
        at(well_inset, well_padding, family_header {
            title = "BLUETOOTH",
            glyph = "wireless-link",
            on = bluetooth.enabled,
            settling = bluetooth.settling,
            on_switch = bluetooth.set_enabled,
            searchable = true,
            searching = bluetooth.scanning,
            on_search = function() bluetooth.set_discovering(not g.untracked(bluetooth.discovering)) end,
        }),
        empty_note(function() return not bluetooth.enabled() or #devices() == 0 end, function()
            if not bluetooth.available() then return "No adapter" end
            if not bluetooth.enabled() then return "Bluetooth is off" end
            if bluetooth.scanning() then return "Looking…" end
            return "Nothing paired"
        end),
        list_area(device_height, devices, function(e: any) return (if e.found then "f:" else "p:") .. e.device.address end,
            device_row, nil, bluetooth.enabled),
    })

    local function content(): any
        return g.box {
            direction = "column",
            gap = well_spacing,
            g.box { present = wired_shown, wired_well },
            wifi_well,
            device_well,
        }
    end

    return {
        panel = {
            width = function() return 340 * f() end,
            height = panel_height,
            content = content,
        },
        -- The keys, while a password is asked for.
        on_key = function(name: string, typed: string?, mods: { [string]: boolean }): boolean
            if not g.untracked(asking) then return false end
            return field_handle.key(name, typed, mods)
        end,
    }
end

return M
