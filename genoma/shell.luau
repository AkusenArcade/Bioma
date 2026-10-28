--!strict
-- Bioma on Genoma (genoma/PORT.md): the core, and a surface for every
-- membrane block marked `"runtime": "genoma"`, laid out by the structure
-- engine (genoma/structure/).
local g = require("@genoma")
local config = require("core/config")
local theme = require("core/theme")
local timing = require("core/timing")
local metrics = require("core/metrics")
local typography = require("core/typography")

local membrane = require("structure/membrane")

-- Which outputs a block belongs to: a name, `all`, or `primary` (the output
-- niri focuses at start; until the Monitors service is ported, $BIOMA_PRIMARY
-- or the first block's own).
local function outputs_of(block: { [string]: any }): any
    local monitor = block.monitor or "primary"
    if monitor == "all" or monitor == "*" then return "all" end
    if monitor == "primary" then return { g.env("BIOMA_PRIMARY") or "DP-1" } end
    return { monitor }
end

-- One surface per membrane block marked as Genoma's, on each output it
-- belongs to.
local surfaces = {}
for i, entry in config.get("membranes", {}) do
    if entry.runtime == "genoma" then
        local index = i
        local function block() return config.get("membranes", {})[index] or entry end
        local edge = entry.edge or "top"
        local horizontal = edge == "top" or edge == "bottom"
        local strip = metrics.step(entry.scale or "normal")
        local reserving = entry.reserve_space == true and horizontal and entry.auto_hide ~= true
        local anchor = {}
        for _, side in { "top", "bottom", "left", "right" } do
            local opposite = ({ top = "bottom", bottom = "top", left = "right", right = "left" })[edge]
            if side ~= opposite then table.insert(anchor, side) end
        end
        table.insert(surfaces, g.surface {
            full = true,
            anchor = anchor,
            outputs = outputs_of(entry),
            reserve = if reserving then math.floor(strip.margin_edge + strip.cell_height + strip.tissue_padding * 2 + 0.5) else false,
            -- Bioma's own name for the edge: niri's rule for it turns blur
            -- xray off (config/niri/bioma.kdl).
            namespace = "bioma-membrane-" .. edge,
            function(output: string, size: any)
                local s = size or { width = 1920, height = 1080 }
                return membrane.new(block, output, s).tree
            end,
        })
    end
end
print(string.format("Bioma on Genoma: %d membranes", #surfaces))

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
