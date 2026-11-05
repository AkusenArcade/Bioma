--!strict
-- The machine, read in full and never closed (organisms/vitals/
-- VitalsOrganism.qml at 2cafc17). See docs/design/ORGANISMS.md §03.
--
-- The vitals cell's indicators gathered in one panel: the same rings, the
-- same rhythms, the same state colours. What it adds is the figures beside
-- them in their state's colour, because a surface put on the desktop to be
-- read may say what it measures. In a row, or a 2 × 2 square.
local g = require("@genoma")
local theme = require("core/theme")
local typography = require("core/typography")
local system = require("services/system_monitor")
local vital = require("components/vital")

local KINDS = { { key = "cpu", label = "CPU" }, { key = "ram", label = "RAM" }, { key = "gpu", label = "GPU" }, { key = "battery", label = "BAT" } }

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function square(): boolean return o.entry().layout == "square" end
        local function domains(): { any }
            local out = {}
            for _, k in KINDS do
                if (k.key ~= "gpu" or system.gpu_present()) and (k.key ~= "battery" or system.has_battery()) then
                    table.insert(out, k)
                end
            end
            return out
        end
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
        local function reading_of(key: string): string
            if key == "battery" then return string.format("%d%%", math.round(system.battery_level() * 100)) end
            return string.format("%d%%", math.round(load_of(key) * 100))
        end
        local function detail_of(key: string): string
            if key == "cpu" then
                return if system.cpu_clock() > 0 then string.format("%.1f GHz", system.cpu_clock() / 1000) else ""
            elseif key == "ram" then
                return tostring(system.ram_used_gb()) .. " / " .. tostring(system.ram_total_gb()) .. " GB"
            elseif key == "gpu" then
                return if system.gpu_clock() > 0 then string.format("%.1f GHz", system.gpu_clock() / 1000) else ""
            end
            return system.battery_detail()
        end
        local function gap(): number return 16 * f() end
        local function columns(): number return if square() then 2 else #domains() end
        local function column(): number return (o.width() - gap() * (columns() - 1)) / columns() end

        local function pod(item: () -> any): any
            local function key(): string return item().key end
            return g.box {
                width = column,
                height = function() return 136 * f() end,
                direction = "column",
                align = "center",
                g.box {
                    width = function() return 62 * f() end,
                    height = function() return 62 * f() end,
                    vital.new {
                        kind = g.untracked(key),
                        size = function() return 62 * f() end,
                        load = function() return load_of(key()) end,
                        rate = function() return rate_of(key()) end,
                        level = function() return level_of(key()) end,
                        inflow = system.battery_inflow,
                        outflow = system.battery_outflow,
                        mains_full = system.battery_mains_full,
                    },
                },
                g.box { height = function() return 10 * f() end },
                g.text {
                    text = function() return item().label end,
                    color = theme.text,
                    font = typography.technical,
                    size = function() return m().font_label end,
                    weight = typography.weight_label,
                    tracking = typography.label_tracking,
                },
                g.box { height = function() return 2 * f() end },
                g.text {
                    text = function() return reading_of(key()) end,
                    color = function() return theme.gradient_top(theme.state_for(load_of(key()))) end,
                    color_bottom = function() return theme.gradient_bottom(theme.state_for(load_of(key()))) end,
                    font = typography.technical,
                    size = function() return m().font_value end,
                    weight = typography.weight_value,
                    tabular = true,
                },
                g.box { height = function() return 2 * f() end },
                g.text {
                    text = function() return detail_of(key()) end,
                    color = theme.text_muted,
                    font = typography.technical,
                    size = function() return m().font_secondary end,
                    weight = typography.weight_secondary,
                    tabular = true,
                },
            }
        end

        return {
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    align = "center",
                    justify = "center",
                    g.each {
                        direction = "column",
                        gap = gap,
                        items = function()
                            local list, out = domains(), {}
                            local per = columns()
                            for i = 1, #list, per do
                                local row = {}
                                for j = i, math.min(#list, i + per - 1) do table.insert(row, list[j]) end
                                table.insert(out, { key = tostring(i), row = row })
                            end
                            return out
                        end,
                        key = function(r: any) return r.key end,
                        row = function(r: () -> any)
                            return g.each {
                                direction = "row",
                                gap = gap,
                                items = function() return r().row end,
                                key = function(k: any) return k.key end,
                                row = pod,
                            }
                        end,
                    },
                }
            end,
        }
    end,
}
