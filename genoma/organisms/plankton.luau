--!strict
-- Plankton: what the machine is running, as a swarm (Genoma's boids, a
-- simulation stepped on the GPU). See docs/design/ORGANISMS.md §17.
--
-- Every motion is the machine. The swarm swims as fast as the processor
-- works, on a square-root scale so an idle machine's few percent still
-- read: a slow drift at rest, a dart with every core busy. Only
-- performance mode's motion lever stops it.
-- How close it keeps is how full the memory is: an empty machine is a
-- loose drift, a full one a tight shoal. How many there are is how much
-- the kernel runs, one creature for every ten of its tasks (threads
-- included), counted in twenty-fives so the swarm does not grow or thin
-- with every thread. A new number keeps the swarm (Genoma 0.1.20): new
-- creatures divide from those there, and fewer, the last go; before it,
-- every new number started the swarm again from the same scatter.
local g = require("@genoma")
local theme = require("core/theme")
local typography = require("core/typography")
local system = require("services/system_monitor")
local performance = require("core/performance")

local PER_CREATURE = 10
-- Frames a second, at rest and with every core busy. Under thirty the
-- swarm visibly jerks, however slowly it swims.
local FEWEST_FRAMES, MOST_FRAMES = 30, 60
local STEP = 25
local FEWEST, MOST = 50, 400
-- The glass's outline: Genoma draws a rim never under two physical pixels,
-- so two units hold it at any scale.
local RIM = 2

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local function load(): number return math.clamp(system.cpu_percent() / 100, 0, 1) end
        local function memory(): number return math.clamp(system.ram_percent() / 100, 0, 1) end
        local function swimming(): boolean return not performance.still() end
        -- Units a second: a drift at rest, a dart with every core busy.
        local function speed(): number return 4 + 92 * math.sqrt(load()) end
        local function themed(): boolean return o.entry().colour == "theme" end
        local function tint(): string return if themed() then theme.primary() else theme.state_for(load()) end
        local function figures(): boolean return o.entry().figures ~= false end
        local function inset(): number return 18 * f() end
        local function inner_width(): number return o.width() - 2 * RIM end
        local function inner_height(): number return o.height() - 2 * RIM end

        -- The population changes only by whole steps; the creatures there
        -- stay when it does.
        local population = g.computed(function(): number
            local n = math.round(system.tasks() / PER_CREATURE / STEP) * STEP
            return math.clamp(n, FEWEST, MOST)
        end)

        local function creatures(): any
            return g.shader {
                overlay = true,
                attach = "corner",
                width = inner_width,
                height = inner_height,
                compute = "genoma:boids",
                agents = function() return population.value end,
                agent_size = function() return 4 * f() end,
                fill = tint,
                clock = swimming,
                -- A drift needs few frames, a dart many; a creature never
                -- moves more than 1.6 units between two. Every frame is
                -- also one the compositor composes again, glass blur
                -- included, so a frame drawn for nothing costs twice (on a
                -- laptop's integrated card, most of its load at rest).
                fps = function() return FEWEST_FRAMES + (MOST_FRAMES - FEWEST_FRAMES) * load() end,
                values = function()
                    local mem = memory()
                    return {
                        -- Swimming speed: a drift at rest, a dart with
                        -- every core busy.
                        speed() * f(),
                        -- How far one sees, how much it keeps apart, how
                        -- much it turns with the others, how much it
                        -- gathers: the memory draws the shoal together.
                        28 * f(),
                        0.9 - 0.5 * mem,
                        1,
                        0.15 + 1.2 * mem,
                        0,
                    }
                end,
            }
        end

        -- Each creature lit: Genoma's bloom over the swarm, a soft light
        -- round each as wide as a few of its lengths. The panel's clip
        -- follows its round corners, which the swarm wraps across.
        local function swarm(): any
            return g.box {
                overlay = true,
                attach = "corner",
                width = inner_width,
                height = inner_height,
                creatures(),
                g.shader {
                    pass = true,
                    attach = "corner",
                    width = inner_width,
                    height = inner_height,
                    src = "genoma:glow",
                    values = function() return { 7 * f(), 1.4, 0.15 } end,
                },
            }
        end

        local function label(text: string): any
            return g.text {
                text = text,
                color = theme.text,
                font = typography.technical,
                size = function() return m().font_label end,
                weight = typography.weight_label,
                tracking = typography.label_tracking,
            }
        end
        local function figure(text: () -> string): any
            return g.text {
                text = text,
                color = function() return theme.gradient_top(tint()) end,
                color_bottom = function() return theme.gradient_bottom(tint()) end,
                font = typography.technical,
                size = function() return m().font_value end,
                weight = typography.weight_value,
                tabular = true,
            }
        end

        return {
            bleeds = true,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    -- The swarm swims inside the glass's outline, never
                    -- over it: clipped to the shape within the rim.
                    g.capsule {
                        overlay = true,
                        attach = "corner",
                        offset_x = RIM,
                        offset_y = RIM,
                        width = inner_width,
                        height = inner_height,
                        radius = function() return m().radius_panel - RIM end,
                        clip = true,
                        fill = "#00000000",
                        rim_top = "#00000000",
                        rim_bottom = "#00000000",
                        swarm(),
                    },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        present = figures,
                        offset_x = inset,
                        offset_y = inset,
                        direction = "row",
                        gap = function() return 22 * f() end,
                        g.box {
                            direction = "column",
                            align = "start",
                            gap = function() return 2 * f() end,
                            label("CPU"),
                            figure(function() return math.round(system.cpu_percent()) .. "%" end),
                        },
                        g.box {
                            direction = "column",
                            align = "start",
                            gap = function() return 2 * f() end,
                            label("RAM"),
                            figure(function() return math.round(system.ram_percent()) .. "%" end),
                        },
                    },
                }
            end,
        }
    end,
}
