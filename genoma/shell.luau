--!strict
-- Bioma on Genoma (genoma/PORT.md). Steps 0 and 1 of the port: the core
-- (configuration, theme, timing, metrics, typography) is loaded, and the
-- blocks marked `"runtime": "genoma"` are found; nothing is drawn yet.
-- Drawing them is the layout engine's, step 2.
local g = require("@genoma")
local config = require("core/config")
local theme = require("core/theme")
local timing = require("core/timing")
local metrics = require("core/metrics")
local typography = require("core/typography")

local owned = 0
for _, kind in { "membranes", "floating" } do
    for i, block in config.get(kind, {}) do
        if block.runtime == "genoma" then
            owned += 1
            print(string.format("genoma owns %s %d: %s on %s", kind, i, block.edge or block.anchor or "?", block.monitor or "primary"))
        end
    end
end
print(string.format("Bioma on Genoma: %d blocks to draw (none drawn yet)", owned))

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

-- No output yet: an empty list of outputs makes no surface.
return g.surface {
    outputs = {},
    namespace = "bioma-genoma",
    function(_output: string) return g.box {} end,
}
