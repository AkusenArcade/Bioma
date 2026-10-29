--!strict
-- What the browsers are downloading (services/Downloads.qml at 11bb81e):
-- the partial files growing in the downloads folder, through
-- `scripts/downloads`, which watches it with inotify. Run only while a cell
-- holds it.
local g = require("@genoma")
local paths = require("core/paths")

local M = {}

local holders: { [any]: boolean } = {}
local held = g.signal(0)
local files = g.signal({})

function M.hold(owner: any, wanted: boolean)
    local was = holders[owner] == true
    if wanted == was then return end
    holders[owner] = if wanted then true else nil
    local n = 0
    for _ in holders do n += 1 end
    held.value = n
end

g.effect(function()
    if held.value == 0 then
        g.untracked(function() files.value = {} end)
        return
    end
    g.untracked(function()
        local function watch()
            g.process {
                command = { paths.script("downloads") },
                on_line = function(line: string)
                    local ok, list = pcall(g.parse_json, line)
                    if ok and type(list) == "table" then files.value = list end
                end,
                on_exit = function()
                    files.value = {}
                    g.after(5, function() if g.untracked(function() return held.value end) > 0 then watch() end end)
                end,
            }
        end
        watch()
    end)
end)

-- { { path, name, size, rate } }: bytes so far and bytes a second.
function M.files(): { any } return files.value end
function M.downloading(): boolean return #files.value > 0 end
function M.rate(): number
    local sum = 0
    for _, f in files.value do sum += f.rate or 0 end
    return sum
end

function M.bytes(value: number): string
    if value >= 1024 ^ 3 then return string.format("%.1f GB", value / 1024 ^ 3) end
    if value >= 1024 ^ 2 then
        return string.format(if value >= 10 * 1024 ^ 2 then "%.0f MB" else "%.1f MB", value / 1024 ^ 2)
    end
    if value >= 1024 then return string.format("%d KB", math.floor(value / 1024 + 0.5)) end
    return string.format("%d B", math.floor(value + 0.5))
end

-- The file shown where it is, by the file manager; the folder opened where
-- there is none that answers.
function M.reveal(path: string)
    local uri = "file://" .. string.gsub(path, "[^%w%-%._~/]", function(c: string) return string.format("%%%02X", string.byte(c)) end)
    local folder = string.match(path, "^(.*)/[^/]*$") or "/"
    g.process { command = { "setsid", "-f", "sh", "-c",
        'gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 '
        .. '--method org.freedesktop.FileManager1.ShowItems "[\'$1\']" "" >/dev/null 2>&1 '
        .. '|| exec "$2" --id xdg-open -- xdg-open "$3"',
        "reveal", uri, paths.script("launch"), folder } }
end

return M
