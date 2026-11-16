--!strict
-- Removable drives, and whether they are being written to (services/
-- Drives.qml at 11bb81e), on Genoma's `@genoma/drives` since Genoma 0.1.16:
-- udisks followed through its signals, the write rate and free space read
-- once a second only while something is mounted. What is Bioma's: how a
-- drive is opened (mounted, then shown in the file manager as a service
-- of its own), and how a failure is said.
--
-- A check without a stick in the machine mocks the service:
-- `genoma snapshot --mock @genoma/drives=<file>`.
local g = require("@genoma")
local config = require("core/config")
local paths = require("core/paths")
local native = require("@genoma/drives")

local M = {}

-- Kept for the cells that hold the service while they show: Genoma reads
-- nothing by the second unless a drive is mounted, so holding costs nothing.
function M.hold(_owner: any, _wanted: boolean) end

g.effect(function()
    native:include_loops(config.get("drives.include_loop", false) == true)
end)

function M.drives(): { any } return native.list end
function M.attached(): boolean return #native.list > 0 end
function M.rate(): number
    local sum = 0
    for _, d in native.list do sum += d.rate or 0 end
    return sum
end
function M.writing(d: any): boolean return d ~= nil and (d.rate or 0) >= 4096 end
function M.mounted(d: any): boolean
    for _, v in (if d then d.volumes else nil) or {} do
        if #(v.mounts or {}) > 0 then return true end
    end
    return false
end
function M.size(d: any): number
    local sum = 0
    for _, v in (if d then d.volumes else nil) or {} do sum += v.size or 0 end
    return sum
end
-- How much of it is used, 0 to 1, over its mounted volumes whose free
-- space Genoma has read; 0 while none is.
function M.used(d: any): number
    local size, free = 0, 0
    for _, v in (if d then d.volumes else nil) or {} do
        if #(v.mounts or {}) > 0 and v.free ~= nil and (v.size or 0) > 0 then
            size += v.size
            free += v.free
        end
    end
    return if size > 0 then math.clamp(1 - free / size, 0, 1) else 0
end

local function reason(lines: { string }): string
    local text = table.concat(lines, "\n")
    local said = string.lower(text)
    if string.find(said, "busy", 1, true) then return "In use — close what has a file open on it" end
    if string.find(said, "not authorized", 1, true) or string.find(said, "dismissed", 1, true) then return "Not allowed" end
    local last = ""
    for _, l in lines do
        local t = string.match(l, "^%s*(.-)%s*$") or ""
        if t ~= "" then last = t end
    end
    return if last ~= "" then (string.gsub(last, "^Error [^:]*:%s*", "")) else "It did not answer"
end

-- Opening is Bioma's (Genoma only mounts), so it is marked here; what
-- Genoma is doing comes with the drive.
local opening = g.signal({} :: { [string]: boolean })
local failed = g.signal({} :: { [string]: string })
local function entry(id: string): any
    for _, d in native.list do if d.id == id then return d end end
    return nil
end
-- What each drive is doing ("opening", "ejecting") and why it could not.
function M.busy(id: string): string
    if opening.value[id] then return "opening" end
    local d = entry(id)
    local doing = if d then d.busy else ""
    if doing == "mounting" then return "opening" end
    return doing
end
function M.error(id: string): string
    if failed.value[id] then return failed.value[id] end
    local d = entry(id)
    return if d and d.error ~= "" then reason({ d.error }) else ""
end
local function mark(id: string, on: boolean, problem: string?)
    local o = table.clone(g.untracked(function() return opening.value end))
    o[id] = if on then true else nil
    opening.value = o
    local f = table.clone(g.untracked(function() return failed.value end))
    f[id] = problem
    failed.value = f
end

-- Mounted if it is not, then shown in the file manager, as its own service.
function M.open(d: any, env: { [string]: string }?)
    if not d or g.untracked(function() return M.busy(d.id) end) ~= "" then return end
    local volume = d.volumes[1]
    if not volume then return end
    mark(d.id, true, nil)
    local function show(at: string)
        mark(d.id, false, nil)
        g.process { command = { paths.script("launch"), "--id", "xdg-open", "--", "xdg-open", at }, env = env }
    end
    if #(volume.mounts or {}) > 0 then
        show(volume.mounts[1])
        return
    end
    local ok, why = pcall(function() native:mount(volume.device) end)
    if not ok then
        mark(d.id, false, reason({ tostring(why) }))
        return
    end
    -- Shown once the mount appears; Genoma's own error ends the wait. A
    -- watch cannot be stopped, so it answers once and is quiet after.
    local answered = false
    g.lasting(function()
        g.watch(function()
            local now = entry(d.id)
            for _, v in (if now then now.volumes else nil) or {} do
                if v.device == volume.device and #(v.mounts or {}) > 0 then return v.mounts[1] end
            end
            return if now and now.busy == "" and now.error ~= "" then "!" else ""
        end, function(at: string)
            if at == "" or answered then return end
            answered = true
            if at == "!" then mark(d.id, false, nil) else show(at) end
        end)
    end)
end

-- Unmounting waits for the last of the writing; then the power goes, so the
-- drive leaves the list when it really is safe to pull.
function M.eject(d: any)
    if not d or g.untracked(function() return M.busy(d.id) end) ~= "" then return end
    mark(d.id, false, nil)
    local ok, why = pcall(function() native:eject(d.id) end)
    if not ok then mark(d.id, false, reason({ tostring(why) })) end
end

function M.bytes(value: number): string
    if value >= 1e9 then return string.format(if value >= 10e9 then "%.0f GB" else "%.1f GB", value / 1e9) end
    if value >= 1e6 then return string.format("%d MB", math.floor(value / 1e6 + 0.5)) end
    if value >= 1e3 then return string.format("%d KB", math.floor(value / 1e3 + 0.5)) end
    return string.format("%d B", math.floor(value + 0.5))
end

return M
