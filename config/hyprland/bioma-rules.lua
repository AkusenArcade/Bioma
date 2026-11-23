-- Bioma — layer rules for Hyprland (config/niri/bioma.kdl is niri's).
--
-- Blur needs no rule: Hyprland blurs, through `ext-background-effect`, the
-- exact region each cell declares and nothing else, as niri does. Its blur
-- skips no layer (`decoration.blur.xray` is off by default), so every cell
-- shows what is really underneath it; with xray on, the membranes, which are
-- as tall as the screen, would show the wallpaper over the windows.
--
-- What does need saying is that Bioma moves its own surfaces. Hyprland fades
-- and slides a layer surface as it maps and unmaps; on Bioma's that would be
-- a second animation over the shell's own, with a rate no value is behind.
--
-- niri's other rule, the blurred wallpaper placed behind its overview, has no
-- counterpart: Hyprland has no overview, and Bioma does not draw that copy
-- here.
--
-- Bioma writes this file (scripts/hypr-include) and keeps it as shipped:
-- your own rules belong in hyprland.lua.

hl.layer_rule({
    name = "bioma-no-anim",
    match = { namespace = "^bioma-" },
    no_anim = true,
})
