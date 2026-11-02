--!strict
-- Colour arithmetic as Qt does it (QColor's HSL, Qt.hsla, Qt.alpha), on
-- "#rrggbb" and "#rrggbbaa" strings, the form Genoma's properties take.
local M = {}

export type RGB = { r: number, g: number, b: number, a: number }

function M.parse(hex: string): RGB
    local function at(i: number): number
        return (tonumber(string.sub(hex, i, i + 1), 16) or 0) / 255
    end
    return { r = at(2), g = at(4), b = at(6), a = if #hex >= 9 then at(8) else 1 }
end

function M.format(c: RGB): string
    local function byte(v: number): string
        return string.format("%02x", math.floor(math.clamp(v, 0, 1) * 255 + 0.5))
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

function M.alpha(hex: string, a: number): string
    local c = M.parse(hex)
    c.a = a
    return M.format(c)
end

-- Rec. 709 relative luminance, good enough to pick a side.
-- Between two colours, `t` of the way from `a` to `b`, alpha included.
function M.mix(a: string, b: string, t: number): string
    local x, y = M.parse(a), M.parse(b)
    local function lerp(p: number, q: number): number return p + (q - p) * t end
    return M.format({ r = lerp(x.r, y.r), g = lerp(x.g, y.g), b = lerp(x.b, y.b), a = lerp(x.a, y.a) })
end

function M.luminance(hex: string): number
    local c = M.parse(hex)
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
end

return M
