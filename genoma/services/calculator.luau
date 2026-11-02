--!strict
-- Sums and conversions, answered in the launcher's field (services/
-- Calculator.qml at 2cafc17).
--
-- `qalc` does the arithmetic, the units and the currencies: one process
-- per question is cheaper than one kept alive all day for the few the
-- launcher will ever ask. It runs in the C locale: a decimal comma in a
-- result would be a different number once pasted somewhere that reads a
-- point.
--
-- The hard part is whether there is a question. qalc makes something of
-- anything ("firefox" comes back as a quantity of bytes), and the first row
-- is the one Enter takes, so a query is a question only when it says so:
-- figures joined by an operator, a conversion (`to`, `in`), a function
-- called, or a leading `=` that asks outright. A word in it must be one of
-- those, or a constant; a name with a figure in it (`gnome-2048`, `7zip`)
-- is an application.
local g = require("@genoma")
local timing = require("core/timing")

local M = {}

local query = g.signal("")
local answer = g.signal("")
local answered = g.signal("")

-- Words a calculation may hold without a call or a conversion to vouch
-- for it.
local CONSTANTS = { pi = true, e = true, tau = true, phi = true, ["π"] = true, ["τ"] = true, ["φ"] = true,
    ["and"] = true, ["or"] = true, ["not"] = true, mod = true, rem = true, xor = true }

local function trim(s: string): string return string.match(s, "^%s*(.-)%s*$") or "" end

-- The expression to hand qalc, or "" when the query is not a question.
function M.question(text: string): string
    local t = trim(text)
    if string.sub(t, 1, 1) == "=" then return trim(string.sub(t, 2)) end
    if not string.find(t, "%d") then return "" end
    -- A trailing operator is a sum still being typed: qalc would answer
    -- "5 +" with 5, and the row would flicker a wrong figure.
    if string.find(t, "[%+%-%*/%^,%.]%s*$") or string.find(t, "×%s*$") or string.find(t, "÷%s*$") then return "" end

    -- A conversion starts from a quantity: "h264 to mp4" is a question
    -- about files, not units.
    local lowered = string.lower(t)
    local converts = string.find(t, "^[%-%+%(]?%s*[%d%.]") ~= nil
        and (string.find(lowered, "%sto%s+%S") ~= nil or string.find(lowered, "%sin%s+%S") ~= nil)
    local operates = string.find(t, "[%d%)]%s*[%+%-%*/%^%%<>=!]") ~= nil
        or string.find(t, "[%+%-%*/%^]%s*[%d%(]") ~= nil
        or string.find(t, "[%d%)]%s*[×÷]") ~= nil or string.find(t, "[×÷]%s*[%d%(]") ~= nil
        or string.find(t, "[πτφ]%s*[%+%-%*/%^]") ~= nil
    local calls = string.find(t, "[%a_][%w_]*%s*%(") ~= nil
    if not converts and not operates and not calls then return "" end

    if not converts then
        local bare = string.gsub(t, "[%a_][%w_]*%s*%(", "(")
        for word in string.gmatch(bare, "[%a_]+") do
            if not CONSTANTS[string.lower(word)] then return "" end
        end
    end
    return t
end

local function asked(): boolean return M.question(query.value) ~= "" end
function M.result(): string
    return if asked() and answered.value == query.value then answer.value else ""
end
-- Between asking and the answer: the launcher says nothing answers only
-- once it knows.
function M.pending(): boolean return asked() and answered.value ~= query.value end

-- What qalc gives back when it understood nothing: the question itself, or
-- a function it could not evaluate left standing in the answer.
local function valid(expression: string, out: string): boolean
    if out == "" or string.find(out, "\n") then return false end
    local function flat(s: string): string
        return string.lower((string.gsub(string.gsub(s, "%s+", ""), "−", "-")))
    end
    if flat(out) == flat(expression) then return false end
    return not string.find(out, "[%a_]%(")
end

-- qalc reads its rates from a file it refreshes only when told to: once a
-- day, on the first question, in the background.
local refreshed = ""
local function refresh_rates()
    local today = os.date("%Y-%m-%d") :: string
    if refreshed == today then return end
    refreshed = today
    g.process { command = { "sh", "-c",
        'rates="${XDG_DATA_HOME:-$HOME/.local/share}/qalculate/rates.json"; '
        .. '[ -n "$(find "$rates" -mmin -1440 2>/dev/null)" ] || exec qalc -e -t 0 >/dev/null 2>&1' } }
end

local settle: any = nil
local function ask()
    refresh_rates()
    local asking = g.untracked(function() return query.value end)
    local expression = M.question(asking)
    local lines = {}
    g.process {
        command = { "qalc", "-t", "--", expression },
        env = { LC_ALL = "C" },
        on_line = function(line: string) table.insert(lines, line) end,
        on_exit = function()
            if g.untracked(function() return query.value end) ~= asking then return end
            local out = trim(table.concat(lines, "\n"))
            g.batch(function()
                answer.value = if valid(expression, out) then out else ""
                answered.value = asking
            end)
        end,
    }
end

function M.ask(text: string)
    query.value = text
    if settle then settle:stop() end
    settle = nil
    if M.question(text) == "" then
        g.batch(function()
            answer.value = ""
            answered.value = text
        end)
        return
    end
    settle = g.after(timing.seconds.search, function()
        settle = nil
        ask()
    end)
end

-- The result alone, as it would be typed: a currency's symbol and a unit
-- stay, because "34.2" without "$" is not what was asked for.
function M.copy()
    local r = g.untracked(M.result)
    if r ~= "" then g.process { command = { "wl-copy", "--type", "text/plain", "--", r } } end
end

return M
