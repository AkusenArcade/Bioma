--!strict
-- The single named timing set (core/Timing.qml). No duration is written
-- anywhere else: a transition names an entry, and an entry's duration comes
-- from `timing.*` in the configuration, multiplied by `timing.speed`.
--
-- Opening is slower than closing on purpose. Reach the opening figure by
-- tightening the cascade, never by shortening an individual growth.
local g = require("@genoma")
local config = require("core/config")
local performance = require("core/performance")

local M = {}

-- In the form Genoma takes: the two control points of a cubic Bézier.
-- Small capsules may overshoot; large panels may not; closing never does.
M.curves = {
    -- The loader's own, and nothing else's: symmetric, it reads as breathing.
    sweep = { 0.45, 0, 0.55, 1 },
    open = { 0.2, 0.9, 0.3, 1.15 },
    open_flat = { 0.2, 0.9, 0.3, 1.0 },
    close = { 0.5, 0.0, 0.9, 0.5 },
    -- Qt's Easing.InOutQuad, for the theme and the wallpaper's crossfade.
    in_out_quad = { 0.455, 0.03, 0.515, 0.955 },
    -- Qt's Easing.OutQuad.
    out_quad = { 0.25, 0.46, 0.45, 0.94 },
}

-- Seconds, after the speed setting: what timers and the cascade read.
-- Updated, with the set, whenever the configuration moves.
M.seconds = {} :: { [string]: number }

-- A shape's movements (scaled, and instant in performance mode, which comes
-- with the services), and the dwells (scaled), and the waits that are not
-- animations (never scaled: the disk does not answer slower because the
-- shell was asked to move slower).
local moved = {
    open = 250, close = 150, grow = 100, transition = 180, reflow = 220, theme = 250,
    content_fade = 120, wallpaper = 600, welcome_open = 450, welcome_stagger = 100, welcome_fade = 1000,
}
local scaled = { stagger = 16, debounce = 180, auto_hide = 500, notification = 5000, loader = 1200, welcome = 900 }
local fixed = {
    locate = 120, pair = 2000, search = 150, pulse = 120, settle = 3000, overview_settle = 800,
    blur_settle = 400, osd = 1500, hush = 1000, fling = 80,
    -- A particle's travel along a thread: its rate is the value, this only
    -- how long one takes to cross.
    flow = 600,
}

g.effect(function()
    local speed = config.get("timing.speed", 1.0)
    -- Performance mode's transitions lever: what moves is over in a
    -- millisecond, and nothing is staggered (Timing.qml).
    local instant = performance.instant()
    for name, ms in moved do
        M.seconds[name] = if instant then 0.001 else config.get("timing." .. name, ms) * speed / 1000
    end
    for name, ms in scaled do M.seconds[name] = config.get("timing." .. name, ms) * speed / 1000 end
    if instant then M.seconds.stagger = 0 end
    for name, ms in fixed do M.seconds[name] = config.get("timing." .. name, ms) / 1000 end
    local s, c = M.seconds, M.curves
    g.timing {
        open = { duration = s.open, curve = c.open },
        open_flat = { duration = s.open, curve = c.open_flat },
        close = { duration = s.close, curve = c.close },
        grow = { duration = s.grow, curve = c.open_flat },
        transition = { duration = s.transition, curve = c.open_flat },
        reflow = { duration = s.reflow, curve = c.open_flat },
        theme = { duration = s.theme, curve = c.in_out_quad },
        -- The theme cell's chips, replacing each other a stagger apart.
        chip_1 = { duration = s.theme, curve = c.in_out_quad },
        chip_2 = { duration = s.theme, delay = s.stagger, curve = c.in_out_quad },
        chip_3 = { duration = s.theme, delay = s.stagger * 2, curve = c.in_out_quad },
        chip_4 = { duration = s.theme, delay = s.stagger * 3, curve = c.in_out_quad },
        chip_5 = { duration = s.theme, delay = s.stagger * 4, curve = c.in_out_quad },
        chip_6 = { duration = s.theme, delay = s.stagger * 5, curve = c.in_out_quad },
        chip_7 = { duration = s.theme, delay = s.stagger * 6, curve = c.in_out_quad },
        -- A cell's appearing and leaving (Cell.qml's opacity Behavior), and a
        -- colour lifting under the pointer (its ColorAnimations, linear).
        fade = { duration = s.reflow, curve = c.in_out_quad },
        colour = { duration = s.transition },
        content_fade = { duration = s.content_fade },
        -- The audio band's bars following the sound (Band.qml's Behavior).
        band = { duration = s.content_fade, curve = c.out_quad },
        -- A panel budding out of its cell takes what Cell.qml's thread and
        -- panel took together, the thread's two staggers and the growth; its
        -- content enters once the shape is at size, and leaves first.
        bud = { duration = s.grow + s.stagger * 2, curve = c.open_flat },
        content_enter = { duration = s.content_fade, delay = s.grow + s.stagger * 2 },
        -- The quick actions' icons, once their capsules have reached the
        -- circle (ActionsCell: in when the spread is done).
        ring_content = { duration = s.content_fade, delay = s.open },
        -- The alarms (Vital.qml), the one thing that repeats at a fixed rate:
        -- an alarm has no value to encode beyond the fact that it is one.
        -- Never scaled, never instant.
        alarm = { duration = 0.9, curve = c.out_quad },
        alarm_fade = { duration = 0.405, curve = c.out_quad },
        full_pulse = { duration = 0.45, curve = c.in_out_quad },
        -- A mark stepping once (WorkspaceBars), small, so it may overshoot.
        shift = { duration = s.transition, curve = c.open },
        -- Shapes budding out of a panel once it has grown, a stagger apart
        -- (the vitals' pods, VitalsExpansion's cascade).
        pod_1 = { duration = s.grow, delay = s.grow + s.stagger * 2, curve = c.open_flat },
        pod_2 = { duration = s.grow, delay = s.grow + s.stagger * 3, curve = c.open_flat },
        pod_3 = { duration = s.grow, delay = s.grow + s.stagger * 4, curve = c.open_flat },
        pod_4 = { duration = s.grow, delay = s.grow + s.stagger * 5, curve = c.open_flat },
        -- The thread that stays once a bud has parted: drawn out as the neck
        -- thins, and taken back first, before the shape it ties.
        thread = { duration = s.grow, delay = s.grow, curve = c.open_flat },
        -- Closing, the content goes first and the shape only once it has
        -- gone (STYLE_GUIDE §6; Akusen, 2026-10-29, as a rule for every
        -- shape that holds something): the content leaves in half its
        -- entering time, so the whole still closes quickly.
        content_leave = { duration = s.content_fade / 2 },
        -- A cell's content back at rest once its header has left.
        content_return = { duration = s.content_fade, delay = s.content_fade / 2 },
        retract = { duration = s.close, delay = s.content_fade / 2, curve = c.close },
        thread_close = { duration = s.stagger * 2, delay = s.content_fade / 2, curve = c.close },
        -- And the shapes go in the order opposite to the one they came in
        -- (Akusen, 2026-10-29): the last pod's thread, then that pod, a
        -- stagger before the one that came before it, and the panel that
        -- came first goes last, with the cell's thread.
        pod_thread_close_4 = { duration = s.stagger * 2, delay = s.content_fade / 2, curve = c.close },
        pod_thread_close_3 = { duration = s.stagger * 2, delay = s.content_fade / 2 + s.stagger, curve = c.close },
        pod_thread_close_2 = { duration = s.stagger * 2, delay = s.content_fade / 2 + s.stagger * 2, curve = c.close },
        pod_thread_close_1 = { duration = s.stagger * 2, delay = s.content_fade / 2 + s.stagger * 3, curve = c.close },
        pod_retract_4 = { duration = s.grow, delay = s.content_fade / 2 + s.stagger * 2, curve = c.close },
        pod_retract_3 = { duration = s.grow, delay = s.content_fade / 2 + s.stagger * 3, curve = c.close },
        pod_retract_2 = { duration = s.grow, delay = s.content_fade / 2 + s.stagger * 4, curve = c.close },
        pod_retract_1 = { duration = s.grow, delay = s.content_fade / 2 + s.stagger * 5, curve = c.close },
        retract_last = { duration = s.close, delay = s.content_fade / 2 + s.stagger * 6, curve = c.close },
        thread_close_last = { duration = s.stagger * 2, delay = s.content_fade / 2 + s.stagger * 6, curve = c.close },
        pod_thread_1 = { duration = s.grow, delay = s.grow * 2 + s.stagger * 2, curve = c.open_flat },
        pod_thread_2 = { duration = s.grow, delay = s.grow * 2 + s.stagger * 3, curve = c.open_flat },
        pod_thread_3 = { duration = s.grow, delay = s.grow * 2 + s.stagger * 4, curve = c.open_flat },
        pod_thread_4 = { duration = s.grow, delay = s.grow * 2 + s.stagger * 5, curve = c.open_flat },
        -- And each pod's content once that pod is at size.
        pod_content_1 = { duration = s.content_fade, delay = s.grow * 2 + s.stagger * 2 },
        pod_content_2 = { duration = s.content_fade, delay = s.grow * 2 + s.stagger * 3 },
        pod_content_3 = { duration = s.content_fade, delay = s.grow * 2 + s.stagger * 4 },
        pod_content_4 = { duration = s.content_fade, delay = s.grow * 2 + s.stagger * 5 },
        -- A column of capsules beside a panel, a stagger apart (settings'
        -- categories, SettingsExpansion's cascade): in after the panel has
        -- budded, and back first, the last one first.
        cascade_1 = { duration = s.grow, delay = s.grow + s.stagger * 2, curve = c.open_flat },
        cascade_2 = { duration = s.grow, delay = s.grow + s.stagger * 3, curve = c.open_flat },
        cascade_3 = { duration = s.grow, delay = s.grow + s.stagger * 4, curve = c.open_flat },
        cascade_4 = { duration = s.grow, delay = s.grow + s.stagger * 5, curve = c.open_flat },
        cascade_5 = { duration = s.grow, delay = s.grow + s.stagger * 6, curve = c.open_flat },
        cascade_6 = { duration = s.grow, delay = s.grow + s.stagger * 7, curve = c.open_flat },
        cascade_7 = { duration = s.grow, delay = s.grow + s.stagger * 8, curve = c.open_flat },
        cascade_8 = { duration = s.grow, delay = s.grow + s.stagger * 9, curve = c.open_flat },
        cascade_9 = { duration = s.grow, delay = s.grow + s.stagger * 10, curve = c.open_flat },
        cascade_10 = { duration = s.grow, delay = s.grow + s.stagger * 11, curve = c.open_flat },
        cascade_11 = { duration = s.grow, delay = s.grow + s.stagger * 12, curve = c.open_flat },
        cascade_12 = { duration = s.grow, delay = s.grow + s.stagger * 13, curve = c.open_flat },
        cascade_close = { duration = s.close, delay = s.content_fade / 2, curve = c.close },
        -- An open cell's header, two staggers after the content has gone.
        header = { duration = s.content_fade, delay = s.stagger * 2 },
        wallpaper = { duration = s.wallpaper, curve = c.in_out_quad },
        loader = { duration = s.loader, curve = c.sweep },
        welcome_open = { duration = s.welcome_open, curve = c.open_flat },
        welcome_fade = { duration = s.welcome_fade, curve = c.in_out_quad },
        instant = { duration = 0 },
    }
end)

-- How long a shape with content takes to be gone once it starts closing;
-- `last` for a panel that waits for the shapes that budded out of it.
function M.retracted(last: boolean?): number
    local s = M.seconds
    return s.content_fade / 2 + (if last then s.stagger * 6 else 0) + s.close
end

-- When the thread of the i-th shape budding out of a panel is drawn whole:
-- its pod_thread_i entry's delay and duration. What travels along a thread
-- starts then, on a connection that is there.
function M.thread_done(i: number): number
    local s = M.seconds
    return s.grow * 2 + s.stagger * (1 + math.clamp(i, 1, 4)) + s.grow
end

-- A staggered entrance as a fraction per shape: `cascade` runs 0 to 1 over
-- the whole opening, each shape starts one stagger after the one before,
-- and each grows over `grow`. The span holds every phase, so it depends on
-- how many shapes there are.
function M.stage(cascade: number, index: number, count: number): number
    local grow, stagger = M.seconds.grow, M.seconds.stagger
    local span = grow + stagger * math.max(0, count - 1)
    local started = cascade * span - index * stagger
    return math.clamp(started / math.max(grow, 1e-6), 0, 1)
end

-- A shadow's opacity for a shape at `growth`: it leaves before the shape and
-- arrives after it (Akusen, 2026-09-27).
function M.shadow_for(growth: number): number
    return math.clamp((growth - 0.5) * 2, 0, 1)
end

return M
