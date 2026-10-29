--!strict
-- The monitors, as niri lays them out (services/Monitors.qml), the part read
-- so far: where each output is and what it runs, and which is primary.
-- Switching outputs on and off, moving them, variable refresh and making one
-- primary come with the settings page that writes them.
--
-- Two sources, because neither says everything. niri answers where each
-- output is (`niri msg --json outputs`, asked again whenever its
-- configuration changes, and with every load, which a change of screens
-- brings), and the configuration says what was asked for: the `output`
-- sections, and which one is focused at startup.
local g = require("@genoma")
local niri_config = require("services/niri_config")
local kdl = require("services/niri_kdl")

local M = {}

-- What niri reports, one entry per output that is on; and the ones
-- connected but switched off, which it lists with no geometry.
local live = g.signal({})
local dark = g.signal({})
-- Whether niri has answered, or given up on after a while.
local answered = g.signal(false)

local function sections(): { any }
    local out = {}
    for _, item in niri_config.items() do
        if item.kind == "output" then table.insert(out, item) end
    end
    return out
end

local function named_by(output: any): { any }
    local out = {}
    for _, section in sections() do
        if kdl.names(section, output.name, output.description) then table.insert(out, section) end
    end
    return out
end

local function with_sections(output: any, on: boolean): any
    local named = named_by(output)
    local record = table.clone(output)
    record.on = on
    record.sections = named
    record.primary = false
    for _, section in named do
        if section.primary then record.primary = true end
    end
    -- niri reads the first section that names it.
    record.vrr = if #named > 0 then named[1].vrr else "off"
    return record
end

local outputs = g.computed(function(): { any }
    local out = {}
    for _, o in live.value do table.insert(out, with_sections(o, true)) end
    return out
end)

function M.outputs(): { any } return outputs.value end
function M.count(): number return #outputs.value end

-- The ones switched off, where their section puts them or beside the
-- others: where niri will put them back when they come on.
function M.off(): { any }
    local right = 0
    for _, o in live.value do right = math.max(right, o.x + o.width) end
    local out = {}
    for _, o in dark.value do
        local record = with_sections(o, false)
        local written = nil
        for _, section in record.sections do
            if section.position then
                written = section.position
                break
            end
        end
        record.x = if written then written.x else right
        record.y = if written then written.y else 0
        record.width, record.height, record.scale = o.mode_width, o.mode_height, 1
        if not written then right += o.mode_width end
        table.insert(out, record)
    end
    return out
end

function M.output_of(name: string): any
    for _, o in outputs.value do
        if o.name == name then return o end
    end
    for _, o in M.off() do
        if o.name == name then return o end
    end
    return nil
end

-- The primary monitor, which is what a block on `primary` means: the one
-- `focus-at-startup` marks, else the first screen.
--
-- Read at once, at the load, from the configuration and the outputs the
-- compositor has described, because the surfaces are decided then: a
-- section naming a monitor by its description rather than its connector is
-- matched against what the compositor says of it.
function M.primary(): string
    local screens = g.outputs()
    for _, section in sections() do
        if section.primary then
            for _, screen in screens do
                if kdl.names(section, screen.name, screen.description) then return screen.name end
            end
        end
    end
    return if #screens > 0 then screens[1].name else ""
end

function M.answered(): boolean return answered.value end

-- ---- Asking niri --------------------------------------------------------------

local asking = false
local again = false

local function description_of(o: any): string
    return table.concat({ o.make or "", o.model or "", o.serial or "Unknown" }, " ")
end

local function refresh()
    if asking then
        again = true
        return
    end
    asking = true
    local lines = {}
    g.process {
        command = { "niri", "msg", "--json", "outputs" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function()
            asking = false
            local ok, parsed = pcall(g.parse_json, table.concat(lines, "\n"))
            if ok and type(parsed) == "table" then
                local names = {}
                for name in parsed do table.insert(names, name) end
                table.sort(names)
                local on, off = {}, {}
                for _, name in names do
                    local o = parsed[name]
                    if not o.logical then
                        local mode = nil
                        for _, m in o.modes or {} do
                            if m.is_preferred then mode = m end
                        end
                        mode = mode or (o.modes or {})[1]
                        if mode then
                            table.insert(off, {
                                name = name,
                                description = description_of(o),
                                mode_width = mode.width,
                                mode_height = mode.height,
                                refresh = mode.refresh_rate / 1000,
                                vrr_supported = o.vrr_supported == true,
                            })
                        end
                    else
                        -- niri counts modes from 0.
                        local mode = if o.current_mode ~= nil then (o.modes or {})[o.current_mode + 1] else nil
                        table.insert(on, {
                            name = name,
                            description = description_of(o),
                            x = o.logical.x,
                            y = o.logical.y,
                            width = o.logical.width,
                            height = o.logical.height,
                            scale = o.logical.scale,
                            mode_width = if mode then mode.width else o.logical.width,
                            mode_height = if mode then mode.height else o.logical.height,
                            refresh = if mode then mode.refresh_rate / 1000 else 0,
                            vrr_supported = o.vrr_supported == true,
                        })
                    end
                end
                dark.value = off
                live.value = on
            end
            answered.value = true
            if again then
                again = false
                refresh()
            end
        end,
    }
end

M.refresh = refresh
refresh()

-- Not niri, or niri not answering: the first screen, after a while.
g.after(2, function() answered.value = true end)

-- niri re-reads its configuration on its own, a moment after the file
-- changes; ask once it has.
local settle: any = nil
g.watch(function() return niri_config.items() end, function()
    if settle then settle:stop() end
    settle = g.after(0.4, refresh)
end)

return M
