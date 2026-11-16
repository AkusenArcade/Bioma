--!strict
-- A glyph drawn by parts: the same file `g.icon` draws (assets/icons),
-- read as nodes (`g.svg`), so a part can carry a reading — the Wi-Fi arcs
-- the signal reaches, a stick filled as far as it is used. At rest it is
-- the icon, pixel for pixel: the same 165° tint across the whole glyph.
--
-- `parts` gives the parts their own props (bindings, transitions). A part
-- the file hides (drawn at opacity 0, so `g.icon` never shows it) is
-- revealed with `M.shown`, which gives it the tint back.
--
-- `under` draws the file once more beneath, in one colour, with its own
-- `under_parts`: the dim arcs under the lit ones. A part lit above and its
-- dim self below cross-fade, so no edge of one shows round the other.
local g = require("@genoma")
local paths = require("core/paths")
local colour = require("core/colour")

local M = {}

export type Options = {
    icon: string,
    size: () -> number,
    top: () -> string,
    bottom: () -> string,
    parts: { [string]: any }?,
    under: (() -> string)?,
    under_parts: { [string]: any }?,
    present: (() -> boolean)?,
}

local function file(icon: string): string return paths.root .. "/assets/icons/" .. icon .. ".svg" end

-- The tint as stops, for a part the file hides: `which` is "fill" or
-- "stroke", `alpha` how much of it shows (a well under a stroke).
function M.shown(which: string, top: () -> string, bottom: () -> string, alpha: number?): { [string]: any }
    local a = alpha or 1
    local function faded(hex: string): string
        return if a >= 1 then hex else colour.alpha(hex, colour.parse(hex).a * a)
    end
    return {
        [which .. "_stops"] = function() return { { 0, faded(top()) }, { 1, faded(bottom()) } } end,
    }
end

-- Two tables of part props as one: `b`'s keys over `a`'s.
function M.merge(a: { [string]: any }, b: { [string]: any }): { [string]: any }
    local out = table.clone(a)
    for k, v in b do out[k] = v end
    return out
end

function M.new(o: Options): any
    local lit = g.svg {
        overlay = o.under ~= nil,
        attach = if o.under then "corner" else nil,
        src = file(o.icon),
        width = o.size,
        height = o.size,
        gradient_top = o.top,
        gradient_bottom = o.bottom,
        parts = o.parts,
    }
    if not o.under then
        if o.present then lit.present = o.present end
        return lit
    end
    return g.box {
        present = o.present,
        width = o.size,
        height = o.size,
        g.svg {
            overlay = true,
            attach = "corner",
            src = file(o.icon),
            width = o.size,
            height = o.size,
            color = o.under,
            parts = o.under_parts,
        },
        lit,
    }
end

return M
