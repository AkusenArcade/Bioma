--!strict
-- niri's configuration, as files (services/NiriConfig.qml): every file
-- `config.kdl` includes, read and followed, and what they say in the order
-- niri reads it, each item carrying the file it came from. What to do with
-- the items is the business of the services built on this one (Monitors,
-- and later Keybinds).
--
-- Writing has one rule: nothing is written that niri would refuse. A write
-- names the file, its new text, and the part niri should look at; that part
-- goes through `niri validate` on its own first, and the file is written
-- only when niri accepts it, so a mistake shows in the settings as a
-- sentence and not as an error in the running compositor. niri watches
-- every included file and reloads by itself.
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

-- ---- Writing ------------------------------------------------------------------

-- The last thing niri refused, in its words; cleared by the next write it
-- accepts. Bumped after every write that landed.
local refused = g.signal("")
local written = g.signal(0)
local busy = g.signal(false)
function M.error(): string return refused.value end
function M.set_error(text: string) refused.value = text end
function M.written(): number return written.value end
function M.busy(): boolean return busy.value end

-- niri explains itself in a boxed, coloured diagnostic that opens with the
-- same generic lines every time; what it objects to is the last marked line
-- after them ("invalid key: Foo").
local GENERIC = { ["error loading config"] = true, ["error parsing"] = true, ["error parsing KDL"] = true }
local function reason(output: string): string
    local plain = string.gsub(output, "\27%[[%d;]*m", "")
    local found = ""
    for line in string.gmatch(plain, "[^\n]+") do
        local marked = string.match(line, "×%s+(.*)$") or string.match(line, "╰─▶%s+(.*)$")
        if marked then
            marked = string.match(marked, "^%s*(.-)%s*$") or ""
            if not GENERIC[marked] then found = marked end
        end
    end
    return if found ~= "" then "niri refused it: " .. found else "niri refused it."
end

-- One write at a time, in order: a page that moves two monitors asks for two
-- files, and the second goes once the first has landed. What was queued
-- after a refusal was built on it, and is dropped.
local queue: { any } = {}
local function next_write()
    if g.untracked(function() return busy.value end) or #queue == 0 then return end
    local job = table.remove(queue, 1)
    busy.value = true
    local said = {}
    local p = g.process {
        command = { "niri", "validate", "-c", "/dev/stdin" },
        on_line = function() end,
        on_error_line = function(line: string) table.insert(said, line) end,
        on_exit = function(code: number)
            busy.value = false
            if code ~= 0 then
                refused.value = reason(table.concat(said, "\n"))
                queue = {}
                return
            end
            local file = files[job.file] or g.file { path = job.file }
            local ok, why = pcall(function() file:write(job.text) end)
            if not ok then
                refused.value = "niri's configuration could not be written."
                print("Bioma: " .. tostring(why))
                queue = {}
                return
            end
            refused.value = ""
            written.value += 1
            next_write()
        end,
    }
    p:write(job.checked)
    p:close_input()
end

function M.write(file: string, text: string, checked: string)
    table.insert(queue, { file = file, text = text, checked = checked })
    next_write()
end

return M
