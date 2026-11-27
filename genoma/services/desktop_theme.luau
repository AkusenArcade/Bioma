--!strict
-- The desktop's theme for every app on Genoma: Bioma writes its look to
-- Genoma's well-known file, $XDG_CONFIG_HOME/genoma/theme.json, and the
-- Genoma kit follows it by itself (kit/theme.luau in Genoma), as GTK apps
-- follow the GTK theme. An app on Genoma — OBS Touch Control, Sinestesia,
-- Rizoma, Xilema — looks like the desktop and retints with it.
--
-- What is written is the palette at rest (the destination, not the
-- crossing): the four interface roles, the alert colour for that side, and
-- whether it is dark; the radius a 32-unit control takes at the
-- Appearance's RADIUS, the panel radius, the two voices and the mono font,
-- and a terminal's sixteen colours as the templates derive them. Nothing in
-- Genoma names Bioma: any shell built on Genoma writes the same file.
--
-- Only the shell writes it (shell.luau starts this): the lock screen and
-- the greeter read the same theme, and never write it.
local g = require("@genoma")
local config = require("core/config")
local metrics = require("core/metrics")
local templates = require("services/templates")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")

local M = {}

M.path = (g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")) .. "/genoma/theme.json"

-- A control's height in the kit, whose radius the file gives: at RADIUS
-- 100 a control is a pill, as Bioma's are.
local CONTROL = 32

local function quoted(s: string): string
    return '"' .. string.gsub(s, '[%c"\\]', function(c: string): string
        return string.format("\\u%04x", string.byte(c))
    end) .. '"'
end

-- The file's text, in a fixed order: the same look is the same text, and
-- an unchanged look is not written again.
local text = g.computed(function(): string
    local dark = theme.target_is_dark()
    local colours = {
        { "background", theme.target("background") },
        { "text", theme.target("text") },
        { "primary", theme.target("primary") },
        { "secondary", theme.target("secondary") },
        { "alert", theme.target_state("alert") },
    }
    local parts = {}
    for _, pair in colours do
        table.insert(parts, `    {quoted(pair[1])}: {quoted(string.sub(pair[2], 1, 7))}`)
    end
    local terminal = templates.terminal()
    local ansi: { string } = {}
    for _, c in terminal.colours do table.insert(ansi, quoted(c)) end
    local radius = math.round(metrics.shaped(CONTROL / 2) * 10) / 10
    local panel = math.round(metrics.shaped(metrics.radius_panel) * 10) / 10
    return table.concat({
        "{",
        '  "version": 1,',
        '  "shell": "bioma",',
        `  "dark": {if dark then "true" else "false"},`,
        '  "colours": {',
        table.concat(parts, ",\n"),
        "  },",
        `  "sizes": \{ "radius": {radius}, "radius_panel": {panel} \},`,
        `  "fonts": \{ "technical": {quoted(typography.technical())}, "expressive": {quoted(typography.expressive())}, "mono": {quoted(typography.mono())} \},`,
        `  "terminal": \{ "colours": [ {table.concat(ansi, ", ")} ], "selection": {quoted(terminal.selection)} \}`,
        "}",
        "",
    }, "\n")
end)

local started = false

function M.start()
    if started then return end
    started = true
    g.lasting(function()
        local file = g.file { path = M.path, watch = false }
        local function write()
            local now = g.untracked(function() return text.value end)
            if file.text ~= now then file:write(now) end
        end
        -- Once the palette has been read (the shell settled), then whenever
        -- the look at rest changes; a colour dragged in the palette editor
        -- is written when the hand rests.
        local settled = false
        local debounce: any = nil
        g.after(timing.seconds.settle, function()
            settled = true
            write()
        end)
        g.watch(function() return text.value end, function()
            if not settled then return end
            if debounce then debounce:stop() end
            debounce = g.after(timing.seconds.blur_settle, function()
                debounce = nil
                write()
            end)
        end)
    end)
end

return M
