--!strict
-- Colour arithmetic as Qt does it (QColor's HSL, Qt.hsla, Qt.alpha), on
-- "#rrggbb" and "#rrggbbaa" strings, the form Genoma's properties take.
-- The string-to-string operations are Genoma's `g.colour`, ported from this
-- file and equal to it to the byte (10 000 random cases, 2026-11-16) at a
-- quarter of the cost; the RGB tables the theme's arithmetic works on stay
-- here.
local g = require("@genoma")

local M = {}

export type RGB = { r: number, g: number, b: number, a: number }

function M.parse(hex: string): RGB
    local function at(i: number): number
        return (tonumber(string.sub(hex, i, i + 1), 16) or 0) / 255
    end
    return { r = at(2), g = at(4), b = at(6), a = if #hex >= 9 then at(8) else 1 }
end

-- Rounded as Qt rounds: a channel is kept in sixteen bits and named in
-- eight by QColor's division by 257, so a value exactly between two bytes
-- falls the way Qt's does (a palette mixed half and half for GTK differed
-- by one there).
function M.format(c: RGB): string
    local function byte(v: number): string
        local wide = math.floor(math.clamp(v, 0, 1) * 65535 + 0.5)
        return string.format("%02x", bit32.rshift(wide - bit32.rshift(wide, 8) + 0x80, 8))
    end
    return "#" .. byte(c.r) .. byte(c.g) .. byte(c.b) .. byte(c.a)
end

-- Hue 0…1, -1 for an achromatic colour (QColor's hslHue), saturation and
-- lightness 0…1.
function M.hsl(c: RGB): (number, number, number)
    local max, min = math.max(c.r, c.g, c.b), math.min(c.r, c.g, c.b)
    local l = (max + min) / 2
    if max == min then return -1, 0, l end
    local d = max - min
    local s = if l > 0.5 then d / (2 - max - min) else d / (max + min)
    local h
    if max == c.r then
        h = (c.g - c.b) / d + (if c.g < c.b then 6 else 0)
    elseif max == c.g then
        h = (c.b - c.r) / d + 2
    else
        h = (c.r - c.g) / d + 4
    end
    return h / 6, s, l
end

function M.hsla(h: number, s: number, l: number, a: number): RGB
    if s == 0 then return { r = l, g = l, b = l, a = a } end
    local function channel(p: number, q: number, t: number): number
        t = t % 1
        if t < 1 / 6 then return p + (q - p) * 6 * t end
        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end
    local q = if l < 0.5 then l * (1 + s) else l + s - l * s
    local p = 2 * l - q
    return { r = channel(p, q, h + 1 / 3), g = channel(p, q, h), b = channel(p, q, h - 1 / 3), a = a }
end

-- Qt.alpha(colour, a).
-- Hue 0…1, -1 for an achromatic colour (QColor's hsvHue), saturation and
-- value 0…1.
function M.hsv(c: RGB): (number, number, number)
    local max, min = math.max(c.r, c.g, c.b), math.min(c.r, c.g, c.b)
    local d = max - min
    local s = if max > 0 then d / max else 0
    if d == 0 then return -1, s, max end
    local h
    if max == c.r then h = ((c.g - c.b) / d) % 6
    elseif max == c.g then h = (c.b - c.r) / d + 2
    else h = (c.r - c.g) / d + 4 end
    return h / 6, s, max
end

-- Qt.hsva: hue, saturation, value and alpha 0…1.
function M.hsva(h: number, s: number, v: number, a: number): RGB
    local i = math.floor(h * 6) % 6
    local fr = h * 6 - math.floor(h * 6)
    local p, q, t = v * (1 - s), v * (1 - fr * s), v * (1 - (1 - fr) * s)
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return { r = r, g = g, b = b, a = a }
end

-- A pure function of two values, remembered: during a palette's crossing
-- every binding asks for the same few colours each step, and working each
-- out again (parse, HSL, format) for every one of them filled the frame
-- (Akusen, 2026-11-03: "the theme change stutters"). Bounded: emptied when
-- it grows past what a few steps ask for.
function M.remembered<A, B>(f: (A, B) -> string): (A, B) -> string
    local store: { [string]: string } = {}
    local count = 0
    return function(a: A, b: B): string
        local key = tostring(a) .. "|" .. tostring(b)
        local hit = store[key]
        if hit then return hit end
        if count >= 1024 then
            store, count = {}, 0
        end
        local value = f(a, b)
        store[key] = value
        count += 1
        return value
    end
end

-- Remembered still: a hit costs as little as before, a miss a quarter.
M.alpha = M.remembered(g.colour.alpha)

-- Between two colours, `t` of the way from `a` to `b`, alpha included, in
-- Qt's own arithmetic, a·(1−t) + b·t.
M.mix = g.colour.mix

-- A mix computed as QML computes `Qt.rgba(a.r * (1 - t) + b.r * t, …)`, to
-- the byte: Qt 6 hands channels out as 32-bit floats (QColor::redF), JS
-- mixes them in doubles, and setRgbF takes a float again and keeps sixteen
-- bits. Where the files written for other applications must say what Bioma
-- on Quickshell said (services/templates.luau), not where colours move.
local function f32(x: number): number return (string.unpack("f", string.pack("f", x))) end
function M.qt_mix(a: RGB, b: RGB, t: number): string
    local function channel(p: number, q: number): string
        local v = f32(p) * (1 - t) + f32(q) * t
        local wide = math.floor(f32(f32(f32(math.clamp(v, 0, 1)) * 65535) + 0.5))
        return string.format("%02x", bit32.rshift(wide - bit32.rshift(wide, 8) + 0x80, 8))
    end
    return "#" .. channel(a.r, b.r) .. channel(a.g, b.g) .. channel(a.b, b.b)
end

-- Rec. 709 weights on the encoded channels, good enough to pick a side.
M.luminance = g.colour.luma

return M
