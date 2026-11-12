--!strict
-- A new version, installed under the running shell: Bioma restarts itself on
-- it once pacman is done (Akusen, 2026-11-12).
--
-- An upgrade replaces /usr/share/bioma under a shell that keeps running the
-- runtime it started with, and every upgrade used to end on a line asking
-- for a restart by hand. The package manager runs as root, outside the
-- session; the shell is the one place that has the session's environment
-- and its place among the session's processes, so the restart starts here,
-- as the setup's own does (services/setup.luau).
--
-- `scripts/genoma` writes what was installed when the shell started into
-- BIOMA_PACKAGES — pacman's own directory names, `bioma-shell-<ver>-<rel>`
-- and `genoma-<ver>-<rel>` — and only for what this process actually runs:
-- Bioma from /usr/share/bioma, Genoma from /usr/bin/genoma. A shell started
-- from a checkout never lists bioma-shell, so an upgrade of the package does
-- not restart it. The environment is the process's, so a hot reload, which
-- pacman's new files trigger halfway through the transaction, does not move
-- the baseline.
--
-- Restarted only once pacman's lock is gone: the transaction is over, its
-- hooks included, and every file of the new version is in place.
local g = require("@genoma")
local paths = require("core/paths")

local M = {}

local pacman = "/var/lib/pacman"
local started = false

-- The package a directory of pacman's database is for: its name, without
-- the version and the release.
local function package_of(entry: string): string?
    return string.match(entry, "^(.+)%-[^%-]+%-[^%-]+$")
end

function M.start()
    if started then return end
    started = true
    local baseline = g.env("BIOMA_PACKAGES") or ""
    if baseline == "" then return end
    local was: { [string]: string } = {}
    for _, entry in string.split(baseline, " ") do
        local name = package_of(entry)
        if name then was[name] = entry end
    end

    local installed = g.folder { path = pacman .. "/local" }
    local root = g.folder { path = pacman }
    local asked = false
    g.effect(function()
        if asked then return end
        local now: { [string]: string } = {}
        for _, e in installed.entries do
            local name = package_of(e.name)
            if name and was[name] then now[name] = e.name end
        end
        -- A package missing is not an upgrade: the folder not read yet, a
        -- removal (nothing left to restart on), or the moment between the
        -- old version's directory going and the new one's coming.
        local changed = false
        for name, entry in was do
            if not now[name] then return end
            if now[name] ~= entry then changed = true end
        end
        if not changed then return end
        for _, e in root.entries do
            if e.name == "db.lck" then return end
        end
        asked = true
        print("Bioma: a new version is installed; restarting on it")
        -- Under the load, not the effect: pacman's folders keep changing,
        -- and an effect that runs again disposes what it started.
        g.lasting(function()
            g.process { command = { "setsid", "-f", paths.script("shell"), "restart" } }
        end)
    end)
end

return M
