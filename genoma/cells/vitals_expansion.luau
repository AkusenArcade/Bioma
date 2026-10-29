--!strict
-- The vitals, opened (cells/vitals/VitalsExpansion.qml at 30c6cc7): a pod
-- for each domain, and the machine's processes beside them. See
-- docs/design/CELLS.md §02.
--
-- The list's panel buds out of the cell, and the pods bud out of the
-- panel's edge, a stagger apart, where Quickshell hangs them on threads
-- (Akusen, 2026-10-28: cells open by budding). Three domains are a column
-- of horizontal pods whose bottoms align with the panel; with a fourth, the
-- battery, a two-by-two matrix of vertical capsules. The indicators in them
-- are the contracted cell's, larger: the cell presents the same vocabulary
-- with room. Pressing one sorts the list by that domain; the sort never
-- changes by itself.
--
-- The keys: typing goes to the filter; Up and Down mark a process, Enter
-- or Delete asks to close it; Escape answers a question with Cancel, and
-- otherwise closes the cell. Not yet: the shell-wide keyboard travel
-- (which reaches the pods too), the matrix's outer pods budding out of the
-- inner ones (they bud out of the panel; the matrix waits for a laptop to
-- be checked on), the list's scroll bar.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")
local typography = require("core/typography")
local metrics_mod = require("core/metrics")
local apps = require("core/apps")
local system = require("services/system_monitor")
local vital = require("components/vital")
local field = require("components/field")
local choice = require("components/choice")
local thread = require("components/thread")

local M = {}

local KINDS = {
    { key = "cpu", label = "CPU" },
    { key = "ram", label = "RAM" },
    { key = "gpu", label = "GPU" },
    { key = "battery", label = "BATTERY", short = "BAT" },
}

function M.new(cell: any)
    local function m(): { [string]: any } return cell.metrics() end
    local function f(): number return m().factor end
    local function gap(): number return m().gap end

    local function present(key: string): boolean
        if key == "gpu" then return system.gpu_present() end
        if key == "battery" then return system.has_battery() end
        return true
    end
    -- The domains this machine has, in order.
    local function domains(): { string }
        local out = {}
        for _, k in KINDS do
            if present(k.key) then table.insert(out, k.key) end
        end
        return out
    end
    local function index_of(key: string): number
        for i, k in domains() do
            if k == key then return i end
        end
        return 0
    end
    local function matrix(): boolean return #domains() == 4 end
    local function rows(): number return if matrix() then 2 else 3 end
    local function pod_width(): number return (if matrix() then 120 else 236) * f() end
    local function pod_height(): number return (if matrix() then 178 else 108) * f() end
    local function panel_width(): number return 372 * f() end
    local function panel_height(): number return rows() * pod_height() + (rows() - 1) * gap() end

    local function load_of(key: string): number
        if key == "cpu" then return system.cpu_percent() / 100 end
        if key == "ram" then return system.ram_percent() / 100 end
        if key == "gpu" then return system.gpu_percent() / 100 end
        return 1 - system.battery_level()
    end
    local function rate_of(key: string): number
        if key == "cpu" then return system.cpu_clock_fraction() end
        if key == "gpu" then return system.gpu_clock_fraction() end
        return 0
    end
    local function level_of(key: string): number
        if key == "ram" then return system.ram_percent() / 100 end
        if key == "battery" then return system.battery_level() end
        return 0
    end
    -- The figure the domain is measured by, and under it the one that says
    -- why: a clock, a quantity of memory, a time.
    -- What flows along the sorted domain's thread, particles a second: the
    -- list draws its order from that domain, and the flow says how hard it
    -- is working (Akusen, 2026-10-29). At idle it is sparse, and at zero
    -- still: nothing moves without a value. The battery's is the watts
    -- going in, as Vital.qml's drops are.
    local function flow_of(key: string): number
        if key == "battery" then
            local w = system.battery_inflow()
            return if w > 0.5 then math.clamp(w / 20, 0.3, 2.5) else 0
        end
        return load_of(key) * 8
    end

    local function reading_of(key: string): string
        if key == "battery" then return string.format("%d%%", math.round(system.battery_level() * 100)) end
        return string.format("%d%%", math.round(load_of(key) * 100))
    end
    local function detail_of(key: string): string
        if key == "cpu" then
            return if system.cpu_clock() > 0 then string.format("%.1f GHz", system.cpu_clock() / 1000) else ""
        elseif key == "ram" then
            return tostring(system.ram_used_gb()) .. "/" .. tostring(system.ram_total_gb()) .. " GB"
        elseif key == "gpu" then
            return if system.gpu_clock() > 0 then string.format("%.1f GHz", system.gpu_clock() / 1000) else ""
        end
        return system.battery_detail()
    end

    -- "cpu" | "ram" | "gpu" | "battery"
    local sort = g.signal("ram")
    local pending = g.signal(-1) -- the pid a close is being asked about
    local marked = g.signal(0) -- the row a key moved to
    local filter = g.signal("")
    local scroll = g.signal(0)

    local filter_field: any = nil -- the filter's handle, made with the list below

    -- The process list is the one sample that costs something: taken only
    -- while it is looked at, and everything let go when the cell closes.
    -- What it shows stays until the shape that holds it is gone: the content
    -- fades with it rather than emptying under it.
    local letting_go: any = nil
    g.watch(function() return cell.open.value end, function(open: boolean)
        if letting_go then letting_go:stop() end
        letting_go = nil
        if open then
            system.set_list_processes(true)
            return
        end
        letting_go = g.after(require("core/timing").retracted(), function()
            letting_go = nil
            system.set_list_processes(false)
            -- Closed, it starts again empty, as Quickshell's, whose expansion
            -- is unloaded.
            g.batch(function()
                pending.value = -1
                marked.value = 0
                scroll.value = 0
                if filter_field then filter_field.set("") end
            end)
        end)
    end)

    -- Sorted here rather than by running `ps` again: a change of order is a
    -- change of view.
    local sorted = g.computed(function(): { any }
        local term = string.lower(filter.value)
        local list = {}
        for _, p in system.processes() do
            if term == "" or string.find(string.lower(p.name), term, 1, true) then table.insert(list, p) end
        end
        local by = sort.value
        table.sort(list, function(a, b)
            if by == "cpu" then return a.cpu > b.cpu end
            return a.mem_mb > b.mem_mb
        end)
        return list
    end)
    local function pending_process(): any
        for _, p in system.processes() do
            if p.pid == pending.value then return p end
        end
        return nil
    end

    -- ---- The pods -------------------------------------------------------------------

    local function label_font(size: number): { [string]: any }
        return { font = typography.technical(), size = size, weight = typography.weight_label, tracking = typography.label_tracking }
    end

    local function sort_dot(key: string): any
        return g.capsule {
            present = function() return sort.value == key end,
            width = function() return 6 * f() end,
            height = function() return 6 * f() end,
            fill = theme.primary,
        }
    end

    local function label(kind: any, short: boolean): any
        local function size(): number return if short then m().font_secondary else m().font_label end
        return g.box {
            direction = "row",
            align = "center",
            gap = function() return 7 * f() end,
            g.text {
                text = if short then (kind.short or kind.label) else kind.label,
                font = function() return label_font(size()).font end,
                size = size,
                weight = typography.weight_label,
                tracking = typography.label_tracking,
                color = theme.text,
            },
            sort_dot(kind.key),
        }
    end

    local function figures(key: string, size_detail: () -> number): { any }
        return {
            g.text {
                text = function() return reading_of(key) end,
                font = typography.technical,
                size = function() return m().font_value end,
                weight = typography.weight_value,
                tabular = true,
                color = function() return theme.state_for(load_of(key)) end,
            },
            g.text {
                present = function() return detail_of(key) ~= "" end,
                text = function() return detail_of(key) end,
                font = typography.technical,
                size = size_detail,
                weight = typography.weight_secondary,
                tabular = true,
                color = function() return colour.alpha(theme.state_for(load_of(key)), 0.8) end,
            },
        }
    end

    -- Where a domain's pod goes, and in what order it buds.
    local function order_of(key: string): number
        local i = index_of(key)
        if not matrix() then return i end
        -- The inner column first: the outer pods sit beyond it.
        local column = (i - 1) % 2
        local row = (i - 1) // 2
        return (1 - column) * 2 + row + 1
    end
    local function column_of(key: string): number return if matrix() then (index_of(key) - 1) % 2 else 0 end
    local function row_of(key: string): number
        return if matrix() then (index_of(key) - 1) // 2 else index_of(key) - 1
    end
    -- The pod's centre against the panel's, down the panel's edge.
    local function rise_of(key: string): number
        return row_of(key) * (pod_height() + gap()) + pod_height() / 2 - panel_height() / 2
    end

    local function pod(kind: any): any
        local key = kind.key
        local function order(): number return order_of(key) end
        local function column(): number return column_of(key) end
        local function row(): number return row_of(key) end
        local function curve(): string
            local i = math.clamp(order(), 1, 4)
            return if cell.open.value then "pod_" .. i else "pod_retract_" .. i
        end
        local horizontal = {
            present = function() return not matrix() end,
            direction = "row",
            align = "center",
            gap = function() return 14 * f() end,
            vital.new { kind = key, size = function() return 62 * f() end, load = function() return load_of(key) end,
                rate = function() return rate_of(key) end, level = function() return level_of(key) end },
            g.box {
                direction = "column",
                gap = function() return 2 * f() end,
                label(kind, false),
            },
        }
        for _, node in figures(key, function() return m().font_secondary end) do table.insert(horizontal[2], node) end
        local vertical = {
            present = matrix,
            direction = "column",
            align = "center",
            gap = function() return 3 * f() end,
            vital.new { kind = key, size = function() return 56 * f() end, load = function() return load_of(key) end,
                rate = function() return rate_of(key) end, level = function() return level_of(key) end },
            g.box { height = function() return 10 * f() end },
        }
        for _, node in figures(key, function() return m().font_meta end) do table.insert(vertical, node) end
        table.insert(vertical, g.box { height = function() return 8 * f() end })
        table.insert(vertical, label(kind, true))

        return g.capsule {
            name = kind.label,
            role = "button",
            overlay = true,
            attach = "left",
            present = function() return present(key) end,
            width = pod_width,
            height = pod_height,
            -- Up to the pill ceiling the cap is a border rather than a shape
            -- the content must keep off; a vertical capsule is a pill too.
            radius = function()
                if matrix() then return metrics_mod.shaped(pod_width() / 2) end
                return metrics_mod.radius_for(pod_height(), m())
            end,
            -- Out from the panel's edge, the matrix's outer column a pod
            -- further.
            offset_x = function()
                if not cell.open.value then return 0 end
                return -gap() - (if column() == 0 and matrix() then pod_width() + gap() else 0)
            end,
            offset_y = function()
                local centre = row() * (pod_height() + gap()) + pod_height() / 2
                return centre - panel_height() / 2
            end,
            growth = function() return if cell.open.value then 1 else 0 end,
            bud = function() return if cell.open.value then 0 else m().cell_height end,
            blur = true,
            fill = function() return colour.alpha(theme.cell(), 0.72) end,
            rim_top = theme.rim,
            rim_bottom = theme.line,
            padding = function() return (if matrix() then 8 else 23) * f() end,
            justify = function() return if matrix() then "center" else "start" end,
            align = "center",
            -- The indicators double as the sort control.
            on_click = function() sort.value = key end,
            transition = { growth = curve, bud = curve, offset_x = curve },
            -- The matrix reads top to bottom: the indicator above its
            -- figures, the name at the foot.
            g.box {
                opacity = function() return if cell.open.value then 1 else 0 end,
                transition = {
                    opacity = function()
                        return if cell.open.value then "pod_content_" .. math.clamp(order(), 1, 4) else "content_leave"
                    end,
                },
                g.box(horizontal) :: any,
                g.box(vertical) :: any,
            },
        }
    end

    -- The thread from the shape a pod hangs off (the panel, or in the
    -- matrix's outer column the inner pod), and the flow along it. Both
    -- belong to that shape: they are drawn out of it, in the place they
    -- keep, while the pod buds out to meet them.
    local function link(kind: any): { any }
        local key = kind.key
        -- The flow starts once its thread is drawn whole, and stops at once
        -- when the cell closes.
        local linked = g.signal(false)
        local waiting: any = nil
        g.watch(function() return cell.open.value end, function(open: boolean)
            if waiting then waiting:stop() end
            waiting = nil
            if open then
                waiting = g.after(require("core/timing").thread_done(g.untracked(function() return order_of(key) end)),
                    function() linked.value = true end)
            else
                linked.value = false
            end
        end)
        local function beyond(): number
            return if matrix() and column_of(key) == 0 then -(gap() + pod_width()) else 0
        end
        local place = {
            overlay = true,
            attach = "left",
            present = function() return present(key) end,
            offset_x = beyond,
            offset_y = function() return rise_of(key) end,
        }
        local function placed(t: { [any]: any }): { [any]: any }
            for k, v in place do t[k] = v end
            return t
        end
        return {
            thread.new(placed {
                vertical = false,
                length = gap,
                reversed = true,
                shown = function() return cell.open.value end,
                timing = function() return "pod_thread_" .. math.clamp(order_of(key), 1, 4) end,
                closing = function() return "pod_thread_close_" .. math.clamp(order_of(key), 1, 4) end,
            }),
            -- Out of the pod and into the list, while the list is sorted by
            -- this domain.
            g.emitter(placed {
                width = gap,
                height = function() return metrics_mod.node_size * 2 end,
                from_x = 0,
                from_y = metrics_mod.node_size,
                to_x = gap,
                to_y = metrics_mod.node_size,
                bend_x = function() return gap() / 2 end,
                bend_y = metrics_mod.node_size,
                rate = function()
                    if not linked.value or sort.value ~= key then return 0 end
                    return flow_of(key)
                end,
                lifetime = function() return require("core/timing").seconds.flow end,
                spread = 0,
                particle_size = function() return metrics_mod.node_size * 1.2 end,
                -- The primary, as the sort's dot is: the particles say which
                -- thread orders the list, their rate how hard it works
                -- (Akusen, 2026-10-29).
                fill = theme.primary,
            }),
        }
    end

    -- ---- The list ---------------------------------------------------------------------

    local filter_node
    filter_node, filter_field = field.new {
        text = filter,
        width = function() return 180 * f() end,
        font = typography.expressive,
        size = function() return m().font_title end,
        placeholder = "Search tasks",
        taking = function() return cell.open.value and pending.value < 0 end,
    }

    local function process_row(item: () -> any, index: () -> number): any
        local function p(): any return item() end
        return g.capsule {
            role = "button",
            height = function() return m().row_height end,
            width = function() return panel_width() - 32 * f() end,
            radius = function() return metrics_mod.shaped(math.min(m().row_height / 2, 14 * f())) end,
            fill = function() return if marked.value == index() then colour.alpha(theme.primary(), 0.12) else "#00000000" end,
            direction = "row",
            align = "center",
            justify = "between",
            padding_x = function() return 4 * f() end,
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 12 * f() end,
                -- A process is not always an application: where one resolves,
                -- its own icon in the circle, untinted; where none does, the
                -- neutral glyph. Never another application's logo.
                g.capsule {
                    width = function() return 20 * f() end,
                    height = function() return 20 * f() end,
                    rim_top = theme.line,
                    rim_bottom = theme.line,
                    justify = "center",
                    align = "center",
                    g.icon {
                        width = function() return 20 * f() * 0.62 end,
                        height = function() return 20 * f() * 0.62 end,
                        color = theme.text_muted,
                        icon = function()
                            local path = apps.icon_for(p().name)
                            return if path ~= "" then path else "app-fallback"
                        end,
                    },
                },
                g.text {
                    text = function() return p().name end,
                    max_width = function() return 150 * f() end,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    color = theme.text,
                },
            },
            g.box {
                direction = "row",
                align = "center",
                gap = function() return 10 * f() end,
                g.text {
                    text = function()
                        local mb = p().mem_mb
                        local mem = if mb >= 1024 then string.format("%.1f GB", mb / 1024) else mb .. " MB"
                        return mem .. " · " .. math.round(p().cpu) .. "%"
                    end,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    weight = typography.weight_secondary,
                    tabular = true,
                    color = theme.text_muted,
                },
                -- Nothing is terminated on one click: the cross asks.
                g.icon {
                    role = "button",
                    name = "Close",
                    width = function() return 14 * f() end,
                    height = function() return 14 * f() end,
                    icon = "close",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    on_click = function() pending.value = g.untracked(p).pid end,
                },
            },
        }
    end

    local function confirm_height(): number return if pending_process() then 44 * f() + 10 * f() else 0 end
    local function well_height(): number
        return panel_height() - 20 * f() - m().field_height - 10 * f() - confirm_height()
    end
    local function scroll_to(y: number)
        local rows_h = #g.untracked(function() return sorted.value end) * g.untracked(m).row_height
        local most = math.max(0, rows_h - g.untracked(well_height) + 12 * g.untracked(f))
        scroll.value = math.clamp(y, 0, most)
    end
    local function reveal(i: number)
        local h = g.untracked(m).row_height
        local top = g.untracked(function() return scroll.value end)
        local room = g.untracked(well_height) - 12 * g.untracked(f)
        local y = (i - 1) * h
        if y < top then scroll_to(y) elseif y + h > top + room then scroll_to(y + h - room) end
    end

    local function close_pending()
        local pid = g.untracked(function() return pending.value end)
        if pid >= 0 then system.terminate(pid) end
        pending.value = -1
    end

    local function content(): any
        local inner = panel_width() - 20 * f()
        return g.box {
            direction = "column",
            justify = "start",
            gap = function() return 10 * f() end,
            -- The search field is the launcher's: a lens in the primary, no
            -- well of its own, and the sort said in words on the other side.
            g.box {
                width = function() return panel_width() - 20 * f() end,
                height = function() return m().field_height end,
                direction = "row",
                align = "center",
                justify = "between",
                g.box {
                    direction = "row",
                    align = "center",
                    gap = function() return 10 * f() end,
                    g.icon {
                        width = function() return 16 * f() end,
                        height = function() return 16 * f() end,
                        icon = "search",
                        gradient_top = function() return theme.gradient_top(theme.primary()) end,
                        gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                    },
                    filter_node,
                },
                g.text {
                    text = function() return "sorted by " .. string.upper(sort.value) end,
                    font = typography.expressive,
                    size = function() return m().font_secondary end,
                    color = theme.text_muted,
                },
            },
            -- The well clips the scroll, never the panel.
            g.capsule {
                width = function() return panel_width() - 20 * f() end,
                height = well_height,
                radius = function() return metrics_mod.inner_radius(m().radius_panel, 10 * f()) end,
                fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                clip = true,
                direction = "column",
                align = "center",
                justify = "start",
                padding_y = function() return 6 * f() end,
                scroll_y = function() return scroll.value end,
                transition = { scroll_y = "reflow" },
                on_wheel = function(_, dy: number)
                    local discrete = dy == math.floor(dy) and math.abs(dy) <= 3
                    local now = g.untracked(function() return scroll.value end)
                    scroll_to(now + (if discrete then dy * g.untracked(m).row_height else dy))
                end,
                g.each {
                    direction = "column",
                    justify = "start",
                    items = function() return sorted.value end,
                    key = function(p: any) return p.pid end,
                    row = process_row,
                },
            },
            -- The question grows out of the list rather than arriving from
            -- somewhere else, and it names the process it is about.
            g.capsule {
                present = function() return pending_process() ~= nil end,
                width = function() return panel_width() - 20 * f() end,
                height = function() return 44 * f() end,
                radius = function() return metrics_mod.radius_for(44 * f(), m()) end,
                rim_top = theme.alert,
                rim_bottom = theme.alert,
                direction = "row",
                align = "center",
                justify = "between",
                padding_left = function() return 16 * f() end,
                padding_right = function() return 6 * f() end,
                g.text {
                    text = function()
                        local p = pending_process()
                        return if p then "Close " .. p.name .. "?" else ""
                    end,
                    font = typography.expressive,
                    size = function() return m().font_title end,
                    color = theme.text,
                },
                g.box {
                    direction = "row",
                    gap = function() return 8 * f() end,
                    choice.new { label = "Cancel", metrics = m, on_click = function() pending.value = -1 end,
                        marked = function() return pending.value >= 0 end },
                    choice.new { label = "Close", kind = "alert", metrics = m, on_click = close_pending },
                },
            },
        }
    end

    local spec = {}

    spec.panel = {
        width = panel_width,
        height = function() return panel_height() end,
        content = content,
        satellites = function()
            local out = {}
            for _, kind in KINDS do
                table.insert(out, pod(kind))
                for _, node in link(kind) do table.insert(out, node) end
            end
            return out
        end,
    }

    function spec.on_key(name: string, typed: string?, mods: { [string]: boolean }): boolean
        local list = g.untracked(function() return sorted.value end)
        local asking = g.untracked(function() return pending.value end) >= 0
        -- The mark goes to the way back out: Enter on a question is Cancel.
        if asking then
            if name == "Escape" or name == "Return" or name == "KP_Enter" then
                pending.value = -1
                return true
            end
            return false
        end
        if name == "Escape" then return false end
        local at = g.untracked(function() return marked.value end)
        if name == "Down" or name == "Up" then
            if #list == 0 then return true end
            at = if at == 0 then 1 else math.clamp(at + (if name == "Down" then 1 else -1), 1, #list)
            marked.value = at
            reveal(at)
            return true
        end
        if (name == "Return" or name == "KP_Enter" or name == "Delete") and at > 0 and list[at] then
            pending.value = list[at].pid
            return true
        end
        -- Everything else is the filter's: a new term starts from the top.
        local before = g.untracked(function() return filter.value end)
        local taken = filter_field.key(name, typed, mods)
        if g.untracked(function() return filter.value end) ~= before then
            g.batch(function()
                marked.value = 0
                scroll.value = 0
            end)
        end
        return taken
    end

    return spec
end

return M
