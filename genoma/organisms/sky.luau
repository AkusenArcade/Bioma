--!strict
-- Where the sun and the moon are (organisms/photoperiod/sky.js at 2cafc17):
-- the low-precision formulas of the astronomical almanac, as SunCalc has
-- them, good to a minute or so, which is what a picture of the day needs.
-- Times in milliseconds since the epoch; angles in degrees.
local M = {}

local RAD = math.pi / 180
local DAY_MS = 86400000
local J1970 = 2440588
local J2000 = 2451545
local OBLIQUITY = RAD * 23.4397
-- The sun's centre at the horizon when its upper limb shows, refraction
-- included.
M.HORIZON = -0.833

local function days(ms: number): number return ms / DAY_MS - 0.5 + J1970 - J2000 end
local function right_ascension(l: number, b: number): number
    return math.atan2(math.sin(l) * math.cos(OBLIQUITY) - math.tan(b) * math.sin(OBLIQUITY), math.cos(l))
end
local function declination(l: number, b: number): number
    return math.asin(math.sin(b) * math.cos(OBLIQUITY) + math.cos(b) * math.sin(OBLIQUITY) * math.sin(l))
end
local function sidereal(d: number, lw: number): number return RAD * (280.16 + 360.9856235 * d) - lw end

local function sun_coords(d: number): (number, number)
    local m = RAD * (357.5291 + 0.98560028 * d)
    local centre = RAD * (1.9148 * math.sin(m) + 0.02 * math.sin(2 * m) + 0.0003 * math.sin(3 * m))
    local longitude = m + centre + RAD * 102.9372 + math.pi
    return right_ascension(longitude, 0), declination(longitude, 0)
end

local function moon_coords(d: number): (number, number, number)
    local l = RAD * (218.316 + 13.176396 * d)
    local m = RAD * (134.963 + 13.064993 * d)
    local f = RAD * (93.272 + 13.229350 * d)
    local longitude = l + RAD * 6.289 * math.sin(m)
    local latitude = RAD * 5.128 * math.sin(f)
    return right_ascension(longitude, latitude), declination(longitude, latitude), 385001 - 20905 * math.cos(m)
end

local function horizontal(ra: number, dec: number, d: number, latitude: number, longitude: number): (number, number)
    local phi = RAD * latitude
    local hour = sidereal(d, RAD * -longitude) - ra
    local altitude = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(hour))
    local azimuth = math.atan2(math.sin(hour), math.cos(hour) * math.sin(phi) - math.tan(dec) * math.cos(phi))
    return altitude / RAD, ((azimuth / RAD + 180) % 360 + 360) % 360
end

-- { altitude, bearing } (bearing from north, clockwise).
function M.sun(ms: number, latitude: number, longitude: number): any
    local d = days(ms)
    local ra, dec = sun_coords(d)
    local altitude, bearing = horizontal(ra, dec, d, latitude, longitude)
    return { altitude = altitude, bearing = bearing }
end

function M.moon(ms: number, latitude: number, longitude: number): any
    local d = days(ms)
    local ra, dec, distance = moon_coords(d)
    local altitude, bearing = horizontal(ra, dec, d, latitude, longitude)
    local parallax = math.asin(6378 / distance) / RAD
    altitude -= parallax * math.cos(altitude * RAD)
    return { altitude = altitude, bearing = bearing }
end

-- How much of the moon is lit (0…1), and its phase (0 new, 0.5 full).
function M.moon_light(ms: number): any
    local d = days(ms)
    local sra, sdec = sun_coords(d)
    local mra, mdec, mdist = moon_coords(d)
    local sun_distance = 149598000
    local elongation = math.acos(math.sin(sdec) * math.sin(mdec) + math.cos(sdec) * math.cos(mdec) * math.cos(sra - mra))
    local incidence = math.atan2(sun_distance * math.sin(elongation), mdist - sun_distance * math.cos(elongation))
    local angle = math.atan2(math.cos(sdec) * math.sin(sra - mra),
        math.sin(sdec) * math.cos(mdec) - math.cos(sdec) * math.sin(mdec) * math.cos(sra - mra))
    return { fraction = (1 + math.cos(incidence)) / 2, phase = 0.5 + 0.5 * incidence * (if angle < 0 then -1 else 1) / math.pi }
end

function M.phase_name(phase: number): string
    local near = 1 / 29.53
    if phase < near or phase > 1 - near then return "New moon" end
    if math.abs(phase - 0.25) < near then return "First quarter" end
    if math.abs(phase - 0.5) < near then return "Full moon" end
    if math.abs(phase - 0.75) < near then return "Last quarter" end
    if phase < 0.25 then return "Waxing crescent" end
    if phase < 0.5 then return "Waxing gibbous" end
    if phase < 0.75 then return "Waning gibbous" end
    return "Waning crescent"
end

function M.path(body: (number, number, number) -> any, from: number, to: number, step: number, latitude: number, longitude: number): { any }
    local out = {}
    local t = from
    while t <= to do
        local p = body(t, latitude, longitude)
        table.insert(out, { time = t, altitude = p.altitude, bearing = p.bearing })
        t += step
    end
    return out
end

-- Where a sampled path crosses the horizon, interpolated.
function M.crossings(samples: { any }): { any }
    local out = {}
    for i = 2, #samples do
        local a = samples[i - 1].altitude - M.HORIZON
        local b = samples[i].altitude - M.HORIZON
        if (a < 0) ~= (b < 0) then
            local k = a / (a - b)
            table.insert(out, { time = samples[i - 1].time + k * (samples[i].time - samples[i - 1].time), rising = b > 0 })
        end
    end
    return out
end

function M.daylight(altitude: number): boolean return altitude > M.HORIZON end

return M
