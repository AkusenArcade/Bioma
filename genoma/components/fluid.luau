--!strict
-- The audio band as a fluid, mirrored from the centre: `plasma`, `vesicles`
-- or `eardrum` (components/Fluid.qml; read its comment for what each form
-- says). The field is components/fluid.wgsl, a Genoma shader node; this
-- takes the bars' measures and turns the two channels into its numbers.
--
-- The easing towards each value is the node's own (`follow`), at the
-- display's rate while a drop is still moving and not at all after; the
-- eardrum's clock runs only while something sounds, so a silent membrane
-- is still and draws nothing new.
local g = require("@genoma")
local colour = require("core/colour")
local paths = require("core/paths")
local theme = require("core/theme")
local timing = require("core/timing")

local M = {}

M.forms = { plasma = true, vesicles = true, eardrum = true }

local SOURCE = paths.root .. "/genoma/components/fluid.wgsl"

-- `t`: left(), right() (one spectrum per channel, 0…1, lowest first),
-- count() (drops in the row, both wings), bar_width(), pitch(), base()
-- (the colour), form(), width(), height(), present().
function M.new(t: { [string]: any }): any
    local function half(): number return t.count() // 2 end
    local function plasma(): boolean return t.form() == "plasma" end
    local function eardrum(): boolean return t.form() == "eardrum" end

    -- Where the band is tall enough, a vesicle stands for two neighbouring
    -- bands at twice the pitch; plasma and the eardrum keep one per band.
    local function step(): number
        if plasma() or eardrum() then return 1 end
        return math.max(1, math.floor(t.height() / (t.pitch() * 6) + 0.5))
    end
    local function drops(): number return math.min(t.count() // step(), 48) end
    local function spacing(): number return t.pitch() * step() end

    local function thread(): number
        return if eardrum() then math.max(1, t.bar_width() * 0.4) else t.bar_width() / 2
    end
    local function drop(): number
        if plasma() then return t.height() * 0.38 end
        return math.max(thread(), math.min(spacing() * 0.6, t.height() * 0.15))
    end

    local function value_at(index: number, left: { number }, right: { number }): number
        local h = half()
        local mirrored = index < h
        local list = if mirrored then left else right
        local place = if mirrored then h - 1 - index else index - h
        return list[place + 1] or 0
    end

    local function push_colour(out: { number }, hex: string)
        local c = colour.parse(hex)
        table.insert(out, c.r)
        table.insert(out, c.g)
        table.insert(out, c.b)
        table.insert(out, c.a)
    end

    -- The colours, as numbers: they change with the theme, not the sound.
    local colours = g.computed(function(): { number }
        local out = {}
        push_colour(out, theme.gradient_top(t.base()))
        push_colour(out, theme.gradient_bottom(t.base()))
        push_colour(out, theme.text())
        return out
    end)

    -- The numbers fluid.wgsl reads, in its order.
    local function values(): { number }
        local left, right = t.left(), t.right()
        local n, s = drops(), step()
        local out = table.create(68, 0)
        for i = 0, n - 1 do
            local v = 0
            for j = 0, s - 1 do
                v = math.max(v, value_at(i * s + j, left, right))
            end
            out[i + 1] = math.clamp(v, 0, 1)
        end
        local d = drop()
        local inset = if plasma() then d + 1 else 0
        local place = if plasma() and n > 1 then (t.width() - 2 * inset) / (n - 1) else spacing()
        local first = if plasma() then inset else t.bar_width() / 2 + (s - 1) * t.pitch() / 2
        out[49] = n
        out[50] = place
        out[51] = first
        out[52] = if plasma() then 0 elseif eardrum() then 2 else 1
        out[53] = thread()
        out[54] = d
        out[55] = d * 0.45
        out[56] = 0
        for i, v in colours.value do out[56 + i] = v end
        return out
    end

    -- Under the bars the shader is not drawn, and reads nothing.
    local function drawn(): boolean return t.present == nil or t.present() end

    local function sounding(): boolean
        if not eardrum() or not drawn() then return false end
        for _, v in t.left() do if v > 0.003 then return true end end
        for _, v in t.right() do if v > 0.003 then return true end end
        return false
    end

    return g.shader {
        src = SOURCE,
        width = t.width,
        height = t.height,
        values = function() return if drawn() then values() else {} end,
        follow = function() return math.max(timing.seconds.content_fade, 0.001) / 3 end,
        clock = sounding,
        present = t.present,
    }
end

return M
