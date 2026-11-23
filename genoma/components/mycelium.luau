--!strict
-- Mycelium on the wallpaper (Settings → Appearance → MYCELIUM, off unless
-- chosen; the vault plan's item 3, decided 2026-11-17): streaks of light in
-- the primary colour, a bright head and a fading tail, running out along
-- hyphae that branch as a mould does (Akusen, 2026-11-18: the streaks'
-- look, the mycelium's branching). Each hypha is grown here once per
-- picture: one of its own outlines is the trunk, and branches leave it
-- and leave each other, wandering and bending towards the nearest other
-- outline, its food. One shader draws one hypha (components/mycelium.wgsl):
-- a streak runs out from the root and divides at every fork. A layer of
-- its own over the picture, which is never drawn again for it.
--
-- The datum is idle time. Enabled, a few hyphae always light, faint and
-- slow, even while the person works; the longer no input comes, the more
-- of them, brighter and faster, until they are a screensaver. The first
-- input brings them back to the least. Against OLED burn-in, the drawing
-- moves most exactly when the screen would otherwise be still.
--
-- The outlines are found once per picture (Genoma's g.contours, off the
-- frame), and the hyphae grown from them, never while it is shown. They
-- stop while windows cover the screen, in performance mode and in focus
-- mode.
local g = require("@genoma")
local config = require("core/config")
local colour = require("core/colour")
local theme = require("core/theme")
local performance = require("core/performance")
local focus_mode = require("core/focus_mode")
local paths = require("core/paths")
local compositor = require("services/compositor")

local M = {}

local SHADER = paths.root .. "/genoma/components/mycelium.wgsl"

-- At rest (the person working) and at full idle: how many hyphae light on
-- a screen, how bright, how fast the clock runs.
local LEAST, MOST = 3, 10
local DIM, BRIGHT = 0.5, 1
local SLOW, FAST = 1, 4
-- Logical units: how fast a head runs at the slowest, how long a tail is,
-- the stroke's half-width on a trunk, the room the glow needs.
local SPEED, TAIL, WIDTH, MARGIN = 70, 220, 1.7, 14
-- A trunk shorter than this on screen grows no hypha.
local SHORTEST = 160
-- Growing: a step's length; how far apart branches leave, at least and at
-- most; how far aside, radians; how long a first branch is, and how much
-- shorter each further one; how deep they go; how far a branch smells
-- food, and how hard it turns to it a step.
local STEP, APART_MIN, APART_MAX = 10, 35, 85
local ASIDE_MIN, ASIDE_MAX = 0.45, 1.05
local BRANCH_MIN, BRANCH_MAX, SHORTER = 90, 220, 0.55
local DEPTH = 3
local SMELL, TURN = 60, 0.12
-- The points one hypha may have: what fits in its shader's numbers, three
-- each, with every run's lead (hypha()).
local POINTS = 220
-- Seconds without input before idle begins, and from then until full.
local IDLE_AFTER, RAMP = 20, 300

function M.on(): boolean return config.get("appearance.mycelium", false) == true end

-- ---- Idle -------------------------------------------------------------------------

-- 0 while the person works, rising to 1 over RAMP seconds of idle.
local level = g.signal(0)
local rising = g.signal(false)
g.lasting(function()
    local idle = require("@genoma/idle")
    g.effect(function()
        local wanted = if M.on() then IDLE_AFTER else 0
        g.untracked(function() idle:watch("mycelium", wanted) end)
    end)
    local ticking: any = nil
    g.watch(function() return idle:is_idle("mycelium") end, function(now_idle: boolean)
        if ticking then
            ticking:stop()
            ticking = nil
        end
        if not now_idle then
            rising.value = false
            level.value = 0
            return
        end
        local began = g.now()
        rising.value = true
        ticking = g.lasting(function()
            return g.timer {
                every = 2,
                on_tick = function()
                    local next_level = math.clamp((g.now() - began) / RAMP, 0, 1)
                    level.value = next_level
                    if next_level >= 1 and ticking then
                        ticking:stop()
                        ticking = nil
                    end
                end,
            }
        end)
    end)
end)

-- ---- The picture's outlines ---------------------------------------------------------

-- Per picture, shared by every screen showing it: nil until found, false
-- for a picture that has none.
local found: { [string]: any } = {}
local function outlines(path: string): any
    local s = found[path]
    if not s then
        s = g.lasting(function() return g.signal(nil :: any) end)
        found[path] = s
        g.contours {
            src = path,
            on_done = function(lines: any, width: number?, height: number?)
                s.value = if lines and width and height then { lines = lines, width = width, height = height } else false
            end,
        }
    end
    return s.value
end

-- ---- Covered ----------------------------------------------------------------------

-- Whether the windows on this screen's workspace cover nearly all of it:
-- columns across nine tenths of its width, each filling most of its
-- height. Then nothing of the mycelium would be seen. Where the layout has
-- no columns (Hyprland), the tiles' own rectangles: four fifths of the
-- screen's area under them, which two windows side by side reach once the
-- gaps and a membrane's strip are taken off (tiled windows do not overlap).
local function covered(output: string, size: { width: number, height: number }): boolean
    local ws = compositor.active_workspace_for_output(output)
    if not ws then return false end
    local columns: { [number]: { w: number, h: number } } = {}
    local area, placed = 0, false
    for _, w in compositor.windows_on_workspace(ws.id) do
        local l = compositor.layout_for(w.id)
        if l and l.column and type(l.tile_size) == "table" then
            local c = columns[l.column] or { w = 0, h = 0 }
            c.w = math.max(c.w, l.tile_size[1])
            c.h += l.tile_size[2]
            columns[l.column] = c
        elseif l and l.position_in_view and not w.is_floating then
            local x0, y0 = math.max(0, l.position_in_view[1]), math.max(0, l.position_in_view[2])
            local x1 = math.min(size.width, l.position_in_view[1] + l.tile_size[1])
            local y1 = math.min(size.height, l.position_in_view[2] + l.tile_size[2])
            if x1 > x0 and y1 > y0 then area += (x1 - x0) * (y1 - y0) end
            placed = true
        end
    end
    if next(columns) == nil and placed then return area >= size.width * size.height * 0.8 end
    local across, any = 0, false
    for _, c in columns do
        if c.h < size.height * 0.8 then return false end
        across += c.w
        any = true
    end
    return any and across >= size.width * 0.9
end

-- ---- Growing a hypha ------------------------------------------------------------------

-- Chance that is the same every time for the same picture: a hypha grows
-- the same way whenever it is shown.
local function chance(seed: number): () -> number
    local state = (seed * 2654435761) % 4294967296
    return function(): number
        state = (state * 1664525 + 1013904223) % 4294967296
        return state / 4294967296
    end
end

-- The outlines' points, bucketed so a branch finds the nearest quickly.
local BUCKET = 40
local function food_map(lines: { { number } }): (number, number) -> (number?, number?)
    local buckets: { [number]: { number } } = {}
    local function key(bx: number, by: number): number return bx * 100003 + by end
    for _, line in lines do
        for k = 1, #line - 1, 2 do
            local x, y = line[k], line[k + 1]
            local b = key(x // BUCKET, y // BUCKET)
            local list = buckets[b]
            if not list then
                list = {}
                buckets[b] = list
            end
            table.insert(list, x)
            table.insert(list, y)
        end
    end
    return function(x: number, y: number): (number?, number?)
        local bx, by = x // BUCKET, y // BUCKET
        local best, fx, fy = SMELL * SMELL, nil, nil
        for dx = -1, 1 do
            for dy = -1, 1 do
                local list = buckets[key(bx + dx, by + dy)]
                if list then
                    for k = 1, #list - 1, 2 do
                        local d = (list[k] - x) ^ 2 + (list[k + 1] - y) ^ 2
                        -- Not where it is: food ahead, not underfoot.
                        if d < best and d > (STEP * 1.5) ^ 2 then
                            best, fx, fy = d, list[k], list[k + 1]
                        end
                    end
                end
            end
        end
        return fx, fy
    end
end

-- A line resampled to points STEP apart.
local function resample(line: { number }): { { number } }
    local out = { { line[1], line[2] } }
    local carry = 0
    for k = 3, #line - 1, 2 do
        local ax, ay, bx, by = line[k - 2], line[k - 1], line[k], line[k + 1]
        local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local at = STEP - carry
        while at <= len do
            local t = at / len
            table.insert(out, { ax + (bx - ax) * t, ay + (by - ay) * t })
            at += STEP
        end
        carry = len - (at - STEP)
    end
    return out
end

-- One hypha from a trunk line (screen units): its branches, each a list of
-- { x, y, distance from the root }, with its weight.
local function grow(trunk: { number }, seed: number, eat: (number, number) -> (number?, number?), size: any): { any }
    local r = chance(seed)
    local branches: { any } = {}
    local count = 0
    local first = resample(trunk)
    local trunk_points = {}
    for i, p in first do table.insert(trunk_points, { p[1], p[2], (i - 1) * STEP }) end
    -- Long trunks thinned to leave room for branches.
    while #trunk_points > POINTS // 3 do
        local thinned = {}
        for i = 1, #trunk_points, 2 do table.insert(thinned, trunk_points[i]) end
        if thinned[#thinned] ~= trunk_points[#trunk_points] then table.insert(thinned, trunk_points[#trunk_points]) end
        trunk_points = thinned
    end
    table.insert(branches, { points = trunk_points, weight = 1, depth = 0 })
    count += #trunk_points + 1
    local function sprout(parent: any)
        if parent.depth >= DEPTH then return end
        local pts = parent.points
        local next_at = APART_MIN + r() * (APART_MAX - APART_MIN)
        for i = 2, #pts do
            if count >= POINTS - 8 then return end
            if pts[i][3] - pts[1][3] >= next_at then
                next_at = pts[i][3] - pts[1][3] + APART_MIN + r() * (APART_MAX - APART_MIN)
                local ax, ay, bx, by = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
                local heading = math.atan2(by - ay, bx - ax)
                heading += (if r() < 0.5 then -1 else 1) * (ASIDE_MIN + r() * (ASIDE_MAX - ASIDE_MIN))
                local length = (BRANCH_MIN + r() * (BRANCH_MAX - BRANCH_MIN)) * SHORTER ^ parent.depth
                local x, y, s = bx, by, pts[i][3]
                local points = { { x, y, s } }
                local travelled = 0
                while travelled < length and count + #points < POINTS - 2 do
                    heading += (r() - 0.5) * 0.5
                    local fx, fy = eat(x, y)
                    if fx and fy then
                        local want = math.atan2(fy - y, fx - x)
                        local turn = (want - heading + math.pi) % (2 * math.pi) - math.pi
                        heading += math.clamp(turn, -TURN, TURN)
                    end
                    x += math.cos(heading) * STEP
                    y += math.sin(heading) * STEP
                    travelled += STEP
                    if x < -MARGIN or y < -MARGIN or x > size.width + MARGIN or y > size.height + MARGIN then break end
                    table.insert(points, { x, y, s + travelled })
                end
                if #points >= 3 then
                    local branch = { points = points, weight = if parent.depth == 0 then 0.7 else 0.5, depth = parent.depth + 1 }
                    table.insert(branches, branch)
                    count += #points + 1
                end
            end
        end
    end
    -- Breadth first: every branch of the trunk before any of theirs.
    local i = 1
    while i <= #branches do
        sprout(branches[i])
        i += 1
    end
    return branches
end

-- A hypha's box on the surface and the numbers its shader reads, but the
-- colour. The branches go in as runs of at most RUN points, each led by
-- its box and the distances it spans: a pixel far from a run, or a run
-- the streak is not on, is passed over whole, without reading its points
-- (the shader drawn per point, every pixel, every frame, held a 9070 at
-- two thirds, Akusen 2026-11-18). Consecutive runs of a branch share
-- their joining point.
local RUN = 12
-- The shader's numbers: 1024, the header's 12 before them.
local NUMBERS = 1024 - 12
local function hypha(branches: { any }, rank: number): any
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    local furthest = 0
    for _, b in branches do
        for _, p in b.points do
            min_x, min_y = math.min(min_x, p[1]), math.min(min_y, p[2])
            max_x, max_y = math.max(max_x, p[1]), math.max(max_y, p[2])
            furthest = math.max(furthest, p[3])
        end
    end
    local x, y = min_x - MARGIN, min_y - MARGIN
    local values = { 0, furthest, TAIL, WIDTH, 1, 1, 1, 1, SPEED, 0, 0, 0 }
    local runs = 0
    for _, b in branches do
        local pts = b.points
        local first = 1
        while first < #pts do
            local last = math.min(first + RUN - 1, #pts)
            local count = last - first + 1
            -- Breadth first, so what does not fit is the furthest twigs.
            if #values - 12 + 8 + count * 3 > NUMBERS then break end
            local lo_x, lo_y, hi_x, hi_y = math.huge, math.huge, -math.huge, -math.huge
            for k = first, last do
                local p = pts[k]
                lo_x, lo_y = math.min(lo_x, p[1] - x), math.min(lo_y, p[2] - y)
                hi_x, hi_y = math.max(hi_x, p[1] - x), math.max(hi_y, p[2] - y)
            end
            for _, v in { count, pts[first][3], pts[last][3], b.weight, lo_x, lo_y, hi_x, hi_y } do
                table.insert(values, v)
            end
            for k = first, last do
                local p = pts[k]
                table.insert(values, p[1] - x)
                table.insert(values, p[2] - y)
                table.insert(values, p[3])
            end
            runs += 1
            first = last
        end
    end
    values[1] = runs
    -- Each its own place in its round and its own wait, so they never run
    -- in step: fixed by its rank, not by chance.
    local out = furthest + TAIL
    local round = out + SPEED * (2 + (rank * 1.7) % 4)
    values[10] = ((rank * 0.618) % 1) * out
    values[11] = round
    return {
        x = x,
        y = y,
        width = max_x - min_x + MARGIN * 2,
        height = max_y - min_y + MARGIN * 2,
        values = values,
    }
end

-- ---- The layer --------------------------------------------------------------------

-- `t`: output, size, source() (the picture's path), box() (where the
-- picture lies on the surface, { x, y, width, height }), fit() ("cover"
-- or "contain"), offset_x() and offset_y() (the depth's), present().
function M.layer(t: { [string]: any }): any
    local function running(): boolean
        if not M.on() or not t.present() then return false end
        if performance.still() or focus_mode.active() then return false end
        return not covered(t.output, t.size)
    end

    -- The hyphae on this screen, longest trunk first.
    local function hyphae(): { any }
        if not M.on() then return {} end
        local path = t.source()
        if path == "" then return {} end
        local o = outlines(path)
        if not o then return {} end
        local b = t.box()
        local iw, ih = o.width, o.height
        local s = if t.fit() == "contain" then math.min(b.width / iw, b.height / ih) else math.max(b.width / iw, b.height / ih)
        local dw, dh = iw * s, ih * s
        local ox, oy = b.x + (b.width - dw) / 2, b.y + (b.height - dh) / 2
        local lines: { { number } } = {}
        local trunks: { any } = {}
        for i, line in o.lines do
            local mapped: { number } = {}
            local inside, length = 0, 0
            for k = 1, #line - 1, 2 do
                local px, py = ox + line[k] * dw, oy + line[k + 1] * dh
                if #mapped >= 2 then
                    length += math.sqrt((px - mapped[#mapped - 1]) ^ 2 + (py - mapped[#mapped]) ^ 2)
                end
                table.insert(mapped, px)
                table.insert(mapped, py)
                if px >= 0 and py >= 0 and px <= t.size.width and py <= t.size.height then inside += 1 end
            end
            if #mapped >= 4 and inside / (#mapped / 2) >= 0.3 then table.insert(lines, mapped) end
            if #mapped >= 4 and inside / (#mapped / 2) >= 0.6 and length >= SHORTEST and #trunks < MOST then
                table.insert(trunks, { line = mapped, index = i })
            end
        end
        local eat = food_map(lines)
        local out = {}
        for rank, trunk in trunks do
            local h = hypha(grow(trunk.line, trunk.index * 7919 + #path, eat, t.size), rank)
            h.key = path .. ":" .. trunk.index
            h.rank = rank
            table.insert(out, h)
        end
        return out
    end

    -- How many light now, and how bright: the idle level.
    local function alpha(rank: number): number
        local l = level.value
        local shown = LEAST + (MOST - LEAST) * l
        return math.clamp(shown - rank + 1, 0, 1) * (DIM + (BRIGHT - DIM) * l)
    end
    local function rate(): number return SLOW + (FAST - SLOW) * level.value end
    -- Rising slowly with the idle time; falling at once to the least.
    local function ease(): string return if rising.value then "mycelium_ramp" else "mycelium_wake" end

    local function row(item: () -> any): any
        local function it(): any return item() end
        return g.shader {
            overlay = true,
            attach = "corner",
            offset_x = function() return it().x end,
            offset_y = function() return it().y end,
            width = function() return it().width end,
            height = function() return it().height end,
            src = SHADER,
            follow = 0,
            -- A head moves a unit or a few a frame at 60: as smooth as at
            -- the screen's 165, at a third of the frames.
            fps = 60,
            clock = function() return running() and alpha(g.untracked(it).rank) > 0 end,
            clock_rate = rate,
            opacity = function() return alpha(it().rank) end,
            transition = { clock_rate = ease, opacity = ease },
            values = function()
                local v = table.clone(it().values)
                local c = colour.parse(theme.primary())
                v[5], v[6], v[7], v[8] = c.r, c.g, c.b, 0.9
                return v
            end,
        }
    end

    return g.each {
        overlay = true,
        attach = "corner",
        width = t.size.width,
        height = t.size.height,
        offset_x = t.offset_x,
        offset_y = t.offset_y,
        transition = { offset_x = "parallax", offset_y = "parallax" },
        present = function() return M.on() and t.present() end,
        items = hyphae,
        key = function(h: any) return h.key end,
        row = row,
    }
end

return M
