--!strict
-- niri's configuration, as files (services/NiriConfig.qml): every file
-- `config.kdl` includes, read and followed, and what they say in the order
-- niri reads it, each item carrying the file it came from. What to do with
-- the items is the business of the services built on this one (Monitors,
-- and later Keybinds).
--
-- Writing, through `niri validate` before anything lands, comes with the
-- first service that writes (Monitors' editing, in settings).
local g = require("@genoma")
local kdl = require("services/niri_kdl")

local M = {}

local home = g.env("HOME") or ""
-- Where niri itself would look.
M.main = g.env("NIRI_CONFIG") or ((g.env("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/niri/config.kdl")

-- Every file found so far. It starts with the main one and grows as the
-- includes are read, since what a file includes is known once it is read.
local files: { [string]: any } = {}
local found = g.signal(0)

local function open(path: string)
    if not files[path] then
        files[path] = g.file { path = path }
        found.value += 1
    end
end
open(M.main)

-- Walk the configuration the way niri does: a file's items in the order
-- they are written, an include expanded where it stands.
local walked = g.computed(function(): { [string]: any }
    local _ = found.value
    local items, missing, seen, texts = {}, {}, {}, {}
    local function walk(path: string)
        if seen[path] then return end
        seen[path] = true
        local file = files[path]
        if not file then
            table.insert(missing, path)
            return
        end
        local text = file.text
        if text == nil then return end
        table.insert(texts, { path = path, text = text })
        for _, item in kdl.scan(text).items do
            if item.kind == "include" then
                walk(kdl.resolve(item.path, kdl.directory_of(path), home))
            else
                item.file = path
                table.insert(items, item)
            end
        end
    end
    walk(M.main)
    return { items = items, missing = missing, texts = texts }
end)

-- A file named for the first time is opened, and the walk runs again.
g.watch(function() return walked.value.missing end, function(missing: { string })
    for _, path in missing do open(path) end
end)

-- Every output section (and, as their services come, every bind and rule),
-- in the order niri reads them.
function M.items(): { any } return walked.value.items end

-- Whether every file the configuration reaches has been read.
function M.ready(): boolean return #walked.value.missing == 0 end

-- Every file's text, each before the files it includes (includes usually
-- close a configuration, so what they set is what stands).
function M.texts(): { { path: string, text: string } } return walked.value.texts end

function M.text_of(path: string): string?
    local file = files[path]
    return if file then file.text else nil
end

return M
