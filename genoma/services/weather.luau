--!strict
-- The weather where the user is (services/Weather.qml at 2cafc17).
--
-- From Open-Meteo: no key, metric units. The place is a city typed in the
-- settings (`weather.city`), geocoded once by Open-Meteo's own geocoder; its
-- name and coordinates are written back beside the city, so the next start
-- asks for the forecast straight away (Akusen's choice, 2026-10-04).
--
-- It asks only while something holds it (a weather organism on screen), and
-- then every thirty minutes, through the proxy when one is on. A reading is
-- trusted for two hours; past that it is not shown rather than shown wrong.
local g = require("@genoma")
local config = require("core/config")
local proxy = require("services/proxy")

local M = {}

local FRESH_FOR = 2 * 3600

local holders = g.signal(0)
function M.hold(on: boolean)
    holders.value = math.max(0, g.untracked(function() return holders.value end) + (if on then 1 else -1))
end
local function active(): boolean return holders.value > 0 end

local function trim(s: string): string return string.match(s or "", "^%s*(.-)%s*$") or "" end
function M.city(): string return trim(config.get("weather.city", "") or "") end
function M.place(): string
    local p = config.get("weather.place", "") or ""
    return if p ~= "" then p else M.city()
end
-- The coordinates belong to the city they were found for.
local function located(): boolean
    return config.get("weather.latitude", nil) ~= nil and config.get("weather.longitude", nil) ~= nil
        and config.get("weather.located_for", "") == M.city()
end

local problem = g.signal("")
local current = g.signal(nil :: any)
local hours = g.signal({} :: { any })
local now = g.signal(os.time())
function M.problem(): string return problem.value end
function M.current(): any return current.value end
function M.hours(): { any } return hours.value end
function M.fresh(): boolean
    local c = current.value
    return c ~= nil and now.value - c.time < FRESH_FOR
end

local function fetch(url: string, done: (string) -> ())
    local out = {}
    g.process {
        command = { "curl", "--silent", "--show-error", "--fail", "--max-time", "20", url },
        env = g.untracked(proxy.environment),
        on_line = function(line: string) table.insert(out, line) end,
        on_exit = function(code: number)
            if code ~= 0 then
                problem.value = "The weather service could not be reached."
                return
            end
            done(table.concat(out, "\n"))
        end,
    }
end

local function encode(s: string): string
    return (string.gsub(s, "[^%w%-%._~]", function(c: string) return string.format("%%%02X", string.byte(c)) end))
end

local function read(text: string)
    local ok, answer = pcall(g.parse_json, text)
    if not ok or type(answer) ~= "table" then
        problem.value = "The weather service answered with something unreadable."
        return
    end
    local c, hourly, daily = answer.current, answer.hourly, answer.daily
    if not c or not hourly or not daily then
        problem.value = "The weather service answered without a forecast."
        return
    end
    -- The hours from the next whole one, in the place's own time.
    local next = {}
    local start = 1
    for i, t in hourly.time do
        if t > c.time then
            start = i
            break
        end
    end
    for i = start, #hourly.time do
        if #next >= 5 then break end
        table.insert(next, {
            hour = tonumber(string.sub(hourly.time[i], 12, 13)) or 0,
            temperature = hourly.temperature_2m[i],
            code = hourly.weather_code[i],
            day = hourly.is_day[i] == 1,
        })
    end
    g.batch(function()
        problem.value = ""
        hours.value = next
        current.value = {
            temperature = c.temperature_2m,
            code = c.weather_code,
            day = c.is_day == 1,
            high = daily.temperature_2m_max[1],
            low = daily.temperature_2m_min[1],
            time = os.time(),
        }
        now.value = os.time()
    end)
end

local function forecast(latitude: number, longitude: number)
    fetch("https://api.open-meteo.com/v1/forecast"
        .. "?latitude=" .. latitude .. "&longitude=" .. longitude
        .. "&current=temperature_2m,weather_code,is_day"
        .. "&hourly=temperature_2m,weather_code,is_day"
        .. "&daily=temperature_2m_max,temperature_2m_min"
        .. "&forecast_days=2&timezone=auto", read)
end

local function locate()
    local asked = g.untracked(M.city)
    fetch("https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=" .. encode(asked), function(text: string)
        if asked ~= g.untracked(M.city) then return end
        local ok, answer = pcall(g.parse_json, text)
        if not ok or type(answer) ~= "table" then
            problem.value = "The weather service answered with something unreadable."
            return
        end
        local found = answer.results and answer.results[1]
        if not found then
            problem.value = "No place called “" .. asked .. "” was found."
            return
        end
        problem.value = ""
        config.set_many({
            { "weather.latitude", found.latitude },
            { "weather.longitude", found.longitude },
            { "weather.place", found.name },
            { "weather.located_for", asked },
        })
        -- The configuration lands asynchronously: asked with what was found.
        forecast(found.latitude, found.longitude)
    end)
end

local function refresh()
    now.value = os.time()
    if g.untracked(M.city) == "" then
        problem.value = "No city is set."
        return
    end
    if not g.untracked(located) then
        locate()
    else
        forecast(config.get("weather.latitude", 0), config.get("weather.longitude", 0))
    end
end
M.refresh = refresh

-- A new city forgets the old reading.
g.watch(M.city, function()
    g.batch(function()
        current.value = nil
        hours.value = {}
        problem.value = ""
    end)
end)

g.effect(function()
    if not active() or M.city() == "" then return end
    local every = math.max(5, config.get("weather.minutes", 30)) * 60
    g.untracked(refresh)
    g.timer { every = every, on_tick = refresh }
    -- The clock freshness is judged by: once a minute is enough.
    g.timer { every = 60, on_tick = function() now.value = os.time() end }
end)

-- WMO weather codes, as Open-Meteo reports them, onto the eight glyphs and
-- a sentence each.
function M.glyph_for(code: number, day: boolean): string
    if code == 0 or code == 1 then return if day then "weather-clear" else "weather-clear-night" end
    if code == 2 then return "weather-partly" end
    if code == 3 then return "weather-cloudy" end
    if code == 45 or code == 48 then return "weather-fog" end
    if (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then return "weather-rain" end
    if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "weather-snow" end
    if code >= 95 then return "weather-storm" end
    return "weather-cloudy"
end

local WORDS = {
    [0] = "Clear", [1] = "Mainly clear", [2] = "Partly cloudy", [3] = "Overcast",
    [45] = "Fog", [48] = "Rime fog",
    [51] = "Light drizzle", [53] = "Drizzle", [55] = "Heavy drizzle", [56] = "Freezing drizzle", [57] = "Freezing drizzle",
    [61] = "Light rain", [63] = "Rain", [65] = "Heavy rain", [66] = "Freezing rain", [67] = "Freezing rain",
    [71] = "Light snow", [73] = "Snow", [75] = "Heavy snow", [77] = "Snow grains",
    [80] = "Light showers", [81] = "Showers", [82] = "Violent showers", [85] = "Snow showers", [86] = "Heavy snow showers",
    [95] = "Thunderstorm", [96] = "Thunderstorm with hail", [99] = "Thunderstorm with hail",
}
function M.words_for(code: number): string return WORDS[code] or "" end

return M
