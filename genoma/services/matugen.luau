--!strict
-- The palette from the wallpaper (services/Matugen.qml at 8ed8892): matugen
-- run on the current picture, rendering Bioma's own template into the
-- configuration directory, where core/theme.luau watches the file. Nothing
-- is handed over and matugen's output format is never read.
--
-- Bioma on Genoma alone runs it (M6 step 7a); beside Quickshell, Quickshell
-- does, and this is not started.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local theme = require("core/theme")
local timing = require("core/timing")
local wallpaper = require("services/wallpaper")

local M = {}

local function enabled(): boolean return config.get("theme.source", "manual") == "matugen" end
-- dark | light | smart: which mode the template's `default` resolves to.
local function variant(): string return config.get("theme.matugen.variant", "dark") end
local function scheme(): string return config.get("theme.matugen.scheme", "scheme-tonal-spot") end
-- An image offers several candidate colours; by dominance, the choice is
-- the same every time, and matugen 4 asks otherwise, which from a process
-- with no terminal is an error.
local function source_index(): number return config.get("theme.matugen.source_color_index", 0) end

local last_error = g.signal("")
function M.last_error(): string return last_error.value end

-- matugen reports a failure as a numbered chain, deepest cause last: that
-- one is worth showing, not the lines about backtraces after it.
local function root_cause(lines: { string }): string
    for i = #lines, 1, -1 do
        local cause = string.match(lines[i], "^%s*%d+:%s*(.*)$")
        if cause then return cause end
    end
    return lines[1] or ""
end

-- The configuration matugen is given: Bioma's template, rendered to the very
-- file core/theme.luau watches. Not config/matugen/config.toml as it is,
-- whose `~/.config/…` is the home's: with XDG_CONFIG_HOME elsewhere (a test
-- of another configuration), matugen wrote the person's own palette and
-- the shell watched a file nobody wrote. Written once a session.
local function quoted(s: string): string
    return '"' .. string.gsub(string.gsub(s, "\\", "\\\\"), '"', '\\"') .. '"'
end
local own_config: string? = nil
local function config_path(): string
    if own_config then return own_config end
    local path = (g.env("XDG_RUNTIME_DIR") or "/tmp") .. "/bioma-matugen.toml"
    g.file({ path = path, watch = false }):write(table.concat({
        "# Written by Bioma's services/matugen.luau for this session.",
        "[config]",
        "",
        "[templates.palette]",
        "input_path = " .. quoted(paths.root .. "/config/matugen/palette.json"),
        "output_path = " .. quoted(theme.matugen_path),
        "",
    }, "\n"))
    own_config = path
    return path
end

local running: any = nil
local function run(image: string)
    -- A run still going is stopped for this one; its exit is not this run
    -- failing.
    if running then
        running.superseded = true
        running.process:kill()
    end
    local errors = {}
    local this = { superseded = false, process = nil :: any }
    running = this
    this.process = g.process {
        command = { "matugen", "--config", config_path(), "--mode", g.untracked(variant),
            "--type", g.untracked(scheme), "--source-color-index", tostring(g.untracked(source_index)), "image", image },
        cwd = paths.root .. "/config/matugen",
        on_error_line = function(line: string)
            local plain = string.match((string.gsub(line, "\27%[[%d;]*m", "")), "^%s*(.-)%s*$") or ""
            if plain ~= "" then table.insert(errors, plain) end
        end,
        on_exit = function(code: number)
            if this.superseded then return end
            if running == this then running = nil end
            if code == 0 then
                last_error.value = ""
            else
                local cause = root_cause(errors)
                last_error.value = if cause ~= "" then cause else "matugen exited " .. code
                print("Matugen: " .. last_error.value)
            end
        end,
    }
end

-- The theme cell retints on hover, so pictures can arrive faster than
-- matugen answers: only the last is generated.
local pending: any = nil
function M.generate(image: string)
    if not g.untracked(enabled) or image == "" then return end
    if pending then pending:stop() end
    pending = g.after(timing.seconds.theme, function()
        pending = nil
        run(image)
    end)
end

local started = false
function M.start()
    if started then return end
    started = true
    -- The wallpaper is the only input; a new variant or scheme generates
    -- again from the picture there is. And when the palette matugen left
    -- was made from another picture (the source set back to matugen after
    -- the wallpaper changed under a manual palette), it is made again.
    local before: any = nil
    g.watch(function()
        return { image = wallpaper.current(), variant = variant(), scheme = scheme(), source = enabled() }
    end, function(now: any)
        local was = before
        before = now
        if not now.source or now.image == "" then return end
        -- At start too, as Quickshell's does when its wallpaper loads.
        local asked = was == nil or now.image ~= was.image or now.variant ~= was.variant or now.scheme ~= was.scheme
        local made = g.untracked(function() return theme.generated_image.value end)
        local stale = made ~= "" and made ~= now.image
        if asked or stale then M.generate(now.image) end
    end)
end

return M
