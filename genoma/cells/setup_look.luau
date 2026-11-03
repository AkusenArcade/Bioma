--!strict
-- The setup's look step (cells/settings/SetupLook.qml at 2cafc17): the
-- palette, the wallpaper, and whether other applications wear them. See
-- docs/design/SETUP.md, step 2.
--
-- Everything here is the theme cell's, offered once in the order a newcomer
-- decides it; the theme is animated, so the desktop retints while the
-- choice is made. Other applications are off until asked for: their
-- configurations are somebody's own, and one switch here turns on every
-- target the theme cell lists for what is installed.
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local theme = require("core/theme")
local page = require("components/page")
local segmented = require("components/segmented")
local choice = require("components/choice")
local switch = require("components/switch")
local wallpaper = require("services/wallpaper")
local focus = require("structure/focus")
local templates = require("services/templates")
local setup = require("services/setup")

local M = {}

function M.new(t: { [string]: any }): any
    local p = page.new(t)
    local f = p.factor
    local function m(): any return t.metrics() end
    local function from_wallpaper(): boolean return theme.source() == "matugen" end
    local function variant(): string return config.get("theme.matugen.variant", "dark") end
    -- What is on screen already counts as an answer.
    g.effect(function()
        local line = if from_wallpaper() then "From the wallpaper, " .. variant() else theme.palette_name()
        g.untracked(function() setup.note("look", line) end)
    end)

    -- The applications a switch here would colour: installed, and not niri,
    -- which is on from the start.
    local function apps(): { any }
        local out = {}
        for _, entry in templates.catalogue() do
            if entry.installed and entry.id ~= "niri" then table.insert(out, entry) end
        end
        return out
    end
    local function apps_on(): boolean
        local list = apps()
        if #list == 0 then return false end
        for _, entry in list do
            if not templates.is_on(entry.id) then return false end
        end
        return true
    end

    local function choices(list: () -> { any }, current: () -> string, on_choose: (string) -> ()): any
        return segmented.new {
            metrics = m,
            font_size = function() return m().font_meta end,
            options = list,
            current = current,
            on_choose = on_choose,
        }
    end

    local function thumb(offset: number): any
        local function path(): string return wallpaper.neighbour(offset) end
        local here = offset == 0
        local function w(): number return 76 * f() end
        local function h(): number return 48 * f() end
        local function radius(): number return metrics_mod.shaped(6 * f()) end
        return g.box {
            role = if here then nil else "button",
            name = "Wallpaper",
            present = function() return path() ~= "" and (here or #wallpaper.entries() > 1) end,
            width = w,
            height = h,
            on_click = if here then nil else function() wallpaper.step(offset) end,
            g.image {
                overlay = true,
                attach = "corner",
                width = w,
                height = h,
                radius = radius,
                fit = "cover",
                opacity = if here then 1 else 0.55,
                src = function() return wallpaper.thumbnail(path()) end,
            },
            g.capsule {
                overlay = true,
                attach = "corner",
                width = w,
                height = h,
                radius = radius,
                fill = "#00000000",
                rim_top = function() return if here then theme.primary() else colour.alpha(theme.line(), 0.7) end,
                rim_bottom = function() return if here then theme.primary() else colour.alpha(theme.line(), 0.7) end,
            },
        }
    end

    return p.column {
        p.section("PALETTE", choices(
            function() return { { key = "manual", label = "Bioma" }, { key = "matugen", label = "Wallpaper" } } end,
            theme.source,
            function(key: string) config.set("theme.source", key) end
        ), {
            g.box {
                present = function() return not from_wallpaper() end,
                choices(function()
                    local out = {}
                    for _, palette in theme.palettes() do table.insert(out, { key = palette.file, label = palette.name }) end
                    return out
                end, theme.manual_palette, function(key: string) config.set("theme.palette", key) end),
            },
            g.box {
                present = from_wallpaper,
                choices(function() return { { key = "dark", label = "Dark" }, { key = "light", label = "Light" } } end,
                    variant, function(key: string) config.set("theme.matugen.variant", key) end),
            },
            p.line(function()
                return if from_wallpaper() then "The colours are taken from the wallpaper, and change with it."
                    else "One of Bioma's palettes, the same whatever the wallpaper."
            end),
        }),
        p.section("WALLPAPER", choice.new {
            metrics = m,
            label = function() return if wallpaper.picking() then "CHOOSING" else "FOLDER" end,
            dimmed = wallpaper.picking,
            -- The settings step aside for the chooser and come back to
            -- show the folder's pictures.
            on_click = function()
                local c = focus.open_cell()
                if c then focus.aside(c, function(done) wallpaper.pick_folder(done) end) else wallpaper.pick_folder() end
            end,
        }, {
            -- The folder's pictures, the one on screen in the middle. A
            -- press on another puts it on the desktop.
            g.box {
                direction = "row",
                gap = function() return 8 * f() end,
                thumb(-2), thumb(-1), thumb(0), thumb(1), thumb(2),
            },
            p.line(function()
                local err = wallpaper.folder_error()
                if err ~= "" then return err end
                if #wallpaper.entries() == 0 then return "No pictures in this folder yet. Bioma's own is on the desktop." end
                return "From " .. string.gsub(wallpaper.folder(), "^/home/[^/]+", "~") .. ". The theme cell has the rest of them."
            end, function() return if wallpaper.folder_error() ~= "" then theme.alert() else theme.text() end),
        }),
        p.section("OTHER APPLICATIONS", switch.new {
            factor = f,
            on = apps_on,
            on_toggle = function(value: boolean)
                for _, entry in g.untracked(apps) do templates.set_on(entry.id, value) end
            end,
        }, {
            p.line(function()
                if apps_on() then
                    local names = {}
                    for _, entry in apps() do table.insert(names, entry.name) end
                    return "The palette reaches " .. table.concat(names, ", ") .. ". Each is switched on or off on its own under APPS in the theme cell (Mod+Alt+T)."
                end
                return "Off: other applications keep their own colours. Switched on, the palette is written into their configurations — each one can be turned back off in the theme cell."
            end),
        }, function() return #apps() > 0 end),
    }
end

return M
