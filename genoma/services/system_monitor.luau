--!strict
-- The machine's vital signs (services/SystemMonitor.qml): load, memory,
-- clock, GPU, temperature, network traffic, battery and processes.
--
-- One cadence for everything, so that two figures read together were read
-- at the same moment. The steady state is one timer and a handful of file
-- reads: /proc and sysfs are read directly, and nothing is spawned on the
-- sampling path. Two probes run once at the start (which card, which
-- sensor) and `ps` only while a process list is being looked at.
--
-- Performance mode's longer interval comes with the performance service.
local g = require("@genoma")
local config = require("core/config")
local power = require("@genoma/power")

local M = {}

local function trim(s: string): string return (string.gsub(s, "^%s+", ""):gsub("%s+$", "")) end

local function file(path: string): any return g.file { path = path, watch = false } end

-- ---- CPU load ---------------------------------------------------------------

local cpu_percent = g.signal(0)
-- The previous cumulative counters: load is a delta, so the first sample
-- reports zero rather than a fabricated figure.
local previous_cpu: { idle: number, total: number }? = nil
local stat_file = file("/proc/stat")

local function read_load(text: string)
    -- Only the aggregate line is wanted, and it is the first.
    local line = string.match(text, "^[^\n]*") or ""
    local numbers = {}
    local first = true
    for word in string.gmatch(line, "%S+") do
        if first then
            if word ~= "cpu" then return end
            first = false
        else
            table.insert(numbers, tonumber(word) or 0)
        end
    end
    if #numbers < 4 then return end
    local idle = numbers[4] + (numbers[5] or 0) -- idle + iowait
    local total = 0
    for _, n in numbers do total += n end
    if previous_cpu then
        local idle_delta = idle - previous_cpu.idle
        local total_delta = total - previous_cpu.total
        if total_delta > 0 then
            cpu_percent.value = math.clamp((1 - idle_delta / total_delta) * 100, 0, 100)
        end
    end
    previous_cpu = { idle = idle, total = total }
end

-- ---- CPU clock ----------------------------------------------------------------
--
-- What the cardiac beat rate is made of: averaged across cores, then over a
-- window of samples, since a real clock swings hundreds of megahertz between
-- two samples and a beat following it raw is arrhythmic.

local cpu_clock_raw = g.signal(0) -- MHz, this sample
local cpu_clock = g.signal(0) -- MHz, averaged over the window
local cores = g.signal(0)
local clock_samples: { number } = {}
local cpuinfo_file = file("/proc/cpuinfo")

local function read_clock(text: string)
    local sum, count = 0, 0
    for mhz in string.gmatch(text, "cpu MHz%s*:%s*([%d%.]+)") do
        sum += tonumber(mhz) or 0
        count += 1
    end
    if count == 0 then return end
    cores.value = count
    cpu_clock_raw.value = sum / count
    table.insert(clock_samples, sum / count)
    local window = math.max(1, config.get("vitals.clock_average", 5))
    while #clock_samples > window do table.remove(clock_samples, 1) end
    local total = 0
    for _, v in clock_samples do total += v end
    cpu_clock.value = total / #clock_samples
end

-- The clock's own range, read once: a fraction is what the beat mapping
-- wants, and a machine without cpufreq has no range and says so.
local function khz(path: string): number
    local f = file(path)
    return (tonumber(trim(f.text or "")) or 0) / 1000
end
local cpu_clock_min = khz("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq")
local cpu_clock_max = khz("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")

-- ---- Memory ---------------------------------------------------------------------

local ram_total = g.signal(0) -- MiB
local ram_used = g.signal(0)
local swap_total = g.signal(0)
local swap_used = g.signal(0)
local meminfo_file = file("/proc/meminfo")

local function read_memory(text: string)
    local function field(name: string): number
        local kb = string.match(text, "\n" .. name .. ":%s+(%d+)") or string.match(text, "^" .. name .. ":%s+(%d+)")
        return (tonumber(kb) or 0) / 1024 -- kB → MiB
    end
    local total = field("MemTotal")
    if total <= 0 then return end
    -- Used is total minus *available*: free excludes the page cache, and a
    -- figure built on it reports a healthy machine as 95% full.
    ram_total.value = total
    ram_used.value = math.max(0, total - field("MemAvailable"))
    local swap = field("SwapTotal")
    swap_total.value = swap
    swap_used.value = if swap > 0 then math.max(0, swap - field("SwapFree")) else 0
end

-- ---- GPU --------------------------------------------------------------------------
--
-- Every figure a sysfs read on AMD. Utilisation and clock stay separate:
-- a card at 30% can sit at full clock, and the cell says one as colour and
-- the other as rotation.

local gpu_path = g.signal("")
local gpu_name = g.signal("")
local gpu_percent = g.signal(0)
local gpu_clock = g.signal(0) -- MHz
local gpu_clock_min = g.signal(0)
local gpu_clock_max = g.signal(0)
local gpu_asleep = g.signal(false)
local vram_total = g.signal(0) -- MiB
local vram_used = g.signal(0)
local gpu_files: { [string]: any } = {}

-- `pp_dpm_sclk` is a table of power states, the current one marked with an
-- asterisk, and gives the card's own range. A sleeping card answers
-- `S: 68Mhz *`, a state rather than an index: asleep, not broken.
local function read_gpu_clock(text: string)
    local current, lowest, highest, asleep = -1, -1, -1, false
    for line in string.gmatch(text, "[^\n]+") do
        local index, value, mark = string.match(line, "^%s*(%S+):%s*(%d+)%s*[Mm][Hh][Zz]%s*(%*?)")
        if index then
            local v = tonumber(value) :: number
            local numbered = tonumber(index) ~= nil
            if mark == "*" then
                current = v
                asleep = not numbered
            end
            -- Sleep states are not part of the operating range.
            if numbered then
                if lowest < 0 or v < lowest then lowest = v end
                if v > highest then highest = v end
            end
        end
    end
    if lowest >= 0 then
        gpu_clock_min.value = lowest
        gpu_clock_max.value = highest
    end
    if current >= 0 then
        gpu_clock.value = current
        gpu_asleep.value = asleep
    end
end

local function sample_gpu()
    local busy = gpu_files.busy:read()
    if busy then gpu_percent.value = tonumber(trim(busy)) or 0 end
    local clock = gpu_files.clock:read()
    if clock then read_gpu_clock(clock) end
    local vram = gpu_files.vram:read()
    if vram then vram_used.value = (tonumber(trim(vram)) or 0) / (1024 * 1024) end
end

-- ---- CPU temperature ----------------------------------------------------------------
--
-- What the lava organism is heated by: the package sensor (`Tctl` on AMD,
-- `Package id 0` on Intel), else a thermal zone. Which hwmon is which
-- changes between boots, so the name and the label are trusted, never the
-- index; `vitals.temperature_sensor` overrides with part of the path.

local temperature_file: any = nil
local cpu_temperature = g.signal(0) -- °C

local function sample_temperature()
    local text = temperature_file:read()
    local value = tonumber(trim(text or ""))
    if value then cpu_temperature.value = value / 1000 end -- millidegrees
end

-- ---- Network traffic -------------------------------------------------------------------
--
-- What the osmosis organism's drops are made of: bytes a second across the
-- machine's own links. Virtual links carry what a physical one carries too,
-- so they are left out by name, with the loopback.

local virtual_prefixes = { "lo", "veth", "docker", "br-", "virbr", "vnet", "tun", "tap", "wg", "tailscale",
    "zt", "vboxnet", "vmnet", "nm-", "dummy", "bond", "team" }
local function is_virtual(name: string): boolean
    for _, prefix in virtual_prefixes do
        if string.sub(name, 1, #prefix) == prefix then return true end
    end
    return false
end

local net_in = g.signal(0) -- bytes a second
local net_out = g.signal(0)
local net_known = g.signal(false)
local previous_net: { received: number, sent: number, time: number }? = nil
local netdev_file = file("/proc/net/dev")

local function read_network(text: string)
    local received, sent, links = 0, 0, 0
    for line in string.gmatch(text, "[^\n]+") do
        local name, rest = string.match(line, "^%s*([^:%s]+):(.*)$")
        if name and not is_virtual(name) then
            local fields = {}
            for word in string.gmatch(rest, "%S+") do table.insert(fields, tonumber(word) or 0) end
            received += fields[1] or 0
            sent += fields[9] or 0
            links += 1
        end
    end
    net_known.value = links > 0
    local now = g.now()
    local last = previous_net
    -- A counter that went backwards is a link that left, taking its bytes
    -- with it: that sample says nothing about traffic.
    if last and now > last.time and received >= last.received and sent >= last.sent then
        local seconds = now - last.time
        net_in.value = (received - last.received) / seconds
        net_out.value = (sent - last.sent) / seconds
    end
    previous_net = { received = received, sent = sent, time = now }
end

-- ---- Sampling ---------------------------------------------------------------------------

-- In one batch: a binding reading several figures runs once per sample.
local function read_all()
    local stat = stat_file:read()
    if stat then read_load(stat) end
    local mem = meminfo_file:read()
    if mem then read_memory(mem) end
    local info = cpuinfo_file:read()
    if info then read_clock(info) end
    if gpu_files.busy then sample_gpu() end
    if temperature_file then sample_temperature() end
    local net = netdev_file:read()
    if net then read_network(net) end
end
local function sample() g.batch(read_all) end

-- A floor: a hand-written 0 would be a timer firing on every frame.
g.effect(function()
    local every = math.max(250, config.get("vitals.interval", 2000)) / 1000
    g.timer { every = every, on_tick = sample }
end)
sample()

-- Picking by index is wrong: card0 here is a 512 MB integrated GPU and card1
-- the 17 GB discrete one. The largest VRAM wins; the configuration overrides.
do
    local found = {}
    g.process {
        command = { "sh", "-c", "for d in /sys/class/drm/card*/device; do "
            .. "[ -e \"$d/gpu_busy_percent\" ] || continue; "
            .. "printf '%s %s\\n' \"$d\" \"$(cat \"$d/mem_info_vram_total\" 2>/dev/null || echo 0)\"; "
            .. "done" },
        on_line = function(line: string)
            local path, vram = string.match(line, "^(%S+)%s+(%d+)")
            if path then table.insert(found, { path = path, vram = tonumber(vram) or 0 }) end
        end,
        on_exit = function()
            if #found == 0 then return end
            local chosen = found[1]
            local configured = config.get("vitals.gpu_card", "")
            if configured ~= "" then
                for _, c in found do
                    if string.find(c.path, configured, 1, true) then chosen = c end
                end
            else
                for _, c in found do
                    if c.vram > chosen.vram then chosen = c end
                end
            end
            vram_total.value = chosen.vram / (1024 * 1024) -- bytes → MiB
            gpu_name.value = string.match(chosen.path, "/(card%d+)/") or ""
            gpu_files.busy = file(chosen.path .. "/gpu_busy_percent")
            gpu_files.clock = file(chosen.path .. "/pp_dpm_sclk")
            gpu_files.vram = file(chosen.path .. "/mem_info_vram_used")
            gpu_path.value = chosen.path
            sample_gpu()
        end,
    }
end

do
    local found = {}
    g.process {
        command = { "sh", "-c", "for h in /sys/class/hwmon/hwmon*; do "
            .. "n=$(cat \"$h/name\" 2>/dev/null); "
            .. "for i in \"$h\"/temp*_input; do [ -e \"$i\" ] || continue; "
            .. "l=$(cat \"${i%_input}_label\" 2>/dev/null); "
            .. "printf 'hwmon\\t%s\\t%s\\t%s\\n' \"$n\" \"$l\" \"$i\"; done; done; "
            .. "for z in /sys/class/thermal/thermal_zone*; do [ -e \"$z/temp\" ] || continue; "
            .. "printf 'zone\\t%s\\t\\t%s\\n' \"$(cat \"$z/type\" 2>/dev/null)\" \"$z/temp\"; done" },
        on_line = function(line: string)
            local kind, name, label, path = string.match(line, "^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
            if kind then table.insert(found, { kind = kind, name = name, label = label, path = path }) end
        end,
        on_exit = function()
            local chosen = nil
            local configured = config.get("vitals.temperature_sensor", "")
            if configured ~= "" then
                for _, s in found do
                    if not chosen and string.find(s.path, configured, 1, true) then chosen = s end
                end
            end
            -- In order of trust: the vendor's package sensor, then the zones.
            local wanted = {
                function(s) return s.name == "k10temp" and s.label == "Tctl" end,
                function(s) return s.name == "zenpower" and s.label == "Tdie" end,
                function(s) return s.name == "k10temp" end,
                function(s) return s.name == "coretemp" and string.sub(s.label, 1, 7) == "Package" end,
                function(s) return s.kind == "zone" and s.name == "x86_pkg_temp" end,
                function(s) return s.kind == "zone" and string.sub(s.name, 1, 3) == "cpu" end,
                function(s) return s.kind == "zone" and s.name == "acpitz" end,
            }
            for _, test in wanted do
                if chosen then break end
                for _, s in found do
                    if test(s) then
                        chosen = s
                        break
                    end
                end
            end
            if not chosen then return end
            temperature_file = file(chosen.path)
            sample_temperature()
        end,
    }
end

-- ---- What the cells read -------------------------------------------------------------------

function M.cpu_percent(): number return cpu_percent.value end
function M.cpu_clock(): number return cpu_clock.value end
function M.cpu_clock_raw(): number return cpu_clock_raw.value end
function M.cores(): number return cores.value end
M.cpu_clock_min = cpu_clock_min
M.cpu_clock_max = cpu_clock_max
function M.cpu_clock_range_known(): boolean return cpu_clock_max > cpu_clock_min end
function M.cpu_clock_fraction(): number
    if cpu_clock_max <= cpu_clock_min then return 0 end
    return math.clamp((cpu_clock.value - cpu_clock_min) / (cpu_clock_max - cpu_clock_min), 0, 1)
end

function M.ram_total(): number return ram_total.value end
function M.ram_used(): number return ram_used.value end
function M.ram_percent(): number
    return if ram_total.value > 0 then ram_used.value / ram_total.value * 100 else 0
end
function M.ram_used_gb(): number return math.round(ram_used.value / 1024 * 10) / 10 end
function M.ram_total_gb(): number return math.round(ram_total.value / 1024 * 10) / 10 end
function M.swap_percent(): number
    return if swap_total.value > 0 then swap_used.value / swap_total.value * 100 else 0
end

function M.gpu_present(): boolean return gpu_path.value ~= "" end
function M.gpu_name(): string return gpu_name.value end
function M.gpu_percent(): number return gpu_percent.value end
function M.gpu_clock(): number return gpu_clock.value end
function M.gpu_asleep(): boolean return gpu_asleep.value end
function M.gpu_clock_fraction(): number
    local low, high = gpu_clock_min.value, gpu_clock_max.value
    if high <= low then return 0 end
    return math.clamp((gpu_clock.value - low) / (high - low), 0, 1)
end
function M.vram_percent(): number
    return if vram_total.value > 0 then vram_used.value / vram_total.value * 100 else 0
end

function M.cpu_temperature(): number return cpu_temperature.value end
function M.cpu_temperature_known(): boolean
    local _ = cpu_temperature.value
    return temperature_file ~= nil
end

function M.net_in(): number return net_in.value end
function M.net_out(): number return net_out.value end
function M.net_known(): boolean return net_known.value end

-- ---- Battery ------------------------------------------------------------------------------
--
-- From UPower's display device, which is a placeholder on a desktop: the
-- laptop test is the presence test.

local function battery(): any return power.battery end

function M.has_battery(): boolean
    local b = battery()
    return b.laptop and b.present
end
-- Genoma gives the level as a fraction already.
function M.battery_level(): number return battery().level end
function M.battery_level_raw(): number return battery().level * 100 end
function M.battery_state(): string return battery().state end
function M.charging(): boolean
    local s = battery().state
    return s == "charging" or s == "pending-charge"
end
function M.full(): boolean return battery().state == "full" end
function M.discharging(): boolean return battery().state == "discharging" end
function M.on_battery(): boolean return power.on_battery end

-- Seconds, in the direction the machine is going.
function M.battery_seconds_left(): number
    local b = battery()
    return if M.charging() then b.time_to_full else b.time_to_empty
end

-- The line under the battery's figure: how long is left, or while charging
-- how long until full. UPower answers 0 while it is still estimating, and
-- then the state is all there is to say.
function M.battery_detail(): string
    local state = battery().state
    local left = M.battery_seconds_left()
    if (state == "discharging" or state == "charging") and left > 0 then
        local minutes = math.round(left / 60)
        local h, m = minutes // 60, minutes % 60
        local time = if h > 0 then string.format("%d H %02d M", h, m) else string.format("%d M", m)
        return if state == "discharging" then time else "FULL " .. time
    end
    return string.upper(state)
end

-- Full with the charger in: the one plugged-in state the drops cannot say.
function M.battery_mains_full(): boolean
    return M.has_battery() and not M.on_battery() and not M.discharging() and M.battery_level() >= 0.995
end
function M.battery_watts(): number return battery().energy_rate end
function M.battery_inflow(): number return if M.charging() then M.battery_watts() else 0 end

-- ---- Processes -------------------------------------------------------------------------------
--
-- The one sample that cannot come from a couple of files, so it is taken
-- only while it is looked at: the expanded cell sets `list_processes` when
-- it opens and clears it when it closes.

local listing = g.signal(false)
local processes = g.signal({})
local refresh_processes: () -> ()

function refresh_processes()
    local found = {}
    g.process {
        -- Sorted by CPU here and re-sorted in the cell: a change of view is
        -- not a reason to run `ps` again.
        command = { "sh", "-c", "ps -eo pid,comm,pcpu,pmem,rss --sort=-%cpu --no-headers 2>/dev/null | head -"
            .. tostring(config.get("vitals.process_count", 60)) },
        on_line = function(line: string)
            local pid, name, cpu, mem, rss = string.match(line, "^%s*(%d+)%s+(%S+)%s+([%d%.]+)%s+([%d%.]+)%s+(%d+)")
            if pid then
                table.insert(found, {
                    pid = tonumber(pid),
                    name = name,
                    cpu = tonumber(cpu),
                    mem_percent = tonumber(mem),
                    mem_mb = math.round((tonumber(rss) :: number) / 1024),
                })
            end
        end,
        -- Applied at once, never appended to a live list: a list that grows
        -- under the hand moves the row it was reaching for.
        on_exit = function() if g.untracked(function() return listing.value end) then processes.value = found end end,
    }
end

g.effect(function()
    if not listing.value then
        processes.value = {}
        return
    end
    local every = math.max(500, config.get("vitals.process_interval", 3000)) / 1000
    g.timer { every = every, on_tick = refresh_processes }
    refresh_processes()
end)

function M.set_list_processes(on: boolean) listing.value = on end
function M.processes(): { any } return processes.value end

-- TERM, not KILL: a shell that kills outright on a click loses whatever the
-- application had not written to disk.
function M.terminate(pid: number)
    g.process {
        command = { "kill", "-TERM", tostring(pid) },
        on_exit = function() if g.untracked(function() return listing.value end) then refresh_processes() end end,
    }
end

return M
