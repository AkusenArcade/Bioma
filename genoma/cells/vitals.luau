--!strict
-- The machine's vital signs (cells/vitals/Vitals.qml at 30c6cc7). See
-- docs/design/CELLS.md §02.
--
-- At rest only shapes that move: no digits, ever. The composition follows
-- the hardware rather than the configuration: three indicators on a
-- desktop, four where there is a battery. Conditional, it watches the worst
-- of the vitals: the cell appears because one of them is critical.
--
-- Pressed, it opens its expansion (cells/vitals_expansion.luau): the pods
-- and the machine's processes.
local g = require("@genoma")
local system = require("services/system_monitor")
local vital = require("components/vital")
local expansion = require("cells/vitals_expansion")

return {
    new = function(cell: any)
        local function f(): number return cell.metrics().factor end
        local function indicator(): number return 26 * f() end
        local function pitch(): number return 10 * f() end

        local function shows_gpu(): boolean return cell.option("gpu", true) and system.gpu_present() end
        local function shows_battery(): boolean return system.has_battery() end
        local function count(): number
            return 2 + (if shows_gpu() then 1 else 0) + (if shows_battery() then 1 else 0)
        end

        local function cpu(): number return system.cpu_percent() / 100 end
        local function ram(): number return system.ram_percent() / 100 end
        local function gpu(): number return system.gpu_percent() / 100 end
        local function battery(): number return system.battery_level() end

        local opened = expansion.new(cell)
        return {
            panel = opened.panel,
            on_key = opened.on_key,
            padding_leading = 14,
            padding_trailing = 14,
            -- The battery's load is how empty it is.
            condition = function()
                return math.max(cpu(), ram(), if shows_gpu() then gpu() else 0, if shows_battery() then 1 - battery() else 0)
            end,
            content_width = function() return count() * indicator() + (count() - 1) * pitch() end,
            -- Open, the capsule names itself rather than the machine's parts.
            header_title = "MACHINE VITALS & TASKS",
            header_mark_size = function() return 22 * f() end,
            header_mark = function(size: () -> number)
                return vital.new { kind = "cpu", size = size, load = cpu, rate = system.cpu_clock_fraction }
            end,
            contracted = function()
                return g.box {
                    direction = "row",
                    align = "center",
                    gap = pitch,
                    -- The processor: the beat is its clock, the colour its load.
                    vital.new { kind = "cpu", size = indicator, load = cpu, rate = system.cpu_clock_fraction },
                    -- The memory: the level is what is in use.
                    vital.new { kind = "ram", size = indicator, load = ram, level = ram },
                    -- The graphics card: utilisation and clock, apart.
                    vital.new { kind = "gpu", size = indicator, load = gpu, rate = system.gpu_clock_fraction,
                        present = shows_gpu },
                    -- The battery, where there is one.
                    vital.new { kind = "battery", size = indicator, load = function() return 1 - battery() end,
                        level = battery, present = shows_battery },
                }
            end,
        }
    end,
}
