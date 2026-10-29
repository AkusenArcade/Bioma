--!strict
-- A line of text to type into (what Qt's TextInput is to Bioma on
-- Quickshell): the process filter, a place's name, the launcher's query.
--
-- It draws no box of its own: the field is the launcher's, a line inside
-- whatever holds it. The caret is a hairline in the text's colour and it
-- holds still: a caret blinking at a fixed rate is motion with nothing
-- behind it, and where typing goes is said by where it stands. A selection
-- is the primary at 35%, the text over it unchanged.
--
-- Keys reach it through its owner, which hands them to `key` while the
-- field is taking them: the text a key types (the keymap and its layout
-- have already made it), and the editing keys, Ctrl and Shift included.
-- The clipboard is the desktop's, through `wl-copy` and `wl-paste`.
--
-- Not yet: placing the caret with the pointer (Genoma's presses carry no
-- position yet); a press gives the field the keys with the caret at the
-- end.
local g = require("@genoma")
local theme = require("core/theme")
local colour = require("core/colour")

local M = {}

-- Code points: the caret moves over characters, never inside one.
local function length(s: string): number return utf8.len(s) or #s end
local function byte_at(s: string, i: number): number
    -- The byte where code point i + 1 starts (i code points before it).
    return utf8.offset(s, i + 1) or (#s + 1)
end
local function sub(s: string, from: number, to: number): string
    -- Code points from + 1 … to.
    return string.sub(s, byte_at(s, from), byte_at(s, to) - 1)
end

-- A word ends where letters and figures do.
local function word_edge(s: string, at: number, step: number): number
    local n = length(s)
    local i = at
    local function is_word(k: number): boolean
        local ch = sub(s, k - 1, k)
        return string.match(ch, "^[%w]$") ~= nil or #ch > 1
    end
    if step < 0 then
        while i > 0 and not is_word(i) do i -= 1 end
        while i > 0 and is_word(i) do i -= 1 end
    else
        while i < n and not is_word(i + 1) do i += 1 end
        while i < n and is_word(i + 1) do i += 1 end
    end
    return i
end

-- `t`: text (a g.signal holding the string), width(), font(), size(),
-- color() (the text's; muted for the placeholder), placeholder,
-- taking() (whether the keys are the field's now), on_submit(text),
-- on_release() (Escape: it lets the keys go).
-- Returns the node and a handle: key(name, text, mods) → whether it was the
-- field's, and set(text).
function M.new(t: { [string]: any })
    local value = t.text
    local caret = g.signal(length(g.untracked(function() return value.value end)))
    local anchor = g.signal(-1) -- the selection's other end, -1 for none
    local scroll = g.signal(0)
    local colour_of = t.color or theme.text
    local function taking(): boolean return if t.taking then t.taking() else true end

    local function text(): string return value.value end
    local function width_of(s: string): number return g.text_width { text = s, font = t.font(), size = t.size() } end
    local function x_of(i: number): number return width_of(sub(text(), 0, i)) end

    local function selection(): (number, number)
        local a, c = anchor.value, caret.value
        if a < 0 or a == c then return c, c end
        return math.min(a, c), math.max(a, c)
    end

    -- The caret stays in sight: the line scrolls under it.
    g.effect(function()
        local x = x_of(caret.value)
        local room = t.width()
        local now = g.untracked(function() return scroll.value end)
        if x - now > room - 2 then
            scroll.value = x - room + 2
        elseif x < now then
            scroll.value = x
        elseif width_of(text()) - now < room and now > 0 then
            scroll.value = math.max(0, width_of(text()) - room + 2)
        end
    end)

    -- The selection, read without becoming a dependency: g.untracked gives
    -- back one value, and a selection is two.
    local function selection_now(): (number, number)
        local both = g.untracked(function() return { selection() } end)
        return both[1], both[2]
    end

    local function current(): (string, number, number, number)
        return g.untracked(text), g.untracked(function() return caret.value end),
            g.untracked(function() return anchor.value end), length(g.untracked(text))
    end

    local function replace(insert: string)
        local s, c = current()
        local from, to = selection_now()
        if from == to then from, to = c, c end
        g.batch(function()
            value.value = sub(s, 0, from) .. insert .. sub(s, to, length(s))
            caret.value = from + length(insert)
            anchor.value = -1
        end)
    end

    local function move(to: number, extend: boolean)
        local _, c, a, n = current()
        to = math.clamp(to, 0, n)
        g.batch(function()
            if extend then
                if a < 0 then anchor.value = c end
            else
                anchor.value = -1
            end
            caret.value = to
        end)
    end

    local function selected(): string
        local s = g.untracked(text)
        local from, to = selection_now()
        return sub(s, from, to)
    end

    local function copy()
        local chosen = selected()
        if chosen == "" then return end
        local p = g.process { command = { "wl-copy" } }
        p:write(chosen)
        p:close_input()
    end

    local function paste()
        local got = {}
        g.process {
            command = { "wl-paste", "--no-newline", "--type", "text/plain" },
            on_line = function(line: string) table.insert(got, line) end,
            -- A line takes no newline: what was copied on several becomes one.
            on_exit = function(code: number) if code == 0 then replace(table.concat(got, " ")) end end,
        }
    end

    local handle = {}

    function handle.set(s: string)
        g.batch(function()
            value.value = s
            caret.value = length(s)
            anchor.value = -1
        end)
    end

    function handle.key(name: string, typed: string?, mods: { [string]: boolean }?): boolean
        local m = mods or {}
        local s, c, _, n = current()
        local from, to = selection_now()
        if m.ctrl then
            if name == "a" or name == "A" then
                g.batch(function()
                    anchor.value = 0
                    caret.value = n
                end)
            elseif name == "c" or name == "C" then
                copy()
            elseif name == "x" or name == "X" then
                copy()
                if from ~= to then replace("") end
            elseif name == "v" or name == "V" then
                paste()
            elseif name == "Left" then
                move(word_edge(s, c, -1), m.shift == true)
            elseif name == "Right" then
                move(word_edge(s, c, 1), m.shift == true)
            elseif name == "BackSpace" then
                if from ~= to then replace("") else
                    local edge = word_edge(s, c, -1)
                    g.batch(function()
                        value.value = sub(s, 0, edge) .. sub(s, c, n)
                        caret.value = edge
                        anchor.value = -1
                    end)
                end
            else
                return false
            end
            return true
        end
        if name == "Left" then
            if from ~= to and not m.shift then move(from, false) else move(c - 1, m.shift == true) end
        elseif name == "Right" then
            if from ~= to and not m.shift then move(to, false) else move(c + 1, m.shift == true) end
        elseif name == "Home" or name == "KP_Home" then
            move(0, m.shift == true)
        elseif name == "End" or name == "KP_End" then
            move(n, m.shift == true)
        elseif name == "BackSpace" then
            if from ~= to then
                replace("")
            elseif c > 0 then
                g.batch(function()
                    value.value = sub(s, 0, c - 1) .. sub(s, c, n)
                    caret.value = c - 1
                end)
            end
        elseif name == "Delete" or name == "KP_Delete" then
            if from ~= to then
                replace("")
            elseif c < n then
                value.value = sub(s, 0, c) .. sub(s, c + 1, n)
            end
        elseif name == "Return" or name == "KP_Enter" then
            if t.on_submit then t.on_submit(s) end
        elseif name == "Escape" then
            if t.on_release then t.on_release() end
        elseif typed and typed ~= "" then
            replace(typed)
        else
            return false
        end
        return true
    end

    local node = g.capsule {
        width = t.width,
        height = function() return t.size() * 1.6 end,
        radius = 0,
        clip = true,
        align = "center",
        justify = "start",
        -- The selection, behind the text.
        g.capsule {
            overlay = true,
            attach = "corner",
            present = function()
                local from, to = selection()
                return from ~= to
            end,
            offset_x = function() return x_of((selection())) - scroll.value end,
            offset_y = function() return t.size() * 0.15 end,
            width = function()
                local from, to = selection()
                return math.max(1, x_of(to) - x_of(from))
            end,
            height = function() return t.size() * 1.3 end,
            radius = 2,
            fill = function() return colour.alpha(theme.primary(), 0.35) end,
        },
        g.text {
            offset_x = function() return -scroll.value end,
            font = t.font,
            size = t.size,
            color = function() return if text() == "" then theme.text_muted() else colour_of() end,
            text = function()
                local s = text()
                if s == "" then return t.placeholder or "" end
                return s
            end,
        },
        -- The caret: a hairline, still.
        g.capsule {
            overlay = true,
            attach = "corner",
            present = taking,
            offset_x = function() return x_of(caret.value) - scroll.value end,
            offset_y = function() return t.size() * 0.15 end,
            width = 1,
            height = function() return t.size() * 1.3 end,
            radius = 0,
            crisp = true,
            fill = colour_of,
        },
    }
    return node, handle
end

return M
