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
-- The VPN well holds its profiles, or the form that adds one; the proxy
-- well its profiles, or, while one is edited, the editor in place of every
-- other well; the printers what CUPS keeps and what a search found.
--
-- Not yet: the keyboard's travel through the rows (Tab goes from field to
-- field).
local g = require("@genoma")
local colour = require("core/colour")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local typography = require("core/typography")
local apps = require("core/apps")
local network = require("services/network")
local bluetooth = require("services/bluetooth")
local vpn = require("services/vpn")
local proxy = require("services/proxy")
local printers = require("services/printers")
local picker = require("services/picker")
local focus = require("structure/focus")
local segmented = require("components/segmented")
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
        if not open and not cell.aside then bluetooth.set_discovering(false) end
    end)

    -- ---- Asking for a password ------------------------------------------------
    --
    -- The row opens into a field rather than a dialog: the network being
    -- joined stays in view above what is being typed.
    -- One field takes the keys at a time, by name: "wifi", the VPN form's
    -- two, the proxy editor's four.
    local typing = g.signal("")
    local asked = g.signal("")
    local secret = g.signal("")
    local function asking(): boolean return asked.value ~= "" end
    local function failed(): boolean return asking() and network.last_error() ~= "" end
    local function stop_asking()
        asked.value = ""
        if g.untracked(function() return typing.value end) == "wifi" then typing.value = "" end
    end
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
        taking = function() return cell.open.value and asking() and typing.value == "wifi" end,
        on_submit = submit,
        on_release = stop_asking,
    }
    local function act(n: any)
        if n.connected then
            network.leave(n)
        elseif network.needs_password(n) then
            field_handle.set("")
            asked.value = n.ssid
            typing.value = "wifi"
        else
            network.join(n)
        end
    end
    -- A network that came up is a question answered.
    g.watch(network.wifi_connected, function(on: boolean) if on then stop_asking() end end)
    g.watch(function() return cell.open.value end, function(open: boolean)
        if not open and not cell.aside then stop_asking() end
    end)
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
    -- ---- Adding a VPN profile, editing a proxy ----------------------------------------
    local adding = g.signal(false)
    local chosen_file = g.signal("")
    local vpn_user = g.signal("")
    local vpn_password = g.signal("")
    local confirming = g.signal("") -- the profile whose removal is asked about
    local editing = g.signal(nil :: any)
    local editing_new = g.signal(false)
    local removing_proxy = g.signal(false)
    local proxy_name = g.signal("")
    local proxy_host = g.signal("")
    local proxy_port = g.signal("")
    local proxy_exceptions = g.signal("")
    local removing_printer = g.signal("")
    g.watch(function() return cell.open.value end, function(open: boolean)
        -- Aside for a dialog, it keeps what it was doing.
        if open or cell.aside then return end
        typing.value = ""
        adding.value = false
        editing.value = nil
        confirming.value = ""
        removing_printer.value = ""
        if picker.busy() then picker.cancel() end
        -- What a printer search found is news for this look, not the next.
        printers.stop_searching()
        printers.clear_found()
    end)

    local function chip_room(): number return 34 * f() end
    local function proxy_row(): number return 44 * f() end
    local function chip_pitch(): number return 32 * f() end
    local function vpn_error(): number return if vpn.error() ~= "" then error_height() else 0 end
    local function form_height(): number return 4 * field_height() + 5 * 8 * f() + vpn_error() end
    local function vpn_height(): number
        if adding.value then return well_padding() * 2 + header_height() + form_height() end
        return well_height(#vpn.profiles(), chip_room() + vpn_error())
    end

    -- What a proxy can be turned on by: each VPN profile, the Wi-Fi in use
    -- (and those already chosen), the cable.
    local function trigger_choices(): { any }
        local out = {}
        for _, p in vpn.profiles() do table.insert(out, { kind = "vpn", uuid = p.uuid, name = p.name }) end
        local ssids = {}
        if network.wifi_connected() and network.ssid() ~= "" then table.insert(ssids, network.ssid()) end
        local e = editing.value
        if e then
            for _, t in e.triggers or {} do
                if t.kind == "wifi" and not table.find(ssids, t.ssid) then table.insert(ssids, t.ssid) end
            end
        end
        for _, ssid in ssids do table.insert(out, { kind = "wifi", ssid = ssid }) end
        table.insert(out, { kind = "wired" })
        return out
    end
    local function proxy_form_height(): number
        local rows = math.ceil(#trigger_choices() / 3)
        return 4 * (field_height() + 8 * f()) + 30 * f() + 20 * f() + rows * chip_pitch() + 24 * f() + 16 * f()
    end
    local function proxy_height(): number
        if editing.value then return well_padding() * 2 + header_height() + proxy_form_height() end
        return well_padding() * 2 + header_height() + math.max(1, #proxy.profiles()) * proxy_row() + chip_room()
    end
    local function printer_rows(): { any }
        local out = {}
        for _, p in printers.printers() do table.insert(out, { printer = p, found = false }) end
        for _, p in printers.found() do table.insert(out, { printer = p, found = true }) end
        return out
    end
    local function printer_height(): number
        return well_height(#printer_rows(), if printers.error() ~= "" then error_height() else 0)
    end

    local function panel_height(): number
        if editing.value then return panel_padding() * 2 + proxy_height() end
        return panel_padding() * 2 + (if wired_shown() then wired_height() + well_spacing() else 0)
            + wifi_height() + well_spacing() + device_height() + well_spacing() + vpn_height()
            + well_spacing() + proxy_height()
            + (if printers.available() then well_spacing() + printer_height() else 0)
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
        if t.switchable ~= false then
            table.insert(right, switch.new { on = t.on, factor = f, on_toggle = t.on_switch, settling = t.settling })
        end
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

    -- ---- Pills and fields --------------------------------------------------------------

    -- A small control in the technical voice: lit when it would act, in the
    -- alert when it removes, dashed when it adds.
    local function pill(t: { [string]: any }): any
        local hovered = g.signal(false)
        local function lit(): boolean return t.lit ~= nil and t.lit() end
        local function alert(): boolean return t.alert ~= nil and t.alert() end
        local function edge(): string
            if alert() then return theme.alert() end
            if lit() then return theme.primary() end
            return if hovered.value then theme.text() else theme.line()
        end
        return g.capsule {
            role = "button",
            name = t.name or "Pill",
            present = t.present,
            height = function() return 24 * f() end,
            padding_x = function() return 12 * f() end,
            align = "center",
            justify = "center",
            radius = function() return metrics_mod.radius_for(24 * f(), m()) end,
            dash = if t.dashed then function() return 4 * f() end else nil,
            dash_gap = if t.dashed then function() return 3 * f() end else nil,
            fill = function()
                if lit() then return colour.alpha(theme.primary(), 0.16) end
                if alert() and hovered.value then return colour.alpha(theme.alert(), 0.16) end
                return CLEAR
            end,
            rim_top = edge,
            rim_bottom = edge,
            on_hover = function(on: boolean) hovered.value = on end,
            on_click = t.on_press,
            g.text {
                text = t.label,
                color = function()
                    if alert() then return theme.alert() end
                    return if lit() then theme.text() else theme.text_muted()
                end,
                font = typography.technical,
                size = function() return m().font_meta end,
                tracking = typography.label_tracking,
            },
        }
    end

    -- A field in a form: an outline that lights while it takes the keys.
    local fields: { [string]: any } = {}
    local order = { "vpn_user", "vpn_password", "proxy_name", "proxy_host", "proxy_port", "proxy_exceptions" }
    local function panel_field(name: string, value: any, t: { [string]: any }): any
        local function on(): boolean return typing.value == name end
        local width = t.width or inner
        local node, handle = field.new {
            text = value,
            secret = t.secret,
            width = function() return width() - 32 * f() end,
            font = typography.expressive,
            size = function() return m().font_secondary end,
            placeholder = t.placeholder,
            taking = function() return cell.open.value and on() end,
            on_submit = t.on_submit,
            on_release = function()
                typing.value = ""
                if t.on_escape then t.on_escape() end
            end,
        }
        fields[name] = { handle = handle, digits = t.digits }
        return g.capsule {
            role = "button",
            name = t.placeholder,
            width = width,
            height = field_height,
            radius = function() return metrics_mod.radius_for(field_height(), m()) end,
            stroke = function() return if on() then 1.5 else metrics_mod.rim_width end,
            rim_top = function() return if on() then theme.primary() else theme.line() end,
            rim_bottom = function() return if on() then theme.primary() else theme.line() end,
            padding_left = function() return 16 * f() end,
            align = "center",
            justify = "start",
            on_click = function() typing.value = name end,
            node,
        }
    end

    -- ---- VPN ------------------------------------------------------------------------------

    local function choose_file()
        if picker.busy() then return end
        -- The chooser is the desktop's window: the cell steps aside for it,
        -- the form kept, and comes back with the file.
        focus.aside(cell, function(done: () -> ())
            picker.choose {
                title = "Choose a VPN profile",
                filters = { { "OpenVPN profiles (*.ovpn *.conf)", { "*.ovpn", "*.conf" } } },
                on_chosen = function(path: string?)
                    if path then chosen_file.value = path end
                    done()
                end,
            }
        end)
    end
    local function import()
        local file = g.untracked(function() return chosen_file.value end)
        if file == "" or g.untracked(vpn.busy) then return end
        vpn.import_profile(file, g.untracked(function() return vpn_user.value end),
            g.untracked(function() return vpn_password.value end))
        fields.vpn_password.handle.set("")
    end
    vpn.on_imported(function() adding.value = false end)
    local function start_adding()
        chosen_file.value = ""
        fields.vpn_user.handle.set("")
        fields.vpn_password.handle.set("")
        adding.value = true
    end
    local function stop_adding()
        adding.value = false
        typing.value = ""
    end

    local function profile_row(item: () -> any, index: () -> number): any
        local function p(): any return item() end
        local function up(): boolean return p().state == "activated" end
        local function moving(): boolean return vpn.working() == p().uuid or (p().state ~= "" and not up()) end
        local function is_asked(): boolean return confirming.value == p().uuid end
        local hovered = g.signal(false)
        return g.box {
            overlay = true,
            attach = "corner",
            offset_y = function() return (index() - 1) * row_height() end,
            width = inner,
            height = row_height,
            direction = "row",
            align = "center",
            gap = function() return 12 * f() end,
            on_hover = function(on: boolean) hovered.value = on end,
            g.icon {
                width = function() return 16 * f() end,
                height = function() return 16 * f() end,
                icon = "lock",
                gradient_top = function() return if up() then theme.gradient_top(theme.primary()) else theme.text_muted() end,
                gradient_bottom = function() return if up() then theme.gradient_bottom(theme.primary()) else theme.text_muted() end,
            },
            g.box {
                grow = 1,
                text {
                    text = function() return if is_asked() then "Remove this profile?" else p().name end,
                    color = function() return if is_asked() then theme.alert() else theme.text() end,
                    max_width = function() return inner() - 16 * f() - 160 * f() end,
                },
            },
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 10 * f() end,
                pill { label = "REMOVE", alert = function() return true end, present = is_asked,
                    on_press = function() confirming.value = "" vpn.remove(g.untracked(p)) end },
                pill { label = "KEEP", present = is_asked, on_press = function() confirming.value = "" end },
                g.box {
                    present = function() return not is_asked() end,
                    meta(function() return if moving() then "Working" elseif up() then "Connected" else "" end),
                },
                g.box {
                    role = "button",
                    name = "Remove",
                    present = function() return not is_asked() and hovered.value end,
                    width = function() return 16 * f() end,
                    height = function() return 16 * f() end,
                    align = "center",
                    justify = "center",
                    on_click = function() confirming.value = g.untracked(p).uuid end,
                    g.icon {
                        width = function() return 9 * f() end,
                        height = function() return 9 * f() end,
                        icon = "close",
                        gradient_top = theme.text,
                        gradient_bottom = theme.text,
                    },
                },
                g.box {
                    present = function() return not is_asked() end,
                    switch.new { on = up, factor = f, settling = moving,
                        on_toggle = function(on: boolean) vpn.toggle(g.untracked(p), on) end },
                },
            },
        }
    end

    local function error_line(say: () -> string): any
        return g.box {
            present = function() return say() ~= "" end,
            height = error_height,
            align = "center",
            g.text {
                text = say,
                color = theme.alert,
                font = typography.expressive,
                size = function() return m().font_meta end,
                max_width = inner,
            },
        }
    end

    local vpn_well = well(vpn_height, {
        at(well_inset, function() return well_padding() + (header_height() - 14 * f()) / 2 end,
            section_title("VPN", "lock")),
        at(well_inset, function() return well_padding() + header_height() end, g.box {
            present = function() return not adding.value end,
            direction = "column",
            width = inner,
            g.box {
                width = inner,
                height = function() return math.max(1, #vpn.profiles()) * row_height() end,
                g.each {
                    overlay = true,
                    attach = "corner",
                    width = inner,
                    items = vpn.profiles,
                    key = function(p: any) return p.uuid end,
                    row = profile_row,
                },
                g.box {
                    overlay = true,
                    present = function() return #vpn.profiles() == 0 end,
                    text { text = "No profiles", color = theme.text_muted },
                },
            },
            error_line(vpn.error),
            g.box {
                width = inner,
                height = chip_room,
                align = "center",
                pill { label = "+ PROFILE", dashed = true, on_press = start_adding },
            },
        }),
        at(well_inset, function() return well_padding() + header_height() end, g.box {
            present = function() return adding.value end,
            direction = "column",
            align = "start",
            width = inner,
            gap = function() return 8 * f() end,
            g.box {
                width = inner,
                height = field_height,
                direction = "row",
                align = "center",
                gap = function() return 10 * f() end,
                pill { label = "CHOOSE FILE", on_press = choose_file },
                text {
                    text = function()
                        local file = chosen_file.value
                        return if file ~= "" then string.match(file, "[^/]*$") or file else "an .ovpn file"
                    end,
                    color = function() return if chosen_file.value ~= "" then theme.text() else theme.text_faint() end,
                    max_width = function() return inner() - 130 * f() end,
                },
            },
            panel_field("vpn_user", vpn_user, { placeholder = "User name", on_escape = stop_adding }),
            panel_field("vpn_password", vpn_password, { placeholder = "Password", secret = true,
                on_submit = import, on_escape = stop_adding }),
            error_line(vpn.error),
            g.box {
                direction = "row",
                gap = function() return 8 * f() end,
                pill {
                    label = function() return if vpn.busy() then "IMPORTING" else "IMPORT" end,
                    lit = function() return chosen_file.value ~= "" and not vpn.busy() end,
                    on_press = import,
                },
                pill { label = "CANCEL", on_press = stop_adding },
            },
        }),
    })

    -- ---- Proxy ----------------------------------------------------------------------------

    local function same_trigger(a: any, b: any): boolean
        return a.kind == b.kind and (a.kind ~= "vpn" or a.uuid == b.uuid) and (a.kind ~= "wifi" or a.ssid == b.ssid)
    end
    local function has_trigger(t: any): boolean
        local e = editing.value
        if not e then return false end
        for _, mine in e.triggers or {} do
            if same_trigger(mine, t) then return true end
        end
        return false
    end
    local function flip_trigger(t: any)
        local e = table.clone(g.untracked(function() return editing.value end))
        local list, at_index = g.array(), 0
        for _, mine in e.triggers or {} do table.insert(list, mine) end
        for i, mine in list do
            if same_trigger(mine, t) then at_index = i end
        end
        if at_index > 0 then table.remove(list, at_index) else table.insert(list, t) end
        e.triggers = list
        editing.value = e
    end
    local function edit(profile: any?)
        adding.value = false
        removing_proxy.value = false
        editing_new.value = profile == nil
        local e = if profile then table.clone(profile) else {
            id = proxy.new_id(), name = "", type = "http", host = "", port = 8080,
            noProxy = "localhost,127.0.0.1,::1", triggers = g.array(),
        }
        editing.value = e
        fields.proxy_name.handle.set(e.name or "")
        fields.proxy_host.handle.set(e.host or "")
        fields.proxy_port.handle.set(if e.port then tostring(e.port) else "")
        fields.proxy_exceptions.handle.set(e.noProxy or "")
        typing.value = "proxy_name"
    end
    local function stop_editing()
        editing.value = nil
        removing_proxy.value = false
        typing.value = ""
    end
    local function proxy_valid(): boolean
        return (string.match(proxy_host.value, "^%s*(.-)%s*$") or "") ~= "" and (tonumber(proxy_port.value) or 0) > 0
    end
    local function trim(s: string): string return string.match(s, "^%s*(.-)%s*$") or "" end
    local function save_proxy()
        if not g.untracked(proxy_valid) then return end
        local p = table.clone(g.untracked(function() return editing.value end))
        local name, host = trim(g.untracked(function() return proxy_name.value end)), trim(g.untracked(function() return proxy_host.value end))
        p.name = if name ~= "" then name else host
        p.host = host
        p.port = math.floor(tonumber(g.untracked(function() return proxy_port.value end)) or 0)
        p.noProxy = trim(g.untracked(function() return proxy_exceptions.value end))
        proxy.save(p)
        stop_editing()
    end
    -- A company's own network assistant, when it is installed, runs with the
    -- proxy in force.
    local function company_wizard(): any
        for _, e in apps.entries() do
            if e.id == "it.akusen.BusinessNetworkWizard" then return e end
        end
        return nil
    end

    local function proxy_row_node(item: () -> any, index: () -> number): any
        local function p(): any return item() end
        local function active(): boolean local c = proxy.current() return c ~= nil and c.id == p().id end
        local function detail(): string
            local x = p()
            local kind = if x.type == "socks5" then "SOCKS5" else "HTTP"
            local names = {}
            for _, t in x.triggers or {} do table.insert(names, proxy.describe(t)) end
            local triggers = table.concat(names, ", ")
            return kind .. " · " .. tostring(x.host) .. ":" .. tostring(x.port) .. (if triggers ~= "" then " · " .. triggers else "")
        end
        return g.box {
            overlay = true,
            attach = "corner",
            offset_y = function() return (index() - 1) * proxy_row() end,
            width = inner,
            height = proxy_row,
            direction = "row",
            align = "center",
            gap = function() return 10 * f() end,
            g.box {
                role = "button",
                name = "Edit proxy",
                grow = 1,
                direction = "column",
                align = "start",
                on_click = function() edit(g.untracked(p)) end,
                text { text = function() return p().name end, max_width = function() return inner() - 60 * f() end },
                g.text {
                    text = detail,
                    color = theme.text_faint,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    max_width = function() return inner() - 60 * f() end,
                },
            },
            switch.new { on = active, factor = f,
                on_toggle = function(on: boolean) proxy.set_mode(if on then g.untracked(p).id else "off") end },
        }
    end

    local function trigger_label(t: any): string
        if t.kind == "wired" then return "WIRED" end
        if t.kind == "wifi" then return t.ssid end
        return t.name
    end

    local proxy_well = well(proxy_height, {
        at(well_inset, function() return well_padding() + (header_height() - 14 * f()) / 2 end,
            section_title("PROXY", "shield")),
        at(function() return inner() + well_inset() - g.text_width { text = "AUTO", font = typography.technical(),
                size = m().font_meta, tracking = typography.label_tracking } - 24 * f() end,
            function() return well_padding() + (header_height() - 24 * f()) / 2 end,
            pill { label = "AUTO", present = function() return editing.value == nil and #proxy.profiles() > 0 end,
                lit = function() return proxy.mode() == "auto" end,
                on_press = function() proxy.set_mode("auto") end }),
        at(well_inset, function() return well_padding() + header_height() end, g.box {
            present = function() return editing.value == nil end,
            direction = "column",
            width = inner,
            g.box {
                width = inner,
                height = function() return math.max(1, #proxy.profiles()) * proxy_row() end,
                g.each {
                    overlay = true,
                    attach = "corner",
                    width = inner,
                    items = proxy.profiles,
                    key = function(p: any) return p.id end,
                    row = proxy_row_node,
                },
                g.box {
                    overlay = true,
                    present = function() return #proxy.profiles() == 0 end,
                    text { text = "No proxies", color = theme.text_muted },
                },
            },
            g.box {
                width = inner,
                height = chip_room,
                direction = "row",
                align = "center",
                justify = "between",
                pill { label = "+ PROXY", dashed = true, on_press = function() edit(nil) end },
                pill { label = "COMPANY NETWORK", present = function() return company_wizard() ~= nil end,
                    on_press = function()
                        apps.run(g.untracked(company_wizard), g.untracked(proxy.environment))
                        cell.open.value = false
                    end },
            },
        }),
        at(well_inset, function() return well_padding() + header_height() end, g.box {
            present = function() return editing.value ~= nil end,
            direction = "column",
            align = "start",
            width = inner,
            gap = function() return 8 * f() end,
            panel_field("proxy_name", proxy_name, { placeholder = "Name", on_escape = stop_editing }),
            segmented.new {
                metrics = m,
                font_size = function() return m().font_meta end,
                button_height = function() return 24 * f() end,
                options = function() return { { key = "http", label = "HTTP" }, { key = "socks5", label = "SOCKS5" } } end,
                current = function() local e = editing.value return if e then e.type else "http" end,
                on_choose = function(key: string)
                    local e = table.clone(g.untracked(function() return editing.value end))
                    e.type = key
                    editing.value = e
                end,
            },
            g.box {
                direction = "row",
                gap = function() return 8 * f() end,
                panel_field("proxy_host", proxy_host, { placeholder = "Host", on_escape = stop_editing,
                    width = function() return inner() - 86 * f() - 8 * f() end }),
                panel_field("proxy_port", proxy_port, { placeholder = "Port", digits = true, on_escape = stop_editing,
                    width = function() return 86 * f() end }),
            },
            panel_field("proxy_exceptions", proxy_exceptions, { placeholder = "Not for: localhost, *.lan",
                on_escape = stop_editing, on_submit = save_proxy }),
            g.box {
                height = function() return 20 * f() end,
                align = "end",
                g.text {
                    text = "ON BY ITSELF WITH",
                    color = theme.text_faint,
                    font = typography.technical,
                    size = function() return m().font_meta end,
                    tracking = typography.label_tracking,
                },
            },
            g.each {
                direction = "row",
                width = inner,
                gap = function() return 8 * f() end,
                items = trigger_choices,
                key = function(t: any) return t.kind .. ":" .. (t.uuid or t.ssid or "") end,
                row = function(t: () -> any)
                    return pill { label = function() return trigger_label(t()) end,
                        lit = function() return has_trigger(t()) end,
                        on_press = function() flip_trigger(g.untracked(t)) end }
                end,
            },
            g.box {
                direction = "row",
                gap = function() return 8 * f() end,
                pill { label = "SAVE", lit = proxy_valid, on_press = save_proxy },
                pill { label = "CANCEL", on_press = stop_editing },
                pill {
                    label = function() return if removing_proxy.value then "REMOVE?" else "REMOVE" end,
                    present = function() return not editing_new.value end,
                    alert = function() return removing_proxy.value end,
                    on_press = function()
                        if not g.untracked(function() return removing_proxy.value end) then
                            removing_proxy.value = true
                            return
                        end
                        proxy.remove(g.untracked(function() return editing.value end).id)
                        stop_editing()
                    end,
                },
            },
        }),
    })

    -- ---- Printers -------------------------------------------------------------------------

    local function printer_row(item: () -> any, index: () -> number): any
        local function p(): any return item().printer end
        local function found(): boolean return item().found end
        local function is_asked(): boolean return not found() and removing_printer.value == p().queue end
        local function busy(): boolean
            local w = printers.working()
            return w ~= "" and w == (if found() then p().uri else p().queue)
        end
        local hovered = g.signal(false)
        local function state(): string
            if busy() then return "Working" end
            if found() then return "Add" end
            local s = p().state
            if s == "printing" then return "Printing" end
            if s == "stopped" then return "Paused" end
            return if (p().jobs or 0) > 0 then "Queued" else ""
        end
        return g.box {
            role = "button",
            name = "Printer",
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
            on_click = function()
                if g.untracked(is_asked) then return end
                if g.untracked(found) then printers.add(g.untracked(p)) else printers.make_default(g.untracked(p)) end
            end,
            radio(function() return p().is_default == true end, function() return not found() and not is_asked() end),
            g.box {
                grow = 1,
                text {
                    text = function() return if is_asked() then "Remove this printer?" else p().name end,
                    color = function()
                        if is_asked() then return theme.alert() end
                        return if found() then theme.text_muted() else theme.text()
                    end,
                    max_width = function() return inner() - 16 * f() - 150 * f() end,
                },
            },
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 10 * f() end,
                pill { label = "REMOVE", alert = function() return true end, present = is_asked,
                    on_press = function() removing_printer.value = "" printers.remove(g.untracked(p)) end },
                pill { label = "KEEP", present = is_asked, on_press = function() removing_printer.value = "" end },
                g.box {
                    present = function() return not is_asked() and not (hovered.value and not found()) end,
                    meta(state),
                },
                g.box {
                    role = "button",
                    name = "Remove",
                    present = function() return not is_asked() and not found() and hovered.value end,
                    width = function() return 18 * f() end,
                    height = function() return 18 * f() end,
                    align = "center",
                    justify = "center",
                    on_click = function() removing_printer.value = g.untracked(p).queue end,
                    g.icon {
                        width = function() return 9 * f() end,
                        height = function() return 9 * f() end,
                        icon = "close",
                        gradient_top = theme.text,
                        gradient_bottom = theme.text,
                    },
                },
            },
        }
    end

    local printer_well = well(printer_height, {
        at(well_inset, well_padding, family_header {
            title = "PRINTERS",
            glyph = "printer",
            on = function() return true end,
            switchable = false,
            searchable = true,
            searching = printers.searching,
            on_search = function()
                if g.untracked(printers.searching) then printers.stop_searching() else printers.search() end
            end,
        }),
        empty_note(function() return #printer_rows() == 0 end,
            function() return if printers.searching() then "Looking…" else "No printers" end),
        list_area(function() return printer_height() - (if printers.error() ~= "" then error_height() else 0) end,
            printer_rows, function(r: any) return (if r.found then "f:" .. r.printer.uri else "q:" .. r.printer.queue) end,
            printer_row),
        at(well_inset, function() return printer_height() - well_padding() - error_height() end,
            error_line(printers.error)),
    })

    local function content(): any
        return g.box {
            direction = "column",
            gap = well_spacing,
            g.box { present = function() return wired_shown() and editing.value == nil end, wired_well },
            g.box { present = function() return editing.value == nil end, wifi_well },
            g.box { present = function() return editing.value == nil end, device_well },
            g.box { present = function() return editing.value == nil end, vpn_well },
            proxy_well,
            g.box { present = function() return printers.available() and editing.value == nil end, printer_well },
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
            local now = g.untracked(function() return typing.value end)
            if now == "" then return false end
            if now == "wifi" then return field_handle.key(name, typed, mods) end
            local here = fields[now]
            if not here then return false end
            -- Tab to the next field of the same form, Shift+Tab back.
            if name == "Tab" or name == "ISO_Left_Tab" then
                local i = table.find(order, now) or 1
                local step = if mods.shift or name == "ISO_Left_Tab" then -1 else 1
                local nxt = order[i + step]
                if nxt and string.sub(nxt, 1, 4) == string.sub(now, 1, 4) then typing.value = nxt end
                return true
            end
            -- A port is figures.
            if here.digits and typed and typed ~= "" and not mods.ctrl and not string.match(typed, "^%d+$") then
                return true
            end
            return here.handle.key(name, typed, mods)
        end,
    }
end

return M
