--!strict
-- The wallpaper for one monitor (structure/WallpaperSurface.qml and
-- components/WallpaperImage.qml at 11bb81e), on the Background layer, below
-- everything. It is not a membrane: it has no edge, cedes no space, and
-- holds no cells.
--
-- A picture that changes arrives over the one it replaces: the new one is
-- laid on top, all but transparent, which is enough for it to be decoded
-- (Genoma does so off the frame, and draws nothing of it until it is
-- ready); `on_ready` says when it is there, and only then does it fade in.
-- The old one goes once it is covered. A crossfade started at once faded in
-- nothing for the first third of its time and then jumped: a spanned
-- picture decodes the box of every screen.
--
-- `backdrop` is the same picture blurred: niri puts it behind the workspaces
-- in the overview (`place-within-backdrop`, config/niri/bioma.kdl), where
-- the wallpaper proper is drawn inside each workspace. Decoded at a quarter
-- of its pixels and blurred once as it is decoded (`soften`): it costs
-- nothing to hold. It runs past the screen's edges, because a blur fades to
-- nothing at the edge of what it blurs.
--
-- Drawn by Bioma on Genoma only when `wallpaper.runtime` is "genoma";
-- Quickshell then leaves its own out (shell.qml).
--
-- Not yet: decoding only this screen's part of a spanned picture (the whole
-- box is decoded and this screen's part shown, as Quickshell did before it
-- measured the picture with ImageMagick); letting the hidden picture go in
-- performance mode (it is gone once covered anyway).
local g = require("@genoma")
local timing = require("core/timing")
local performance = require("core/performance")
local wallpaper = require("services/wallpaper")
local monitors = require("services/monitors")

local M = {}

-- Where this screen sits inside the box of all of them, logical units, or
-- nil when not spanning.
local function span_of(output: string): any
    if wallpaper.mode() ~= "span" then return nil end
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    local target = nil
    for _, o in monitors.outputs() do
        min_x = math.min(min_x, o.x)
        min_y = math.min(min_y, o.y)
        max_x = math.max(max_x, o.x + o.width)
        max_y = math.max(max_y, o.y + o.height)
        if o.name == output then target = o end
    end
    if not target then return nil end
    return {
        total_width = max_x - min_x,
        total_height = max_y - min_y,
        offset_x = target.x - min_x,
        offset_y = target.y - min_y,
        width = target.width,
        height = target.height,
    }
end

function M.node(output: string, size: { width: number, height: number }, backdrop: boolean): any
    local bleed = if backdrop then 96 else 0
    local density = if backdrop then 0.25 else 1
    local function source(): string return wallpaper.path_for(output) end

    -- One generation per picture shown, newest last; an older one goes once
    -- the newer has covered it.
    local generations = g.signal({} :: { any })
    local serial = 0
    g.watch(source, function(path: string)
        if path == "" then return end
        local now = g.untracked(function() return generations.value end)
        if #now > 0 and now[#now].path == path then return end
        serial += 1
        local next_list = {}
        for _, gen in now do table.insert(next_list, gen) end
        local newest = serial
        table.insert(next_list, {
            key = serial,
            path = path,
            shown = g.signal(#now == 0),
            -- Once it is there: raised, and what it covers let go after.
            ready = function()
                local list = g.untracked(function() return generations.value end)
                local gen = list[#list]
                if not gen or gen.key ~= newest then return end
                gen.shown.value = true
                g.after(timing.seconds.wallpaper + 0.1, function()
                    local now_list = g.untracked(function() return generations.value end)
                    local kept = {}
                    for _, other in now_list do
                        if other.key >= newest then table.insert(kept, other) end
                    end
                    if #kept ~= #now_list then generations.value = kept end
                end)
            end,
        })
        generations.value = next_list
    end)

    local function picture(item: () -> any): any
        local function gen(): any return item() end
        -- Spanning, the picture covers the box of every screen and this
        -- screen shows its own part: each cuts its slice out of the same
        -- covering picture, so the slices line up across the seam.
        local function box(): any
            local s = span_of(output)
            local w, h = size.width + bleed * 2, size.height + bleed * 2
            if not s then return { x = -bleed, y = -bleed, width = w, height = h } end
            local kx, ky = w / s.width, h / s.height
            return {
                x = -bleed - s.offset_x * kx,
                y = -bleed - s.offset_y * ky,
                width = s.total_width * kx,
                height = s.total_height * ky,
            }
        end
        return g.image {
            overlay = true,
            attach = "corner",
            src = function() return gen().path end,
            offset_x = function() return box().x end,
            offset_y = function() return box().y end,
            width = function() return box().width end,
            height = function() return box().height end,
            decode_width = function() return box().width * density end,
            decode_height = function() return box().height * density end,
            -- Covered, never stretched; fit letterboxes on the black below.
            fit = function() return if wallpaper.mode() == "fit" then "contain" else "cover" end,
            soften = if backdrop then 16 else 0,
            -- Not quite nothing while it waits: a transparent node is not
            -- drawn, and one not drawn is never decoded.
            opacity = function() return if gen().shown.value then 1 else 0.004 end,
            transition = { opacity = "wallpaper" },
            on_ready = function() g.untracked(gen).ready() end,
        }
    end

    return g.box {
        width = size.width,
        height = size.height,
        g.capsule {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            fill = "#000000",
            rim_top = "#00000000",
            rim_bottom = "#00000000",
        },
        g.each {
            overlay = true,
            attach = "corner",
            width = size.width,
            height = size.height,
            -- The backdrop is put away in performance mode with its
            -- wallpaper lever on: a second picture per screen, for a view a
            -- game does not open.
            present = function() return not (backdrop and performance.lever("wallpaper")) end,
            items = function() return generations.value end,
            key = function(gen: any) return tostring(gen.key) end,
            row = picture,
        },
    }
end

return M
