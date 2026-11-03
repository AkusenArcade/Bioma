--!strict
-- Bioma on Genoma (genoma/PORT.md): the core, and a surface for every
-- membrane block that is Genoma's (core/runtime.luau: marked
-- `"runtime": "genoma"`, or every one once the switch is made), laid out by
-- the structure engine (genoma/structure/).
local g = require("@genoma")
local config = require("core/config")
local theme = require("core/theme")
local timing = require("core/timing")
local metrics = require("core/metrics")
local typography = require("core/typography")

local membrane = require("structure/membrane")
local float = require("structure/float")
local focus = require("structure/focus")
local input_surface = require("structure/input_surface")
local selection = require("structure/selection")
local registry = require("cells/registry")

local monitors = require("services/monitors")
local paths = require("core/paths")
local runtime = require("core/runtime")

-- The shell's own glyphs, by name: assets/icons, the runtime copy.
g.icon_dir(paths.root .. "/assets/icons")

-- Which outputs a block belongs to: a name, `all`, or `primary` (the one
-- niri focuses at startup, else the first screen).
local function outputs_of(block: { [string]: any }): any
    local monitor = block.monitor or "primary"
    if monitor == "all" or monitor == "*" then return "all" end
    if monitor == "primary" then
        local primary = monitors.primary()
        return if primary ~= "" then { primary } else {}
    end
    return { monitor }
end

-- Whether a block belongs on `output`: by name, `all`, or `primary`.
local function on_output(block: { [string]: any }, output: string): boolean
    local where = outputs_of(block)
    if where == "all" then return true end
    return table.find(where, output) ~= nil
end

-- The membranes: a surface for each edge on every output, asleep where no
-- block of Genoma's names that edge of that output, and the block read by
-- the pair (Membrane.qml, the Variants keyed by edge). A block that appears,
-- goes or changes is followed as it happens: a tissue copied to the other
-- monitor did not appear until a reload, and Fixed/Auto-hide did nothing
-- (Akusen, 2026-11-03).
local function membrane_for(output: string, edge: string): { [string]: any }?
    for _, entry in config.get("membranes", {}) do
        if type(entry) == "table" and runtime.ours(entry) and (entry.edge or "top") == edge and on_output(entry, output) then
            return entry
        end
    end
    return nil
end
local surfaces = {}
for _, side in { "top", "bottom", "left", "right" } do
    local edge = side
    local horizontal = edge == "top" or edge == "bottom"
    local anchor = {}
    for _, s in { "top", "bottom", "left", "right" } do
        local opposite = ({ top = "bottom", bottom = "top", left = "right", right = "left" })[edge]
        if s ~= opposite then table.insert(anchor, s) end
    end
    table.insert(surfaces, g.surface {
        full = true,
        anchor = anchor,
        outputs = "all",
        present = function(output: string) return membrane_for(output, edge) ~= nil end,
        -- Only a horizontal edge keeps its strip, and only while Fixed.
        reserve = function(output: string): any
            local entry = membrane_for(output, edge)
            if not entry or not horizontal or entry.reserve_space ~= true or entry.auto_hide == true then return false end
            local strip = metrics.step(entry.scale or "normal")
            return math.floor(strip.margin_edge + strip.cell_height + strip.tissue_padding * 2 + 0.5)
        end,
        -- Keeping no strip, it lies over every zone, as the floats do: its
        -- place is measured from the output's edge, whoever else keeps one.
        above_zones = true,
        -- Bioma's own name for the edge: niri's rule for it turns blur
        -- xray off (config/niri/bioma.kdl).
        namespace = "bioma-membrane-" .. edge,
        -- Its size followed, not built again for: another membrane taking
        -- or letting go of its strip changes this one's area, and rebuilding
        -- closed whatever was open on it.
        fluid = true,
        function(output: string, size: any)
            local s = size or { width = 1920, height = 1080 }
            local current = g.computed(function() return membrane_for(output, edge) end)
            local function block(): { [string]: any } return current.value or { edge = edge } end
            return membrane.new(block, output, s).tree
        end,
    })
end

-- The tissues with no edge, declared in `floating` the same way: all of an
-- output's on one surface, asleep while it has none. Each is kept by its
-- place in that output's list and its anchor, and reads its block by its
-- place (Membrane.qml keeps its tissues so): one that changes keeps its
-- cells, and only what it gained or lost is built or let go.
local function floats_on(output: string): { any }
    local out = {}
    for _, entry in config.get("floating", {}) do
        if type(entry) == "table" and runtime.ours(entry) and on_output(entry, output) then table.insert(out, entry) end
    end
    return out
end
table.insert(surfaces, g.surface {
    full = true,
    anchor = { "top", "bottom", "left", "right" },
    outputs = "all",
    present = function(output: string) return #floats_on(output) > 0 end,
    reserve = false,
    -- The whole output, every zone included: a floating tissue's place is
    -- measured from the screen's edge (float.luau, `margin`), so a strip
    -- another surface keeps must not move its origin.
    above_zones = true,
    namespace = "bioma-float",
    -- Its size followed: a membrane taking or letting go of its strip must
    -- not rebuild the floating tissues under it, and close what is open.
    fluid = true,
    function(output: string, size: any)
        local s = size or { width = 1920, height = 1080 }
        local list = g.computed(function() return floats_on(output) end)
        return g.box {
            width = function() return s.width end,
            height = function() return s.height end,
            g.each {
                overlay = true,
                attach = "corner",
                width = function() return s.width end,
                height = function() return s.height end,
                items = function()
                    local out = {}
                    for i, entry in list.value do table.insert(out, { place = i, anchor = entry.anchor or "centre" }) end
                    return out
                end,
                key = function(item: any) return item.place .. "|" .. item.anchor end,
                row = function(item: () -> any)
                    local place = g.untracked(item).place
                    local first = list.value[place]
                    local function block(): { [string]: any } return list.value[place] or first end
                    return g.box {
                        overlay = true,
                        attach = "corner",
                        width = function() return s.width end,
                        height = function() return s.height end,
                        float.new(block, output, s),
                    }
                end,
            },
        }
    end,
})
-- What Genoma has to hold now: while every surface is Quickshell's, the
-- host, the input catcher and the polkit agent below stay Quickshell's too.
local function holds_blocks(): boolean
    if runtime.alone() then return true end
    for _, key in { "membranes", "floating" } do
        for _, entry in config.get(key, {}) do
            if runtime.ours(entry) then return true end
        end
    end
    return false
end

-- The wallpaper, and its blurred copy behind niri's overview, when
-- `wallpaper.runtime` or the switch gives them to Genoma (Quickshell then
-- leaves its own out). Below everything, one of each per monitor, over every zone.
local wallpaper_surface = require("structure/wallpaper")
local wallpapers = 0
if runtime.part("wallpaper") then
    for _, backdrop in { false, true } do
        local blurred = backdrop
        table.insert(surfaces, g.surface {
            full = true,
            anchor = { "top", "bottom", "left", "right" },
            outputs = "all",
            reserve = false,
            above_zones = true,
            layer = "background",
            -- niri's rules match these: the backdrop is placed behind the
            -- workspaces in the overview (config/niri/bioma.kdl).
            namespace = if blurred then "bioma-backdrop" else "bioma-wallpaper",
            function(output: string, size: any)
                return wallpaper_surface.node(output, size or { width = 1920, height = 1080 }, blurred)
            end,
        })
        wallpapers += 1
    end
end
-- The organisms marked for this runtime, on the Bottom layer: above the
-- wallpaper, under every window (structure/organisms.luau).
local organisms = require("structure/organisms")
-- Always there, empty while no organism is Genoma's: the first one added
-- from the settings appears without a reload.
table.insert(surfaces, g.surface {
    full = true,
    anchor = { "top", "bottom", "left", "right" },
    outputs = "all",
    reserve = false,
    above_zones = true,
    layer = "bottom",
    namespace = "bioma-organisms",
    function(output: string, size: any)
        return organisms.surface(output, size or { width = 1920, height = 1080 })
    end,
})
-- And above the windows while they are placed (structure/arranging.luau).
table.insert(surfaces, g.surface {
    full = true,
    anchor = { "top", "bottom", "left", "right" },
    outputs = "all",
    reserve = false,
    above_zones = true,
    layer = "top",
    namespace = "bioma-organisms",
    function(output: string, size: any)
        return organisms.arrange_surface(output, size or { width = 1920, height = 1080 })
    end,
})
local organism_surfaces = 2
g.ipc("organisms", {
    arrange = function(): string
        local arranging = require("structure/arranging")
        arranging.toggle()
        return if g.untracked(arranging.active) then "arranging" else "done"
    end,
    done = function(): string
        require("structure/arranging").finish()
        return "done"
    end,
    state = function(): string
        return if g.untracked(require("structure/arranging").active) then "arranging" else "at rest"
    end,
    -- Where each one is: the list being edited while the mode lasts.
    list = function(): string
        local arranging = require("structure/arranging")
        local list = if g.untracked(arranging.active) then g.untracked(arranging.working) else config.get("organisms", {})
        return g.to_json(g.array(table.clone(list)))
    end,
})
if holds_blocks() then
    -- Where a cell with no place of its own appears when it is asked for:
    -- the middle of each monitor, empty until then.
    table.insert(surfaces, g.surface {
        full = true,
        anchor = { "top", "bottom", "left", "right" },
        outputs = "all",
        reserve = false,
        above_zones = true,
        namespace = "bioma-float",
        -- Followed, not built again: a summoned cell outlives a membrane
        -- taking or letting go of its strip.
        fluid = true,
        function(output: string, size: any)
            return float.host(output, size or { width = 1920, height = 1080 })
        end,
    })

    -- The session's authentication agent, there before anything asks: it
    -- summons the polkit cell into a host.
    require("services/polkit").start()

    -- While a cell is open, a press on any other monitor closes it.
    table.insert(surfaces, g.surface {
        full = true,
        anchor = { "top", "bottom", "left", "right" },
        outputs = "all",
        reserve = false,
        -- A press anywhere on the screen, a membrane's strip included.
        above_zones = true,
        namespace = "bioma-input",
        function(output: string, size: any)
            return input_surface.node(output, size or { width = 1920, height = 1080 })
        end,
    })

    -- Bioma's own selection rectangle, over everything, another shell's
    -- surfaces included, while the capture service asks for a region.
    table.insert(surfaces, g.surface {
        full = true,
        anchor = { "top", "bottom", "left", "right" },
        outputs = "all",
        reserve = false,
        above_zones = true,
        layer = "overlay",
        namespace = "bioma-selection",
        function(output: string, size: any)
            return selection.node(output, size or { width = 1920, height = 1080 })
        end,
    })
end

-- Being asked for: `scripts/genoma ipc cell toggle <domain> [output]`. The
-- output the keyboard is on is the one meant, unless the call names one. An
-- old name still reaches the cell it became.
local niri = require("services/niri")
local function meant(output: string?): string?
    if output and output ~= "" then return output end
    local focused = g.untracked(niri.focused_output)
    return if focused ~= "" then focused else nil
end
g.ipc("cell", {
    toggle = function(domain: string, output: string?): string
        domain = registry.canonical(domain or "")
        return if focus.invoke(domain, meant(output)) then "toggled " .. domain
            else 'no invocable cell "' .. domain .. '"'
    end,
    close = function(domain: string, output: string?): string
        domain = registry.canonical(domain or "")
        return if focus.retire(domain, meant(output)) then "closed " .. domain
            else 'no invocable cell "' .. domain .. '"'
    end,
    -- Everything that answers to a name, for a keybind file to be written
    -- against rather than guessed at.
    list = function(): string return table.concat(focus.domains(), "\n") end,
})

-- The rest of what Quickshell's shell.qml answers (genoma/ipc.luau).
require("ipc").register()

-- What Bioma on Quickshell does to the desktop, done here once the switch
-- is made (M6 step 7a; genoma/PORT.md, "Who acts on the desktop"): beside
-- Quickshell, it acts and these only choose.
if runtime.alone() then
    require("services/matugen").start()
    require("services/templates").start()
    require("services/looks").start()
    require("services/proxy").start()
    require("services/locker").start()
    require("services/session").start()
    require("services/clipboard").start()
    require("services/greeter_sync").start()
    require("services/sounds").start()
    require("services/power").start()
    require("services/printers").start()
    require("services/osd").start()
    -- The on-screen display, over everything and taking nothing.
    local osd_surface = require("structure/osd")
    table.insert(surfaces, g.surface {
        full = true,
        anchor = { "top", "bottom", "left", "right" },
        outputs = "all",
        reserve = false,
        above_zones = true,
        layer = "overlay",
        namespace = "bioma-osd",
        function(output: string, size: any)
            return osd_surface.node(output, size or { width = 1920, height = 1080 })
        end,
    })
end

-- The walk-through, as Quickshell's `setup` target has it: opened on a
-- screen, moved to a step, its state read.
g.ipc("setup", {
    open = function(output: string?): string
        local setup = require("services/setup")
        local screen = meant(output)
        setup.open(screen)
        return "open on " .. (screen or "the primary screen") .. ", step " .. g.untracked(setup.step)
    end,
    go = function(step: string): string
        local setup = require("services/setup")
        for _, s in g.untracked(setup.steps) do
            if s.key == step then
                setup.go(step)
                return step
            end
        end
        return 'no step "' .. tostring(step) .. '"'
    end,
    state = function(): string
        local setup = require("services/setup")
        local keys = {}
        for _, s in g.untracked(setup.steps) do table.insert(keys, s.key) end
        return g.to_json({
            active = g.untracked(setup.active), output = g.untracked(setup.output), step = g.untracked(setup.step),
            steps = g.array(keys), done = g.untracked(setup.done), pending = g.untracked(setup.pending),
        })
    end,
})

-- BIOMA_GENOMA_CHECK=<service>: that service's state as it changes, with
-- no interface (services/check.luau), the way each was verified on Quickshell.
local check = g.env("BIOMA_GENOMA_CHECK")
if check and check ~= "1" and check ~= "write" then
    local checks = require("services/check")
    if checks[check] then checks[check]() else print("check: no service " .. check) end
end

-- BIOMA_GENOMA_CHECK=1: the core's values, to set beside the QML's and the
-- token set's, and the theme's transit as it happens.
if g.env("BIOMA_GENOMA_CHECK") then
    g.effect(function()
        print(string.format("check theme %s source %s: background %s text %s primary %s secondary %s",
            if theme.is_dark() then "dark" else "light", config.get("theme.source", "manual"),
            theme.background(), theme.text(), theme.primary(), theme.secondary()))
        print(string.format("check derived elevated %s cell %s line %s node %s rim %s muted %s top %s bottom %s",
            theme.elevated(), theme.cell(), theme.line(), theme.node(), theme.rim(), theme.text_muted(),
            theme.gradient_top(theme.primary()), theme.gradient_bottom(theme.primary())))
    end)
    g.effect(function()
        local s = metrics.step("normal")
        print(string.format("check metrics edge %s gap %s tissue %s panel radius %s blur %.2f fonts %d/%d/%d/%d/%d",
            s.margin_edge, s.gap, s.tissue_padding, s.radius_panel, s.blur_radius,
            s.font_value, s.font_label, s.font_secondary, s.font_meta, s.font_title))
        print(string.format("check timing speed %s open %.3f close %.3f theme %.3f stagger %.3f stage(0.5, 1, 3) %.3f",
            tostring(config.get("timing.speed", 1)), timing.seconds.open, timing.seconds.close, timing.seconds.theme,
            timing.seconds.stagger, timing.stage(0.5, 1, 3)))
        print("check fonts " .. typography.expressive() .. " / " .. typography.technical())
    end)
    -- BIOMA_GENOMA_CHECK=write: one setting written back, as Settings would.
    if g.env("BIOMA_GENOMA_CHECK") == "write" then
        config.set_many({ { "appearance.gap", 30 }, { "genoma_check.written", true } })
        print("check wrote appearance.gap = " .. tostring(config.get("appearance.gap", 0)))
    end
end

-- Nothing marked as Genoma's: one surface on no output, which makes none.
if #surfaces == 0 then
    return g.surface { outputs = {}, namespace = "bioma-genoma", function() return g.box {} end }
end
return surfaces
